import 'package:flutter/foundation.dart';
import '../models/download_task.dart';
import '../models/m3u8_stream.dart';
import '../services/database_service.dart';
import '../services/downloader_service.dart';
import '../services/ffmpeg_service.dart';
import '../services/m3u8_parser.dart';
import '../services/audit_log_service.dart';
import 'dart:io';

class DownloadProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();
  final DownloaderService _downloaderService = DownloaderService();
  final FFmpegService _ffmpegService = FFmpegService();
  final M3U8Parser _m3u8Parser = M3U8Parser();
  final AuditLogService _auditLog = AuditLogService();

  List<DownloadTask> _tasks = [];
  bool _isLoading = false;
  String? _error;
  
  // 進捗更新のスロットリング用
  final Map<String, DateTime> _lastNotifyTime = {};
  static const Duration _notifyThrottle = Duration(milliseconds: 1000);

  List<DownloadTask> get tasks => _tasks;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<DownloadTask> get activeTasks =>
      _tasks.where((t) => t.status == DownloadStatus.downloading || t.status == DownloadStatus.merging).toList();
  
  List<DownloadTask> get pendingTasks =>
      _tasks.where((t) => t.status == DownloadStatus.pending).toList();
  
  List<DownloadTask> get completedTasks =>
      _tasks.where((t) => t.status == DownloadStatus.completed).toList();

  DownloadProvider() {
    _initializeServices();
    loadTasks();
  }

  void _initializeServices() {
    _downloaderService.onProgress = (taskId, progress, downloadedSegments) {
      final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
      if (taskIndex != -1) {
        _tasks[taskIndex].progress = progress;
        _tasks[taskIndex].downloadedSegments = downloadedSegments;
        
        // スロットリング: 最後の通知から一定時間経過した場合のみ通知
        final now = DateTime.now();
        final lastNotify = _lastNotifyTime[taskId];
        
        if (lastNotify == null || now.difference(lastNotify) >= _notifyThrottle) {
          _lastNotifyTime[taskId] = now;
          _dbService.updateTask(_tasks[taskIndex]);
          notifyListeners();
        }
      }
    };

    _downloaderService.onCompleted = (taskId) {
      _lastNotifyTime.remove(taskId); // スロットリングマップをクリーンアップ
      final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
      if (taskIndex != -1) {
        final task = _tasks[taskIndex];
        // MP4の場合はマージ不要
        if (_isMp4Url(task.url)) {
          task.status = DownloadStatus.completed;
          task.progress = 1.0;
          task.completedAt = DateTime.now();
          _dbService.updateTask(task);
          _auditLog.logArchiveComplete(taskId: task.id, url: task.url);
          notifyListeners();
        } else {
          // M3U8の場合はマージ処理へ
          _startMerging(taskId);
        }
      }
    };

    _downloaderService.onError = (taskId, error) {
      _lastNotifyTime.remove(taskId); // スロットリングマップをクリーンアップ
      final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
      if (taskIndex != -1) {
        _tasks[taskIndex].status = DownloadStatus.failed;
        _tasks[taskIndex].errorMessage = error;
        _dbService.updateTask(_tasks[taskIndex]);
        notifyListeners();
      }
    };
  }

  Future<void> loadTasks() async {
    _isLoading = true;
    notifyListeners();

    try {
      _tasks = await _dbService.getAllTasks();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<M3U8Stream>> getAvailableStreams(String m3u8Url) async {
    try {
      return await _m3u8Parser.getAllStreams(m3u8Url);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return [];
    }
  }

  // ローカルM3U8ファイルから利用可能なストリームを取得
  Future<List<M3U8Stream>> getAvailableLocalStreams(String filePath) async {
    try {
      return await _m3u8Parser.getAllLocalStreams(filePath);
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return [];
    }
  }

  // ローカルM3U8ファイルからダウンロードタスクを追加
  Future<void> addLocalDownloadTask({
    required String m3u8FilePath,
    String? fileName,
    M3U8Stream? selectedStream,
  }) async {
    try {
      final downloadDir = await _downloaderService.getDownloadDirectory();
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final name = fileName ?? 'video_$id.mp4';

      final task = DownloadTask(
        id: id,
        url: m3u8FilePath, // ローカルファイルパスをurlとして保存
        websiteUrl: 'local://$m3u8FilePath', // ローカルファイルであることを示す
        outputPath: downloadDir,
        fileName: name,
      );

      await _dbService.insertTask(task);
      _tasks.insert(0, task);
      notifyListeners();

      // 監査ログ記録
      await _auditLog.logArchiveStart(
        taskId: task.id,
        url: m3u8FilePath,
        fileName: fileName,
      );

      // 自動ダウンロード開始
      await startLocalDownload(task.id, selectedStream: selectedStream);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  // ローカルM3U8ファイルからダウンロード開始
  Future<void> startLocalDownload(String taskId, {M3U8Stream? selectedStream}) async {
    final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;

    final task = _tasks[taskIndex];
    task.status = DownloadStatus.downloading;
    await _dbService.updateTask(task);
    notifyListeners();

    try {
      // ローカルM3U8ファイルを解析
      M3U8Stream stream = selectedStream ?? await _m3u8Parser.parseLocalM3U8(task.url);
      
      // 並列ダウンロードを使用（ローカルファイルの場合はコピー）
      await _downloaderService.downloadM3U8Parallel(task, stream);
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.errorMessage = e.toString().replaceAll('Exception: ', '');
      await _dbService.updateTask(task);
      notifyListeners();
    }
  }

  Future<void> addDownloadTask({
    required String m3u8Url,
    required String websiteUrl,
    String? fileName,
    M3U8Stream? selectedStream,
  }) async {
    try {
      final downloadDir = await _downloaderService.getDownloadDirectory();
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final name = fileName ?? 'video_$id.mp4';

      final task = DownloadTask(
        id: id,
        url: m3u8Url,
        websiteUrl: websiteUrl,
        outputPath: downloadDir,
        fileName: name,
      );

      await _dbService.insertTask(task);
      _tasks.insert(0, task);
      notifyListeners();

      // 監査ログ記録
      await _auditLog.logArchiveStart(
        taskId: task.id,
        url: m3u8Url,
        fileName: name,
      );

      // 自動ダウンロード開始
      await startDownload(task.id, selectedStream: selectedStream);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> startDownload(String taskId, {M3U8Stream? selectedStream}) async {
    final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;

    final task = _tasks[taskIndex];
    task.status = DownloadStatus.downloading;
    await _dbService.updateTask(task);
    notifyListeners();

    try {
      // URLがMP4かM3U8かを判別
      if (_isM3u8Url(task.url)) {
        // M3U8の処理
        M3U8Stream stream = selectedStream ?? await _m3u8Parser.parseM3U8(task.url);
        
        // 並列ダウンロードを使用
        await _downloaderService.downloadM3U8Parallel(task, stream);
      } else if (_isMp4Url(task.url)) {
        // MP4の直接ダウンロード
        await _downloaderService.downloadMP4(task, task.url);
      } else {
        // 拡張子が曖昧な場合はM3U8として扱う
        M3U8Stream stream = selectedStream ?? await _m3u8Parser.parseM3U8(task.url);
        await _downloaderService.downloadM3U8Parallel(task, stream);
      }
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.errorMessage = e.toString();
      await _dbService.updateTask(task);
      notifyListeners();
    }
  }

  bool _isM3u8Url(String url) {
    final normalized = url.trim().toLowerCase();
    try {
      final uri = Uri.parse(normalized);
      return uri.path.endsWith('.m3u8');
    } catch (e) {
      return normalized.contains('.m3u8');
    }
  }

  bool _isMp4Url(String url) {
    final normalized = url.trim().toLowerCase();
    if (_isM3u8Url(normalized)) {
      return false;
    }
    try {
      final uri = Uri.parse(normalized);
      return uri.path.endsWith('.mp4');
    } catch (e) {
      return normalized.contains('.mp4');
    }
  }

  Future<void> _startMerging(String taskId) async {
    final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;

    final task = _tasks[taskIndex];
    task.status = DownloadStatus.merging;
    task.progress = 0.9;
    await _dbService.updateTask(task);
    notifyListeners();

    try {
      final segmentPaths = await _downloaderService.getSegmentPaths(
        task.id,
        task.outputPath,
      );

      if (segmentPaths.isEmpty) {
        throw Exception('No segments found to merge');
      }

      final outputFile = '${task.outputPath}/${task.fileName}';
      
      _ffmpegService.onCompleted = () async {
        final output = File(outputFile);
        if (!await output.exists() || await output.length() == 0) {
          task.status = DownloadStatus.failed;
          task.errorMessage = 'Merge failed: output file is empty';
          await _dbService.updateTask(task);
          notifyListeners();
          return;
        }

        task.status = DownloadStatus.completed;
        task.progress = 1.0;
        task.completedAt = DateTime.now();
        await _dbService.updateTask(task);

        // FFmpegがファイルを解放するまで少し待機
        await Future.delayed(const Duration(milliseconds: 500));

        // 一時ファイル削除
        try {
          await _downloaderService.cleanupTempFiles(task.id, task.outputPath);
        } catch (e) {
          // Ignore cleanup errors
        }

        notifyListeners();
      };

      _ffmpegService.onError = (error) async {
        task.status = DownloadStatus.failed;
        task.errorMessage = 'Merge failed: $error';
        await _dbService.updateTask(task);
        notifyListeners();
      };

      // MP4に結合
      final extension = task.fileName.split('.').last.toLowerCase();
      if (extension == 'mkv') {
        await _ffmpegService.mergeSegmentsToMKV(segmentPaths, outputFile);
      } else {
        await _ffmpegService.mergeSegmentsToMP4(segmentPaths, outputFile);
      }
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.errorMessage = 'Merge error: ${e.toString()}';
      await _dbService.updateTask(task);
      notifyListeners();
    }
  }

  Future<void> pauseDownload(String taskId) async {
    final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;

    _tasks[taskIndex].status = DownloadStatus.paused;
    await _dbService.updateTask(_tasks[taskIndex]);
    notifyListeners();
  }

  Future<void> resumeDownload(String taskId) async {
    await startDownload(taskId);
  }

  Future<void> deleteTask(String taskId) async {
    _lastNotifyTime.remove(taskId); // スロットリングマップをクリーンアップ
    
    final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;

    final task = _tasks[taskIndex];
    
    // 一時ファイル削除（エラーが発生しても続行）
    try {
      await _downloaderService.cleanupTempFiles(task.id, task.outputPath);
    } catch (e) {
      // Ignore cleanup errors
    }
    
    // 出力ファイル削除（完了済みの場合）
    if (task.status == DownloadStatus.completed) {
      try {
        final outputFile = File('${task.outputPath}/${task.fileName}');
        if (await outputFile.exists()) {
          await outputFile.delete();
        }
      } catch (e) {
        // Ignore file deletion errors
      }
    }

    await _dbService.deleteTask(taskId);
    _tasks.removeAt(taskIndex);
    notifyListeners();
  }

  Future<void> clearCompleted() async {
    await _dbService.clearCompletedTasks();
    _tasks.removeWhere((task) => task.status == DownloadStatus.completed);
    notifyListeners();
  }

  Future<void> retryTask(String taskId) async {
    final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;

    _tasks[taskIndex].status = DownloadStatus.pending;
    _tasks[taskIndex].progress = 0;
    _tasks[taskIndex].downloadedSegments = 0;
    _tasks[taskIndex].errorMessage = null;
    
    await _dbService.updateTask(_tasks[taskIndex]);
    notifyListeners();

    await startDownload(taskId);
  }
}
