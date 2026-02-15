import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class LicenseService {
  static const String _licenseKey = 'license_key';
  static const String _activationDate = 'activation_date';

  // ライセンス検証用のシークレットキー（本番環境では安全に管理すること）
  static const String _secretKey = 'HLSBackupManager2026SecretKey';

  Future<bool> isLicenseValid() async {
    final prefs = await SharedPreferences.getInstance();
    final licenseKey = prefs.getString(_licenseKey);
    
    if (licenseKey == null || licenseKey.isEmpty) {
      return false;
    }

    return _validateLicenseKey(licenseKey);
  }

  Future<bool> activateLicense(String licenseKey) async {
    if (!_validateLicenseKey(licenseKey)) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_licenseKey, licenseKey);
    await prefs.setString(_activationDate, DateTime.now().toIso8601String());
    
    return true;
  }

  Future<void> deactivateLicense() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_licenseKey);
    await prefs.remove(_activationDate);
  }

  Future<String?> getLicenseKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_licenseKey);
  }

  Future<DateTime?> getActivationDate() async {
    final prefs = await SharedPreferences.getInstance();
    final dateStr = prefs.getString(_activationDate);
    if (dateStr == null) return null;
    return DateTime.parse(dateStr);
  }

  bool _validateLicenseKey(String licenseKey) {
    // 簡易的なライセンスキー検証
    // フォーマット: SGXX-XXXX-XXXX-XXXX (SG = HLS Backup Manager)
    final regex = RegExp(r'^SG[A-Z0-9]{2}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$');
    
    if (!regex.hasMatch(licenseKey)) {
      return false;
    }

    // チェックサム検証（簡易版）
    final parts = licenseKey.split('-');
    final checksum = _calculateChecksum(parts.sublist(1, 4).join());
    
    return parts[0].substring(2) == checksum;
  }

  String _calculateChecksum(String data) {
    final bytes = utf8.encode(data + _secretKey);
    final digest = sha256.convert(bytes);
    final checksum = digest.toString().substring(0, 2).toUpperCase();
    return checksum;
  }

  // ライセンスキー生成（管理者用）
  String generateLicenseKey() {
    final random = DateTime.now().millisecondsSinceEpoch.toString();
    final hash = sha256.convert(utf8.encode(random + _secretKey));
    
    final part1 = hash.toString().substring(0, 4).toUpperCase();
    final part2 = hash.toString().substring(4, 8).toUpperCase();
    final part3 = hash.toString().substring(8, 12).toUpperCase();
    
    final combined = '$part1$part2$part3';
    final checksum = _calculateChecksum(combined);
    
    return 'SG$checksum-$part1-$part2-$part3';
  }

  // トライアルモード（30日間）
  Future<bool> isTrialValid() async {
    final prefs = await SharedPreferences.getInstance();
    final firstRunStr = prefs.getString('first_run_date');
    
    if (firstRunStr == null) {
      await prefs.setString('first_run_date', DateTime.now().toIso8601String());
      return true;
    }

    final firstRun = DateTime.parse(firstRunStr);
    final daysSinceFirstRun = DateTime.now().difference(firstRun).inDays;
    
    return daysSinceFirstRun < 30;
  }

  Future<int> getTrialDaysRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    final firstRunStr = prefs.getString('first_run_date');
    
    if (firstRunStr == null) {
      return 30;
    }

    final firstRun = DateTime.parse(firstRunStr);
    final daysSinceFirstRun = DateTime.now().difference(firstRun).inDays;
    
    return 30 - daysSinceFirstRun;
  }
}
