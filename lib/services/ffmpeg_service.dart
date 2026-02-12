import 'dart:io';

class FFmpegService {
  Function(double progress)? onProgress;
  Function(String error)? onError;
  Function()? onCompleted;

  // FFmpegコマンドを実行
  Future<bool> _executeFFmpeg(List<String> arguments) async {
    try {
      // Windowsの場合、システムのffmpeg.exeを使用
      String ffmpegPath = 'ffmpeg';
      
      if (Platform.isWindows) {
        // システムパスのffmpegを使用
        ffmpegPath = 'ffmpeg.exe';
      }

      final result = await Process.run(
        ffmpegPath,
        arguments,
        runInShell: true,
      );

      if (result.exitCode == 0) {
        onCompleted?.call();
        return true;
      } else {
        final error = result.stderr.toString();
        onError?.call(error.isNotEmpty ? error : 'FFmpeg execution failed');
        return false;
      }
    } catch (e) {
      onError?.call(e.toString());
      return false;
    }
  }

  // TSセグメントをMP4に結合
  Future<bool> mergeSegmentsToMP4(
    List<String> segmentPaths,
    String outputPath,
  ) async {
    try {
      // セグメントリストファイル作成
      final listFile = File('${outputPath}_segments.txt');
      final listContent = segmentPaths
          .map((path) => "file '${path.replaceAll('\\', '/')}'")
          .join('\n');
      
      await listFile.writeAsString(listContent);

      // FFmpegコマンド実行
      final arguments = [
        '-f', 'concat',
        '-safe', '0',
        '-i', listFile.path,
        '-c', 'copy',
        '-bsf:a', 'aac_adtstoasc',
        outputPath,
        '-y', // 上書き許可
      ];
      
      final success = await _executeFFmpeg(arguments);

      // リストファイル削除
      if (await listFile.exists()) {
        await listFile.delete();
      }

      return success;
    } catch (e) {
      onError?.call(e.toString());
      return false;
    }
  }

  // TSセグメントをMKVに結合
  Future<bool> mergeSegmentsToMKV(
    List<String> segmentPaths,
    String outputPath,
  ) async {
    try {
      final listFile = File('${outputPath}_segments.txt');
      final listContent = segmentPaths
          .map((path) => "file '${path.replaceAll('\\', '/')}'")
          .join('\n');
      
      await listFile.writeAsString(listContent);

      final arguments = [
        '-f', 'concat',
        '-safe', '0',
        '-i', listFile.path,
        '-c', 'copy',
        outputPath,
        '-y',
      ];
      
      final success = await _executeFFmpeg(arguments);

      if (await listFile.exists()) {
        await listFile.delete();
      }

      return success;
    } catch (e) {
      onError?.call(e.toString());
      return false;
    }
  }

  // 動画情報取得
  Future<Map<String, dynamic>?> getVideoInfo(String videoPath) async {
    try {
      String ffmpegPath = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
      
      final result = await Process.run(
        ffmpegPath,
        ['-i', videoPath, '-hide_banner'],
        runInShell: true,
      );

      final output = result.stderr.toString(); // FFmpegは情報をstderrに出力

      if (output.isEmpty) return null;
      
      // 解像度抽出
      final resolutionMatch = RegExp(r'(\d{3,4})x(\d{3,4})').firstMatch(output);
      final durationMatch = RegExp(r'Duration: (\d{2}):(\d{2}):(\d{2})').firstMatch(output);

      return {
        'width': resolutionMatch?.group(1),
        'height': resolutionMatch?.group(2),
        'duration': durationMatch?.group(0),
      };
    } catch (e) {
      return null;
    }
  }

  // FFmpeg利用可能性チェック
  Future<bool> isFFmpegAvailable() async {
    try {
      String ffmpegPath = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
      final result = await Process.run(
        ffmpegPath,
        ['-version'],
        runInShell: true,
      );
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  // FFmpegバージョン確認
  Future<String?> getFFmpegVersion() async {
    try {
      String ffmpegPath = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
      final result = await Process.run(
        ffmpegPath,
        ['-version'],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        return result.stdout.toString().split('\n').first;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // 進捗付きでリエンコード（品質調整）
  Future<bool> reencodeVideo(
    String inputPath,
    String outputPath, {
    String codec = 'libx264',
    String quality = '23', // CRF値（0-51、低いほど高品質）
  }) async {
    try {
      String ffmpegPath = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
      
      final result = await Process.run(
        ffmpegPath,
        [
          '-i', inputPath,
          '-c:v', codec,
          '-crf', quality,
          '-c:a', 'aac',
          '-b:a', '128k',
          outputPath,
        ],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        onCompleted?.call();
        return true;
      } else {
        final output = result.stderr.toString();
        onError?.call(output.isNotEmpty ? output : 'Unknown error');
        return false;
      }
    } catch (e) {
      onError?.call(e.toString());
      return false;
    }
  }
}
