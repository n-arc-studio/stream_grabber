import 'package:flutter/foundation.dart';
import '../models/download_task.dart';
import '../models/m3u8_stream.dart';
import '../services/database_service.dart';
import '../services/downloader_service.dart';
import '../services/ffmpeg_service.dart';
import '../services/m3u8_parser.dart';
import 'dart:io';

class DownloadProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();
  final DownloaderService _downloaderService = DownloaderService();
  final FFmpegService _ffmpegService = FFmpegService();
  final M3U8Parser _m3u8Parser = M3U8Parser();

  List<DownloadTask> _tasks = [];
  bool _isLoading = false;
  String? _error;

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
        _dbService.updateTask(_tasks[taskIndex]);
        notifyListeners();
      }
    };

    _downloaderService.onCompleted = (taskId) {
      final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
      if (taskIndex != -1) {
        final task = _tasks[taskIndex];
        // MP4の場合はマージ不要
        if (task.url.toLowerCase().contains('.mp4')) {
          task.status = DownloadStatus.completed;
          task.progress = 1.0;
          task.completedAt = DateTime.now();
          _dbService.updateTask(task);
          notifyListeners();
        } else {
          // M3U8の場合はマージ処理へ
          _startMerging(taskId);
        }
      }
    };

    _downloaderService.onError = (taskId, error) {
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

  Future<List<String>> detectM3U8FromWebsite(String websiteUrl) async {
    try {
      return await _m3u8Parser.detectM3U8FromWebsite(websiteUrl);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return [];
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
      if (task.url.toLowerCase().contains('.mp4')) {
        // MP4の直接ダウンロード
        await _downloaderService.downloadMP4(task, task.url);
      } else {
        // M3U8のダウンロード
        M3U8Stream stream = selectedStream ?? await _m3u8Parser.parseM3U8(task.url);
        
        // 並列ダウンロードを使用
        await _downloaderService.downloadM3U8Parallel(task, stream);
      }
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.errorMessage = e.toString();
      await _dbService.updateTask(task);
      notifyListeners();
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
          print('Warning: Failed to cleanup temp files: $e');
          // 削除に失敗してもタスクは完了として扱う
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
    final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;

    final task = _tasks[taskIndex];
    
    // 一時ファイル削除（エラーが発生しても続行）
    try {
      await _downloaderService.cleanupTempFiles(task.id, task.outputPath);
    } catch (e) {
      print('Warning: Failed to cleanup temp files during task deletion: $e');
    }
    
    // 出力ファイル削除（完了済みの場合）
    if (task.status == DownloadStatus.completed) {
      try {
        final outputFile = File('${task.outputPath}/${task.fileName}');
        if (await outputFile.exists()) {
          await outputFile.delete();
        }
      } catch (e) {
        print('Warning: Failed to delete output file: $e');
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
