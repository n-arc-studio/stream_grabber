import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import '../models/m3u8_stream.dart';
import 'dart:io';

class M3U8Parser {
  final Dio _dio = Dio(
    BaseOptions(
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
        'Accept-Language': 'ja-JP,ja;q=0.9,en-US;q=0.8,en;q=0.7',
        'Accept-Encoding': 'gzip, deflate, br',
        'Sec-Ch-Ua': '"Google Chrome";v="131", "Chromium";v="131", "Not_A Brand";v="24"',
        'Sec-Ch-Ua-Mobile': '?0',
        'Sec-Ch-Ua-Platform': '"Windows"',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'none',
        'Sec-Fetch-User': '?1',
        'Upgrade-Insecure-Requests': '1',
        'Connection': 'keep-alive',
        'DNT': '1',
      },
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: true,
      maxRedirects: 5,
    ),
  );

  // 訪問済みURLを追跡（循環参照を防ぐ）
  final Set<String> _visitedUrls = {};

  // WebページからM3U8およびMP4 URLを検出
  Future<List<String>> detectM3U8FromWebsite(String websiteUrl, {int depth = 0}) async {
    // 深さ制限（無限ループ防止）
    if (depth > 2) {
      print('Max depth reached for: $websiteUrl');
      return [];
    }

    // 訪問済みURLチェック（循環参照防止）
    if (_visitedUrls.contains(websiteUrl)) {
      return [];
    }
    _visitedUrls.add(websiteUrl);

    try {
      print('Fetching URL: $websiteUrl (depth: $depth)');
      
      // まずリダイレクトなしで取得を試みる
      Response response;
      try {
        response = await _dio.get(
          websiteUrl,
          options: Options(
            headers: {
              'Referer': websiteUrl,
              'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            },
            followRedirects: false, // リダイレクトを無効化
            validateStatus: (status) => status! < 400, // 3xxも成功として扱う
          ),
        );
      } catch (e) {
        // リダイレクトエラーの場合、通常通り取得
        print('Retry with redirects enabled');
        response = await _dio.get(
          websiteUrl,
          options: Options(
            headers: {
              'Referer': websiteUrl,
            },
          ),
        );
      }
      
      final document = html_parser.parse(response.data);
      final bodyText = response.data.toString();
      
      print('Response status: ${response.statusCode}');
      print('Content length: ${bodyText.length}');
      print('Final URL: ${response.realUri}');
      
      final List<String> videoUrls = [];
      final Set<String> urlSet = {}; // 重複除去用

      // 1. iframeのsrc属性を検索（埋め込み動画）
      final iframes = document.getElementsByTagName('iframe');
      print('Found ${iframes.length} iframe(s)');
      
      for (var iframe in iframes) {
        final src = iframe.attributes['src'] ?? 
                    iframe.attributes['data-src'] ?? 
                    iframe.attributes['data-lazy-src'];
        if (src != null && src.isNotEmpty) {
          print('iframe src: $src');
          
          // 相対URLを絶対URLに変換
          String iframeSrc = src;
          if (!src.startsWith('http')) {
            final baseUri = Uri.parse(websiteUrl);
            if (src.startsWith('//')) {
              iframeSrc = '${baseUri.scheme}:$src';
            } else if (src.startsWith('/')) {
              iframeSrc = '${baseUri.scheme}://${baseUri.host}$src';
            } else {
              iframeSrc = '${baseUri.scheme}://${baseUri.host}/${baseUri.path}/$src';
            }
          }
          
          // 広告ドメインをスキップ
          if (!_isAdDomain(iframeSrc)) {
            try {
              print('Fetching iframe content: $iframeSrc');
              final iframeUrls = await detectM3U8FromWebsite(iframeSrc, depth: depth + 1);
              if (iframeUrls.isNotEmpty) {
                print('Found ${iframeUrls.length} URL(s) in iframe');
                urlSet.addAll(iframeUrls);
              }
            } catch (e) {
              print('Failed to fetch iframe: $iframeSrc - $e');
            }
          } else {
            print('Skipping ad domain: $iframeSrc');
          }
        }
      }

      // 2. scriptタグ内の動画URLを検索（複数パターン）
      final scripts = document.getElementsByTagName('script');
      print('Found ${scripts.length} script tag(s)');
      
      for (var script in scripts) {
        final content = script.text;
        if (content.isEmpty) continue;
        
        // エスケープされたURLも検出（\/ を / に置換して検索）
        final unescapedContent = content.replaceAll(r'\/', '/');
        
        // M3U8 URLを検索（より柔軟なパターン）
        final m3u8Patterns = [
          RegExp(r'https?://[^\s"<>\\]+\.m3u8[^\s"<>\\]*', caseSensitive: false),
          RegExp(r'''["']([^"']*\.m3u8[^"']*)["']''', caseSensitive: false),
          RegExp(r'''file["\s]*:["\s]*["']([^"']*\.m3u8[^"']*)["']''', caseSensitive: false),
          RegExp(r'''source["\s]*:["\s]*["']([^"']*\.m3u8[^"']*)["']''', caseSensitive: false),
        ];
        
        for (var pattern in m3u8Patterns) {
          final matches = pattern.allMatches(unescapedContent);
          for (var match in matches) {
            final url = match.group(1) ?? match.group(0);
            if (url != null && url.contains('.m3u8')) {
              final cleanUrl = _cleanUrl(url);
              if (cleanUrl.isNotEmpty && _isValidUrl(cleanUrl)) {
                print('Found M3U8 in script: $cleanUrl');
                urlSet.add(cleanUrl);
              }
            }
          }
        }
        
        // MP4 URLを検索
        final mp4Patterns = [
          RegExp(r'https?://[^\s"<>\\]+\.mp4[^\s"<>\\]*', caseSensitive: false),
          RegExp(r'''["']([^"']*\.mp4[^"']*)["']''', caseSensitive: false),
          RegExp(r'''file["\s]*:["\s]*["']([^"']*\.mp4[^"']*)["']''', caseSensitive: false),
          RegExp(r'''source["\s]*:["\s]*["']([^"']*\.mp4[^"']*)["']''', caseSensitive: false),
        ];
        
        for (var pattern in mp4Patterns) {
          final matches = pattern.allMatches(unescapedContent);
          for (var match in matches) {
            final url = match.group(1) ?? match.group(0);
            if (url != null && url.contains('.mp4')) {
              final cleanUrl = _cleanUrl(url);
              if (cleanUrl.isNotEmpty && _isValidUrl(cleanUrl)) {
                print('Found MP4 in script: $cleanUrl');
                urlSet.add(cleanUrl);
              }
            }
          }
        }
      }

      // 3. videoタグのsrc属性を検索
      final videos = document.getElementsByTagName('video');
      for (var video in videos) {
        final src = video.attributes['src'] ?? video.attributes['data-src'];
        if (src != null && (src.contains('.m3u8') || src.contains('.mp4'))) {
          final cleanUrl = _cleanUrl(src);
          if (cleanUrl.isNotEmpty && _isValidUrl(cleanUrl)) {
            urlSet.add(cleanUrl);
          }
        }
      }

      // 4. sourceタグを検索
      final sources = document.getElementsByTagName('source');
      for (var source in sources) {
        final src = source.attributes['src'] ?? source.attributes['data-src'];
        if (src != null && (src.contains('.m3u8') || src.contains('.mp4'))) {
          final cleanUrl = _cleanUrl(src);
          if (cleanUrl.isNotEmpty && _isValidUrl(cleanUrl)) {
            urlSet.add(cleanUrl);
          }
        }
      }

      // 5. data-*属性からURLを検索
      final allElements = document.querySelectorAll('[data-video], [data-src], [data-source], [data-url]');
      for (var element in allElements) {
        final dataVideo = element.attributes['data-video'];
        final dataSrc = element.attributes['data-src'];
        final dataSource = element.attributes['data-source'];
        final dataUrl = element.attributes['data-url'];
        
        for (var attr in [dataVideo, dataSrc, dataSource, dataUrl]) {
          if (attr != null && (attr.contains('.m3u8') || attr.contains('.mp4'))) {
            final cleanUrl = _cleanUrl(attr);
            if (cleanUrl.isNotEmpty && _isValidUrl(cleanUrl)) {
              urlSet.add(cleanUrl);
            }
          }
        }
      }

      // 6. ページ全体のテキストから検索（fallback）
      if (urlSet.isEmpty) {
        print('Searching entire page for video URLs...');
        final unescapedBody = bodyText.replaceAll(r'\/', '/');
        
        // M3U8検索
        final allM3u8 = RegExp(r'https?://[^\s"<>\\]+\.m3u8[^\s"<>\\]*', caseSensitive: false)
            .allMatches(unescapedBody);
        for (var match in allM3u8) {
          final url = match.group(0);
          if (url != null) {
            final cleanUrl = _cleanUrl(url);
            if (cleanUrl.isNotEmpty && _isValidUrl(cleanUrl)) {
              urlSet.add(cleanUrl);
            }
          }
        }
        
        // MP4検索
        final allMp4 = RegExp(r'https?://[^\s"<>\\]+\.mp4[^\s"<>\\]*', caseSensitive: false)
            .allMatches(unescapedBody);
        for (var match in allMp4) {
          final url = match.group(0);
          if (url != null) {
            final cleanUrl = _cleanUrl(url);
            if (cleanUrl.isNotEmpty && _isValidUrl(cleanUrl)) {
              urlSet.add(cleanUrl);
            }
          }
        }
        
        // MPD検索 (MPEG-DASH)
        final allMpd = RegExp(r'https?://[^\s"<>\\]+\.mpd[^\s"<>\\]*', caseSensitive: false)
            .allMatches(unescapedBody);
        for (var match in allMpd) {
          final url = match.group(0);
          if (url != null) {
            final cleanUrl = _cleanUrl(url);
            if (cleanUrl.isNotEmpty && _isValidUrl(cleanUrl)) {
              print('Found MPD URL: $cleanUrl');
              urlSet.add(cleanUrl);
            }
          }
        }
      }

      // 7. embedドメインや動画ホスティングサービスのURLを検出
      final embedPatterns = [
        RegExp(r'https?://[^/]*(?:embed|player|video)[^/]*/[^\s"<>]+', caseSensitive: false),
        RegExp(r'https?://(?:www\.)?(?:youtube\.com|youtu\.be|vimeo\.com|dailymotion\.com)/[^\s"<>]+', caseSensitive: false),
      ];
      
      for (var pattern in embedPatterns) {
        final matches = pattern.allMatches(bodyText);
        for (var match in matches) {
          final url = match.group(0);
          if (url != null && _isValidUrl(url)) {
            print('Found embed URL: $url');
            // embedページを再帰的に検索
            if (depth < 2) {
              try {
                final embedUrls = await detectM3U8FromWebsite(url, depth: depth + 1);
                urlSet.addAll(embedUrls);
              } catch (e) {
                print('Failed to fetch embed URL: $url - $e');
              }
            }
          }
        }
      }

      videoUrls.addAll(urlSet);
      
      // デバッグ情報
      if (videoUrls.isEmpty) {
        print('No video URLs found on page: $websiteUrl');
        print('Page title: ${document.querySelector('title')?.text ?? 'N/A'}');
      } else {
        print('Found ${videoUrls.length} video URL(s)');
      }

      return videoUrls;
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        print('========================================');
        print('403 Access Denied: $websiteUrl');
        print('Website is blocking automated access');
        print('Possible causes: Cloudflare, geographic restrictions, required authentication');
        print('Solution: Use browser DevTools (F12 > Network tab) to find actual video URL');
        print('========================================');
      } else if (e.response?.statusCode == 404) {
        print('Error: Page not found (404). Please check the URL.');
      } else if (e.response?.statusCode == 429) {
        print('Error: Too many requests (429). Please wait before retrying.');
      } else {
        print('Error detecting video URLs: ${e.message}');
        print('Status code: ${e.response?.statusCode}');
      }
      return [];
    } catch (e) {
      print('Error detecting video URLs: $e');
      return [];
    }
  }

  // URLをクリーンアップ
  String _cleanUrl(String url) {
    // 前後の空白や引用符を削除
    var cleaned = url.trim().replaceAll('"', '').replaceAll("'", '');
    
    // エスケープされたスラッシュを戻す
    cleaned = cleaned.replaceAll(r'\/', '/');
    
    // URLの末尾の不要な文字を削除
    cleaned = cleaned.replaceAll(RegExp(r'[,;}\]]+$'), '');
    
    return cleaned;
  }

  // URLが有効かチェック
  bool _isValidUrl(String url) {
    if (url.isEmpty) return false;
    
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  // 広告ドメインかチェック
  bool _isAdDomain(String url) {
    final adDomains = [
      'doubleclick.net',
      'googlesyndication.com',
      'googleadservices.com',
      'adnxs.com',
      'adsystem.com',
      'advertising.com',
      'exoclick.com',
      'exosrv.com',
      'trafficjunky.com',
      'trafficjunky.net',
      'clickadu.com',
      'popads.net',
      'popcash.net',
      'adsterra.com',
      'propellerads.com',
      'myavlive.com', // 今回のケース
      'juicyads.com',
      'ads-display.com',
    ];
    
    try {
      final uri = Uri.parse(url);
      return adDomains.any((ad) => uri.host.contains(ad));
    } catch (e) {
      return false;
    }
  }

  // M3U8ファイルを解析
  Future<M3U8Stream> parseM3U8(String m3u8Url) async {
    try {
      final response = await _dio.get(
        m3u8Url,
        options: Options(
          headers: {
            'Referer': m3u8Url,
          },
        ),
      );
      final content = response.data as String;
      final lines = content.split('\n').map((line) => line.trim()).toList();

      // マスタープレイリストかどうかを確認
      final isMasterPlaylist = lines.any((line) => line.startsWith('#EXT-X-STREAM-INF'));

      if (isMasterPlaylist) {
        // マスタープレイリストの場合、最高品質のストリームを選択
        return _parseMasterPlaylist(m3u8Url, lines);
      } else {
        // メディアプレイリストの場合、セグメントURLを抽出
        return _parseMediaPlaylist(m3u8Url, lines);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        throw Exception('アクセスが拒否されました (403)。このストリームは認証が必要か、アクセスが制限されている可能性があります。');
      } else if (e.response?.statusCode == 404) {
        throw Exception('M3U8ファイルが見つかりません (404)。URLを確認してください。');
      } else if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
        throw Exception('接続タイムアウト。ネットワーク接続を確認してください。');
      } else {
        throw Exception('M3U8の解析に失敗しました: ${e.message}');
      }
    } catch (e) {
      print('Error parsing M3U8: $e');
      rethrow;
    }
  }

  M3U8Stream _parseMasterPlaylist(String baseUrl, List<String> lines) {
    int maxBandwidth = 0;
    String? bestQualityUrl;
    String? resolution;

    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('#EXT-X-STREAM-INF')) {
        final info = lines[i];
        final bandwidthMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(info);
        final resolutionMatch = RegExp(r'RESOLUTION=([\d]+x[\d]+)').firstMatch(info);

        if (bandwidthMatch != null) {
          final bandwidth = int.parse(bandwidthMatch.group(1)!);
          if (bandwidth > maxBandwidth) {
            maxBandwidth = bandwidth;
            resolution = resolutionMatch?.group(1);
            
            // 次の行がURL
            if (i + 1 < lines.length && !lines[i + 1].startsWith('#')) {
              bestQualityUrl = _resolveUrl(baseUrl, lines[i + 1]);
            }
          }
        }
      }
    }

    return M3U8Stream(
      url: bestQualityUrl ?? baseUrl,
      quality: 'Best',
      bandwidth: maxBandwidth,
      resolution: resolution,
    );
  }

  Future<M3U8Stream> _parseMediaPlaylist(String baseUrl, List<String> lines) async {
    final List<String> segmentUrls = [];
    bool isEncrypted = false;
    String? keyUri;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.startsWith('#EXT-X-KEY')) {
        isEncrypted = true;
        final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(line);
        if (uriMatch != null) {
          keyUri = _resolveUrl(baseUrl, uriMatch.group(1)!);
        }
      }

      if (!line.startsWith('#') && line.isNotEmpty) {
        final segmentUrl = _resolveUrl(baseUrl, line);
        segmentUrls.add(segmentUrl);
      }
    }

    return M3U8Stream(
      url: baseUrl,
      quality: 'Standard',
      segmentUrls: segmentUrls,
      isEncrypted: isEncrypted,
      keyUri: keyUri,
    );
  }

  String _resolveUrl(String baseUrl, String relativeUrl) {
    if (relativeUrl.startsWith('http://') || relativeUrl.startsWith('https://')) {
      return relativeUrl;
    }

    final uri = Uri.parse(baseUrl);
    if (relativeUrl.startsWith('/')) {
      return '${uri.scheme}://${uri.host}$relativeUrl';
    } else {
      final basePath = uri.path.substring(0, uri.path.lastIndexOf('/') + 1);
      return '${uri.scheme}://${uri.host}$basePath$relativeUrl';
    }
  }

  // すべての利用可能なストリーム品質を取得
  Future<List<M3U8Stream>> getAllStreams(String m3u8Url) async {
    try {
      final response = await _dio.get(
        m3u8Url,
        options: Options(
          headers: {
            'Referer': m3u8Url,
          },
        ),
      );
      final content = response.data as String;
      final lines = content.split('\n').map((line) => line.trim()).toList();

      final isMasterPlaylist = lines.any((line) => line.startsWith('#EXT-X-STREAM-INF'));

      if (!isMasterPlaylist) {
        // メディアプレイリストの場合、1つだけ返す
        final stream = await parseM3U8(m3u8Url);
        return [stream];
      }

      final List<M3U8Stream> streams = [];

      for (int i = 0; i < lines.length; i++) {
        if (lines[i].startsWith('#EXT-X-STREAM-INF')) {
          final info = lines[i];
          final bandwidthMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(info);
          final resolutionMatch = RegExp(r'RESOLUTION=([\d]+x[\d]+)').firstMatch(info);

          if (i + 1 < lines.length && !lines[i + 1].startsWith('#')) {
            final streamUrl = _resolveUrl(m3u8Url, lines[i + 1]);
            
            streams.add(M3U8Stream(
              url: streamUrl,
              quality: resolutionMatch?.group(1) ?? 'Unknown',
              bandwidth: bandwidthMatch != null 
                  ? int.parse(bandwidthMatch.group(1)!) 
                  : null,
              resolution: resolutionMatch?.group(1),
            ));
          }
        }
      }

      // 帯域幅でソート（高い順）
      streams.sort((a, b) => (b.bandwidth ?? 0).compareTo(a.bandwidth ?? 0));

      return streams;
    } catch (e) {
      print('Error getting all streams: $e');
      return [];
    }
  }

  // 訪問済みURLをクリア（新しい検索を開始する前に呼び出す）
  void clearVisitedUrls() {
    _visitedUrls.clear();
  }

  // ローカルM3U8ファイルを解析
  Future<M3U8Stream> parseLocalM3U8(String filePath) async {
    try {
      print('Parsing local M3U8 file: $filePath');
      
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('ファイルが存在しません: $filePath');
      }

      final content = await file.readAsString();
      if (content.isEmpty) {
        throw Exception('ファイルが空です: $filePath');
      }

      print('File content length: ${content.length}');
      final lines = content.split('\n').map((line) => line.trim()).toList();

      // M3U8ファイルかどうかを確認
      if (!lines.any((line) => line.startsWith('#EXTM3U') || line.startsWith('#EXT-X-'))) {
        throw Exception('有効なM3U8ファイルではありません。#EXTM3Uヘッダーが見つかりませんでした。');
      }

      // マスタープレイリストかどうかを確認
      final isMasterPlaylist = lines.any((line) => line.startsWith('#EXT-X-STREAM-INF'));
      print('Is master playlist: $isMasterPlaylist');

      if (isMasterPlaylist) {
        // マスタープレイリストの場合、最高品質のストリームを選択
        return _parseLocalMasterPlaylist(filePath, lines);
      } else {
        // メディアプレイリストの場合、セグメントURLを抽出
        return await _parseLocalMediaPlaylist(filePath, lines);
      }
    } on FileSystemException catch (e) {
      print('File system error: $e');
      throw Exception('ファイル読み込みエラー: ${e.message}');
    } catch (e, stackTrace) {
      print('Error parsing local M3U8: $e');
      print('Stack trace: $stackTrace');
      throw Exception('M3U8の解析に失敗しました: ${e.toString()}');
    }
  }

  M3U8Stream _parseLocalMasterPlaylist(String baseFilePath, List<String> lines) {
    try {
      int maxBandwidth = 0;
      String? bestQualityUrl;
      String? resolution;

      for (int i = 0; i < lines.length; i++) {
        if (lines[i].startsWith('#EXT-X-STREAM-INF')) {
          final info = lines[i];
          final bandwidthMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(info);
          final resolutionMatch = RegExp(r'RESOLUTION=([\d]+x[\d]+)').firstMatch(info);

          if (bandwidthMatch != null) {
            final bandwidth = int.parse(bandwidthMatch.group(1)!);
            if (bandwidth > maxBandwidth) {
              maxBandwidth = bandwidth;
              resolution = resolutionMatch?.group(1);
              
              // 次の行がURL
              if (i + 1 < lines.length && !lines[i + 1].startsWith('#')) {
                bestQualityUrl = _resolveLocalUrl(baseFilePath, lines[i + 1]);
              }
            }
          }
        }
      }

      if (bestQualityUrl == null) {
        print('Warning: No quality URL found in master playlist, using base file path');
      }

      return M3U8Stream(
        url: bestQualityUrl ?? baseFilePath,
        quality: 'Best',
        bandwidth: maxBandwidth,
        resolution: resolution,
      );
    } catch (e) {
      print('Error parsing local master playlist: $e');
      throw Exception('マスタープレイリストの解析に失敗しました: $e');
    }
  }

  Future<M3U8Stream> _parseLocalMediaPlaylist(String baseFilePath, List<String> lines) async {
    try {
      final List<String> segmentUrls = [];
      bool isEncrypted = false;
      String? keyUri;

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];

        if (line.startsWith('#EXT-X-KEY')) {
          isEncrypted = true;
          final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(line);
          if (uriMatch != null) {
            keyUri = _resolveLocalUrl(baseFilePath, uriMatch.group(1)!);
          }
        }

        if (!line.startsWith('#') && line.isNotEmpty) {
          final segmentUrl = _resolveLocalUrl(baseFilePath, line);
          segmentUrls.add(segmentUrl);
        }
      }

      print('Found ${segmentUrls.length} segments in media playlist');
      if (segmentUrls.isEmpty) {
        throw Exception('セグメントが見つかりませんでした。M3U8ファイルの形式を確認してください。');
      }

      if (isEncrypted) {
        print('Warning: Stream is encrypted');
      }

      return M3U8Stream(
        url: baseFilePath,
        quality: 'Standard',
        segmentUrls: segmentUrls,
        isEncrypted: isEncrypted,
        keyUri: keyUri,
      );
    } catch (e) {
      print('Error parsing local media playlist: $e');
      throw Exception('メディアプレイリストの解析に失敗しました: $e');
    }
  }

  String _resolveLocalUrl(String baseFilePath, String relativeUrl) {
    // 絶対URLの場合はそのまま返す
    if (relativeUrl.startsWith('http://') || 
        relativeUrl.startsWith('https://') ||
        relativeUrl.startsWith('file://')) {
      return relativeUrl;
    }

    // Windowsの絶対パス
    if (relativeUrl.contains(':') && relativeUrl.indexOf(':') == 1) {
      return relativeUrl;
    }

    // Unix/Linuxの絶対パス
    if (relativeUrl.startsWith('/') && !Platform.isWindows) {
      return relativeUrl;
    }

    // 相対パスの場合、baseFilePathのディレクトリを基準に解決
    final baseDir = File(baseFilePath).parent.path;
    
    if (relativeUrl.startsWith('/')) {
      // ルート相対パス（ローカルファイルでは使用しない）
      return '$baseDir$relativeUrl';
    } else {
      // 相対パス
      return '$baseDir${Platform.pathSeparator}$relativeUrl';
    }
  }

  // すべての利用可能なローカルストリーム品質を取得
  Future<List<M3U8Stream>> getAllLocalStreams(String filePath) async {
    try {
      print('Getting all local streams from: $filePath');
      
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('ファイルが存在しません: $filePath');
      }

      final content = await file.readAsString();
      final lines = content.split('\n').map((line) => line.trim()).toList();

      final isMasterPlaylist = lines.any((line) => line.startsWith('#EXT-X-STREAM-INF'));
      print('Is master playlist: $isMasterPlaylist');

      if (!isMasterPlaylist) {
        // メディアプレイリストの場合、1つだけ返す
        final stream = await parseLocalM3U8(filePath);
        return [stream];
      }

      final List<M3U8Stream> streams = [];

      for (int i = 0; i < lines.length; i++) {
        if (lines[i].startsWith('#EXT-X-STREAM-INF')) {
          final info = lines[i];
          final bandwidthMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(info);
          final resolutionMatch = RegExp(r'RESOLUTION=([\d]+x[\d]+)').firstMatch(info);

          if (i + 1 < lines.length && !lines[i + 1].startsWith('#')) {
            final streamUrl = _resolveLocalUrl(filePath, lines[i + 1]);
            
            streams.add(M3U8Stream(
              url: streamUrl,
              quality: resolutionMatch?.group(1) ?? 'Unknown',
              bandwidth: bandwidthMatch != null 
                  ? int.parse(bandwidthMatch.group(1)!) 
                  : null,
              resolution: resolutionMatch?.group(1),
            ));
          }
        }
      }

      // 帯域幅でソート（高い順）
      streams.sort((a, b) => (b.bandwidth ?? 0).compareTo(a.bandwidth ?? 0));

      print('Found ${streams.length} streams');
      return streams;
    } catch (e, stackTrace) {
      print('Error getting all local streams: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }
}
