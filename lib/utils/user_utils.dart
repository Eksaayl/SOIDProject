import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<String> getCurrentUsername() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return 'unknown';
  
  try {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    return userDoc.data()?['username'] ?? user.displayName ?? user.email ?? user.uid;
  } catch (e) {
    return user.displayName ?? user.email ?? user.uid;
  }
}

String formatYearRange(String yearCode) {
  if (yearCode.length != 4) return yearCode;
  
  final startYear = '20${yearCode.substring(0, 2)}';
  final endYear = '20${yearCode.substring(2, 4)}';
  
  return '$startYear - $endYear';
} 