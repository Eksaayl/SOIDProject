import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class HistoryPage extends StatelessWidget {
  final String documentId;
  const HistoryPage({Key? key, required this.documentId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final sectionsRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(documentId)
        .collection('sections');

    return Scaffold(
      appBar: AppBar(
        title: Text('History • $documentId'),
        centerTitle: true,
      ),
      body: FutureBuilder<QuerySnapshot>(
        future: sectionsRef.get(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting)
            return Center(child: CircularProgressIndicator());
          if (snap.hasError)
            return Center(child: Text('Error: ${snap.error}'));

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty)
            return Center(child: Text('No sections found.', style: TextStyle(fontSize: 16)));

          return ListView.builder(
            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final docSnap = docs[i];
              final data = docSnap.data() as Map<String, dynamic>;

              String formatTimestamp(dynamic ts) {
                if (ts is Timestamp) {
                  return DateFormat.yMMMd().add_jm().format(ts.toDate());
                }
                return '—';
              }

              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                margin: EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  leading: Icon(Icons.folder_open, color: Theme.of(context).primaryColor),
                  title: Text(
                    data['sectionTitle'] ?? docSnap.id,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Last modified: ${formatTimestamp(data['lastModified'])}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  childrenPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    SizedBox(height: 12),

                    // metadata chips row
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Chip(
                          avatar: Icon(
                            data['isFinalized'] == true ? Icons.check_circle : Icons.hourglass_bottom,
                            size: 20,
                            color: data['isFinalized'] == true ? Colors.green : Colors.orange,
                          ),
                          label: Text(
                            data['isFinalized'] == true ? 'Finalized' : 'In Progress',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        Chip(
                          avatar: Icon(Icons.person, size: 20),
                          label: Text(
                            data['createdBy'] ?? '—',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        Chip(
                          avatar: Icon(Icons.calendar_today, size: 20),
                          label: Text(
                            'Created: ${formatTimestamp(data['createdAt'])}',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 8),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
