import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/download_provider.dart';
import '../models/m3u8_stream.dart';

class UrlInputScreen extends StatefulWidget {
  const UrlInputScreen({super.key});

  @override
  State<UrlInputScreen> createState() => _UrlInputScreenState();
}

class _UrlInputScreenState extends State<UrlInputScreen> {
  final _m3u8UrlController = TextEditingController();
  final _fileNameController = TextEditingController();
  
  String? _selectedM3u8Url;
  String? _selectedLocalFilePath;
  List<M3U8Stream>? _availableStreams;
  M3U8Stream? _selectedStream;
  bool _isLoadingStreams = false;
  String _outputFormat = 'mp4';
  bool _isLocalFile = false;

  @override
  void dispose() {
    _m3u8UrlController.dispose();
    _fileNameController.dispose();
    super.dispose();
  }

  Future<void> _setM3u8Url() async {
    final url = _m3u8UrlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('M3U8のURLを入力してください')),
      );
      return;
    }

    if (!url.toLowerCase().contains('.m3u8')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('M3U8形式のURLを入力してください（.m3u8を含むURL）'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _selectedM3u8Url = url;
      _isLocalFile = false;
      _selectedLocalFilePath = null;
      _availableStreams = null;
      _selectedStream = null;
    });

    await _loadAvailableStreams();
  }

  Future<void> _loadAvailableStreams() async {
    if (_selectedM3u8Url == null && _selectedLocalFilePath == null) return;

    setState(() => _isLoadingStreams = true);

    final provider = context.read<DownloadProvider>();
    final streams = _isLocalFile
        ? await provider.getAvailableLocalStreams(_selectedLocalFilePath!)
        : await provider.getAvailableStreams(_selectedM3u8Url!);

    // DRM/暗号化ストリームをフィルタ（警告表示）
    final encryptedStreams = streams.where((s) => s.isEncrypted || s.keyUri != null).toList();
    final safeStreams = streams.where((s) => !s.isEncrypted && s.keyUri == null).toList();

    if (encryptedStreams.isNotEmpty && safeStreams.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'このストリームはDRM保護されているため処理できません。\n'
            '本ソフトウェアは暗号化コンテンツに対応していません。',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    }

    setState(() {
      _availableStreams = safeStreams;
      _selectedStream = safeStreams.isNotEmpty ? safeStreams.first : null;
      _isLoadingStreams = false;
    });
  }

  Future<void> _pickLocalFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['m3u8'],
        dialogTitle: 'M3U8ファイルを選択',
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedLocalFilePath = result.files.single.path!;
          _isLocalFile = true;
          _selectedM3u8Url = null;
          _availableStreams = null;
          _selectedStream = null;
        });
        _loadAvailableStreams();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ファイル選択エラー: $e')),
        );
      }
    }
  }

  Future<void> _addToQueue() async {
    if (_selectedM3u8Url == null && _selectedLocalFilePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('M3U8 URLまたはファイルを指定してください')),
      );
      return;
    }

    final fileName = _fileNameController.text.trim().isEmpty
        ? null
        : '${_fileNameController.text.trim()}.$_outputFormat';

    final provider = context.read<DownloadProvider>();
    
    if (_isLocalFile && _selectedLocalFilePath != null) {
      await provider.addLocalDownloadTask(
        m3u8FilePath: _selectedLocalFilePath!,
        fileName: fileName,
        selectedStream: _selectedStream,
      );
    } else {
      await provider.addDownloadTask(
        m3u8Url: _selectedM3u8Url!,
        websiteUrl: _selectedM3u8Url!, // M3U8 URL自体を記録
        fileName: fileName,
        selectedStream: _selectedStream,
      );
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('アーカイブキューに追加しました')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新規アーカイブ'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 注意書き
            Card(
              color: Colors.amber[50],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber[800], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '本ソフトウェアは著作権者自身の配信管理用途専用です。\n'
                        '権利を持つHLSストリームのURLを直接入力してください。',
                        style: TextStyle(fontSize: 12, color: Colors.amber[900]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ステップ1: M3U8 URLを入力',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _m3u8UrlController,
                      decoration: const InputDecoration(
                        labelText: 'M3U8 URL',
                        hintText: 'https://example.com/stream/playlist.m3u8',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.link),
                        helperText: '自分が権利を持つHLSストリームのURLを入力',
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _isLoadingStreams ? null : _setM3u8Url,
                      icon: _isLoadingStreams
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(_isLoadingStreams ? '解析中...' : 'ストリーム解析'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),
            Center(
              child: Text(
                'または',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
              ),
            ),
            const SizedBox(height: 8),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ローカルM3U8ファイルを選択',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    if (_selectedLocalFilePath != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.insert_drive_file, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedLocalFilePath!,
                                style: const TextStyle(fontSize: 12),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                setState(() {
                                  _selectedLocalFilePath = null;
                                  _isLocalFile = false;
                                  _availableStreams = null;
                                  _selectedStream = null;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    ElevatedButton.icon(
                      onPressed: _pickLocalFile,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('M3U8ファイルを選択'),
                    ),
                  ],
                ),
              ),
            ),

            if (_availableStreams != null && _availableStreams!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ステップ2: 品質を選択',
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

            if (_selectedM3u8Url != null || _selectedLocalFilePath != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ステップ3: オプション設定',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _fileNameController,
                        decoration: const InputDecoration(
                          labelText: 'ファイル名（オプション）',
                          hintText: '例: my_archive',
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
                icon: const Icon(Icons.archive),
                label: const Text('アーカイブ開始'),
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
