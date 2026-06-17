import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../services/transfer_controller.dart';
import '../../models/transfer_item.dart';

class SummaryScreen extends StatelessWidget {
  final VoidCallback onNewTransfer;

  const SummaryScreen({super.key, required this.onNewTransfer});

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return '${d.toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = TransferController();
    final items = controller.queue.items;
    final completedItems = items
        .where((item) => item.status == TransferStatus.completed)
        .toList();
    final failedItems = items
        .where((item) => item.status == TransferStatus.failed)
        .toList();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSuccessBanner(
            context,
            completedItems.length,
            failedItems.length,
            controller.deleteSource,
          ),
          const SizedBox(height: 24),
          _buildMetricsRow(controller),
          const SizedBox(height: 24),
          const Text(
            'Transfer Details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildItemsList(completedItems, failedItems)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              controller.clearQueue();
              onNewTransfer();
            },
            icon: const Icon(Icons.add_circle_outline_rounded),
            label: const Text('New Backup Queue'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessBanner(
    BuildContext context,
    int successCount,
    int failCount,
    bool deleteSource,
  ) {
    final hasFailed = failCount > 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: hasFailed ? const Color(0xFF2C1616) : const Color(0xFF0F2E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasFailed
              ? Colors.redAccent.withValues(alpha: 0.3)
              : Colors.green.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (hasFailed ? Colors.redAccent : Colors.green).withValues(
                alpha: 0.15,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasFailed
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: hasFailed ? Colors.redAccent : Colors.green,
              size: 36,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasFailed
                      ? 'Backup Completed with Errors'
                      : 'Backup Completed Successfully',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasFailed
                      ? '$successCount files moved, $failCount files failed.'
                      : 'All $successCount files transferred & verified. ${deleteSource ? "Source files purged." : "Source files preserved."}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[300]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsRow(TransferController controller) {
    return Row(
      children: [
        Expanded(
          child: _buildSummaryMetric(
            'Total Moved',
            _formatBytes(controller.totalBytesMoved),
            Icons.data_exploration_rounded,
            Colors.green,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildSummaryMetric(
            'Local Reclaimed',
            _formatBytes(controller.totalStorageReclaimed),
            Icons.delete_sweep_rounded,
            Colors.purpleAccent,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryMetric(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[850]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList(
    List<TransferItem> completed,
    List<TransferItem> failed,
  ) {
    final allItems = [...completed, ...failed];
    if (allItems.isEmpty) {
      return Center(
        child: Text(
          'No transfer history in this queue.',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    return ListView.builder(
      itemCount: allItems.length,
      itemBuilder: (context, index) {
        final item = allItems[index];
        final name = p.basename(item.sourcePath);
        final isSuccess = item.status == TransferStatus.completed;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[900]!),
          ),
          child: Row(
            children: [
              Icon(
                isSuccess ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: isSuccess ? Colors.green : Colors.redAccent,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!isSuccess && item.errorMessage != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.errorMessage!,
                        style: TextStyle(fontSize: 11, color: Colors.red[350]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _formatBytes(item.fileSize),
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ],
          ),
        );
      },
    );
  }
}
