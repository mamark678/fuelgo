import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String email;
  final String name;
  final String role;
  final DateTime? createdAt;

  AppUser({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    this.createdAt,
  });

  factory AppUser.fromMap(String uid, Map<String, dynamic> data) {
    return AppUser(
      uid: uid,
      email: data['email'] ?? '',
      name: data['name'] ?? '',
      role: data['role'] ?? 'user',
      createdAt: data['createdAt'] != null ? (data['createdAt'] as Timestamp).toDate() : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'name': name,
      'role': role,
      'createdAt': createdAt,
    };
  }
} 