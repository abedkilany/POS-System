class SyncQueueItem {
  const SyncQueueItem({
    required this.id,
    required this.changeId,
    required this.target,
    required this.status,
    required this.attempts,
    required this.createdAt,
    required this.updatedAt,
    this.lastError = '',
    this.nextRetryAt,
  });

  final String id;
  final String changeId;
  final String target; // host, cloud, marketplace
  final String status; // pending, inProgress, failed, synced
  final int attempts;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String lastError;
  final DateTime? nextRetryAt;

  bool get isPending => status == 'pending' || status == 'failed';

  SyncQueueItem copyWith({
    String? id,
    String? changeId,
    String? target,
    String? status,
    int? attempts,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? lastError,
    DateTime? nextRetryAt,
    bool clearNextRetryAt = false,
  }) {
    return SyncQueueItem(
      id: id ?? this.id,
      changeId: changeId ?? this.changeId,
      target: target ?? this.target,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastError: lastError ?? this.lastError,
      nextRetryAt: clearNextRetryAt ? null : (nextRetryAt ?? this.nextRetryAt),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'changeId': changeId,
        'target': target,
        'status': status,
        'attempts': attempts,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'lastError': lastError,
        'nextRetryAt': nextRetryAt?.toIso8601String(),
      };

  factory SyncQueueItem.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return SyncQueueItem(
      id: json['id'] as String? ?? '',
      changeId: json['changeId'] as String? ?? '',
      target: json['target'] as String? ?? 'host',
      status: json['status'] as String? ?? 'pending',
      attempts: (json['attempts'] as num? ?? 0).toInt(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
      lastError: json['lastError'] as String? ?? '',
      nextRetryAt: DateTime.tryParse(json['nextRetryAt'] as String? ?? ''),
    );
  }
}
