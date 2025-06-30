import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:file_saver/file_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:test_project/parts/part_i/part_ia.dart';
import 'package:test_project/parts/part_i/part_ib.dart';
import 'package:test_project/parts/part_i/part_ic.dart';
import 'package:test_project/parts/part_i/part_id.dart';
import 'package:test_project/parts/part_i/part_ie.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_storage/firebase_storage.dart';
import '../config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../state/selection_model.dart';
import 'package:provider/provider.dart';

class Part1 extends StatefulWidget {
  const Part1({Key? key}) : super(key: key);
  @override
  _Part1State createState() => _Part1State();
}

class _Part1State extends State<Part1> with TickerProviderStateMixin {
  int _selectedIndex = -1;
  bool _isCompiling = false;
  String get _yearRange => context.read<SelectionModel>().yearRange ?? '2729';
  bool _hasAccess = false;
  String _userRole = '';
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
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
          _hasAccess = role == 'admin' || role == 'itds';
        });
      }
    }
  }

  Future<void> mergeCompiledAndUploadsAndDownload(BuildContext context, String documentId) async {
    try {
      final storage = FirebaseStorage.instance;
      final firestore = FirebaseFirestore.instance;
      setState(() => _isCompiling = true);

      final sectionRefs = await Future.wait([
        firestore.collection('issp_documents').doc(_yearRange).collection('sections').doc('I.A').get(),
        firestore.collection('issp_documents').doc(_yearRange).collection('sections').doc('I.B').get(),
        firestore.collection('issp_documents').doc(_yearRange).collection('sections').doc('I.C').get(),
        firestore.collection('issp_documents').doc(_yearRange).collection('sections').doc('I.D').get(),
        firestore.collection('issp_documents').doc(_yearRange).collection('sections').doc('I.E').get(),
      ]);

      final sectionsWithData = <String>[];
      final sectionsWithoutData = <String>[];
      
      for (var i = 0; i < sectionRefs.length; i++) {
        final sectionName = ['I.A', 'I.B', 'I.C', 'I.D', 'I.E'][i];
        final data = sectionRefs[i].data();
        if (data != null && data.isNotEmpty) {
          sectionsWithData.add(sectionName);
        } else {
          sectionsWithoutData.add(sectionName);
        }
      }

      if (sectionsWithoutData.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('The following sections have no data: ${sectionsWithoutData.join(", ")}'))
        );
        return;
      }

      // Get DOCX files from storage
      try {
        final iaBytes = await storage.ref().child('$_yearRange/I.A/document.docx').getData();
        final ibBytes = await storage.ref().child('$_yearRange/I.B/document.docx').getData();
        final icBytes = await storage.ref().child('$_yearRange/I.C/document.docx').getData();
        final idBytes = await storage.ref().child('$_yearRange/I.D/document.docx').getData();
        final ieBytes = await storage.ref().child('$_yearRange/I.E/document.docx').getData();

        if (iaBytes == null || ibBytes == null || icBytes == null || idBytes == null || ieBytes == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('One or more Part I documents are missing. Please ensure all parts are finalized.'))
          );
          return;
        }

        // Merge DOCX files using server endpoint
        await _mergeDocxFiles(iaBytes, ibBytes, icBytes, idBytes, ieBytes);

      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error accessing DOCX files from storage: $e'))
        );
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error merging documents: $e'))
      );
    } finally {
      setState(() => _isCompiling = false);
    }
  }

  Future<void> _mergeDocxFiles(Uint8List iaBytes, Uint8List ibBytes, Uint8List icBytes, Uint8List idBytes, Uint8List ieBytes) async {
    try {
      // Create multipart request for merging
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${Config.serverUrl}/merge-documents-part-i-all'),
      );

      // Add all documents
      request.files.add(http.MultipartFile.fromBytes('part_ia', iaBytes, filename: 'part_ia.docx'));
      request.files.add(http.MultipartFile.fromBytes('part_ib', ibBytes, filename: 'part_ib.docx'));
      request.files.add(http.MultipartFile.fromBytes('part_ic', icBytes, filename: 'part_ic.docx'));
      request.files.add(http.MultipartFile.fromBytes('part_id', idBytes, filename: 'part_id.docx'));
      request.files.add(http.MultipartFile.fromBytes('part_ie', ieBytes, filename: 'part_ie.docx'));

      // Send merge request
      var response = await request.send();
      if (response.statusCode != 200) {
        final error = await response.stream.bytesToString();
        throw Exception('Failed to merge documents: ${response.statusCode} - $error');
      }

      // Get merged document
      final responseBytes = await response.stream.toBytes();

      final storage = FirebaseStorage.instance;
      final mergedRef = storage.ref().child('$_yearRange/part_i_merged.docx');
      await mergedRef.putData(responseBytes);

      final docRef = FirebaseFirestore.instance.collection('issp_documents').doc(_yearRange);
      final docSnap = await docRef.get();
      if (!docSnap.exists) {
        await docRef.set({}); // create an empty document if it doesn't exist
      }
      await docRef.update({
        'partIMergedPath': '$_yearRange/part_i_merged.docx',
        'lastModified': FieldValue.serverTimestamp(),
      });

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'Part_I_Merged_${DateTime.now().millisecondsSinceEpoch}.docx',
          bytes: responseBytes,
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/Part_I_Merged_${DateTime.now().millisecondsSinceEpoch}.docx');
        await file.writeAsBytes(responseBytes);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Documents merged successfully'))
      );
    } catch (e) {
      throw Exception('Error merging DOCX files: $e');
    }
  }

  Widget _pill(String label, IconData icon, int idx) {
    final sel = _selectedIndex == idx;
    return ElevatedButton.icon(
      onPressed: () {
        setState(() => _selectedIndex = idx);
        switch (idx) {
          case 0:
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => PartIAFormPage(documentId: _yearRange),
            ));
            break;
          case 1:
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => PartIBFormPage(documentId: _yearRange),
            ));
            break;
          case 2:
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => PartICFormPage(documentId: _yearRange),
            ));
            break;
          case 3:
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => PartIDFormPage(documentId: _yearRange),
            ));
            break;
          case 4:
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => PartIEFormPage(documentId: _yearRange),
            ));
            break;
        }
      },
      icon: Icon(icon, color: sel ? Colors.white : Colors.black),
      label: Text(label,
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: sel ? Colors.white : Colors.black)),
      style: ElevatedButton.styleFrom(
        backgroundColor: sel ? const Color(0xff021e84) : Colors.transparent,
        side: const BorderSide(color: Colors.black),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                        angle: _controller.value * 3.1416, // 180 degrees
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
                  'Access Restricted',
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
                  'Only administrators have access to Part I. Please contact your system administrator if you need access.',
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

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ORGANIZATIONAL PROFILE',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  _pill('Part I.A', Icons.article, 0),
                  _pill('Part I.B', Icons.people, 1),
                  _pill('Part I.C', Icons.insert_photo, 2),
                  _pill('Part I.D', Icons.warning, 3),
                  _pill('Part I.E', Icons.computer, 4),
                ],
              ),
              const SizedBox(height: 24),
              if (_isCompiling)
                const CircularProgressIndicator()
              else
                ElevatedButton.icon(
                  onPressed: () => mergeCompiledAndUploadsAndDownload(context, _yearRange),
                  icon: Icon(Icons.merge_type),
                  label: Text('Merge All Parts I'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff021e84),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}