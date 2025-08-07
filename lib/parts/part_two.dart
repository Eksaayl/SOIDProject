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
import '../state/selection_model.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Part2 extends StatefulWidget {
  const Part2({super.key});

  @override
  _Part2State createState() => _Part2State();
}

class _Part2State extends State<Part2> {
  int _selectedIndex = -1;
  bool _isCompiling = false;
  String get _yearRange => context.read<SelectionModel>().yearRange ?? '2729';
  String _userRole = '';
  bool _hasLoadedRole = false;

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
  }

  Future<void> _fetchUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      setState(() {
        _userRole = userDoc.data()?['role'] ?? '';
        _hasLoadedRole = true;
      });
    }
  }

  bool _canAccessSection(String section) {
    if (!_hasLoadedRole) return false;
    
    final role = _userRole.toLowerCase();
    
    if (section == 'II.A' || section == 'II.B' || section == 'II.C') {
      return role == 'admin' || role == 'itds';
    }
    
    if (section == 'II.D') {
      return role == 'admin' || role == 'itds' || role == 'editor';
    }
    
    return false;
  }

  bool _canMerge() {
    if (!_hasLoadedRole) return false;
    final role = _userRole.toLowerCase();
    return role == 'admin';
  }

  Future<void> uploadGeneratedDocxToStorage(String documentId, String part, List<int> docxBytes) async {
    final storage = FirebaseStorage.instance;
    final ref = storage.ref().child('$_yearRange/$part/document.docx');
    await ref.putData(Uint8List.fromList(docxBytes));
  }

  Future<void> mergePartIIDocuments(BuildContext context, String documentId) async {
    try {
      final storage = FirebaseStorage.instance;
      final firestore = FirebaseFirestore.instance;
      setState(() => _isCompiling = true);

      final sectionRefs = await Future.wait([
        firestore.collection('issp_documents').doc(_yearRange).collection('sections').doc('II.A').get(),
        firestore.collection('issp_documents').doc(_yearRange).collection('sections').doc('II.B').get(),
        firestore.collection('issp_documents').doc(_yearRange).collection('sections').doc('II.C').get(),
        firestore.collection('issp_documents').doc(_yearRange).collection('sections').doc('II.D').get(),
      ]);

      final notFinalized = <String>[];
      for (var i = 0; i < sectionRefs.length; i++) {
        final data = sectionRefs[i].data();
        if (data == null || !(data['isFinalized'] as bool? ?? false)) {
          notFinalized.add(['II.A', 'II.B', 'II.C', 'II.D'][i]);
        }
      }

      if (notFinalized.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please finalize the following sections first: ${notFinalized.join(", ")}'))
        );
        return;
      }

      final ii_a_bytes = await storage.ref().child('$_yearRange/II.A/document.docx').getData();
      final ii_b_bytes = await storage.ref().child('$_yearRange/II.B/document.docx').getData();
      final ii_c_bytes = await storage.ref().child('$_yearRange/II.C/document.docx').getData();
      final ii_d_bytes = await storage.ref().child('$_yearRange/II.D/document.docx').getData();

      if (ii_a_bytes == null || ii_b_bytes == null || ii_c_bytes == null || ii_d_bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('One or more Part II documents are missing. Please ensure all parts are finalized.'))
        );
        return;
      }

      final merge_request = http.MultipartRequest(
        'POST',
        Uri.parse('${Config.serverUrl}/merge-documents-part-ii'),
      );

      merge_request.files.add(http.MultipartFile.fromBytes('part_ii_a', ii_a_bytes, filename: 'part_ii_a.docx'));
      merge_request.files.add(http.MultipartFile.fromBytes('part_ii_b', ii_b_bytes, filename: 'part_ii_b.docx'));
      merge_request.files.add(http.MultipartFile.fromBytes('part_ii_c', ii_c_bytes, filename: 'part_ii_c.docx'));
      merge_request.files.add(http.MultipartFile.fromBytes('part_ii_d', ii_d_bytes, filename: 'part_ii_d.docx'));

      final merge_response = await merge_request.send();
      if (merge_response.statusCode != 200) {
        final error = await merge_response.stream.bytesToString();
        throw Exception('Failed to merge documents: ${merge_response.statusCode} - $error');
      }

      final responseBytes = await merge_response.stream.toBytes();

      final mergedRef = storage.ref().child('$_yearRange/part_ii_merged.docx');
      await mergedRef.putData(responseBytes);

      await firestore.collection('issp_documents').doc(_yearRange).update({
        'partIIMergedPath': '$_yearRange/part_ii_merged.docx',
        'lastModified': FieldValue.serverTimestamp(),
      });

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

    if (!_hasLoadedRole) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

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
                          if (_canAccessSection('II.A'))
                            _buildTopButton('Part II.A', Icons.insights, 0),
                          if (_canAccessSection('II.A') && _canAccessSection('II.B'))
                            const SizedBox(width: 16),
                          if (_canAccessSection('II.B'))
                            _buildTopButton('Part II.B', Icons.book, 1),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_canAccessSection('II.C'))
                            _buildTopButton('Part II.C', Icons.storage, 2),
                          if (_canAccessSection('II.C') && _canAccessSection('II.D'))
                            const SizedBox(width: 16),
                          if (_canAccessSection('II.D'))
                            _buildTopButton('Part II.D', Icons.network_cell, 3),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_isCompiling)
                    const CircularProgressIndicator()
                  else if (_canMerge())
                    ElevatedButton.icon(
                      onPressed: () => mergePartIIDocuments(context, _yearRange),
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
                  if (_canAccessSection('II.A'))
                    _buildTopButton('Part II.A', Icons.insights, 0),
                  if (_canAccessSection('II.A') && _canAccessSection('II.B'))
                    const SizedBox(width: 16),
                  if (_canAccessSection('II.B'))
                    _buildTopButton('Part II.B', Icons.book, 1),
                  if (_canAccessSection('II.B') && _canAccessSection('II.C'))
                    const SizedBox(width: 16),
                  if (_canAccessSection('II.C'))
                    _buildTopButton('Part II.C', Icons.storage, 2),
                  if (_canAccessSection('II.C') && _canAccessSection('II.D'))
                    const SizedBox(width: 16),
                  if (_canAccessSection('II.D'))
                    _buildTopButton('Part II.D', Icons.network_cell, 3),
                ],
              ),
              const SizedBox(height: 24),
              if (_isCompiling)
                const CircularProgressIndicator()
              else if (_canMerge())
                ElevatedButton.icon(
                  onPressed: () => mergePartIIDocuments(context, _yearRange),
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
    String section = '';
    switch (index) {
      case 0:
        section = 'II.A';
        break;
      case 1:
        section = 'II.B';
        break;
      case 2:
        section = 'II.C';
        break;
      case 3:
        section = 'II.D';
        break;
    }

    if (!_canAccessSection(section)) {
      return const SizedBox.shrink();
    }

    return ElevatedButton.icon(
      onPressed: () {
        setState(() => _selectedIndex = index);
        switch (index) {
          case 0:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartIIA(documentId: _yearRange),
              ),
            );
            break;
          case 1:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartIIB(documentId: _yearRange),
              ),
            );
            break;
          case 2:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartIIC(documentId: _yearRange),
              ),
            );
            break;
          case 3:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartIID(documentId: _yearRange),
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
