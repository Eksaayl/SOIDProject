import 'package:flutter/material.dart';
import 'Parts/part_five.dart';
import 'Parts/part_four.dart';
import 'Parts/part_one.dart';
import 'Parts/part_three.dart';
import 'Parts/part_two.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/notification_service.dart';
import 'roles.dart';
import 'package:provider/provider.dart';
import 'state/selection_model.dart';

Future<bool> showFinalizeConfirmation(BuildContext context, String sectionName) async {
  return await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Confirm Submission'),
        content: Text('Are you sure you want to submit $sectionName? This action cannot be undone.'),
        actions: <Widget>[
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: const Text('Submit'),
            onPressed: () async {
              Navigator.of(context).pop(true);
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xff021e84),
            ),
          ),
        ],
      );
    },
  ) ?? false;
}

class HorizontalTabsPage extends StatefulWidget {
  const HorizontalTabsPage({super.key});

  @override
  State<HorizontalTabsPage> createState() => _HorizontalTabsPageState();
}

typedef _HorizontalTabsPageStateBase = State<HorizontalTabsPage>;
class _HorizontalTabsPageState extends _HorizontalTabsPageStateBase with TickerProviderStateMixin {
  int _selectedIndex = 0;
  String? _username;
  bool _hasAccess = false;
  String _userRole = '';
  late final AnimationController _controller;

  final List<Map<String, dynamic>> _tabs = [
    {'label': 'Part I', 'content': const Part1()},
    {'label': 'Part II', 'content': const Part2()},
    {'label': 'Part III', 'content': const Part3()},
    {'label': 'Part IV', 'content': const Part4()},
    {'label': 'Part V', 'content': const Part5()},
  ];

  List<Map<String, dynamic>> _notifications = [];

  Future<void> _fetchUsername() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    setState(() {
      _username = userDoc.data()?['username'] ?? user.uid;
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchUsername();
    _checkUserAccess();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkUserAccess() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      
      if (userDoc.exists) {
        final role = (userDoc.data()?['role'] as String?)?.toLowerCase() ?? '';
        setState(() {
          _userRole = role;
          _hasAccess = hasAccess(role);
        });
      }
    }
  }

