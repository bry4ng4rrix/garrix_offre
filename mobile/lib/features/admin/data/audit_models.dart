import '../../../core/models/enums.dart';
import '../../../core/utils/json.dart';

/// Entrée du journal d'audit (`AuditLogRead`).
class AuditLog {
  const AuditLog({
    required this.id,
    required this.action,
    required this.actorTypeValue,
    this.actorId,
    this.entityType,
    this.entityId,
    this.details = const {},
    this.createdAt,
  });

  final String id;

  /// Ex. `auth.login`, `application.status_changed`.
  final String action;
  final String actorTypeValue;
  final String? actorId;
  final String? entityType;
  final String? entityId;
  final Map<String, dynamic> details;
  final DateTime? createdAt;

  ActorType? get actorType => ActorType.fromApi(actorTypeValue);

  factory AuditLog.fromJson(Map<String, dynamic> json) => AuditLog(
    id: json['id'] as String,
    action: json['action']?.toString() ?? '',
    actorTypeValue: json['actor_type']?.toString() ?? 'system',
    actorId: json['actor_id']?.toString(),
    entityType: json['entity_type']?.toString(),
    entityId: json['entity_id']?.toString(),
    details: parseMap(json['details']),
    createdAt: parseDate(json['created_at']),
  );
}
