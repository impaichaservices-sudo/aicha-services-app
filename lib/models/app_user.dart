import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String name;
  final String phone;
  final String email;

  const AppUser({
    required this.uid,
    required this.name,
    required this.phone,
    required this.email,
  });

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return AppUser(
      uid: doc.id,
      name: (d['name'] ?? '') as String,
      phone: (d['phone'] ?? '') as String,
      email: (d['email'] ?? '') as String,
    );
  }
}
