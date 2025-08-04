import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../state/selection_model.dart';
import 'dart:async';

class PartIIIChecklist extends StatefulWidget {
  const PartIIIChecklist({Key? key}) : super(key: key);

  @override
  State<PartIIIChecklist> createState() => _PartIIIChecklistState();
}

class _PartIIIChecklistState extends State<PartIIIChecklist> {
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
      final yearRange = context.read<SelectionModel>().yearRange ?? '2729';
      final docs = await Future.wait([
        FirebaseFirestore.instance
            .collection('issp_documents')
            .doc(yearRange)
            .collection('sections')
            .doc('III.A')
            .get(),
        FirebaseFirestore.instance
            .collection('issp_documents')
            .doc(yearRange)
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
        
        final iiiaSubRoles = <String>{};
        final iiibSubRoles = <String>{};
        final iiiaSubmittedSubRoles = <String>{};
        final iiibSubmittedSubRoles = <String>{};
        
        for (final project in iiiaProjects) {
          final subRoles = List<String>.from(project['sub_roles'] ?? []);
          iiiaSubRoles.addAll(subRoles);
          if (subRoles.isNotEmpty) {
            iiiaSubmittedSubRoles.addAll(subRoles);
          }
        }
        
        for (final project in iiibProjects) {
          final subRoles = List<String>.from(project['sub_roles'] ?? []);
          iiibSubRoles.addAll(subRoles);
          if (subRoles.isNotEmpty) {
            iiibSubmittedSubRoles.addAll(subRoles);
          }
        }
        
        final sortedIIIA = iiiaSubRoles.toList()..sort();
        final sortedIIIB = iiibSubRoles.toList()..sort();
        
        final totalSubRoles = (iiiaSubRoles.length + iiibSubRoles.length);
        final totalSubmitted = (iiiaSubmittedSubRoles.length + iiibSubmittedSubRoles.length);
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
} 