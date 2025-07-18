import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_html/flutter_html.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'admin_route_guard.dart';
import 'services/notification_service.dart';
import 'utils/user_utils.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'state/selection_model.dart';
import '../config.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({Key? key}) : super(key: key);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> with TickerProviderStateMixin {
  late TabController _tabController;
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Pending', 'Approved', 'Rejected'];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Set<String> _selectedSections = <String>{};
  bool _isSelectMode = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<String?> _convertDocxToHtml(Uint8List bytes, String filename) async {
    final uri = Uri.parse('${Config.serverUrl}/convert-docx');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final response = await request.send();
    final respStr = await response.stream.bytesToString();
    if (response.statusCode == 200) {
      final data = json.decode(respStr);
      return data['html'] as String?;
    } else {
      return null;
    }
  }

  Future<void> _viewDocument(BuildContext context, String documentId, String sectionId) async {
    try {
      final storage = FirebaseStorage.instance;
      final ref = storage.ref().child('$documentId/$sectionId/document.docx');
      final bytes = await ref.getData();
      if (bytes != null) {
        final htmlContent = await _convertDocxToHtml(bytes, '$sectionId.docx');
        if (htmlContent != null) {
          showDialog(
            context: context,
            builder: (context) => Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.9,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white,
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xff021e84), Color(0xff1e40af)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
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
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.visibility, color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Preview: $sectionId',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        child: SingleChildScrollView(
                          child: Html(data: htmlContent),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to convert DOCX to HTML.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading document: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _downloadDocument(BuildContext context, String documentId, String sectionId) async {
    try {
      final storage = FirebaseStorage.instance;
      final ref = storage.ref().child('$documentId/$sectionId/document.docx');
      final bytes = await ref.getData();
      if (bytes != null) {
        if (kIsWeb) {
          await FileSaver.instance.saveFile(
            name: '${sectionId}_document.docx',
            bytes: bytes,
            mimeType: MimeType.microsoftWord,
          );
        } else {
          final directory = await getApplicationDocumentsDirectory();
          final file = File('${directory.path}/${sectionId}_document.docx');
          await file.writeAsBytes(bytes);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Document downloaded successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error downloading document: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _updateScreeningStatus(BuildContext context, DocumentSnapshot section, bool approved, {String? rejectionMessage}) async {
    try {
      final data = section.data() as Map<String, dynamic>;
      final sectionName = data['sectionTitle'] as String? ?? 'Unknown Section';
      final createdBy = data['createdBy'] as String? ?? 'Unknown User';
      final yearRange = context.read<SelectionModel>().yearRange ?? '2729';

      if (approved) {
        await section.reference.update({
          'screening': FieldValue.delete(),
          'isFinalized': true,
          'screeningDate': FieldValue.serverTimestamp(),
          'screenedBy': await getCurrentUsername(),
        });
        await createFinalizationNotification(sectionName, yearRange);
      } else {
        await section.reference.update({
          'isFinalized': false,
          'screening': false,
          'screeningDate': FieldValue.serverTimestamp(),
          'screenedBy': await getCurrentUsername(),
          'rejectionMessage': rejectionMessage,
        });
        await createRejectionNotification(sectionName, rejectionMessage ?? 'No reason provided', yearRange);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approved ? 'Section approved and finalized successfully' : 'Section rejected successfully'),
          backgroundColor: approved ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _finalizeSection(BuildContext context, String sectionId, String sectionName) async {
    try {
      final yearRange = context.read<SelectionModel>().yearRange ?? '2729';
      await FirebaseFirestore.instance
          .collection('issp_documents')
          .doc(yearRange)
          .collection('sections')
          .doc(sectionId)
          .update({
        'isFinalized': true,
        'finalizedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error finalizing section: $e');
    }
  }

  Future<void> _showRejectionDialog(BuildContext context, DocumentSnapshot section) async {
    final TextEditingController _controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _PrettyRejectionDialog(controller: _controller),
    );
    if (result != null && result.isNotEmpty) {
      await _updateScreeningStatus(context, section, false, rejectionMessage: result);
    }
  }

  Widget _buildStatusChip(String status) {
    Color color;
    IconData icon;
    Color backgroundColor;
    Color borderColor;

    switch (status.toLowerCase()) {
      case 'pending':
        color = const Color(0xFFF59E0B);
        backgroundColor = const Color(0xFFFFFBEB);
        borderColor = const Color(0xFFFCD34D);
        icon = Icons.schedule;
        break;
      case 'approved':
        color = const Color(0xFF059669);
        backgroundColor = const Color(0xFFECFDF5);
        borderColor = const Color(0xFF6EE7B7);
        icon = Icons.check_circle;
        break;
      case 'rejected':
        color = const Color(0xFFDC2626);
        backgroundColor = const Color(0xFFFEF2F2);
        borderColor = const Color(0xFFFCA5A5);
        icon = Icons.cancel;
        break;
      default:
        color = const Color(0xFF6B7280);
        backgroundColor = const Color(0xFFF9FAFB);
        borderColor = const Color(0xFFD1D5DB);
        icon = Icons.help;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            status,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(BuildContext context, DocumentSnapshot doc, Map<String, dynamic> data) {
    final sectionName = data['sectionTitle'] as String? ?? 'Unknown Section';
    final createdBy = data['createdBy'] as String? ?? 'Unknown';
    final submittedAt = data['submittedAt'] as Timestamp?;
    final isFinalized = data['isFinalized'] as bool? ?? false;
    final screening = data['screening'];

    String status = 'Pending';
    if (isFinalized) {
      status = 'Approved';
    } else if (screening == false) {
      status = 'Rejected';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            const Color(0xFFF8FAFC),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff021e84).withOpacity(0.08),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.grey.withOpacity(0.06),
            spreadRadius: 0,
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
        border: Border.all(
          color: const Color(0xff021e84).withOpacity(0.08),
          width: 1.5,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.9),
              Colors.white.withOpacity(0.7),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xff021e84), Color(0xff1e40af)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xff021e84).withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.description,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sectionName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A202C),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.person_outline,
                                    size: 14,
                                    color: const Color(0xFF4A5568),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    createdBy,
                                    style: const TextStyle(
                                      color: Color(0xFF4A5568),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (submittedAt != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule_outlined,
                                size: 14,
                                color: const Color(0xFF718096),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatDate(submittedAt.toDate()),
                                style: const TextStyle(
                                  color: Color(0xFF718096),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  _buildStatusChip(status),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 120,
                          child: _buildActionButton(
                            icon: Icons.download,
                            label: 'Download',
                            color: Colors.green,
                            onPressed: () => _downloadDocument(context, context.read<SelectionModel>().yearRange ?? '2729', doc.id),
                          ),
                        ),
                      ],
                    ),
                    if (screening == true) ...[
                      const SizedBox(height: 16),
                      Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              const Color(0xFFE2E8F0),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 120,
                            child: _buildActionButton(
                              icon: Icons.cancel,
                              label: 'Reject',
                              color: Colors.red,
                              onPressed: () => _showRejectionDialog(context, doc),
                            ),
                          ),
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 120,
                            child: _buildActionButton(
                              icon: Icons.check_circle,
                              label: 'Approve',
                              color: Colors.green,
                              onPressed: () async {
                                await _updateScreeningStatus(context, doc, true);
                                if (!isFinalized) {
                                  await _finalizeSection(context, doc.id, sectionName);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildSearchAndFilters() {
    return Container(
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
          TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value.toLowerCase();
              });
            },
            decoration: InputDecoration(
              hintText: 'Search sections...',
              prefixIcon: const Icon(Icons.search, color: Color(0xff021e84)),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xff021e84)),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Filter by status:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4A5568),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: _filters.map((filter) {
                    final isSelected = _selectedFilter == filter;
                    return FilterChip(
                      label: Text(filter),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          _selectedFilter = selected ? filter : 'All';
                        });
                      },
                      backgroundColor: Colors.grey.shade100,
                      selectedColor: const Color(0xff021e84).withOpacity(0.2),
                      checkmarkColor: const Color(0xff021e84),
                      labelStyle: TextStyle(
                        color: isSelected ? const Color(0xff021e84) : Colors.grey.shade700,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected ? const Color(0xff021e84) : Colors.grey.shade300,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _matchesSearch(Map<String, dynamic> data) {
    if (_searchQuery.isEmpty) return true;

    final sectionName = (data['sectionTitle'] as String? ?? '').toLowerCase();
    final createdBy = (data['createdBy'] as String? ?? '').toLowerCase();

    return sectionName.contains(_searchQuery) || createdBy.contains(_searchQuery);
  }

  bool _matchesFilter(Map<String, dynamic> data) {
    if (_selectedFilter == 'All') return true;

    final isFinalized = data['isFinalized'] as bool? ?? false;
    final screening = data['screening'];

    String status = 'Pending';
    if (isFinalized) {
      status = 'Approved';
    } else if (screening == false) {
      status = 'Rejected';
    }

    return status == _selectedFilter;
  }

  @override
  Widget build(BuildContext context) {
    final yearRange = context.read<SelectionModel>().yearRange ?? '2729';
    return AdminRouteGuard(
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FAFC),
        appBar: AppBar(
          title: const Text(
            'Admin Dashboard',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 24,
              color: Colors.black,
            ),
          ),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.black),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xff021e84),
            indicatorWeight: 3,
            labelColor: const Color(0xff021e84),
            unselectedLabelColor: Colors.grey,
            tabs: const [
              Tab(text: 'Pending Review'),
              Tab(text: 'All Sections'),
              Tab(text: 'Statistics'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildPendingReviewTab(yearRange),
            _buildAllSectionsTab(yearRange),
            _buildStatisticsTab(yearRange),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingReviewTab(String yearRange) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('issp_documents')
          .doc(yearRange)
          .collection('sections')
          .where('screening', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Color(0xff021e84)),
                SizedBox(height: 16),
                Text(
                  'Loading pending reviews...',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF4A5568),
                  ),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'Error: ${snapshot.error}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF4A5568),
                  ),
                ),
              ],
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
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
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: Colors.green.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No sections pending review',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D3748),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'All sections have been reviewed',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF4A5568),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildSectionCard(context, doc, data);
          },
        );
      },
    );
  }

  Widget _buildAllSectionsTab(String yearRange) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('issp_documents')
          .doc(yearRange)
          .collection('sections')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xff21e84)));
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'No sections found',
              style: TextStyle(fontSize: 16, color: Color(0xFF4A5568)),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildSectionCard(context, doc, data);
          },
        );
      },
    );
  }

  Widget _buildStatisticsTab(String yearRange) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('issp_documents')
          .doc(yearRange)
          .collection('sections')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xff21e84)));
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final docs = snapshot.data?.docs ?? [];

        int pending = 0;
        int approved = 0;
        int rejected = 0;

        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final isFinalized = data['isFinalized'] as bool? ?? false;
          final screening = data['screening'];

          if (isFinalized) {
            approved++;
          } else if (screening == false) {
            rejected++;
          } else if (screening == true) {
            pending++;
          }
        }

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _buildStatCard(
                title: 'Total Sections',
                value: docs.length.toString(),
                icon: Icons.folder,
                color: const Color(0xff021e84),
              ),
              const SizedBox(height: 16),
              _buildStatCard(
                title: 'Pending Review',
                value: pending.toString(),
                icon: Icons.pending,
                color: Colors.orange,
              ),
              const SizedBox(height: 16),
              _buildStatCard(
                title: 'Approved',
                value: approved.toString(),
                icon: Icons.check_circle,
                color: Colors.green,
              ),
              const SizedBox(height: 16),
              _buildStatCard(
                title: 'Rejected',
                value: rejected.toString(),
                icon: Icons.cancel,
                color: Colors.red,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF4A5568),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchActionsBar() {
    if (!_isSelectMode || _selectedSections.isEmpty) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xff021e84), Color(0xff1e40af)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff021e84).withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle,
            color: Colors.white,
            size: 24,
          ),
          const SizedBox(width: 12),
          Text(
            '${_selectedSections.length} section${_selectedSections.length == 1 ? '' : 's'} selected',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              _buildBatchActionButton(
                icon: Icons.download,
                label: 'Download All',
                onPressed: () => _downloadSelectedSections(),
              ),
              const SizedBox(width: 8),
              _buildBatchActionButton(
                icon: Icons.check_circle,
                label: 'Approve All',
                onPressed: () => _approveSelectedSections(),
              ),
              const SizedBox(width: 8),
              _buildBatchActionButton(
                icon: Icons.cancel,
                label: 'Reject All',
                onPressed: () => _rejectSelectedSections(),
              ),
              const SizedBox(width: 8),
              _buildBatchActionButton(
                icon: Icons.close,
                label: 'Clear',
                onPressed: () {
                  setState(() {
                    _selectedSections.clear();
                    _isSelectMode = false;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBatchActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 18),
        label: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }

  Future<void> _downloadSelectedSections() async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Downloading ${_selectedSections.length} sections...'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  Future<void> _approveSelectedSections() async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Approving ${_selectedSections.length} sections...'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _rejectSelectedSections() async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Rejecting ${_selectedSections.length} sections...'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

class _PrettyRejectionDialog extends StatelessWidget {
  final TextEditingController controller;
  const _PrettyRejectionDialog({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      elevation: 20,
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xff021e84), Color(0xff1e40af)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.cancel, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Reject Section',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFECACA),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Color.fromARGB(255, 132, 2, 2),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Please provide a reason for rejecting this section. The submitter will be notified.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF7F1D1D),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Reason for rejection',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xff021e84)),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color.fromARGB(255, 132, 2, 2), Color.fromARGB(255, 175, 30, 30)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Color.fromARGB(255, 175, 30, 30).withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(controller.text.trim()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Reject',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}