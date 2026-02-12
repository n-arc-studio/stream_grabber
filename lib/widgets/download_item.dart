import 'package:flutter/material.dart';
import '../models/download_task.dart';

class DownloadItem extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onDelete;
  final VoidCallback? onRetry;

  const DownloadItem({
    super.key,
    required this.task,
    this.onPause,
    this.onResume,
    this.onDelete,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildStatusIcon(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.fileName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        task.websiteUrl,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                _buildActionButtons(context),
              ],
            ),
            const SizedBox(height: 12),
            _buildProgressSection(),
            if (task.status == DownloadStatus.failed && task.errorMessage != null) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () {
                  _showErrorDetails(context);
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, size: 16, color: Colors.red[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          task.errorMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red[700],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.info_outline, size: 16, color: Colors.red[400]),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    IconData icon;
    Color color;

    switch (task.status) {
      case DownloadStatus.pending:
        icon = Icons.schedule;
        color = Colors.grey;
        break;
      case DownloadStatus.downloading:
        icon = Icons.downloading;
        color = Colors.blue;
        break;
      case DownloadStatus.merging:
        icon = Icons.merge;
        color = Colors.orange;
        break;
      case DownloadStatus.completed:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case DownloadStatus.failed:
        icon = Icons.error;
        color = Colors.red;
        break;
      case DownloadStatus.paused:
        icon = Icons.pause_circle;
        color = Colors.grey;
        break;
    }

    return Icon(icon, color: color, size: 40);
  }

  void _showErrorDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            const Text('エラー詳細'),
          ],
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            task.errorMessage ?? 'Unknown error',
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        switch (value) {
          case 'pause':
            onPause?.call();
            break;
          case 'resume':
            onResume?.call();
            break;
          case 'retry':
            onRetry?.call();
            break;
          case 'delete':
            onDelete?.call();
            break;
        }
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[];

        if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.merging) {
          items.add(
            const PopupMenuItem(
              value: 'pause',
              child: Row(
                children: [
                  Icon(Icons.pause),
                  SizedBox(width: 8),
                  Text('一時停止'),
                ],
              ),
            ),
          );
        }

        if (task.status == DownloadStatus.paused) {
          items.add(
            const PopupMenuItem(
              value: 'resume',
              child: Row(
                children: [
                  Icon(Icons.play_arrow),
                  SizedBox(width: 8),
                  Text('再開'),
                ],
              ),
            ),
          );
        }

        if (task.status == DownloadStatus.failed) {
          items.add(
            const PopupMenuItem(
              value: 'retry',
              child: Row(
                children: [
                  Icon(Icons.refresh),
                  SizedBox(width: 8),
                  Text('リトライ'),
                ],
              ),
            ),
          );
        }

        items.add(
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete, color: Colors.red),
                SizedBox(width: 8),
                Text('削除', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        );

        return items;
      },
    );
  }

  Widget _buildProgressSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _getStatusText(),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
              ),
            ),
            Text(
              '${(task.progress * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: task.progress,
          backgroundColor: Colors.grey[200],
          valueColor: AlwaysStoppedAnimation<Color>(_getProgressColor()),
        ),
        if (task.totalSegments > 0) ...[
          const SizedBox(height: 4),
          Text(
            'セグメント: ${task.downloadedSegments} / ${task.totalSegments}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
          ),
        ],
      ],
    );
  }

  String _getStatusText() {
    switch (task.status) {
      case DownloadStatus.pending:
        return 'ダウンロード待機中...';
      case DownloadStatus.downloading:
        return 'ダウンロード中...';
      case DownloadStatus.merging:
        return 'ビデオ結合中...';
      case DownloadStatus.completed:
        return '完了';
      case DownloadStatus.failed:
        return '失敗';
      case DownloadStatus.paused:
        return '一時停止';
    }
  }

  Color _getProgressColor() {
    switch (task.status) {
      case DownloadStatus.downloading:
        return Colors.blue;
      case DownloadStatus.merging:
        return Colors.orange;
      case DownloadStatus.completed:
        return Colors.green;
      case DownloadStatus.failed:
        return Colors.red;
      case DownloadStatus.paused:
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }
}
