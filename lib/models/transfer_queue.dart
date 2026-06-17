import 'transfer_item.dart';

class TransferQueue {
  final List<TransferItem> items;

  TransferQueue({required this.items});

  int get totalBytes => items.fold(0, (sum, item) => sum + item.fileSize);

  int get transferredBytes =>
      items.fold(0, (sum, item) => sum + item.transferredBytes);

  double get overallProgress {
    final total = totalBytes;
    if (total == 0) return 0.0;
    return transferredBytes / total;
  }

  void add(TransferItem item) {
    items.add(item);
  }

  void remove(String id) {
    items.removeWhere((item) => item.id == id);
  }

  void clear() {
    items.clear();
  }

  Map<String, dynamic> toJson() {
    return {'items': items.map((item) => item.toJson()).toList()};
  }

  factory TransferQueue.fromJson(Map<String, dynamic> json) {
    final list = json['items'] as List<dynamic>? ?? [];
    return TransferQueue(
      items: list
          .map((e) => TransferItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