  void _markAllAsRead() async {
    if (_username == null) return;
    final yearRange = context.read<SelectionModel>().yearRange ?? '2729';
    final snapshot = await FirebaseFirestore.instance
      .collection('notifications')
      .doc(yearRange)
      .collection('items')
      .get();
    for (var doc in snapshot.docs) {
      doc.reference.update({
        'readBy.${_username!}': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _removeNotification(String notificationId) async {
    try {
      final yearRange = context.read<SelectionModel>().yearRange ?? '2729';
      await FirebaseFirestore.instance
        .collection('notifications')
        .doc(yearRange)
        .collection('items')
        .doc(notificationId)
        .delete();
      setState(() {
        _notifications.removeWhere((n) => n['id'] == notificationId);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error removing notification: $e'))
      );
    }
  }

  Future<void> _dismissNotification(String notificationId) async {
    if (_username == null) return;
    final yearRange = context.read<SelectionModel>().yearRange ?? '2729';
    await FirebaseFirestore.instance
      .collection('notifications')
      .doc(yearRange)
      .collection('items')
      .doc(notificationId)
      .update({'dismissedBy.${_username!}': true});
  }

  bool _isNotificationExpired(Map<String, dynamic> notification) {
    if (notification['expiresAt'] == null) return false;
    final expiresAt = (notification['expiresAt'] as Timestamp).toDate();
    return DateTime.now().isAfter(expiresAt);
  }

  Future<void> _markNotificationAsRead(String notificationId) async {
    if (_username == null) return;
    final yearRange = context.read<SelectionModel>().yearRange ?? '2729';
    final doc = await FirebaseFirestore.instance
      .collection('notifications')
      .doc(yearRange)
      .collection('items')
      .doc(notificationId)
      .get();
    final data = doc.data();
    if (data == null) return;
    final readBy = data['readBy'] as Map<String, dynamic>? ?? {};
    final expiresAtBy = data['expiresAtBy'] as Map<String, dynamic>? ?? {};
    if (!readBy.containsKey(_username!)) {
      final now = DateTime.now();
      final expiresAt = now.add(const Duration(hours: 24));
      await doc.reference.update({
        'readBy.${_username!}': FieldValue.serverTimestamp(),
        'expiresAtBy.${_username!}': Timestamp.fromDate(expiresAt),
      });
    } else {
      await doc.reference.update({
        'readBy.${_username!}': FieldValue.serverTimestamp(),
      });
    }
  }

  Widget _buildNotificationsDialog(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Container(
        padding: const EdgeInsets.only(bottom: 16),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Color(0xFFE0DAD2),
              width: 1,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xff021e84).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.notifications_active,
                    color: Color(0xff021e84),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Notifications',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D3748),
                  ),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: () {
                _markAllAsRead();
              },
              icon: const Icon(Icons.done_all, size: 20),
              label: const Text('Mark all as read'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xff021e84),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Color(0xff021e84), width: 1),
                ),
              ),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: 400,
        child: StreamBuilder<QuerySnapshot>(
          stream: () {
            final yearRange = context.watch<SelectionModel>().yearRange;
            print('Notification StreamBuilder yearRange: $yearRange');
            if (yearRange == null) {
              print('Warning: yearRange is null, using default');
              return FirebaseFirestore.instance
                .collection('notifications')
                .doc('2729')
                .collection('items')
                .orderBy('timestamp', descending: true)
                .snapshots();
            }
            return FirebaseFirestore.instance
              .collection('notifications')
              .doc(yearRange)
              .collection('items')
              .orderBy('timestamp', descending: true)
              .snapshots();
          }(),
          builder: (context, snapshot) {
            final yearRange = context.watch<SelectionModel>().yearRange;
            print('Notification StreamBuilder yearRange: $yearRange');
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              print('Notification StreamBuilder error: ${snapshot.error}');
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading notifications',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.red[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }
            final docs = snapshot.data?.docs ?? [];
            print('Loaded notifications: ${docs.length}');
            for (var doc in docs) {
              print('Notification doc: ${doc.data()}');
            }
            final notifications = docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final readBy = data['readBy'] as Map<String, dynamic>? ?? {};
              final expiresAtBy = data['expiresAtBy'] as Map<String, dynamic>? ?? {};
              final dismissedBy = data['dismissedBy'] as Map<String, dynamic>? ?? {};
              final readTimestamp = _username != null ? readBy[_username] : null;
              final expiresAt = _username != null ? expiresAtBy[_username] : null;
              return {
                'id': doc.id,
                'title': data['title'] ?? '',
                'body': data['body'] ?? '',
                'read': readTimestamp != null,
                'readTimestamp': readTimestamp,
                'expiresAt': expiresAt,
                'timestamp': data['timestamp'],
                'readBy': readBy,
                'expiresAtBy': expiresAtBy,
                'dismissedBy': dismissedBy,
              };
            })
            .where((n) => !_isNotificationExpired(n) && (_username == null || !(n['dismissedBy'] as Map<String, dynamic>).containsKey(_username)))
            .toList();

            notifications.sort((a, b) {
              if (a['read'] != b['read']) {
                return a['read'] ? 1 : -1;
              }
              final at = a['timestamp'] as Timestamp? ?? a['expiresAt'] as Timestamp? ?? Timestamp.now();
              final bt = b['timestamp'] as Timestamp? ?? b['expiresAt'] as Timestamp? ?? Timestamp.now();
              return bt.compareTo(at);
            });

            if (notifications.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.notifications_none,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No notifications',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              itemCount: notifications.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final n = notifications[index];
                final readBy = n['readBy'] as Map<String, dynamic>? ?? {};
                final readers = readBy.keys.toList();
                DateTime? expiresAt;
                if (n['expiresAt'] != null && n['expiresAt'] is Timestamp) {
                  expiresAt = (n['expiresAt'] as Timestamp).toDate();
                }
                final hoursRemaining = expiresAt != null ? expiresAt.difference(DateTime.now()).inHours : null;
                
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: n['read'] 
                            ? Colors.grey[100] 
                            : const Color(0xff021e84).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        n['read'] ? Icons.notifications_none : Icons.notifications,
                        color: n['read'] ? Colors.grey : const Color(0xff021e84),
                        size: 22,
                      ),
                    ),
                    title: Text(
                      n['title'],
                      style: TextStyle(
                        fontWeight: n['read'] ? FontWeight.w500 : FontWeight.bold,
                        color: const Color(0xFF2D3748),
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),
                        Text(
                          n['body'],
                          style: TextStyle(
                            color: Colors.grey[700],
                            height: 1.4,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 14,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                hoursRemaining != null ? '$hoursRemaining h remaining' : '—',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!n['read'])
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => _dismissNotification(n['id']),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          color: Colors.grey[600],
                        ),
                      ],
                    ),
                    onTap: () => _markNotificationAsRead(n['id']),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasAccess) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Container(
            padding: const EdgeInsets.all(32),
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xff021e84).withOpacity(0.1),
                  blurRadius: 24,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ],
              border: Border.all(
                color: const Color(0xff021e84).withOpacity(0.18),
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xff021e84).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _controller.value * 3.1416,  
                        child: child,
                      );
                    },
                    child: const Icon(
                      Icons.hourglass_bottom,
                      size: 48,
                      color: Color(0xff021e84),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Waiting for Access',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xff021e84),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Your current role is: $_userRole',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF4A5568),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Please wait for an administrator to grant you access to the document parts.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF4A5568),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final bool isSmallScreen = MediaQuery.of(context).size.width < 650;
    final bool isSmallerScreen = MediaQuery.of(context).size.width < 450;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            height: isSmallScreen ? 50 : 60,
            color: const Color(0xFFE0DAD2),
            child: Row(
              children: [
                ...List.generate(_tabs.length, (index) {
                  final bool selected = _selectedIndex == index;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                    child: Container(
                      width: isSmallScreen ? 70 : 120,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: selected ? Colors.white : const Color(0xFFD0C9C0),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _tabs[index]['label'],
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: isSmallScreen ? 14 : 16,
                            color: selected ? Colors.black : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications, color: Color(0xff021e84)),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => _buildNotificationsDialog(context),
                          );
                        },
                      ),
                      StreamBuilder<QuerySnapshot>(
                        stream: () {
                          final yearRange = context.watch<SelectionModel>().yearRange;
                          if (yearRange == null) {
                            return FirebaseFirestore.instance
                              .collection('notifications')
                              .doc('2729')
                              .collection('items')
                              .snapshots();
                          }
                          return FirebaseFirestore.instance
                            .collection('notifications')
                            .doc(yearRange)
                            .collection('items')
                            .snapshots();
                        }(),
                        builder: (context, snapshot) {
                          final userId = FirebaseAuth.instance.currentUser?.uid;
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const SizedBox();
                          }
                          final docs = snapshot.data?.docs ?? [];
                          final unreadCount = docs.where((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final readBy = data['readBy'] as Map<String, dynamic>? ?? {};
                            return _username == null || !readBy.containsKey(_username);
                          }).length;
                          if (unreadCount > 0) {
                            return Positioned(
                              right: 6,
                              top: 6,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '$unreadCount',
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: () {
                final yearRange = context.watch<SelectionModel>().yearRange;
                if (yearRange == null) {
                  return FirebaseFirestore.instance
                    .collection('notifications')
                    .doc('2729')
                    .collection('items')
                    .snapshots();
                }
                return FirebaseFirestore.instance
                  .collection('notifications')
                  .doc(yearRange)
                  .collection('items')
                  .snapshots();
              }(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final docs = snapshot.data?.docs ?? [];
                _notifications = docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return {
                    'id': doc.id,
                    'title': data['title'] ?? '',
                    'body': data['body'] ?? '',
                    'read': data['read'] ?? false,
                    'expiresAt': data['expiresAt'],
                  };
                }).toList();
                return _tabs[_selectedIndex]['content'];
              },
            ),
          ),
        ],
      ),
    );
  }
}

