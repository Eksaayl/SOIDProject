import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class HistoryPage extends StatelessWidget {
  final String documentId;
  const HistoryPage({Key? key, required this.documentId}) : super(key: key);

  Future<void> _toggleFinalizedStatus(BuildContext context, DocumentSnapshot section) async {
    final data = section.data() as Map<String, dynamic>;
    final currentStatus = data['isFinalized'] as bool? ?? false;
    
    // Only allow unfinalizing (true -> false), not finalizing (false -> true)
    if (!currentStatus) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sections can only be finalized from their respective pages'))
      );
      return;
    }

    try {
      await section.reference.update({
        'isFinalized': false,
        'lastModified': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating status: $e'))
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sectionsRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(documentId)
        .collection('sections');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'History • $documentId',
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
      body: Column(
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
                const Text(
                  'You can unfinalize a section by clicking its status chip, but sections can only be finalized from their respective pages.',
                  style: TextStyle(
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
                          dividerColor: Colors.transparent, // Remove black line
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
                            data['sectionTitle'] ?? docSnap.id,
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
                                Chip(
                                  avatar: const Icon(Icons.person, size: 20, color: Color(0xff021e84)),
                                  label: Text(
                                    data['createdBy'] ?? '—',
                                    style: const TextStyle(fontSize: 13, color: Color(0xFF4A5568)),
                                  ),
                                  backgroundColor: const Color(0xff021e84).withOpacity(0.1),
                                ),
                                Chip(
                                  avatar: const Icon(Icons.calendar_today, size: 20, color: Color(0xff021e84)),
                                  label: Text(
                                    'Created: ${formatTimestamp(data['createdAt'])}',
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
      ),
    );
  }
}
