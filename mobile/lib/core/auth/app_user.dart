import '../utils/json.dart';

/// Utilisateur connecté (`UserRead`).
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.isActive,
    required this.isSuperuser,
    this.createdAt,
    this.lastLoginAt,
  });

  final String id;
  final String email;
  final bool isActive;
  final bool isSuperuser;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    email: json['email'] as String,
    isActive: json['is_active'] as bool? ?? true,
    isSuperuser: json['is_superuser'] as bool? ?? false,
    createdAt: parseDate(json['created_at']),
    lastLoginAt: parseDate(json['last_login_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'is_active': isActive,
    'is_superuser': isSuperuser,
    'created_at': createdAt?.toIso8601String(),
    'last_login_at': lastLoginAt?.toIso8601String(),
  };
}
