import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/download_task.dart';
import '../models/m3u8_stream.dart';
import 'm3u8_parser.dart';

class DownloaderService {
  final Dio _dio = Dio(
    BaseOptions(
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': '*/*',
        'Accept-Language': 'ja,en-US;q=0.9,en;q=0.8',
        'Accept-Encoding': 'gzip, deflate, br',
        'Connection': 'keep-alive',
      },
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(minutes: 3),
      followRedirects: true,
      maxRedirects: 5,
    ),
  );
  final M3U8Parser _parser = M3U8Parser();
  final Map<String, String> _tempDirByTask = {};
  
  // ダウンロード進捗コールバック
  Function(String taskId, double progress, int downloadedSegments)? onProgress;
  Function(String taskId, String error)? onError;
  Function(String taskId)? onCompleted;

  bool _hasNonAscii(String value) {
    return value.codeUnits.any((unit) => unit > 127);
  }

  Future<Directory> _getTempDir(String taskId, String outputPath) async {
    final existing = _tempDirByTask[taskId];
    if (existing != null) {
      return Directory(existing);
    }

    String basePath = outputPath;
    if (_hasNonAscii(outputPath)) {
      final systemTemp = await getTemporaryDirectory();
      basePath = '${systemTemp.path}/HLSBackupManager';
    }

    final dir = Directory('$basePath/temp_$taskId');
    _tempDirByTask[taskId] = dir.path;
    return dir;
  }

  String _getSegmentExtension(String url, {String fallback = 'ts'}) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      final lastDot = path.lastIndexOf('.');
      if (lastDot != -1 && lastDot < path.length - 1) {
        final ext = path.substring(lastDot + 1).toLowerCase();
        if (ext.length <= 6) {
          return ext;
        }
      }
    } catch (e) {
      // Ignore parse errors and fall back.
    }
    return fallback;
  }

  String? _getReferer(DownloadTask task, M3U8Stream stream) {
    if (task.websiteUrl.startsWith('http://') ||
        task.websiteUrl.startsWith('https://')) {
      return task.websiteUrl;
    }
    if (stream.url.startsWith('http://') || stream.url.startsWith('https://')) {
      return stream.url;
    }
    return null;
  }

  Future<String> getDownloadDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${directory.path}/HLSBackupManager/Archives');
    
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    
    return downloadDir.path;
  }

  // MP4ファイルの直接ダウンロード
  Future<void> downloadMP4(DownloadTask task, String mp4Url) async {
    try {
      task.totalSegments = 1;
      task.downloadedSegments = 0;

      final outputFile = '${task.outputPath}/${task.fileName}';
      
      await _dio.download(
        mp4Url,
        outputFile,
        options: Options(
          headers: {
            'Referer': mp4Url,
            'Origin': Uri.parse(mp4Url).origin,
          },
          receiveTimeout: const Duration(minutes: 30),
          sendTimeout: const Duration(seconds: 30),
        ),
        onReceiveProgress: (received, total) {
          if (total != -1) {
            task.progress = received / total;
            onProgress?.call(task.id, task.progress, 0);
          }
        },
      );

      task.downloadedSegments = 1;
      task.progress = 1.0;
      onProgress?.call(task.id, task.progress, task.downloadedSegments);
      onCompleted?.call(task.id);
    } on DioException catch (e) {
      String errorMessage;
      if (e.response?.statusCode == 403) {
        errorMessage = 'アクセスが拒否されました (403)。このファイルはアクセスが制限されている可能性があります。';
      } else if (e.response?.statusCode == 404) {
        errorMessage = 'ファイルが見つかりません (404)。URLを確認してください。';
      } else if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
        errorMessage = '接続タイムアウト。ネットワーク接続を確認してください。';
      } else {
        errorMessage = '取得エラー: ${e.message}';
      }
      onError?.call(task.id, errorMessage);
      rethrow;
    } catch (e) {
      onError?.call(task.id, e.toString());
      rethrow;
    }
  }

  /// 暗号化/DRM保護されたストリームかどうかを検証し、該当する場合は例外をスロー
  void _rejectIfEncrypted(M3U8Stream stream) {
    if (stream.isEncrypted || stream.keyUri != null) {
      throw Exception(
        'このストリームは暗号化（DRM保護）されています。\n'
        '本ソフトウェアは著作権者自身の配信管理用途専用であり、\n'
        'DRM保護されたコンテンツの処理には対応していません。',
      );
    }
  }

  Future<void> downloadM3U8(DownloadTask task, M3U8Stream stream) async {
    try {
      // DRM/暗号化チェック
      _rejectIfEncrypted(stream);

      // セグメントURLがない場合、M3U8を解析
      List<String> segmentUrls = stream.segmentUrls;
      
      if (segmentUrls.isEmpty) {
        final parsedStream = await _parser.parseM3U8(stream.url);
        _rejectIfEncrypted(parsedStream);
        segmentUrls = parsedStream.segmentUrls;
      }

      if (segmentUrls.isEmpty) {
        throw Exception('No segments found in M3U8 playlist');
      }

      task.totalSegments = segmentUrls.length + (stream.initSegmentUrl != null ? 1 : 0);
      task.downloadedSegments = 0;

      // 一時ディレクトリ作成
      final tempDir = await _getTempDir(task.id, task.outputPath);
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }

      final referer = _getReferer(task, stream);

      // Initセグメント（fMP4/CMAF）を先に取得
      if (stream.initSegmentUrl != null) {
        final initUrl = stream.initSegmentUrl!;
        final initExt = _getSegmentExtension(initUrl);
        final initPath = '${tempDir.path}/segment_-1.$initExt';
        await _downloadSegment(initUrl, initPath, referer: referer);
        task.downloadedSegments = 1;
        task.progress = (task.downloadedSegments / task.totalSegments) * 0.9;
        onProgress?.call(task.id, task.progress, task.downloadedSegments);
      }

      // セグメントをダウンロード
      for (int i = 0; i < segmentUrls.length; i++) {
        final segmentUrl = segmentUrls[i];
        final segmentExt = _getSegmentExtension(segmentUrl);
        final segmentPath = '${tempDir.path}/segment_$i.$segmentExt';

        await _downloadSegment(segmentUrl, segmentPath, referer: referer);

        final downloaded = (stream.initSegmentUrl != null) ? i + 2 : i + 1;
        task.downloadedSegments = downloaded;
        task.progress = (task.downloadedSegments / task.totalSegments) * 0.9; // 90%まで（残り10%はマージ用）

        onProgress?.call(task.id, task.progress, task.downloadedSegments);
      }

      onCompleted?.call(task.id);
    } on DioException catch (e) {
      String errorMessage;
      if (e.response?.statusCode == 403) {
        errorMessage = 'アクセスが拒否されました (403)。このストリームはアクセスが制限されている可能性があります。';
      } else if (e.response?.statusCode == 404) {
        errorMessage = 'セグメントが見つかりません (404)。ストリームが期限切れまたは削除された可能性があります。';
      } else if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
        errorMessage = '接続タイムアウト。ネットワーク接続を確認してください。';
      } else {
        errorMessage = 'ダウンロードエラー: ${e.message}';
      }
      onError?.call(task.id, errorMessage);
      rethrow;
    } catch (e) {
      onError?.call(task.id, e.toString());
      rethrow;
    }
  }

  Future<void> _downloadSegment(
    String url,
    String savePath, {
    String? referer,
  }) async {
    int maxRetries = 5;
    int retryCount = 0;
    
    while (retryCount < maxRetries) {
      try {
        // ローカルファイルの場合はコピー
        if (url.startsWith('file://')) {
          final sourceFile = File(url.substring(7)); // file:// を削除
          await sourceFile.copy(savePath);
          return;
        } else if (!url.startsWith('http://') && !url.startsWith('https://')) {
          // http/httpsで始まらない場合はローカルファイルパスと見なす
          final sourceFile = File(url);
          if (await sourceFile.exists()) {
            await sourceFile.copy(savePath);
            return;
          }
        }

        // HTTPダウンロード
        final originSource = referer ?? url;
        final originUri = Uri.tryParse(originSource);
        final response = await _dio.download(
          url,
          savePath,
          options: Options(
            headers: {
              if (referer != null) 'Referer': referer,
              if (originUri != null && originUri.hasScheme)
                'Origin': originUri.origin,
            },
            receiveTimeout: const Duration(minutes: 3),
            sendTimeout: const Duration(minutes: 1),
            validateStatus: (status) => status != null && status >= 200 && status < 400,
          ),
        );

        if (response.statusCode == null ||
            response.statusCode! < 200 ||
            response.statusCode! >= 400) {
          throw DioException(
            requestOptions: response.requestOptions,
            response: response,
            type: DioExceptionType.badResponse,
          );
        }

        final file = File(savePath);
        if (!await file.exists()) {
          throw Exception('Segment file missing: $savePath');
        }
        if (await file.length() == 0) {
          await file.delete();
          throw Exception('Segment file is empty: $savePath');
        }
        return; // 成功したら終了
      } on DioException {
        retryCount++;
        if (retryCount >= maxRetries) {
          rethrow;
        }
        // タイムアウトや接続エラーの場合は長めに待機
        int waitSeconds = 3 * retryCount;
        await Future.delayed(Duration(seconds: waitSeconds));
      } catch (e) {
        retryCount++;
        if (retryCount >= maxRetries) {
          rethrow;
        }
        await Future.delayed(Duration(seconds: 2 * retryCount));
      }
    }
  }

  Future<List<String>> getSegmentPaths(String taskId, String outputPath) async {
    final tempDir = await _getTempDir(taskId, outputPath);
    
    if (!await tempDir.exists()) {
      final legacyDir = Directory('$outputPath/temp_$taskId');
      if (!await legacyDir.exists()) {
        return [];
      }
      if (_hasNonAscii(outputPath)) {
        await tempDir.create(recursive: true);
        for (final entry in legacyDir.listSync()) {
          if (entry is File) {
            final fileName = entry.path.split(Platform.pathSeparator).last;
            await entry.copy('${tempDir.path}/$fileName');
          }
        }
        return _listSegmentFiles(tempDir);
      }
      return _listSegmentFiles(legacyDir);
    }

    return _listSegmentFiles(tempDir);
  }

  List<String> _listSegmentFiles(Directory dir) {
    final files = dir.listSync()
      ..sort((a, b) {
        final aNum = int.parse(a.path.split('_').last.split('.').first);
        final bNum = int.parse(b.path.split('_').last.split('.').first);
        return aNum.compareTo(bNum);
      });

    return files.map((file) => file.path).toList();
  }

  Future<void> cleanupTempFiles(String taskId, String outputPath) async {
    final tempDir = await _getTempDir(taskId, outputPath);
    final legacyDir = Directory('$outputPath/temp_$taskId');
    
    if (!await tempDir.exists() && !await legacyDir.exists()) {
      _tempDirByTask.remove(taskId);
      return;
    }

    // リトライロジック付きで削除
    int maxRetries = 3;
    int retryCount = 0;

    while (retryCount < maxRetries) {
      try {
        // まず個別のファイルを削除
        if (await tempDir.exists()) {
          final files = tempDir.listSync();
          for (var file in files) {
            try {
              if (file is File) {
                await file.delete();
              }
            } catch (e) {
              // Ignore individual file deletion errors
            }
          }
        }

        if (await legacyDir.exists()) {
          final files = legacyDir.listSync();
          for (var file in files) {
            try {
              if (file is File) {
                await file.delete();
              }
            } catch (e) {
              // Ignore individual file deletion errors
            }
          }
        }

        // 短い待機時間を入れる（ファイルハンドルが解放されるのを待つ）
        await Future.delayed(const Duration(milliseconds: 100));

        // ディレクトリを削除
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
        if (await legacyDir.exists()) {
          await legacyDir.delete(recursive: true);
        }
        _tempDirByTask.remove(taskId);
        return;
      } catch (e) {
        retryCount++;
        
        if (retryCount >= maxRetries) {
          // 削除に失敗してもエラーを投げずに続行
          _tempDirByTask.remove(taskId);
          return;
        }
        
        // リトライ前に待機（指数バックオフ）
        await Future.delayed(Duration(milliseconds: 500 * retryCount));
      }
    }
  }

  // 並列ダウンロード版（高速化）
  Future<void> downloadM3U8Parallel(
    DownloadTask task,
    M3U8Stream stream, {
    int concurrentDownloads = 3, // 5から3に削減してUI負荷を軽減
  }) async {
    try {
      // DRM/暗号化チェック
      _rejectIfEncrypted(stream);

      List<String> segmentUrls = stream.segmentUrls;
      
      if (segmentUrls.isEmpty) {
        final parsedStream = await _parser.parseM3U8(stream.url);
        _rejectIfEncrypted(parsedStream);
        segmentUrls = parsedStream.segmentUrls;
      }

      if (segmentUrls.isEmpty) {
        throw Exception('No segments found in M3U8 playlist');
      }

      task.totalSegments = segmentUrls.length + (stream.initSegmentUrl != null ? 1 : 0);
      task.downloadedSegments = 0;

      final tempDir = await _getTempDir(task.id, task.outputPath);
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }

      final referer = _getReferer(task, stream);

      // Initセグメント（fMP4/CMAF）を先に取得
      int completedCount = 0;
      if (stream.initSegmentUrl != null) {
        final initUrl = stream.initSegmentUrl!;
        final initExt = _getSegmentExtension(initUrl);
        final initPath = '${tempDir.path}/segment_-1.$initExt';
        await _downloadSegment(initUrl, initPath, referer: referer);
        completedCount = 1;
        task.downloadedSegments = completedCount;
        task.progress = (task.downloadedSegments / task.totalSegments) * 0.9;
        onProgress?.call(task.id, task.progress, task.downloadedSegments);
      }

      // 並列ダウンロード（ワーカー方式）
      int nextIndex = 0;

      Future<void> worker() async {
        while (true) {
          final currentIndex = nextIndex;
          nextIndex++;

          if (currentIndex >= segmentUrls.length) {
            break;
          }

          final segmentUrl = segmentUrls[currentIndex];
          final segmentExt = _getSegmentExtension(segmentUrl);
          final segmentPath = '${tempDir.path}/segment_$currentIndex.$segmentExt';

          await _downloadSegment(segmentUrl, segmentPath, referer: referer);

          completedCount++;
          task.downloadedSegments = completedCount;
          task.progress = (task.downloadedSegments / task.totalSegments) * 0.9;
          onProgress?.call(task.id, task.progress, task.downloadedSegments);
        }
      }

      final workers = List.generate(
        concurrentDownloads,
        (_) => worker(),
      );

      await Future.wait(workers);

      onCompleted?.call(task.id);
    } catch (e) {
      onError?.call(task.id, e.toString());
      rethrow;
    }
  }
}
