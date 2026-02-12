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
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      followRedirects: true,
      maxRedirects: 5,
    ),
  );
  final M3U8Parser _parser = M3U8Parser();
  
  // ダウンロード進捗コールバック
  Function(String taskId, double progress, int downloadedSegments)? onProgress;
  Function(String taskId, String error)? onError;
  Function(String taskId)? onCompleted;

  Future<String> getDownloadDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${directory.path}/StreamGrabber/Downloads');
    
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
        errorMessage = 'アクセスが拒否されました (403)。このファイルはダウンロードが制限されている可能性があります。';
      } else if (e.response?.statusCode == 404) {
        errorMessage = 'ファイルが見つかりません (404)。URLを確認してください。';
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

  Future<void> downloadM3U8(DownloadTask task, M3U8Stream stream) async {
    try {
      // セグメントURLがない場合、M3U8を解析
      List<String> segmentUrls = stream.segmentUrls;
      
      if (segmentUrls.isEmpty) {
        final parsedStream = await _parser.parseM3U8(stream.url);
        segmentUrls = parsedStream.segmentUrls;
      }

      if (segmentUrls.isEmpty) {
        throw Exception('No segments found in M3U8 playlist');
      }

      task.totalSegments = segmentUrls.length;
      task.downloadedSegments = 0;

      // 一時ディレクトリ作成
      final tempDir = Directory('${task.outputPath}/temp_${task.id}');
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }

      // セグメントをダウンロード
      for (int i = 0; i < segmentUrls.length; i++) {
        final segmentUrl = segmentUrls[i];
        final segmentPath = '${tempDir.path}/segment_$i.ts';

        await _downloadSegment(segmentUrl, segmentPath);

        task.downloadedSegments = i + 1;
        task.progress = (task.downloadedSegments / task.totalSegments) * 0.9; // 90%まで（残り10%はマージ用）

        onProgress?.call(task.id, task.progress, task.downloadedSegments);
      }

      onCompleted?.call(task.id);
    } on DioException catch (e) {
      String errorMessage;
      if (e.response?.statusCode == 403) {
        errorMessage = 'アクセスが拒否されました (403)。このストリームはダウンロードが制限されている可能性があります。';
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

  Future<void> _downloadSegment(String url, String savePath) async {
    int maxRetries = 3;
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
        await _dio.download(
          url,
          savePath,
          options: Options(
            headers: {
              'Referer': url,
              'Origin': Uri.parse(url).origin,
            },
            receiveTimeout: const Duration(seconds: 60),
            sendTimeout: const Duration(seconds: 30),
          ),
        );
        return; // 成功したら終了
      } catch (e) {
        retryCount++;
        if (retryCount >= maxRetries) {
          rethrow; // 最大リトライ回数を超えたら例外を投げる
        }
        // リトライ前に待機（指数バックオフ）
        await Future.delayed(Duration(seconds: 2 * retryCount));
      }
    }
  }

  Future<List<String>> getSegmentPaths(String taskId, String outputPath) async {
    final tempDir = Directory('$outputPath/temp_$taskId');
    
    if (!await tempDir.exists()) {
      return [];
    }

    final files = tempDir.listSync()
      ..sort((a, b) {
        final aNum = int.parse(a.path.split('_').last.split('.').first);
        final bNum = int.parse(b.path.split('_').last.split('.').first);
        return aNum.compareTo(bNum);
      });

    return files.map((file) => file.path).toList();
  }

  Future<void> cleanupTempFiles(String taskId, String outputPath) async {
    final tempDir = Directory('$outputPath/temp_$taskId');
    
    if (!await tempDir.exists()) {
      return;
    }

    // リトライロジック付きで削除
    int maxRetries = 3;
    int retryCount = 0;

    while (retryCount < maxRetries) {
      try {
        // まず個別のファイルを削除
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

        // 短い待機時間を入れる（ファイルハンドルが解放されるのを待つ）
        await Future.delayed(const Duration(milliseconds: 100));

        // ディレクトリを削除
        await tempDir.delete(recursive: true);
        return;
      } catch (e) {
        retryCount++;
        
        if (retryCount >= maxRetries) {
          // 削除に失敗してもエラーを投げずに続行
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
      List<String> segmentUrls = stream.segmentUrls;
      
      if (segmentUrls.isEmpty) {
        final parsedStream = await _parser.parseM3U8(stream.url);
        segmentUrls = parsedStream.segmentUrls;
      }

      if (segmentUrls.isEmpty) {
        throw Exception('No segments found in M3U8 playlist');
      }

      task.totalSegments = segmentUrls.length;
      task.downloadedSegments = 0;

      final tempDir = Directory('${task.outputPath}/temp_${task.id}');
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }

      // 並列ダウンロード
      final downloadQueue = <Future>[];
      int completedCount = 0;

      for (int i = 0; i < segmentUrls.length; i++) {
        final segmentUrl = segmentUrls[i];
        final segmentPath = '${tempDir.path}/segment_$i.ts';

        final downloadFuture = _downloadSegment(segmentUrl, segmentPath).then((_) {
          completedCount++;
          task.downloadedSegments = completedCount;
          task.progress = (task.downloadedSegments / task.totalSegments) * 0.9;
          onProgress?.call(task.id, task.progress, task.downloadedSegments);
        });

        downloadQueue.add(downloadFuture);

        // 同時ダウンロード数を制限
        if (downloadQueue.length >= concurrentDownloads) {
          await Future.any(downloadQueue);
          downloadQueue.removeWhere((future) => future.toString().contains('completed'));
        }
      }

      // 残りのダウンロードを待機
      await Future.wait(downloadQueue);

      onCompleted?.call(task.id);
    } catch (e) {
      onError?.call(task.id, e.toString());
      rethrow;
    }
  }
}
