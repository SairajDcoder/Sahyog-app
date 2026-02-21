class AppUser {
  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.organizationId,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final String? organizationId;
  final bool isActive;

  AppUser copyWith({
    String? id,
    String? name,
    String? email,
    String? role,
    String? organizationId,
    bool? isActive,
  }) {
    return AppUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      organizationId: organizationId ?? this.organizationId,
      isActive: isActive ?? this.isActive,
    );
  }

  bool get isVolunteer => role == 'volunteer';
  bool get isCoordinator => role == 'coordinator';
  bool get isAdmin => role == 'admin';
  bool get isOrganization => role == 'organization';

  factory AppUser.fromSync(Map<String, dynamic> json) {
    return AppUser(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Volunteer').toString(),
      email: (json['email'] ?? '').toString(),
      role: normalizeRole((json['role'] ?? 'volunteer').toString()),
      organizationId: json['organization_id']?.toString(),
      isActive: json['is_active'] is bool ? json['is_active'] as bool : true,
    );
  }

  factory AppUser.fromMe(Map<String, dynamic> json) {
    return AppUser(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? json['email'] ?? 'Volunteer').toString(),
      email: (json['email'] ?? '').toString(),
      role: normalizeRole((json['role'] ?? 'volunteer').toString()),
      organizationId: json['organization_id']?.toString(),
      isActive: json['is_active'] is bool ? json['is_active'] as bool : true,
    );
  }
}

String normalizeRole(String rawRole) {
  const roleMap = {
    'volunteer': 'volunteer',
    'coordinator': 'coordinator',
    'admin': 'admin',
    'organization': 'organization',
    'org:user': 'volunteer',
    'org:volunteer': 'volunteer',
    'org:volunteer_head': 'coordinator',
    'org:coordinator': 'coordinator',
    'org:admin': 'admin',
    'org:organization': 'organization',
  };

  return roleMap[rawRole] ?? 'volunteer';
}

double? parseLat(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

double? parseLng(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
