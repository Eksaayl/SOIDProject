import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/user_utils.dart';

Future<void> createNotification(String title, String body) async {
  try {
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 24));
    final username = await getCurrentUsername();
    
    await FirebaseFirestore.instance.collection('notifications').add({
      'title': title,
      'body': body,
      'timestamp': FieldValue.serverTimestamp(),
      'readBy': {},
      'expiresAtBy': {},
      'dismissedBy': {},
      'expiresAt': Timestamp.fromDate(expiresAt),
      'createdBy': username,
    });
  } catch (e) {
    print('Error creating notification: $e');
  }
}

Future<void> createSubmissionNotification(String sectionName) async {
  final username = await getCurrentUsername();
  await createNotification(
    'New Submission',
    '$sectionName has been submitted for review by $username.',
  );
}

Future<void> createFinalizationNotification(String sectionName) async {
  final username = await getCurrentUsername();
  await createNotification(
    'Section Finalized',
    '$sectionName has been finalized by $username(Admin).',
  );
} 