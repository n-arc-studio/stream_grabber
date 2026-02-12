enum DownloadStatus {
  pending,
  downloading,
  merging,
  completed,
  failed,
  paused,
}

class DownloadTask {
  final String id;
  final String url;
  final String websiteUrl;
  final String outputPath;
  final String fileName;
  DownloadStatus status;
  double progress;
  int totalSegments;
  int downloadedSegments;
  String? errorMessage;
  DateTime createdAt;
  DateTime? completedAt;

  DownloadTask({
    required this.id,
    required this.url,
    required this.websiteUrl,
    required this.outputPath,
    required this.fileName,
    this.status = DownloadStatus.pending,
    this.progress = 0.0,
    this.totalSegments = 0,
    this.downloadedSegments = 0,
    this.errorMessage,
    DateTime? createdAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'url': url,
      'websiteUrl': websiteUrl,
      'outputPath': outputPath,
      'fileName': fileName,
      'status': status.index,
      'progress': progress,
      'totalSegments': totalSegments,
      'downloadedSegments': downloadedSegments,
      'errorMessage': errorMessage,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
    };
  }

  factory DownloadTask.fromMap(Map<String, dynamic> map) {
    return DownloadTask(
      id: map['id'] as String,
      url: map['url'] as String,
      websiteUrl: map['websiteUrl'] as String,
      outputPath: map['outputPath'] as String,
      fileName: map['fileName'] as String,
      status: DownloadStatus.values[map['status'] as int],
      progress: (map['progress'] as num).toDouble(),
      totalSegments: map['totalSegments'] as int,
      downloadedSegments: map['downloadedSegments'] as int,
      errorMessage: map['errorMessage'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      completedAt: map['completedAt'] != null
          ? DateTime.parse(map['completedAt'] as String)
          : null,
    );
  }

  DownloadTask copyWith({
    String? id,
    String? url,
    String? websiteUrl,
    String? outputPath,
    String? fileName,
    DownloadStatus? status,
    double? progress,
    int? totalSegments,
    int? downloadedSegments,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      url: url ?? this.url,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      outputPath: outputPath ?? this.outputPath,
      fileName: fileName ?? this.fileName,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      totalSegments: totalSegments ?? this.totalSegments,
      downloadedSegments: downloadedSegments ?? this.downloadedSegments,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
