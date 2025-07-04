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

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({Key? key}) : super(key: key);

  Future<String?> _convertDocxToHtml(Uint8List bytes, String filename) async {
    final uri = Uri.parse('http://localhost:8000/convert-docx'); 
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
              child: Container(
                width: MediaQuery.of(context).size.width * 0.8,
                height: MediaQuery.of(context).size.height * 0.8,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Preview: $sectionId',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Html(data: htmlContent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to convert DOCX to HTML.')),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading document: $e')),
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
          const SnackBar(content: Text('Document downloaded successfully')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error downloading document: $e')),
      );
    }
  }

  Future<void> _updateScreeningStatus(BuildContext context, DocumentSnapshot section, bool approved, {String? rejectionMessage}) async {
    try {
      final data = section.data() as Map<String, dynamic>;
      final sectionName = data['sectionTitle'] as String? ?? 'Unknown Section';
      final createdBy = data['createdBy'] as String? ?? 'Unknown User';
      final yearRange = context.read<SelectionModel>().yearRange ?? '2729';
      if (yearRange == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No year range selected. Cannot send notification.'))
        );
        return;
      }
      
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
        SnackBar(content: Text('Error updating status: $e')),
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
      builder: (context) => AlertDialog(
        title: const Text('Reject Section'),
        content: TextField(
          controller: _controller,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason for rejection',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff021e84),
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await _updateScreeningStatus(context, section, false, rejectionMessage: result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final yearRange = context.read<SelectionModel>().yearRange ?? '2729';
    return AdminRouteGuard(
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text(
            'Admin Dashboard',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF2D3748),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('issp_documents')
              .doc(yearRange)
              .collection('sections')
              .where('screening', isEqualTo: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Color(0xff021e84)));
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Center(
                child: Text(
                  'No sections pending screening',
                  style: TextStyle(fontSize: 16, color: Color(0xFF4A5568)),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;
                final sectionName = data['sectionTitle'] as String? ?? 'Unknown Section';
                final isFinalized = data['isFinalized'] as bool? ?? false;
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 2,
                        blurRadius: 8,
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              sectionName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2D3748),
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.download, color: Color(0xff021e84)),
                                  onPressed: () => _downloadDocument(context, yearRange, doc.id),
                                  tooltip: 'Download Document',
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Submitted by: ${data['createdBy'] ?? 'Unknown'}',
                          style: const TextStyle(
                            color: Color(0xFF4A5568),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => _showRejectionDialog(context, doc),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              child: const Text('Reject'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () async {
                                await _updateScreeningStatus(context, doc, true);
                                if (!isFinalized) {
                                  await _finalizeSection(context, doc.id, sectionName);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xff021e84),
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Approve'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}