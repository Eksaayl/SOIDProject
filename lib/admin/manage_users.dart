import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../admin_route_guard.dart';
import '../utils/dialog_utils.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

class ManageUsersPage extends StatefulWidget {
  const ManageUsersPage({super.key});

  @override
  State<ManageUsersPage> createState() => _ManageUsersPageState();
}

class _ManageUsersPageState extends State<ManageUsersPage> {
  final int _rowsPerPage = 10;
  final List<String> _allRoles = ['user', 'admin', 'editor', 'itds'];
  final List<String> _allSubRoles = [
    'CBMS', 'POPCEN', 'CAF', 'PHILSYS', 'FIES', 'FLEMMS', 'CRVS', 'APIS', 'STEP', 
    'DEDSSFIGI', 'ASPBI', 'CPBI', 'NDHS', 'SICT', 'CES', 'CVS', 'BRIMPS', 'OIDPMS', 
    'QSPBI', 'PSA', 'SOIS', 'SCR', 'SFD', 'NMS', 'NICTHS', 'HSDV', 'HECS'
  ];
  final Map<String, String> _editedRoles = {};
  final Map<String, String> _editedSubRoles = {};
  final DateFormat _fmt = DateFormat.yMd().add_jm();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  String _filterText = '';
  int _currentPage = 0;
  bool _createdAtAscending = true;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _filterText = value.trim().toLowerCase();
        _currentPage = 0; 
      });
    });
  }

  List<DocumentSnapshot> _getPagedDocs(List<DocumentSnapshot> docs) {
    final start = _currentPage * _rowsPerPage;
    final end = start + _rowsPerPage;
    return docs.sublist(
      start,
      end > docs.length ? docs.length : end,
    );
  }

  void _showProfilePicture(BuildContext context, String username, String? photoURL, Map<String, dynamic> userData) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 775),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFF8FAFF),
                Color(0xFFF0F4FF),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Color(0xff021e84),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$username\'s Profile',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Profile Picture',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white),
                        tooltip: 'Close',
                      ),
                    ),
                  ],
                ),
              ),
              
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Container(
                        width: 280,
                        height: 280,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xff021e84).withOpacity(0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: photoURL != null && photoURL.isNotEmpty
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(
                                      photoURL,
                                      fit: BoxFit.cover,
                                      loadingBuilder: (context, child, loadingProgress) {
                                        if (loadingProgress == null) return child;
                                        return Container(
                                          decoration: BoxDecoration(
                                            color: Colors.grey[100],
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Center(
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                CircularProgressIndicator(
                                                  value: loadingProgress.expectedTotalBytes != null
                                                      ? loadingProgress.cumulativeBytesLoaded /
                                                          loadingProgress.expectedTotalBytes!
                                                      : null,
                                                  color: const Color(0xff021e84),
                                                  strokeWidth: 3,
                                                ),
                                                const SizedBox(height: 16),
                                                Text(
                                                  'Loading image...',
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                      errorBuilder: (context, error, stackTrace) {
                                        return Container(
                                          decoration: BoxDecoration(
                                            color: Colors.grey[100],
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(16),
                                                decoration: BoxDecoration(
                                                  color: Colors.red[50],
                                                  borderRadius: BorderRadius.circular(16),
                                                ),
                                                child: Icon(
                                                  Icons.error_outline,
                                                  size: 48,
                                                  color: Colors.red[400],
                                                ),
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                                                'Failed to load image',
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Please try again later',
                                                style: TextStyle(
                                                  color: Colors.grey[500],
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      right: 0,
                                      child: Container(
                                        height: 60,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.transparent,
                                              Colors.black.withOpacity(0.3),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          color: const Color(0xff021e84).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(40),
                                        ),
                                        child: const Icon(
                                          Icons.person,
                                          size: 48,
                                          color: Color(0xff021e84),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No profile picture',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'User hasn\'t uploaded a photo yet',
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 14,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xff021e84).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.info_outline,
                                    color: Color(0xff021e84),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'User Information',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[800],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Username',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              username,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xff021e84),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Mobile Number',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              userData['mobile'] as String? ?? 'Not specified',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xff021e84),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Service/Division',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              userData['service'] as String? ?? 'Not specified',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xff021e84),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                  border: Border(
                    top: BorderSide(
                      color: Colors.grey[200]!,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xff021e84),
                          side: const BorderSide(color: Color(0xff021e84)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Close',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? validSubRole(String? value) {
    if (value == null || !_allSubRoles.contains(value)) return null;
    return value;
  }

  String subRolesToString(dynamic subRoles) {
    if (subRoles == null) return '';
    if (subRoles is String) return subRoles;
    if (subRoles is List) return subRoles.join(',');
    return subRoles.toString();
  }

  Future<bool> _deleteUserFromBackend(String email) async {
    final url = Uri.parse('${Config.serverUrl}/delete-user');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: '{"email": "${email.trim()}"}',
      );
      if (response.statusCode == 200) {
        final body = response.body;
        if (body.contains('success') || body.contains('deleted')) {
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isNarrow = width < 1150;

    return AdminRouteGuard(
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .orderBy('username')
            .snapshots(),
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.active) {
            return const Center(
              child: CircularProgressIndicator(
                color: Color(0xff021e84),
              ),
            );
          }

          final docs = (snap.data?.docs ?? []).where((d) {
            final data = d.data()! as Map<String, dynamic>;
            final name = (data['username'] as String? ?? '').toLowerCase();
            final email = (data['email'] as String? ?? '').toLowerCase();
            return name.contains(_filterText) || email.contains(_filterText);
          }).toList();

          docs.sort((a, b) {
            final aData = a.data()! as Map<String, dynamic>;
            final bData = b.data()! as Map<String, dynamic>;
            String aRole = (aData['role'] ?? '').toString().toLowerCase();
            String bRole = (bData['role'] ?? '').toString().toLowerCase();
            int roleRank(String role) {
              if (role == 'admin') return 0;
              if (role == 'itds') return 1;
              if (role == 'editor') return 2;
              return 3;
            }
            int cmp = roleRank(aRole).compareTo(roleRank(bRole));
            if (cmp != 0) return cmp;
            final aCreated = aData['createdAt'] as Timestamp?;
            final bCreated = bData['createdAt'] as Timestamp?;
            if (aCreated != null && bCreated != null) {
              return _createdAtAscending
                  ? aCreated.compareTo(bCreated)
                  : bCreated.compareTo(aCreated);
            }
            return 0;
          });

          if (_currentPage * _rowsPerPage >= docs.length && _currentPage != 0) {
            _currentPage = 0;
          }

          final pagedDocs = _getPagedDocs(docs);

          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF8FAFF),
                  Color(0xFFF0F4FF),
                ],
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xff021e84).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.people,
                            color: Color(0xff021e84),
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Manage Users',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A202C),
                                ),
                              ),
                              Text(
                                '${docs.length} total users',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF718096),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  height: 1,
                  color: const Color(0xFFE2E8F0),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xff021e84).withOpacity(0.1),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                constraints: const BoxConstraints(maxWidth: 400),
                                child: TextField(
                                  controller: _searchController,
                                  decoration: InputDecoration(
                                    hintText: 'Search by username or email...',
                                    hintStyle: TextStyle(color: Colors.grey[400]),
                                    prefixIcon: Container(
                                      margin: const EdgeInsets.all(8),
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xff021e84).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.search,
                                        color: Color(0xff021e84),
                                        size: 20,
                                      ),
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey[50],
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: const BorderSide(
                                        color: Color(0xff021e84),
                                        width: 2,
                                      ),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 16,
                                    ),
                                  ),
                                  onChanged: _onSearchChanged,
                                  onSubmitted: _onSearchChanged,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xff021e84).withOpacity(0.1),
                                  blurRadius: 20,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: isNarrow
                                ? _buildMobileLayout(pagedDocs)
                                : _buildDesktopLayout(pagedDocs, docs),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMobileLayout(List<DocumentSnapshot> pagedDocs) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: pagedDocs.length,
      itemBuilder: (ctx, i) {
        final d = pagedDocs[i];
        final data = d.data()! as Map<String, dynamic>;
        final id = d.id;
        final username = data['username'] as String? ?? '';
        final email = data['email'] as String? ?? '';
        final ts = data['createdAt'] as Timestamp?;
        final createdAt = ts != null ? _fmt.format(ts.toDate()) : '—';
        final currentRole = data['role'] as String? ?? '';
        final currentSubRole = subRolesToString(data['sub_roles']);
        final editedRole = _editedRoles[id] ?? currentRole;
        final editedSubRole = _editedSubRoles[id] ?? currentSubRole;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xff021e84).withOpacity(0.1),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _showProfilePicture(context, username, data['profilePictureURL'] as String?, data);
                        },
                        icon: const Icon(Icons.photo_camera, size: 18),
                        label: const Text('View Profile'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xff021e84),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xff021e84).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.person,
                        color: Color(0xff021e84),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            username,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xff021e84),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            email,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Created: $createdAt',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xff021e84).withOpacity(0.2),
                          ),
                        ),
                        child: DropdownButton<String>(
                          value: editedRole,
                          isExpanded: true,
                          underline: const SizedBox(),
                          icon: const Icon(
                            Icons.keyboard_arrow_down,
                            color: Color(0xff021e84),
                          ),
                          items: _allRoles.map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(
                              r.toUpperCase(),
                              style: const TextStyle(
                                color: Color(0xff021e84),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          )).toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _editedRoles[id] = v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: editedRole != currentRole || editedSubRole != currentSubRole 
                            ? const Color(0xff021e84)
                            : Colors.grey[300],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.save, color: Colors.white, size: 20),
                        tooltip: 'Save role',
                        onPressed: editedRole != currentRole || editedSubRole != currentSubRole
                            ? () async {
                                final confirmed = await DialogUtils.showDeleteConfirmationDialog(
                                  context: context,
                                  title: 'Confirm Save',
                                  message: 'Are you sure you want to save these changes for this user?',
                                  cancelText: 'Cancel',
                                  confirmText: 'Save',
                                );
                                if (confirmed != true) return;
                                final newRole = _editedRoles[id];
                                final newSubRole = _editedSubRoles[id];
                                if (newRole != null && newRole != currentRole) {
                                  FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(id)
                                      .update({'role': newRole});
                                }
                                if (newSubRole != null && newSubRole != currentSubRole) {
                                  final subRoleToSave = newSubRole is List ? (newSubRole as List).join(',') : newSubRole.toString();
                                  FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(id)
                                      .update({'sub_roles': subRoleToSave});
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: [
                                        const Icon(Icons.check_circle, color: Colors.white),
                                        const SizedBox(width: 8),
                                        Text('Role updated to ${newRole?.toUpperCase() ?? 'N/A'}'),
                                        const SizedBox(width: 8),
                                        Text('Sub-role updated to ${newSubRole?.toUpperCase() ?? 'N/A'}'),
                                      ],
                                    ),
                                    backgroundColor: const Color(0xff021e84),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                );
                                setState(() {
                                  _editedRoles.remove(id);
                                  _editedSubRoles.remove(id);
                                });
                              }
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xff021e84).withOpacity(0.2),
                    ),
                  ),
                  child: DropdownButton<String>(
                    value: validSubRole(editedSubRole),
                    isExpanded: true,
                    underline: const SizedBox(),
                    icon: const Icon(
                      Icons.keyboard_arrow_down,
                      color: Color(0xff021e84),
                    ),
                    items: _allSubRoles.map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(
                        s.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xff021e84),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _editedSubRoles[id] = v);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopLayout(List<DocumentSnapshot> pagedDocs, List<DocumentSnapshot> docs) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          decoration: const BoxDecoration(
            color: Color(0xff021e84),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            children: [
              const _HeaderCell('View Profile', flex: 1, textColor: Colors.white),
              const _HeaderCell('Username', flex: 2, textColor: Colors.white),
              const _HeaderCell('Email', flex: 3, textColor: Colors.white),
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    const Text(
                      'Created At',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: IconButton(
                        padding: const EdgeInsets.all(4),
                        icon: Icon(
                          _createdAtAscending ? Icons.arrow_upward : Icons.arrow_downward,
                          color: Colors.white,
                          size: 16,
                        ),
                        tooltip: _createdAtAscending ? 'Sort by newest' : 'Sort by oldest',
                        onPressed: () {
                          setState(() => _createdAtAscending = !_createdAtAscending);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.only(left: 30),
                  child: Text(
                    'Role',
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Text(
                    'Sub-Role',
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Center(
                  child: Text(
                    'Actions',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        
        Expanded(
          child: Container(
            color: Colors.grey[50],
            child: ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: pagedDocs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final d = pagedDocs[i];
                final data = d.data()! as Map<String, dynamic>;
                final id = d.id;
                final username = data['username'] as String? ?? '';
                final email = data['email'] as String? ?? '';
                final ts = data['createdAt'] as Timestamp?;
                final createdAt = ts != null ? _fmt.format(ts.toDate()) : '—';
                final currentRole = data['role'] as String? ?? '';
                final currentSubRole = subRolesToString(data['sub_roles']);
                final editedRole = _editedRoles[id] ?? currentRole;
                final editedSubRole = _editedSubRoles[id] ?? currentSubRole;

                return _HoverableRow(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xff021e84).withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              _showProfilePicture(context, username, data['profilePictureURL'] as String?, data);
                            },
                            icon: const Icon(Icons.photo_camera, size: 16),
                            label: const Text('View'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xff021e84),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              minimumSize: const Size(0, 36),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(width: 16),
                        
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 20),
                            child: Text(
                              username,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xff021e84),
                              ),
                            ),
                          ),
                        ),
                        
                        Expanded(
                          flex: 3,
                          child: Text(
                            email,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                        
                        Expanded(
                          flex: 2,
                          child: Text(
                            createdAt,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                        ),
                        
                        Expanded(
                          flex: 1,
                          child: Container(
                            margin: const EdgeInsets.only(right: 20),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xff021e84).withOpacity(0.2),
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: editedRole,
                                isExpanded: true,
                                icon: const Icon(
                                  Icons.keyboard_arrow_down,
                                  color: Color(0xff021e84),
                                  size: 20,
                                ),
                                items: _allRoles.map((r) => DropdownMenuItem(
                                  value: r,
                                  child: Text(
                                    r.toUpperCase(),
                                    style: const TextStyle(
                                      color: Color(0xff021e84),
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                )).toList(),
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _editedRoles[id] = v);
                                },
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(width: 16),
                        
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xff021e84).withOpacity(0.2),
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: validSubRole(editedSubRole),
                                isExpanded: true,
                                icon: const Icon(
                                  Icons.keyboard_arrow_down,
                                  color: Color(0xff021e84),
                                  size: 20,
                                ),
                                items: _allSubRoles.map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(
                                    s.toUpperCase(),
                                    style: const TextStyle(
                                      color: Color(0xff021e84),
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                )).toList(),
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _editedSubRoles[id] = v);
                                },
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(width: 16),
                        
                        Expanded(
                          flex: 1,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 20),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: editedRole != currentRole || editedSubRole != currentSubRole 
                                        ? const Color(0xff021e84)
                                        : Colors.grey[300],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: IconButton(
                                    icon: const Icon(Icons.save, color: Colors.white, size: 20),
                                    tooltip: 'Save role',
                                    onPressed: editedRole != currentRole || editedSubRole != currentSubRole
                                        ? () async {
                                            final confirmed = await DialogUtils.showDeleteConfirmationDialog(
                                              context: context,
                                              title: 'Confirm Save',
                                              message: 'Are you sure you want to save these changes for this user?',
                                              cancelText: 'Cancel',
                                              confirmText: 'Save',
                                            );
                                            if (confirmed != true) return;
                                            final newRole = _editedRoles[id];
                                            final newSubRole = _editedSubRoles[id];
                                            if (newRole != null && newRole != currentRole) {
                                              FirebaseFirestore.instance
                                                  .collection('users')
                                                  .doc(id)
                                                  .update({'role': newRole});
                                            }
                                            if (newSubRole != null && newSubRole != currentSubRole) {
                                              final subRoleToSave = newSubRole is List ? (newSubRole as List).join(',') : newSubRole.toString();
                                              FirebaseFirestore.instance
                                                  .collection('users')
                                                  .doc(id)
                                                  .update({'sub_roles': subRoleToSave});
                                            }
                                            setState(() {
                                              _editedRoles.remove(id);
                                              _editedSubRoles.remove(id);
                                            });
                                          }
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.white, size: 20),
                                    tooltip: 'Delete user',
                                    onPressed: () async {
                                      final confirmed = await DialogUtils.showDeleteConfirmationDialog(
                                        context: context,
                                        title: 'Delete User',
                                        message: 'Are you sure you want to delete this user? This action cannot be undone.',
                                        cancelText: 'Cancel',
                                        confirmText: 'Delete',
                                      );
                                      if (confirmed == true) {
                                        showDialog(
                                          context: context,
                                          barrierDismissible: false,
                                          builder: (context) => const Center(child: CircularProgressIndicator()),
                                        );
                                        final success = await _deleteUserFromBackend(email);
                                        Navigator.of(context).pop(); 
                                        if (success) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('User deleted from Auth and Firestore!'),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        } else {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Failed to delete user. Please check backend logs.'),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        
        Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            border: Border(
              top: BorderSide(
                color: Colors.grey[200]!,
                width: 1,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              RichText(
                text: TextSpan(
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
                  children: [
                    const TextSpan(text: 'Showing '),
                    TextSpan(
                      text: '${_currentPage * _rowsPerPage + 1}-${(_currentPage + 1) * _rowsPerPage > docs.length ? docs.length : (_currentPage + 1) * _rowsPerPage}',
                      style: const TextStyle(
                        color: Color(0xff021e84),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(text: ' of ${docs.length} users'),
                  ],
                ),
              ),
              Row(
                children: [
                  _PrettyNavButton(
                    label: 'Previous',
                    enabled: _currentPage > 0,
                    onTap: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xff021e84),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_currentPage + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _PrettyNavButton(
                    label: 'Next',
                    enabled: (_currentPage + 1) * _rowsPerPage < docs.length,
                    onTap: (_currentPage + 1) * _rowsPerPage < docs.length ? () => setState(() => _currentPage++) : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  final int flex;
  final Color textColor;

  const _HeaderCell(this.text, {required this.flex, this.textColor = const Color(0xff021e84)});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }
}

class _HoverableRow extends StatefulWidget {
  final Widget child;

  const _HoverableRow({required this.child});

  @override
  State<_HoverableRow> createState() => _HoverableRowState();
}

class _HoverableRowState extends State<_HoverableRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        color: _hovering ? const Color(0xff021e84).withOpacity(0.05) : Colors.white,
        child: widget.child,
      ),
    );
  }
}

class _PrettyNavButton extends StatefulWidget {
  final String label;
  final bool enabled;
  final VoidCallback? onTap;
  const _PrettyNavButton({required this.label, required this.enabled, this.onTap});

  @override
  State<_PrettyNavButton> createState() => _PrettyNavButtonState();
}

class _PrettyNavButtonState extends State<_PrettyNavButton> {
  bool _hovering = false;
  @override
  Widget build(BuildContext context) {
    final color = widget.enabled
        ? (_hovering ? const Color(0xff021e84).withOpacity(0.85) : const Color(0xff021e84))
        : Colors.grey.shade400;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: widget.enabled ? color.withOpacity(0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}
