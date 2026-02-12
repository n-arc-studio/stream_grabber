import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/download_provider.dart';
import '../models/m3u8_stream.dart';

class UrlInputScreen extends StatefulWidget {
  const UrlInputScreen({super.key});

  @override
  State<UrlInputScreen> createState() => _UrlInputScreenState();
}

class _UrlInputScreenState extends State<UrlInputScreen> {
  final _websiteController = TextEditingController();
  final _fileNameController = TextEditingController();
  
  bool _isDetecting = false;
  List<String> _detectedUrls = [];
  String? _selectedM3u8Url;
  List<M3U8Stream>? _availableStreams;
  M3U8Stream? _selectedStream;
  bool _isLoadingStreams = false;
  String _outputFormat = 'mp4';

  @override
  void dispose() {
    _websiteController.dispose();
    _fileNameController.dispose();
    super.dispose();
  }

  Future<void> _detectM3U8() async {
    if (_websiteController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WebサイトのURLを入力してください')),
      );
      return;
    }

    setState(() {
      _isDetecting = true;
      _detectedUrls = [];
      _selectedM3u8Url = null;
      _availableStreams = null;
      _selectedStream = null;
    });

    final provider = context.read<DownloadProvider>();
    final urls = await provider.detectM3U8FromWebsite(_websiteController.text);

    setState(() {
      _detectedUrls = urls;
      _isDetecting = false;
      
      if (urls.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '動画URLが検出されませんでした。\n'
              'サイトがアクセスをブロックしている可能性があります。\n'
              'ブラウザの開発者ツール(F12)のNetworkタブで\n'
              '動画URLを直接確認してください。',
            ),
            duration: Duration(seconds: 6),
          ),
        );
      } else if (urls.length == 1) {
        _selectedM3u8Url = urls.first;
        _loadAvailableStreams();
      }
    });
  }

  Future<void> _loadAvailableStreams() async {
    if (_selectedM3u8Url == null) return;

    setState(() => _isLoadingStreams = true);

    final provider = context.read<DownloadProvider>();
    final streams = await provider.getAvailableStreams(_selectedM3u8Url!);

    setState(() {
      _availableStreams = streams;
      _selectedStream = streams.isNotEmpty ? streams.first : null;
      _isLoadingStreams = false;
    });
  }

  Future<void> _addToQueue() async {
    if (_selectedM3u8Url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('動画URLを選択してください')),
      );
      return;
    }

    final fileName = _fileNameController.text.trim().isEmpty
        ? null
        : '${_fileNameController.text.trim()}.$_outputFormat';

    final provider = context.read<DownloadProvider>();
    await provider.addDownloadTask(
      m3u8Url: _selectedM3u8Url!,
      websiteUrl: _websiteController.text,
      fileName: fileName,
      selectedStream: _selectedStream,
    );

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ダウンロードキューに追加しました')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新規ダウンロード'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ステップ1: WebサイトURLを入力',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _websiteController,
                      decoration: const InputDecoration(
                        labelText: 'WebサイトURL',
                        hintText: 'https://example.com/video',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.link),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _isDetecting ? null : _detectM3U8,
                      icon: _isDetecting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search),
                      label: Text(_isDetecting ? '検出中...' : '動画URLを検出'),
                    ),
                  ],
                ),
              ),
            ),
            
            if (_detectedUrls.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ステップ2: 動画URLを選択',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Text('${_detectedUrls.length}個の動画URLが見つかりました'),
                      const SizedBox(height: 8),
                      ..._detectedUrls.map((url) => RadioListTile<String>(
                        title: Text(
                          url,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        value: url,
                        groupValue: _selectedM3u8Url,
                        onChanged: (value) {
                          setState(() {
                            _selectedM3u8Url = value;
                            _availableStreams = null;
                            _selectedStream = null;
                          });
                          _loadAvailableStreams();
                        },
                      )),
                    ],
                  ),
                ),
              ),
            ],

            if (_availableStreams != null && _availableStreams!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ステップ3: 品質を選択',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      if (_isLoadingStreams)
                        const Center(child: CircularProgressIndicator())
                      else
                        ..._availableStreams!.map((stream) => RadioListTile<M3U8Stream>(
                          title: Text(stream.displayName),
                          subtitle: stream.bandwidth != null
                              ? Text('${(stream.bandwidth! / 1000000).toStringAsFixed(2)} Mbps')
                              : null,
                          value: stream,
                          groupValue: _selectedStream,
                          onChanged: (value) {
                            setState(() => _selectedStream = value);
                          },
                        )),
                    ],
                  ),
                ),
              ),
            ],

            if (_selectedM3u8Url != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ステップ4: オプション設定',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _fileNameController,
                        decoration: const InputDecoration(
                          labelText: 'ファイル名（オプション）',
                          hintText: '例: my_video',
                          border: OutlineInputBorder(),
                          helperText: '空欄の場合は自動生成されます',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text('出力形式: '),
                          const SizedBox(width: 16),
                          ChoiceChip(
                            label: const Text('MP4'),
                            selected: _outputFormat == 'mp4',
                            onSelected: (selected) {
                              setState(() => _outputFormat = 'mp4');
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('MKV'),
                            selected: _outputFormat == 'mkv',
                            onSelected: (selected) {
                              setState(() => _outputFormat = 'mkv');
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _addToQueue,
                icon: const Icon(Icons.download),
                label: const Text('ダウンロード開始'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
