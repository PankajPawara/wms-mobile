class UserModel {
  final String id;
  final String employeeId;
  final String name;
  final String mobile;
  final String email;
  final String role;
  final String status;
  final bool isFirstLogin;

  const UserModel({
    required this.id,
    required this.employeeId,
    required this.name,
    required this.mobile,
    required this.email,
    required this.role,
    required this.status,
    required this.isFirstLogin,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['_id'] ?? '',
      employeeId: json['employee_id'] ?? '',
      name: json['name'] ?? '',
      mobile: json['mobile'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'employee',
      status: json['status'] ?? 'active',
      isFirstLogin: json['is_first_login'] ?? false,
    );
  }

  bool get isAdmin => role == 'admin';
}
