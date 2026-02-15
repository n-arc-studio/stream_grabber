import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'providers/download_provider.dart';
import 'screens/home_screen.dart';
import 'services/license_service.dart';
import 'services/audit_log_service.dart';

void main() {
  // Initialize FFI for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DownloadProvider(),
      child: MaterialApp(
        title: 'StreamVault',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        home: const DisclaimerGate(),
      ),
    );
  }
}

/// 起動時に免責事項同意を要求するゲート画面
class DisclaimerGate extends StatefulWidget {
  const DisclaimerGate({super.key});

  @override
  State<DisclaimerGate> createState() => _DisclaimerGateState();
}

class _DisclaimerGateState extends State<DisclaimerGate> {
  bool _loading = true;
  bool _accepted = false;

  @override
  void initState() {
    super.initState();
    _checkDisclaimer();
  }

  Future<void> _checkDisclaimer() async {
    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool('disclaimer_accepted') ?? false;
    setState(() {
      _accepted = accepted;
      _loading = false;
    });
  }

  Future<void> _acceptDisclaimer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('disclaimer_accepted', true);

    // 同意ログを記録
    await AuditLogService().log(
      action: 'disclaimer_accepted',
      detail: '利用規約に同意しました',
    );

    setState(() => _accepted = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_accepted) {
      return const LicenseCheckScreen();
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 64, color: Colors.deepPurple),
              const SizedBox(height: 24),
              const Text(
                'StreamVault',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'HLS Backup Manager',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[400]!),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey[50],
                ),
                constraints: const BoxConstraints(maxWidth: 600),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '利用規約',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 16),
                    Text(
                      '本ソフトウェアは、著作権者自身が権利を持つ'
                      'HLSストリーミング配信のアーカイブ・品質検査・'
                      'バックアップ用途に限定して提供されます。\n\n'
                      '以下の行為は禁止されています：\n'
                      '・第三者が権利を持つコンテンツの保存\n'
                      '・動画配信サービスの利用規約に違反する使用\n'
                      '・DRM保護されたコンテンツの処理\n'
                      '・不正アクセスまたはアクセス制御の回避\n\n'
                      '本ソフトウェアはDRM保護されたストリームに'
                      '対応していません（暗号鍵の取得・復号処理は'
                      '一切実装されていません）。\n\n'
                      'すべての操作は監査ログとして記録されます。',
                      style: TextStyle(fontSize: 14, height: 1.6),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _acceptDisclaimer,
                icon: const Icon(Icons.check_circle),
                label: const Text('上記に同意して利用を開始'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LicenseCheckScreen extends StatefulWidget {
  const LicenseCheckScreen({super.key});

  @override
  State<LicenseCheckScreen> createState() => _LicenseCheckScreenState();
}

class _LicenseCheckScreenState extends State<LicenseCheckScreen> {
  final LicenseService _licenseService = LicenseService();
  bool _isLoading = true;
  bool _isLicensed = false;
  bool _isTrialValid = false;

  @override
  void initState() {
    super.initState();
    _checkLicense();
  }

  Future<void> _checkLicense() async {
    final isLicensed = await _licenseService.isLicenseValid();
    final isTrialValid = await _licenseService.isTrialValid();

    setState(() {
      _isLicensed = isLicensed;
      _isTrialValid = isTrialValid;
      _isLoading = false;
    });
  }

  void _showLicenseDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ライセンスキーを入力'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('StreamVaultのライセンスキーを入力してください。'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'ライセンスキー',
                hintText: 'SGXX-XXXX-XXXX-XXXX',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () async {
              final success = await _licenseService.activateLicense(controller.text);
              
              if (success) {
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ライセンスが有効化されました')),
                  );
                  _checkLicense();
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('無効なライセンスキーです')),
                  );
                }
              }
            },
            child: const Text('有効化'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_isLicensed || _isTrialValid) {
      return const HomeScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('StreamVault'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.cloud_download_outlined,
                size: 80,
                color: Colors.deepPurple,
              ),
              const SizedBox(height: 24),
              const Text(
                'StreamVault',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'HLS Backup Manager',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              if (!_isTrialValid) ...[
                const Text(
                  'トライアル期間が終了しました',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              ElevatedButton.icon(
                onPressed: _showLicenseDialog,
                icon: const Icon(Icons.vpn_key),
                label: const Text('ライセンスキーを入力'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
              if (!_isTrialValid) ...[
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    // 購入ページを開く（Gumroad等）
                  },
                  child: const Text('ライセンスを購入'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
