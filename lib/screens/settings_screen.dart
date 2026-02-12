import 'package:flutter/material.dart';
import '../services/license_service.dart';
import '../services/ffmpeg_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final LicenseService _licenseService = LicenseService();
  final FFmpegService _ffmpegService = FFmpegService();
  
  bool _isLicensed = false;
  String? _licenseKey;
  DateTime? _activationDate;
  int _trialDaysRemaining = 0;
  bool _isLoading = true;
  bool _isFFmpegAvailable = false;
  String? _ffmpegVersion;

  @override
  void initState() {
    super.initState();
    _loadLicenseInfo();
    _checkFFmpeg();
  }

  Future<void> _checkFFmpeg() async {
    final isAvailable = await _ffmpegService.isFFmpegAvailable();
    String? version;
    if (isAvailable) {
      version = await _ffmpegService.getFFmpegVersion();
    }

    setState(() {
      _isFFmpegAvailable = isAvailable;
      _ffmpegVersion = version;
    });
  }

  Future<void> _loadLicenseInfo() async {
    final isLicensed = await _licenseService.isLicenseValid();
    final licenseKey = await _licenseService.getLicenseKey();
    final activationDate = await _licenseService.getActivationDate();
    final daysRemaining = await _licenseService.getTrialDaysRemaining();

    setState(() {
      _isLicensed = isLicensed;
      _licenseKey = licenseKey;
      _activationDate = activationDate;
      _trialDaysRemaining = daysRemaining;
      _isLoading = false;
    });
  }

  void _showActivateLicenseDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ライセンスキーを入力'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                  _loadLicenseInfo();
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

  void _showDeactivateDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ライセンス解除'),
        content: const Text('このデバイスのライセンスを解除しますか？\n解除後は再度ライセンスキーの入力が必要です。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _licenseService.deactivateLicense();
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ライセンスを解除しました')),
                );
                _loadLicenseInfo();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('解除'),
          ),
        ],
      ),
    );
  }

  void _generateTestLicense() {
    final testKey = _licenseService.generateLicenseKey();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('テストライセンスキー'),
        content: SelectableText(
          testKey,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _licenseService.activateLicense(testKey);
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('テストライセンスを有効化しました')),
                );
                _loadLicenseInfo();
              }
            },
            child: const Text('このキーを使用'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // ライセンス情報
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.vpn_key, size: 32),
                              const SizedBox(width: 12),
                              Text(
                                'ライセンス情報',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          _buildInfoRow(
                            'ステータス',
                            _isLicensed ? '有効' : 'トライアル',
                            _isLicensed ? Colors.green : Colors.orange,
                          ),
                          if (_isLicensed) ...[
                            const SizedBox(height: 8),
                            _buildInfoRow('ライセンスキー', _licenseKey ?? 'N/A'),
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              '有効化日',
                              _activationDate != null
                                  ? '${_activationDate!.year}/${_activationDate!.month}/${_activationDate!.day}'
                                  : 'N/A',
                            ),
                          ] else ...[
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              'トライアル残り',
                              '$_trialDaysRemaining日',
                              _trialDaysRemaining > 7 ? null : Colors.red,
                            ),
                          ],
                          const SizedBox(height: 16),
                          if (_isLicensed)
                            OutlinedButton.icon(
                              onPressed: _showDeactivateDialog,
                              icon: const Icon(Icons.remove_circle_outline),
                              label: const Text('ライセンス解除'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                            )
                          else
                            ElevatedButton.icon(
                              onPressed: _showActivateLicenseDialog,
                              icon: const Icon(Icons.vpn_key),
                              label: const Text('ライセンスキーを入力'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                // FFmpeg情報
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _isFFmpegAvailable ? Icons.check_circle : Icons.error_outline,
                                size: 32,
                                color: _isFFmpegAvailable ? Colors.green : Colors.red,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'FFmpeg状態',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          _buildInfoRow(
                            'ステータス',
                            _isFFmpegAvailable ? '利用可能' : '未インストール',
                            _isFFmpegAvailable ? Colors.green : Colors.red,
                          ),
                          if (_isFFmpegAvailable && _ffmpegVersion != null) ...[
                            const SizedBox(height: 8),
                            _buildInfoRow('バージョン', _ffmpegVersion!.split(' ').take(3).join(' ')),
                          ],
                          if (!_isFFmpegAvailable) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orange.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.warning, color: Colors.orange, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        'インストールが必要です',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    '動画ファイルの結合にはFFmpegが必要です。',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'インストール手順：',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    '1. https://www.gyan.dev/ffmpeg/builds/ へアクセス\n'
                                    '2. "ffmpeg-release-essentials.zip" をダウンロード\n'
                                    '3. 解凍後、bin フォルダのパスを環境変数 PATH に追加',
                                    style: TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () async {
                              await _checkFFmpeg();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _isFFmpegAvailable
                                          ? 'FFmpegが見つかりました'
                                          : 'FFmpegが見つかりません',
                                    ),
                                    backgroundColor: _isFFmpegAvailable ? Colors.green : Colors.red,
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('再確認'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // アプリ情報
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.info_outline, size: 32),
                              const SizedBox(width: 12),
                              Text(
                                'アプリ情報',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          _buildInfoRow('アプリ名', 'StreamGrabber'),
                          const SizedBox(height: 8),
                          _buildInfoRow('バージョン', '1.0.0'),
                          const SizedBox(height: 8),
                          _buildInfoRow('ビルド', '1'),
                        ],
                      ),
                    ),
                  ),
                ),

                // 開発者向けオプション
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.code, size: 32),
                              const SizedBox(width: 12),
                              Text(
                                '開発者向け',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          ElevatedButton.icon(
                            onPressed: _generateTestLicense,
                            icon: const Icon(Icons.key),
                            label: const Text('テストライセンス生成'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildInfoRow(String label, String value, [Color? valueColor]) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: valueColor != null ? FontWeight.bold : null,
          ),
        ),
      ],
    );
  }
}
