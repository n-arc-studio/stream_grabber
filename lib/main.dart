import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'providers/download_provider.dart';
import 'screens/home_screen.dart';
import 'services/license_service.dart';

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
        title: 'StreamGrabber',
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
        home: const LicenseCheckScreen(),
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
            const Text('StreamGrabberのライセンスキーを入力してください。'),
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
        title: const Text('StreamGrabber'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.download,
                size: 80,
                color: Colors.deepPurple,
              ),
              const SizedBox(height: 24),
              const Text(
                'StreamGrabber',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'M3U8ストリーミングビデオダウンローダー',
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
