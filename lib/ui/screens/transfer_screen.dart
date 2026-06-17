import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../services/transfer_controller.dart';
import '../../models/transfer_item.dart';

class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final _controller = TransferController();

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

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0s';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h}h ${m}m ${s}s';
    }
    if (m > 0) {
      return '${m}m ${s}s';
    }
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final hasItems = _controller.queue.items.isNotEmpty;
        final isConnected = _controller.isConnected;
        final isTransferring = _controller.isTransferring;
        final isPaused = _controller.isPaused;
        final isReconnecting = _controller.isReconnecting;

        // Find currently transferring item
        final activeItem = _controller.queue.items.firstWhere(
          (item) =>
              item.status == TransferStatus.transferring ||
              item.status == TransferStatus.verifying,
          orElse: () =>
              TransferItem(id: '', sourcePath: '', remotePath: '', fileSize: 0),
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              if (isReconnecting) _buildReconnectingBanner(),
              if (!isConnected) _buildNotConnectedBanner(),
              const SizedBox(height: 16),
              _buildOverallProgressCard(),
              const SizedBox(height: 24),
              if (activeItem.id.isNotEmpty) ...[
                _buildActiveItemCard(activeItem),
                const SizedBox(height: 24),
              ],
              _buildStatsGrid(),
              const SizedBox(height: 24),
              _buildSettingsCard(),
              const SizedBox(height: 32),
              _buildControls(hasItems, isConnected, isTransferring, isPaused),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSettingsCard() {
    final bool disabled = _controller.isTransferring;
    return Container(
      padding: const EdgeInsets.all(20),
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
              const Icon(
                Icons.settings_suggest_rounded,
                color: Colors.blueAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Transfer Settings',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Delete source files after backup',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Purge source files immediately upon successful SHA-256 validation.',
                      style: TextStyle(fontSize: 11, color: Colors.grey[450]),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _controller.deleteSource,
                onChanged: disabled
                    ? null
                    : (val) {
                        _controller.deleteSource = val;
                      },
                activeColor: Colors.blueAccent,
              ),
            ],
          ),
          const Divider(height: 32, color: Colors.black38),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Parallel transfers',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${_controller.parallelism} files concurrent',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.cyan,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Set the number of concurrent file streams to transfer to the remote share.',
                style: TextStyle(fontSize: 11, color: Colors.grey[450]),
              ),
              const SizedBox(height: 12),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.blueAccent,
                  inactiveTrackColor: Colors.black45,
                  thumbColor: Colors.blueAccent,
                  overlayColor: Colors.blueAccent.withOpacity(0.2),
                ),
                child: Slider(
                  value: _controller.parallelism.toDouble(),
                  min: 1.0,
                  max: 8.0,
                  divisions: 7,
                  onChanged: disabled
                      ? null
                      : (val) {
                          _controller.parallelism = val.round();
                        },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Backup Control',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Perform safe transfers with SHA-256 validation.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.grey[400]),
        ),
      ],
    );
  }

  Widget _buildReconnectingBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.orange[900]?.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[800]!),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              color: Colors.orangeAccent,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Text(
              'Network connection lost. Attempting auto-reconnect...',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotConnectedBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.red[950]?.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[900]!),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
          SizedBox(width: 16),
          Expanded(
            child: Text(
              'No active SMB share connection. Please connect first.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverallProgressCard() {
    final progress = _controller.queue.overallProgress;
    final progressPercent = (progress * 100).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[850]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Overall Progress',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                '$progressPercent%',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: Colors.black45,
              color: Colors.blueAccent,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${_formatBytes(_controller.queue.transferredBytes)} of ${_formatBytes(_controller.queue.totalBytes)} transferred',
            style: TextStyle(fontSize: 12, color: Colors.grey[450]),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveItemCard(TransferItem item) {
    final name = p.basename(item.sourcePath);
    final statusString = item.status == TransferStatus.verifying
        ? 'Verifying integrity (SHA-256)...'
        : 'Transferring file...';

    return Container(
      padding: const EdgeInsets.all(20),
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
              Icon(
                item.status == TransferStatus.verifying
                    ? Icons.check_circle_outline_rounded
                    : Icons.sync_rounded,
                color: Colors.blueAccent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            statusString,
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: item.progress,
              minHeight: 6,
              backgroundColor: Colors.black45,
              color: Colors.cyan,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_formatBytes(item.transferredBytes)} / ${_formatBytes(item.fileSize)}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              Text(
                '${(item.progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    // Estimations
    final remainingBytes =
        _controller.queue.totalBytes - _controller.queue.transferredBytes;
    final double speedMBps = _controller.speedMBps;
    final int etaSecs = (speedMBps > 0 && remainingBytes > 0)
        ? (remainingBytes / (speedMBps * 1024 * 1024)).round()
        : 0;

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(
          'Transfer Speed',
          speedMBps > 0 ? '${speedMBps.toStringAsFixed(1)} MB/s' : '--',
          Icons.speed_rounded,
          Colors.cyan,
        ),
        _buildStatCard(
          'Time Remaining',
          etaSecs > 0 ? _formatDuration(etaSecs) : '--',
          Icons.timer_rounded,
          Colors.amber,
        ),
        _buildStatCard(
          'Data Transferred',
          _formatBytes(_controller.totalBytesMoved),
          Icons.data_exploration_rounded,
          Colors.green,
        ),
        _buildStatCard(
          'Storage Reclaimed',
          _formatBytes(_controller.totalStorageReclaimed),
          Icons.storage_rounded,
          Colors.purpleAccent,
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(
    bool hasItems,
    bool isConnected,
    bool isTransferring,
    bool isPaused,
  ) {
    if (!hasItems) {
      return Center(
        child: Text(
          'Add files to the queue to start backing up.',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      );
    }

    if (!isTransferring && !isPaused) {
      return ElevatedButton.icon(
        onPressed: isConnected ? () => _controller.startTransfer() : null,
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Start Backup'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blueAccent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey[800],
          disabledForegroundColor: Colors.grey[600],
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isPaused
                ? () => _controller.resumeTransfer()
                : () => _controller.pauseTransfer(),
            icon: Icon(
              isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            ),
            label: Text(isPaused ? 'Resume' : 'Pause'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isPaused ? Colors.green[800] : Colors.grey[900],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: isPaused
                    ? BorderSide.none
                    : BorderSide(color: Colors.grey[800]!),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _controller.cancelTransfer(),
            icon: const Icon(Icons.cancel_rounded),
            label: const Text('Cancel'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[900],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
