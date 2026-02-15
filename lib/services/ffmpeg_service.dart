import 'dart:io';

class FFmpegService {
  Function(double progress)? onProgress;
  Function(String error)? onError;
  Function()? onCompleted;

  bool _hasNonAscii(String value) {
    return value.codeUnits.any((unit) => unit > 127);
  }

  String _buildTempListFilePath() {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '${Directory.systemTemp.path}/HLSBackup_segments_$stamp.txt';
  }

  String _buildSafeOutputPath(String outputPath) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final extension = outputPath.contains('.')
        ? outputPath.split('.').last
        : 'mp4';
    return '${Directory.systemTemp.path}/HLSBackup_output_$stamp.$extension';
  }

  Future<void> _moveOutputFile(String fromPath, String toPath) async {
    if (fromPath == toPath) return;
    final source = File(fromPath);
    if (!await source.exists()) return;
    final target = File(toPath);
    await target.parent.create(recursive: true);
    await source.copy(toPath);
    await source.delete();
  }

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

      final stdoutText = result.stdout.toString();
      final stderrText = result.stderr.toString();
      if (stdoutText.isNotEmpty) {
        print('FFmpeg stdout:\n$stdoutText');
      }
      if (stderrText.isNotEmpty) {
        print('FFmpeg stderr:\n$stderrText');
      }

      if (result.exitCode == 0) {
        onCompleted?.call();
        return true;
      } else {
        final error = stderrText;
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
      final listFile = File(_buildTempListFilePath());
      final listContent = segmentPaths
          .map((path) => "file '${path.replaceAll('\\', '/')}'")
          .join('\n');
      
      await listFile.writeAsString(listContent);

      final useSafeOutput = _hasNonAscii(outputPath);
      final actualOutputPath =
          useSafeOutput ? _buildSafeOutputPath(outputPath) : outputPath;

      // FFmpegコマンド実行
      final arguments = [
        '-f', 'concat',
        '-safe', '0',
        '-i', listFile.path,
        '-c', 'copy',
        '-bsf:a', 'aac_adtstoasc',
        actualOutputPath,
        '-y', // 上書き許可
      ];
      
      final success = await _executeFFmpeg(arguments);

      if (success && useSafeOutput) {
        await _moveOutputFile(actualOutputPath, outputPath);
      } else if (!success && useSafeOutput) {
        final tempFile = File(actualOutputPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }

      // 失敗時は原因調査のためリストを残す
      if (success) {
        if (await listFile.exists()) {
          await listFile.delete();
        }
      } else {
        onError?.call('Concat list retained for debugging: ${listFile.path}');
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
      final listFile = File(_buildTempListFilePath());
      final listContent = segmentPaths
          .map((path) => "file '${path.replaceAll('\\', '/')}'")
          .join('\n');
      
      await listFile.writeAsString(listContent);

      final useSafeOutput = _hasNonAscii(outputPath);
      final actualOutputPath =
          useSafeOutput ? _buildSafeOutputPath(outputPath) : outputPath;

      final arguments = [
        '-f', 'concat',
        '-safe', '0',
        '-i', listFile.path,
        '-c', 'copy',
        actualOutputPath,
        '-y',
      ];
      
      final success = await _executeFFmpeg(arguments);

      if (success && useSafeOutput) {
        await _moveOutputFile(actualOutputPath, outputPath);
      } else if (!success && useSafeOutput) {
        final tempFile = File(actualOutputPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }

      if (success) {
        if (await listFile.exists()) {
          await listFile.delete();
        }
      } else {
        onError?.call('Concat list retained for debugging: ${listFile.path}');
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
