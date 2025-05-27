import 'package:flutter/material.dart';
import 'part_ii/part_ii_a.dart';
import 'part_ii/part_ii_b.dart';
import 'part_ii/part_ii_c.dart';
import 'part_ii/part_ii_d.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:file_saver/file_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'dart:typed_data';
import '../config.dart';

class Part2 extends StatefulWidget {
  const Part2({super.key});

  @override
  _Part2State createState() => _Part2State();
}

class _Part2State extends State<Part2> {
  int _selectedIndex = -1;
  bool _isCompiling = false;
  static const _docId = 'document';

  Future<void> uploadGeneratedDocxToStorage(String documentId, String part, List<int> docxBytes) async {
    final storage = FirebaseStorage.instance;
    final ref = storage.ref().child('$documentId/$part/document.docx');
    await ref.putData(Uint8List.fromList(docxBytes));
  }

  Future<void> mergePartIIDocuments(BuildContext context, String documentId) async {
    try {
      final storage = FirebaseStorage.instance;
      final firestore = FirebaseFirestore.instance;
      setState(() => _isCompiling = true);

      // Check if all sections are finalized
      final sectionRefs = await Future.wait([
        firestore.collection('issp_documents').doc(documentId).collection('sections').doc('II.A').get(),
        firestore.collection('issp_documents').doc(documentId).collection('sections').doc('II.B').get(),
        firestore.collection('issp_documents').doc(documentId).collection('sections').doc('II.C').get(),
        firestore.collection('issp_documents').doc(documentId).collection('sections').doc('II.D').get(),
      ]);

      final notFinalized = <String>[];
      for (var i = 0; i < sectionRefs.length; i++) {
        final data = sectionRefs[i].data();
        if (data == null || !(data['finalized'] as bool? ?? false)) {
          notFinalized.add(['II.A', 'II.B', 'II.C', 'II.D'][i]);
        }
      }

      if (notFinalized.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please finalize the following sections first: ${notFinalized.join(", ")}'))
        );
        return;
      }

      // Get all Part II documents from storage
      final ii_a_bytes = await storage.ref().child('$documentId/II.A/document.docx').getData();
      final ii_b_bytes = await storage.ref().child('$documentId/II.B/document.docx').getData();
      final ii_c_bytes = await storage.ref().child('$documentId/II.C/document.docx').getData();
      final ii_d_bytes = await storage.ref().child('$documentId/II.D/document.docx').getData();

      if (ii_a_bytes == null || ii_b_bytes == null || ii_c_bytes == null || ii_d_bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('One or more Part II documents are missing. Please ensure all parts are finalized.'))
        );
        return;
      }

      // Create multipart request for merging
      final merge_request = http.MultipartRequest(
        'POST',
        Uri.parse('${Config.serverUrl}/merge-documents-part-ii'),
      );

      // Add all documents
      merge_request.files.add(http.MultipartFile.fromBytes('part_ii_a', ii_a_bytes, filename: 'part_ii_a.docx'));
      merge_request.files.add(http.MultipartFile.fromBytes('part_ii_b', ii_b_bytes, filename: 'part_ii_b.docx'));
      merge_request.files.add(http.MultipartFile.fromBytes('part_ii_c', ii_c_bytes, filename: 'part_ii_c.docx'));
      merge_request.files.add(http.MultipartFile.fromBytes('part_ii_d', ii_d_bytes, filename: 'part_ii_d.docx'));

      // Send merge request
      final merge_response = await merge_request.send();
      if (merge_response.statusCode != 200) {
        final error = await merge_response.stream.bytesToString();
        throw Exception('Failed to merge documents: ${merge_response.statusCode} - $error');
      }

      // Get merged document
      final responseBytes = await merge_response.stream.toBytes();

      // Save the merged document to storage
      final mergedRef = storage.ref().child('$documentId/part_ii_merged.docx');
      await mergedRef.putData(responseBytes);

      // Update Firestore with merged document path
      await firestore.collection('issp_documents').doc(documentId).update({
        'partIIMergedPath': '$documentId/part_ii_merged.docx',
        'lastModified': FieldValue.serverTimestamp(),
      });

      // Download the merged document
      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'Part_II_Merged_${DateTime.now().millisecondsSinceEpoch}.docx',
          bytes: responseBytes,
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/Part_II_Merged_${DateTime.now().millisecondsSinceEpoch}.docx');
        await file.writeAsBytes(responseBytes);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Documents merged successfully'))
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error merging documents: $e'))
      );
    } finally {
      setState(() => _isCompiling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isSmallScreen = MediaQuery.of(context).size.width < 650;

    return isSmallScreen
        ? Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),
                  const Text(
                    'INFORMATION SYSTEMS STRATEGY',
                    style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildTopButton('Part II.A', Icons.insights, 0),
                          const SizedBox(width: 16),
                          _buildTopButton('Part II.B', Icons.book, 1),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildTopButton('Part II.C', Icons.storage, 2),
                          const SizedBox(width: 16),
                          _buildTopButton('Part II.D', Icons.network_cell, 3),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_isCompiling)
                    const CircularProgressIndicator()
                  else
                    ElevatedButton.icon(
                      onPressed: () => mergePartIIDocuments(context, _docId),
                      icon: const Icon(Icons.merge_type),
                      label: const Text('Merge All Parts II'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xff021e84),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'INFORMATION SYSTEMS STRATEGY',
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildTopButton('Part II.A', Icons.insights, 0),
                  const SizedBox(width: 16),
                  _buildTopButton('Part II.B', Icons.book, 1),
                  const SizedBox(width: 16),
                  _buildTopButton('Part II.C', Icons.storage, 2),
                  const SizedBox(width: 16),
                  _buildTopButton('Part II.D', Icons.network_cell, 3),
                ],
              ),
              const SizedBox(height: 24),
              if (_isCompiling)
                const CircularProgressIndicator()
              else
                ElevatedButton.icon(
                  onPressed: () => mergePartIIDocuments(context, _docId),
                  icon: const Icon(Icons.merge_type),
                  label: const Text('Merge All Parts II'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff021e84),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
            ],
          );
  }

  Widget _buildTopButton(String text, IconData icon, int index) {
    return ElevatedButton.icon(
      onPressed: () {
        setState(() => _selectedIndex = index);
        switch (index) {
          case 0:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PartIIA(),
              ),
            );
            break;
          case 1:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PartIIB(),
              ),
            );
            break;
          case 2:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PartIIC(),
              ),
            );
            break;
          case 3:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PartIID(),
              ),
            );
            break;
        }
      },
      icon: Icon(icon, color: _selectedIndex == index ? Colors.white : Colors.black),
      label: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: _selectedIndex == index ? Colors.white : Colors.black,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: _selectedIndex == index ? const Color(0xff021e84) : Colors.transparent,
        foregroundColor: Colors.black,
        side: const BorderSide(color: Colors.black),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
