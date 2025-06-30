import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'services/notification_service.dart';
import 'package:provider/provider.dart';
import 'state/selection_model.dart';
import 'utils/user_utils.dart';
import 'dart:async';

class HistoryPage extends StatelessWidget {
  const HistoryPage({Key? key}) : super(key: key);

  Future<void> _toggleFinalizedStatus(BuildContext context, DocumentSnapshot section) async {
    final data = section.data() as Map<String, dynamic>;
    final currentStatus = data['isFinalized'] as bool? ?? false;
    
    if (!currentStatus) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sections can only be finalized from their respective pages'))
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    
    if (!userDoc.exists) return;
    
    final role = (userDoc.data()?['role'] as String?)?.toLowerCase() ?? '';
    if (role != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only administrators can unfinalize sections'))
      );
      return;
    }

    try {
      await section.reference.update({
        'isFinalized': false,
        'lastModified': FieldValue.serverTimestamp(),
      });
      
      await createUnfinalizationNotification(
        data['sectionTitle'] ?? section.id,
        context.read<SelectionModel>().yearRange ?? '2729',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating status: $e'))
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final yearRange = context.read<SelectionModel>().yearRange ?? '2729';
    final sectionsRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(yearRange)
        .collection('sections');

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser?.uid)
          .snapshots(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
          return const Scaffold(
            body: Center(
              child: Text('Access denied. Please log in.'),
            ),
          );
        }

        final userData = userSnapshot.data!.data() as Map<String, dynamic>;
        final role = (userData['role'] as String?)?.toLowerCase() ?? '';

        if (role != 'admin' && role != 'editor') {
          return const Scaffold(
            body: Center(
              child: Text('Access denied. Editor privileges required.'),
            ),
          );
        }

        final bool isAdmin = role == 'admin';

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: Text(
              'History • ${formatYearRange(yearRange)}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            centerTitle: true,
            elevation: 0,
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF2D3748),
          ),
          body: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                Container(
                  color: Colors.white,
                  child: const TabBar(
                    labelColor: Color(0xff021e84),
                    unselectedLabelColor: Color(0xFF4A5568),
                    indicatorColor: Color(0xff021e84),
                    tabs: [
                      Tab(text: 'Section History'),
                      Tab(text: 'Part III Checklist'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildSectionHistoryTab(sectionsRef, isAdmin),
                      _buildPartIIIChecklistTab(yearRange),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHistoryTab(CollectionReference sectionsRef, bool isAdmin) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 2,
                blurRadius: 8,
                offset: const Offset(0, 2),
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
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Note',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D3748),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                isAdmin 
                  ? 'You can unfinalize a section by clicking its status chip, but sections can only be finalized from their respective pages.'
                  : 'You can view the history of sections. Only administrators can unfinalize sections.',
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF4A5568),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: sectionsRef.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting)
                return const Center(child: CircularProgressIndicator(color: Color(0xff021e84)));
              if (snap.hasError)
                return Center(child: Text('Error: ${snap.error}'));

              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty)
                return const Center(
                  child: Text(
                    'No sections found.',
                    style: TextStyle(fontSize: 16, color: Color(0xFF4A5568)),
                  ),
                );

              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final docSnap = docs[i];
                  final data = docSnap.data() as Map<String, dynamic>;
                  final isFinalized = data['isFinalized'] == true;

                  String formatTimestamp(dynamic ts) {
                    if (ts is Timestamp) {
                      return DateFormat.yMMMd().add_jm().format(ts.toDate());
                    }
                    return '—';
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xff021e84).withOpacity(0.13),
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
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        dividerColor: Colors.transparent, 
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        unselectedWidgetColor: const Color(0xff021e84),
                        colorScheme: Theme.of(context).colorScheme.copyWith(
                          primary: const Color(0xff021e84),
                        ),
                      ),
                      child: ExpansionTile(
                        leading: Icon(Icons.folder_open, color: const Color(0xff021e84)),
                        title: Text(
                          docSnap.id,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2D3748),
                          ),
                        ),
                        subtitle: Text(
                          'Last modified: ${formatTimestamp(data['lastModified'])}',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF4A5568)),
                        ),
                        childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        children: [
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              if (isAdmin) ...[
                                InkWell(
                                  onTap: () => _toggleFinalizedStatus(context, docSnap),
                                  child: Chip(
                                    avatar: Icon(
                                      isFinalized ? Icons.check_circle : Icons.hourglass_bottom,
                                      size: 20,
                                      color: isFinalized ? const Color(0xff021e84) : const Color(0xFF4A5568),
                                    ),
                                    label: Text(
                                      isFinalized ? 'Finalized' : 'In Progress',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isFinalized ? const Color(0xff021e84) : const Color(0xFF4A5568),
                                      ),
                                    ),
                                    backgroundColor: isFinalized 
                                      ? const Color(0xff021e84).withOpacity(0.1)
                                      : const Color(0xFF4A5568).withOpacity(0.1),
                                  ),
                                ),
                              ] else ...[
                                Chip(
                                  avatar: Icon(
                                    isFinalized ? Icons.check_circle : Icons.hourglass_bottom,
                                    size: 20,
                                    color: isFinalized ? const Color(0xff021e84) : const Color(0xFF4A5568),
                                  ),
                                  label: Text(
                                    isFinalized ? 'Finalized' : 'In Progress',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isFinalized ? const Color(0xff021e84) : const Color(0xFF4A5568),
                                    ),
                                  ),
                                  backgroundColor: isFinalized 
                                    ? const Color(0xff021e84).withOpacity(0.1)
                                    : const Color(0xFF4A5568).withOpacity(0.1),
                                ),
                              ],
                              Chip(
                                avatar: const Icon(Icons.person, size: 20, color: Color(0xff021e84)),
                                label: Text(
                                  data['modifiedBy'] ?? data['createdBy'] ?? '—',
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF4A5568)),
                                ),
                                backgroundColor: const Color(0xff021e84).withOpacity(0.1),
                              ),
                              Chip(
                                avatar: const Icon(Icons.calendar_today, size: 20, color: Color(0xff021e84)),
                                label: Text(
                                  'Modified: ${formatTimestamp(data['lastModified'])}',
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF4A5568)),
                                ),
                                backgroundColor: const Color(0xff021e84).withOpacity(0.1),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPartIIIChecklistTab(String yearRange) {
    return _PartIIIChecklistWidget(yearRange: yearRange);
  }
}

