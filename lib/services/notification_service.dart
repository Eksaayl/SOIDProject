import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/user_utils.dart';

Future<void> createNotification(String title, String body, String yearRange) async {
  try {
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 24));
    final username = await getCurrentUsername();
    
    await FirebaseFirestore.instance
      .collection('notifications')
      .doc(yearRange)
      .collection('items')
      .add({
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

Future<void> createSubmissionNotification(String sectionName, String yearRange) async {
  final username = await getCurrentUsername();
  await createNotification(
    'Section Submitted for Review',
    '$sectionName has been submitted for admin approval by $username.',
    yearRange,
  );
}

Future<void> createFinalizationNotification(String sectionName, String yearRange) async {
  final username = await getCurrentUsername();
  await createNotification(
    'Section Approved and Finalized',
    '$sectionName has been approved and finalized by $username (Admin).',
    yearRange,
  );
}

Future<void> createRejectionNotification(String sectionName, String message, String yearRange) async {
  final username = await getCurrentUsername();
  await createNotification(
    'Section Rejected',
    '$sectionName has been rejected by $username (Admin).\nReason: $message',
    yearRange,
  );
}

Future<void> createUnfinalizationNotification(String sectionName, String yearRange) async {
  final username = await getCurrentUsername();
  await createNotification(
    'Section Unfinalized',
    '$sectionName has been unfinalized by $username (Admin).',
    yearRange,
  );
} 