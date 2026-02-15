import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as win_webview;

enum _SortMode {
  recent,
  duration,
  size,
}

class _DetectedItem {
  _DetectedItem({required this.url, required this.detectedAt});

  final String url;
  final DateTime detectedAt;
  bool isLoading = false;
  Duration? duration;
  int? estimatedSizeBytes;
}

class WebViewDetectScreen extends StatefulWidget {
  const WebViewDetectScreen({super.key, required this.initialUrl});

  final String initialUrl;

  @override
  State<WebViewDetectScreen> createState() => _WebViewDetectScreenState();
}

class _WebViewDetectScreenState extends State<WebViewDetectScreen> {
  WebViewController? _controller;
  win_webview.WebviewController? _windowsController;
  final Map<String, _DetectedItem> _detectedByUrl = {};
  String? _currentUrl;
  bool _isLoading = true;
  String? _selectedUrl;
  bool _windowsReady = false;
  _SortMode _sortMode = _SortMode.size;
  bool _sortDescending = true;
  final Dio _dio = Dio();
  bool _autoSelectLargest = true;

  @override
  void initState() {
    super.initState();

    if (!_isSupportedPlatform()) {
      return;
    }

    if (Platform.isWindows) {
      _initializeWindowsWebView();
    } else {
      _initializeFlutterWebView();
    }
  }

  bool _isSupportedPlatform() {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows;
  }