class _PartIIIChecklistWidget extends StatefulWidget {
  final String yearRange;
  
  const _PartIIIChecklistWidget({required this.yearRange});
  
  @override
  State<_PartIIIChecklistWidget> createState() => _PartIIIChecklistWidgetState();
}

class _PartIIIChecklistWidgetState extends State<_PartIIIChecklistWidget> {
  late StreamController<List<DocumentSnapshot>> _streamController;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _streamController = StreamController<List<DocumentSnapshot>>.broadcast();
    _loadData();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _streamController.close();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    try {
      final docs = await Future.wait([
        FirebaseFirestore.instance
            .collection('issp_documents')
            .doc(widget.yearRange)
            .collection('sections')
            .doc('III.A')
            .get(),
        FirebaseFirestore.instance
            .collection('issp_documents')
            .doc(widget.yearRange)
            .collection('sections')
            .doc('III.B')
            .get(),
      ]);
      
      if (!_streamController.isClosed) {
        _streamController.add(docs);
      }
    } catch (e) {
      if (!_streamController.isClosed) {
        _streamController.addError(e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DocumentSnapshot>>(
      stream: _streamController.stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && snapshot.data == null) {
          return const Center(child: CircularProgressIndicator(color: Color(0xff021e84)));
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        
        final docs = snapshot.data ?? [];
        final iiiaDoc = docs.isNotEmpty ? docs[0] : null;
        final iiibDoc = docs.length > 1 ? docs[1] : null;
        
        final iiiaData = iiiaDoc?.data() as Map<String, dynamic>?;
        final iiibData = iiibDoc?.data() as Map<String, dynamic>?;
        
        final iiiaProjects = iiiaData?['projects'] as List<dynamic>? ?? [];
        final iiibProjects = iiibData?['projects'] as List<dynamic>? ?? [];
        
        // Collect sub-roles for each part separately
        final iiiaSubRoles = <String>{};
        final iiibSubRoles = <String>{};
        final iiiaSubmittedSubRoles = <String>{};
        final iiibSubmittedSubRoles = <String>{};
        
        // Process III.A projects
        for (final project in iiiaProjects) {
          final subRoles = List<String>.from(project['sub_roles'] ?? []);
          iiiaSubRoles.addAll(subRoles);
          if (subRoles.isNotEmpty) {
            iiiaSubmittedSubRoles.addAll(subRoles);
          }
        }
        
        // Process III.B projects
        for (final project in iiibProjects) {
          final subRoles = List<String>.from(project['sub_roles'] ?? []);
          iiibSubRoles.addAll(subRoles);
          if (subRoles.isNotEmpty) {
            iiibSubmittedSubRoles.addAll(subRoles);
          }
        }
        
        final sortedIIIA = iiiaSubRoles.toList()..sort();
        final sortedIIIB = iiibSubRoles.toList()..sort();
        
        // Overall statistics
        final totalSubRoles = (iiiaSubRoles.length + iiibSubRoles.length);
        final totalSubmitted = (iiiaSubmittedSubRoles.length + iiibSubmittedSubRoles.length);
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xff021e84).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xff021e84).withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xff021e84).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.checklist,
                        color: Color(0xff021e84),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Part III Submission Checklist',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2D3748),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                'Sub-roles that have submitted their Part III projects',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: const Color(0xFF4A5568),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Auto-refresh every 5s',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.green,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Part III.A Section
              if (sortedIIIA.isNotEmpty) ...[
                _buildPartSection(
                  'Part III.A - Internal Systems Development Components',
                  Icons.laptop,
                  sortedIIIA,
                  iiiaSubmittedSubRoles,
                  const Color(0xff021e84),
                ),
                const SizedBox(height: 24),
              ],
              
              // Part III.B Section
              if (sortedIIIB.isNotEmpty) ...[
                _buildPartSection(
                  'Part III.B - Cross-Agency ICT Projects',
                  Icons.link,
                  sortedIIIB,
                  iiibSubmittedSubRoles,
                  const Color(0xff1e40af),
                ),
                const SizedBox(height: 24),
              ],
              
              // Show empty state if no sub-roles found in either part
              if (sortedIIIA.isEmpty && sortedIIIB.isEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: const Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 48,
                          color: Color(0xFF4A5568),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No sub-roles found in Part III',
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFF4A5568),
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Sub-roles will appear here once projects are created',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF4A5568),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildPartSection(String title, IconData icon, List<String> subRoles, Set<String> submittedSubRoles, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: color.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Section Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2D3748),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: submittedSubRoles.length == subRoles.length && subRoles.isNotEmpty
                        ? Colors.green.withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: submittedSubRoles.length == subRoles.length && subRoles.isNotEmpty
                          ? Colors.green
                          : Colors.orange,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '${submittedSubRoles.length}/${subRoles.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: submittedSubRoles.length == subRoles.length && subRoles.isNotEmpty
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Sub-roles List
          ...subRoles.asMap().entries.map((entry) {
            final index = entry.key;
            final subRole = entry.value;
            final isSubmitted = submittedSubRoles.contains(subRole);
            
            return Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: index < subRoles.length - 1
                        ? Colors.grey.shade200
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSubmitted
                        ? Colors.green.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isSubmitted ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: isSubmitted ? Colors.green : Colors.grey,
                    size: 20,
                  ),
                ),
                title: Text(
                  subRole,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isSubmitted ? const Color(0xFF2D3748) : Colors.grey.shade600,
                  ),
                ),
                subtitle: Text(
                  isSubmitted ? 'Submitted' : 'Not submitted',
                  style: TextStyle(
                    fontSize: 14,
                    color: isSubmitted ? Colors.green : Colors.grey.shade500,
                    fontWeight: isSubmitted ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSubmitted
                        ? Colors.green.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSubmitted ? Colors.green : Colors.grey,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    isSubmitted ? '✓' : '○',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isSubmitted ? Colors.green : Colors.grey,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(String label, bool isComplete) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isComplete ? Icons.check_circle : Icons.circle_outlined,
          color: isComplete ? Colors.green : Colors.grey,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: isComplete ? Colors.green : Colors.grey,
            fontWeight: isComplete ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildProjectCard(int index, Map<String, dynamic> project, String partType) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: const Color(0xff021e84).withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xff021e84),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    project['name'] ?? 'Unnamed Project',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D3748),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xff021e84).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    partType,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xff021e84),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildProjectField('Objectives', project['objectives']),
            _buildProjectField('Duration', project['duration']),
            _buildProjectField('Deliverables', project['deliverables'] is List 
              ? (project['deliverables'] as List).join(', ')
              : project['deliverables']),
            _buildProjectField('Project', project['sub_roles'] is List 
              ? (project['sub_roles'] as List).join(', ')
              : project['sub_roles']),
            _buildProjectField('Submitted By', project['submitted_by']),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectField(String label, dynamic value) {
    if (value == null || value.toString().isEmpty) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF4A5568),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.toString(),
              style: const TextStyle(
                color: Color(0xFF2D3748),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
