import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import '../models/m3u8_stream.dart';

class M3U8Parser {
  final Dio _dio = Dio(
    BaseOptions(
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': '*/*',
        'Accept-Language': 'ja,en-US;q=0.9,en;q=0.8',
        'Accept-Encoding': 'gzip, deflate, br',
        'Connection': 'keep-alive',
      },
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: true,
      maxRedirects: 5,
    ),
  );

  // WebページからM3U8およびMP4 URLを検出
  Future<List<String>> detectM3U8FromWebsite(String websiteUrl) async {
    try {
      final response = await _dio.get(
        websiteUrl,
        options: Options(
          headers: {
            'Referer': websiteUrl,
          },
        ),
      );
      final document = html_parser.parse(response.data);
      
      final List<String> videoUrls = [];

      // scriptタグ内のM3U8/MP4 URLを検索
      final scripts = document.getElementsByTagName('script');
      for (var script in scripts) {
        final content = script.text;
        // M3U8 URLを検索
        final m3u8Matches = RegExp(r'https?://[^\s"<>]+\.m3u8[^\s"<>]*')
            .allMatches(content);
        for (var match in m3u8Matches) {
          final url = match.group(0);
          if (url != null && !videoUrls.contains(url)) {
            videoUrls.add(url);
          }
        }
        // MP4 URLを検索
        final mp4Matches = RegExp(r'https?://[^\s"<>]+\.mp4[^\s"<>]*')
            .allMatches(content);
        for (var match in mp4Matches) {
          final url = match.group(0);
          if (url != null && !videoUrls.contains(url)) {
            videoUrls.add(url);
          }
        }
      }

      // videoタグのsrc属性を検索
      final videos = document.getElementsByTagName('video');
      for (var video in videos) {
        final src = video.attributes['src'];
        if (src != null && (src.contains('.m3u8') || src.contains('.mp4'))) {
          if (!videoUrls.contains(src)) {
            videoUrls.add(src);
          }
        }
      }

      // sourceタグを検索
      final sources = document.getElementsByTagName('source');
      for (var source in sources) {
        final src = source.attributes['src'];
        if (src != null && (src.contains('.m3u8') || src.contains('.mp4'))) {
          if (!videoUrls.contains(src)) {
            videoUrls.add(src);
          }
        }
      }

      // ページ全体のテキストからM3U8/MP4 URLを検索（fallback）
      if (videoUrls.isEmpty) {
        final bodyText = response.data.toString();
        // M3U8 URLを検索
        final m3u8Matches = RegExp(r'https?://[^\s"<>]+\.m3u8[^\s"<>]*')
            .allMatches(bodyText);
        for (var match in m3u8Matches) {
          final url = match.group(0);
          if (url != null && !videoUrls.contains(url)) {
            videoUrls.add(url);
          }
        }
        // MP4 URLを検索
        final mp4Matches = RegExp(r'https?://[^\s"<>]+\.mp4[^\s"<>]*')
            .allMatches(bodyText);
        for (var match in mp4Matches) {
          final url = match.group(0);
          if (url != null && !videoUrls.contains(url)) {
            videoUrls.add(url);
          }
        }
      }

      return videoUrls;
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        print('Error: Access denied (403). The server blocked the request. This website may require authentication or different headers.');
      } else if (e.response?.statusCode == 404) {
        print('Error: Page not found (404). Please check the URL.');
      } else {
        print('Error detecting video URLs: ${e.message}');
      }
      return [];
    } catch (e) {
      print('Error detecting video URLs: $e');
      return [];
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
}
