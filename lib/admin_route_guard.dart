import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminRouteGuard extends StatelessWidget {
  final Widget child;

  const AdminRouteGuard({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser?.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Scaffold(
            body: Center(
              child: Text('Access denied. Admin privileges required.'),
            ),
          );
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final role = (userData['role'] as String?)?.toLowerCase() ?? '';

        if (role != 'admin') {
          return const Scaffold(
            body: Center(
              child: Text('Access denied. Admin privileges required.'),
            ),
          );
        }

        return child;
      },
    );
  }
} 