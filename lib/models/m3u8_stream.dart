class M3U8Stream {
  final String url;
  final String quality;
  final int? bandwidth;
  final String? resolution;
  final List<String> segmentUrls;
  final String? initSegmentUrl;
  final bool isEncrypted;
  final String? keyUri;

  M3U8Stream({
    required this.url,
    required this.quality,
    this.bandwidth,
    this.resolution,
    this.segmentUrls = const [],
    this.initSegmentUrl,
    this.isEncrypted = false,
    this.keyUri,
  });

  String get displayName {
    if (resolution != null) {
      return '$resolution ($quality)';
    }
    if (bandwidth != null) {
      final mbps = (bandwidth! / 1000000).toStringAsFixed(1);
      return '${mbps}Mbps';
    }
    return quality;
  }

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'quality': quality,
      'bandwidth': bandwidth,
      'resolution': resolution,
      'segmentUrls': segmentUrls,
      'initSegmentUrl': initSegmentUrl,
      'isEncrypted': isEncrypted,
      'keyUri': keyUri,
    };
  }

  factory M3U8Stream.fromMap(Map<String, dynamic> map) {
    return M3U8Stream(
      url: map['url'] as String,
      quality: map['quality'] as String,
      bandwidth: map['bandwidth'] as int?,
      resolution: map['resolution'] as String?,
      segmentUrls: (map['segmentUrls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      initSegmentUrl: map['initSegmentUrl'] as String?,
      isEncrypted: map['isEncrypted'] as bool? ?? false,
      keyUri: map['keyUri'] as String?,
    );
  }
}