  void _initializeFlutterWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      )
      ..addJavaScriptChannel(
        'M3U8Detector',
        onMessageReceived: (message) {
          _handleDetectedUrl(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              _currentUrl = url;
              _isLoading = true;
            });
          },
          onPageFinished: (url) async {
            _currentUrl = url;
            await _injectHookScriptFlutter();
            setState(() => _isLoading = false);
          },
          onUrlChange: (change) {
            if (change.url != null) {
              _currentUrl = change.url;
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  Future<void> _initializeWindowsWebView() async {
    final controller = win_webview.WebviewController();
    await controller.initialize();
    controller.setBackgroundColor(Colors.white);
    controller.webMessage.listen((message) => _handleDetectedUrl(message.toString()));
    controller.url.listen((url) {
      setState(() => _currentUrl = url);
    });
    controller.loadingState.listen((state) async {
      final isLoading = state == win_webview.LoadingState.loading;
      setState(() => _isLoading = isLoading);
      if (state == win_webview.LoadingState.navigationCompleted) {
        await _injectHookScriptWindows(controller);
      }
    });

    await controller.loadUrl(widget.initialUrl);
    if (!mounted) return;

    setState(() {
      _windowsController = controller;
      _windowsReady = true;
    });
  }

  void _handleDetectedUrl(String rawUrl) {
    final resolved = _resolvePossibleUrl(_currentUrl, rawUrl);
    if (!resolved.toLowerCase().contains('.m3u8')) {
      return;
    }

    if (_detectedByUrl.containsKey(resolved)) {
      return;
    }

    final item = _DetectedItem(url: resolved, detectedAt: DateTime.now());

    setState(() {
      _detectedByUrl[resolved] = item;
      _selectedUrl ??= resolved;
    });

    _fetchMetadata(item);
  }

  Future<void> _fetchMetadata(_DetectedItem item) async {
    if (item.isLoading) return;
    setState(() => item.isLoading = true);

    try {
      final info = await _loadM3u8Info(item.url);
      setState(() {
        item.duration = info.duration;
        item.estimatedSizeBytes = info.estimatedSizeBytes;
        item.isLoading = false;
      });
      _autoSelectBestCandidate();
    } catch (e) {
      setState(() => item.isLoading = false);
    }
  }

  Future<_M3u8Info> _loadM3u8Info(String m3u8Url) async {
    final response = await _dio.get(
      m3u8Url,
      options: Options(
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
          'Referer': _currentUrl ?? m3u8Url,
          'Accept': '*/*',
        },
        responseType: ResponseType.plain,
      ),
    );

    final content = response.data.toString();
    final lines = content.split('\n').map((line) => line.trim()).toList();
    final segmentUrls = <String>[];
    double durationSeconds = 0.0;

    for (final line in lines) {
      if (line.startsWith('#EXTINF:')) {
        final value = line.substring(8);
        final commaIndex = value.indexOf(',');
        final numberText = commaIndex == -1 ? value : value.substring(0, commaIndex);
        final seconds = double.tryParse(numberText);
        if (seconds != null) {
          durationSeconds += seconds;
        }
        continue;
      }
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      segmentUrls.add(_resolvePossibleUrl(m3u8Url, line));
    }

    int? estimatedSizeBytes;
    if (segmentUrls.isNotEmpty) {
      estimatedSizeBytes = await _estimateTotalSize(segmentUrls);
    }

    return _M3u8Info(
      duration: durationSeconds > 0
          ? Duration(milliseconds: (durationSeconds * 1000).round())
          : null,
      estimatedSizeBytes: estimatedSizeBytes,
    );
  }

  Future<int?> _estimateTotalSize(List<String> segmentUrls) async {
    const sampleCount = 5;
    final targets = segmentUrls.take(sampleCount).toList();
    int totalSampleBytes = 0;
    int sampled = 0;

    for (final url in targets) {
      final size = await _fetchContentLength(url);
      if (size != null && size > 0) {
        totalSampleBytes += size;
        sampled++;
      }
    }

    if (sampled == 0) {
      return null;
    }

    final average = (totalSampleBytes / sampled).round();
    return average * segmentUrls.length;
  }

  Future<int?> _fetchContentLength(String url) async {
    try {
      final headResponse = await _dio.head(
        url,
        options: Options(
          headers: {
            'Referer': _currentUrl ?? url,
            'Accept': '*/*',
          },
          followRedirects: true,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final lengthHeader = headResponse.headers.value('content-length');
      final length = int.tryParse(lengthHeader ?? '');
      if (length != null && length > 0) {
        return length;
      }
    } catch (e) {
      // Fallback below.
    }

    try {
      final rangeResponse = await _dio.get(
        url,
        options: Options(
          headers: {
            'Referer': _currentUrl ?? url,
            'Range': 'bytes=0-0',
          },
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      final contentRange = rangeResponse.headers.value('content-range');
      if (contentRange != null) {
        final parts = contentRange.split('/');
        if (parts.length == 2) {
          final total = int.tryParse(parts[1]);
          if (total != null && total > 0) {
            return total;
          }
        }
      }

      final lengthHeader = rangeResponse.headers.value('content-length');
      final length = int.tryParse(lengthHeader ?? '');
      if (length != null && length > 0) {
        return length;
      }
    } catch (e) {
      return null;
    }

    return null;
  }

  String get _hookScript => """
(function() {
  if (window.__m3u8_hooked) return;
  window.__m3u8_hooked = true;

  function postMessage(value) {
    try {
      if (window.M3U8Detector && typeof M3U8Detector.postMessage === 'function') {
        M3U8Detector.postMessage(value);
        return;
      }
      if (window.chrome && window.chrome.webview && typeof window.chrome.webview.postMessage === 'function') {
        window.chrome.webview.postMessage(value);
      }
    } catch (e) {}
  }

  function emit(url) {
    try {
      if (!url) return;
      var value = String(url);
      if (value.toLowerCase().indexOf('.m3u8') === -1) return;
      postMessage(value);
    } catch (e) {}
  }

  var originalFetch = window.fetch;
  if (originalFetch) {
    window.fetch = function() {
      try {
        var input = arguments[0];
        var url = input && (input.url || input);
        emit(url);
      } catch (e) {}
      return originalFetch.apply(this, arguments).then(function(resp) {
        try { emit(resp.url); } catch (e) {}
        return resp;
      });
    };
  }

  var originalOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url) {
    try { emit(url); } catch (e) {}
    return originalOpen.apply(this, arguments);
  };

  var originalSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function() {
    this.addEventListener('load', function() {
      try { emit(this.responseURL); } catch (e) {}
    });
    return originalSend.apply(this, arguments);
  };

  var originalSetAttribute = Element.prototype.setAttribute;
  Element.prototype.setAttribute = function(name, value) {
    try {
      if (String(name).toLowerCase() === 'src') {
        emit(value);
      }
    } catch (e) {}
    return originalSetAttribute.apply(this, arguments);
  };
})();
""";

  Future<void> _injectHookScriptFlutter() async {
    final controller = _controller;
    if (controller == null) return;

    try {
      await controller.runJavaScript(_hookScript);
    } catch (e) {
      // Ignore injection failures.
    }
  }

  Future<void> _injectHookScriptWindows(win_webview.WebviewController controller) async {
    try {
      await controller.executeScript(_hookScript);
    } catch (e) {
      // Ignore injection failures.
    }
  }

  String _resolvePossibleUrl(String? baseUrl, String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('//')) {
      try {
        final baseUri = Uri.parse(baseUrl ?? widget.initialUrl);
        return '${baseUri.scheme}:$trimmed';
      } catch (e) {
        return trimmed;
      }
    }
    try {
      final baseUri = Uri.parse(baseUrl ?? widget.initialUrl);
      return baseUri.resolve(trimmed).toString();
    } catch (e) {
      return trimmed;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSupportedPlatform()) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('WebView検出'),
        ),
        body: const Center(
          child: Text('このプラットフォームではWebView検出が利用できません。'),
        ),
      );
    }

    final isWindows = Platform.isWindows;
    final canReload = isWindows ? _windowsReady : _controller != null;
    final items = _sortedItems();

    return Scaffold(
      appBar: AppBar(
        title: const Text('WebView検出'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: !canReload
                ? null
                : () {
                    if (isWindows) {
                      _windowsController?.reload();
                    } else {
                      _controller?.reload();
                    }
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_currentUrl != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.link, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _currentUrl!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          if (_isLoading)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: isWindows
                ? (_windowsReady
                    ? win_webview.Webview(_windowsController!)
                    : const Center(child: CircularProgressIndicator()))
                : WebViewWidget(controller: _controller!),
          ),
          if (items.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('検出されたM3U8'),
                      const SizedBox(width: 8),
                      Text(
                        '(${items.length})',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Spacer(),
                      DropdownButton<_SortMode>(
                        value: _sortMode,
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _sortMode = value);
                        },
                        items: const [
                          DropdownMenuItem(
                            value: _SortMode.recent,
                            child: Text('新着順'),
                          ),
                          DropdownMenuItem(
                            value: _SortMode.duration,
                            child: Text('長さ順'),
                          ),
                          DropdownMenuItem(
                            value: _SortMode.size,
                            child: Text('サイズ順'),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(
                          _sortDescending ? Icons.arrow_downward : Icons.arrow_upward,
                          size: 18,
                        ),
                        onPressed: () {
                          setState(() => _sortDescending = !_sortDescending);
                        },
                      ),
                      IconButton(
                        tooltip: _autoSelectLargest ? '自動選択オン' : '自動選択オフ',
                        icon: Icon(
                          _autoSelectLargest ? Icons.star : Icons.star_border,
                          size: 18,
                        ),
                        onPressed: () {
                          setState(() => _autoSelectLargest = !_autoSelectLargest);
                          if (_autoSelectLargest) {
                            _autoSelectBestCandidate();
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 180,
                    child: ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final isRecent = DateTime.now().difference(item.detectedAt).inSeconds < 10;
                        final subtitle = _formatMetadata(item);

                        return RadioListTile<String>(
                          value: item.url,
                          groupValue: _selectedUrl,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(
                            item.url,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          subtitle: subtitle == null
                              ? null
                              : Text(
                                  subtitle,
                                  style: const TextStyle(fontSize: 11),
                                ),
                          secondary: isRecent
                              ? const Icon(Icons.fiber_new, size: 18)
                              : null,
                          onChanged: (value) {
                            setState(() => _selectedUrl = value);
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _selectedUrl == null
                              ? null
                              : () {
                                  Navigator.pop(context, _selectedUrl);
                                },
                          icon: const Icon(Icons.check),
                          label: const Text('このURLを使用'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<_DetectedItem> _sortedItems() {
    final items = _detectedByUrl.values.toList();

    int compareNullableInt(int? a, int? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.compareTo(b);
    }

    int compareNullableDuration(Duration? a, Duration? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.compareTo(b);
    }

    items.sort((a, b) {
      int result;
      switch (_sortMode) {
        case _SortMode.duration:
          result = compareNullableDuration(a.duration, b.duration);
          break;
        case _SortMode.size:
          result = compareNullableInt(a.estimatedSizeBytes, b.estimatedSizeBytes);
          break;
        case _SortMode.recent:
          result = a.detectedAt.compareTo(b.detectedAt);
          break;
      }

      return _sortDescending ? -result : result;
    });

    return items;
  }

  void _autoSelectBestCandidate() {
    if (!_autoSelectLargest || _detectedByUrl.isEmpty) {
      return;
    }

    _DetectedItem? best;
    for (final item in _detectedByUrl.values) {
      if (best == null || _isBetterCandidate(item, best)) {
        best = item;
      }
    }

    if (best != null && best.url != _selectedUrl) {
      setState(() => _selectedUrl = best!.url);
    }
  }

  bool _isBetterCandidate(_DetectedItem candidate, _DetectedItem current) {
    if (candidate.estimatedSizeBytes != null || current.estimatedSizeBytes != null) {
      final candidateSize = candidate.estimatedSizeBytes ?? -1;
      final currentSize = current.estimatedSizeBytes ?? -1;
      if (candidateSize != currentSize) {
        return candidateSize > currentSize;
      }
    }

    if (candidate.duration != null || current.duration != null) {
      final candidateDuration = candidate.duration?.inMilliseconds ?? -1;
      final currentDuration = current.duration?.inMilliseconds ?? -1;
      if (candidateDuration != currentDuration) {
        return candidateDuration > currentDuration;
      }
    }

    return candidate.detectedAt.isAfter(current.detectedAt);
  }

  String? _formatMetadata(_DetectedItem item) {
    final durationText = item.duration == null ? null : _formatDuration(item.duration!);
    final sizeText = item.estimatedSizeBytes == null ? null : _formatBytes(item.estimatedSizeBytes!);

    if (item.isLoading && durationText == null && sizeText == null) {
      return 'メタ情報を取得中...';
    }

    if (durationText == null && sizeText == null) {
      return null;
    }

    final parts = <String>[];
    if (durationText != null) {
      parts.add('長さ $durationText');
    }
    if (sizeText != null) {
      parts.add('サイズ 約$sizeText');
    } else if (item.isLoading) {
      parts.add('サイズ 取得中');
    }

    return parts.join(' / ');
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    int unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    return '${value.toStringAsFixed(unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
  }
}

class _M3u8Info {
  _M3u8Info({this.duration, this.estimatedSizeBytes});

  final Duration? duration;
  final int? estimatedSizeBytes;
}
