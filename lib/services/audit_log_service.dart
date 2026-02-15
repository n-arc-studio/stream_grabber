import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 操作ログを記録する監査ログサービス。
///
/// 入力URL、利用同意、実行履歴をファイルに記録する。
/// 「侵害用途を想定していない証拠」として機能する。
class AuditLogService {
  static AuditLogService? _instance;
  File? _logFile;

  factory AuditLogService() {
    _instance ??= AuditLogService._internal();
    return _instance!;
  }

  AuditLogService._internal();

  Future<File> _getLogFile() async {
    if (_logFile != null) return _logFile!;
    final dir = await getApplicationDocumentsDirectory();
    final logDir = Directory('${dir.path}/StreamVault/logs');
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }
    _logFile = File('${logDir.path}/audit.log');
    return _logFile!;
  }

  /// 操作をログに記録する
  Future<void> log({
    required String action,
    String? url,
    String? detail,
  }) async {
    try {
      final file = await _getLogFile();
      final timestamp = DateTime.now().toIso8601String();
      final parts = <String>[
        '[$timestamp]',
        'ACTION=$action',
        if (url != null) 'URL=$url',
        if (detail != null) 'DETAIL=$detail',
      ];
      final line = '${parts.join(' | ')}\n';
      await file.writeAsString(line, mode: FileMode.append);
    } catch (e) {
      // ログ書き込みエラーはアプリの動作に影響させない
    }
  }

  /// アーカイブ開始をログに記録
  Future<void> logArchiveStart({
    required String taskId,
    required String url,
    String? fileName,
  }) async {
    await log(
      action: 'archive_start',
      url: url,
      detail: 'taskId=$taskId${fileName != null ? ', fileName=$fileName' : ''}',
    );
  }

  /// アーカイブ完了をログに記録
  Future<void> logArchiveComplete({
    required String taskId,
    required String url,
  }) async {
    await log(
      action: 'archive_complete',
      url: url,
      detail: 'taskId=$taskId',
    );
  }

  /// DRM拒否をログに記録
  Future<void> logDrmRejected({
    required String url,
  }) async {
    await log(
      action: 'drm_rejected',
      url: url,
      detail: 'DRM保護ストリームのため処理を拒否',
    );
  }

  /// アプリ起動をログに記録
  Future<void> logAppStart() async {
    await log(action: 'app_start');
  }

  /// ログファイルのパスを取得
  Future<String> getLogFilePath() async {
    final file = await _getLogFile();
    return file.path;
  }
}
