class NotificationModel {
  final String id;
  final String? userId;
  final String title;
  final String message;
  final String type; // 'PASSWORD_RESET_REQUEST', 'PASSWORD_RESET_APPROVED', 'PASSWORD_RESET_REJECTED', 'APP_UPDATE', 'GENERAL'
  final Map<String, dynamic> metadata;
  final bool isRead;
  final bool isActioned;
  final DateTime createdAt;

  NotificationModel({
    required this.id,
    this.userId,
    required this.title,
    required this.message,
    required this.type,
    required this.metadata,
    required this.isRead,
    required this.isActioned,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['_id'] ?? '',
      userId: json['user_id'] is Map ? json['user_id']['_id'] : json['user_id'],
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      type: json['type'] ?? 'GENERAL',
      metadata: json['metadata'] ?? {},
      isRead: json['is_read'] ?? false,
      isActioned: json['is_actioned'] ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
}
