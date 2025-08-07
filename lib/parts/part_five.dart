import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_saver/file_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../state/selection_model.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'part_v/part_v_a.dart';
import 'part_v/part_v_b.dart';
import 'part_v/part_v_c.dart';
import 'part_v/part_v_d.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Part5 extends StatefulWidget {
  const Part5({super.key});

  @override
  _Part5State createState() => _Part5State();
}

class _Part5State extends State<Part5> {
  int _selectedIndex = -1;
  bool _isMerging = false;
  String _userRole = '';
  bool _hasLoadedRole = false;

  String get _yearRange => context.read<SelectionModel>().yearRange ?? '2729';
  final _storage = FirebaseStorage.instance;
  final _firestore = FirebaseFirestore.instance;

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
    
    if (section == 'V.A') {
      return role == 'admin' || role == 'itds' || role == 'editor';
    }
    
    if (section == 'V.B') {
      return role == 'admin' || role == 'itds' || role == 'editor';
    }
    
    if (section == 'V.C') {
      return role == 'admin' || role == 'itds';
    }
    
    if (section == 'V.D') {
      return role == 'admin';
    }
    
    return false;
  }

  @override
  Widget build(BuildContext context) {
    bool isSmallScreen = MediaQuery.of(context).size.width < 650;

    if (!_hasLoadedRole) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final canAccessVA = _canAccessSection('V.A');
    final canAccessVB = _canAccessSection('V.B');
    final canAccessVC = _canAccessSection('V.C');
    final canAccessVD = _canAccessSection('V.D');

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
              ' DEVELOPMENT AND INVESTMENT PROGRAM',
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
                    if (canAccessVA) _buildTopButton('Part V.A', Icons.calendar_today, 0),
                    if (canAccessVA && canAccessVB) const SizedBox(width: 16),
                    if (canAccessVB) _buildTopButton('Part V.B', Icons.event, 1),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (canAccessVC) _buildTopButton('Part V.C', Icons.attach_money, 2),
                    if (canAccessVC && canAccessVD) const SizedBox(width: 16),
                    if (canAccessVD) _buildTopButton('Part V.D', Icons.pie_chart_outline, 3),
                  ],
                ),
                const SizedBox(height: 24),
                if (canAccessVA && canAccessVB && canAccessVC && canAccessVD && _userRole == 'admin') _buildMergeButton(),
              ],
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
          ' DEVELOPMENT AND INVESTMENT PROGRAM',
          style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (canAccessVA) _buildTopButton('Part V.A', Icons.calendar_today, 0),
            if (canAccessVA && canAccessVB) const SizedBox(width: 16),
            if (canAccessVB) _buildTopButton('Part V.B', Icons.event, 1),
            if (canAccessVB && canAccessVC) const SizedBox(width: 16),
            if (canAccessVC) _buildTopButton('Part V.C', Icons.attach_money, 2),
            if (canAccessVC && canAccessVD) const SizedBox(width: 16),
            if (canAccessVD) _buildTopButton('Part V.D', Icons.pie_chart_outline, 3),
          ],
        ),
        const SizedBox(height: 24),
        if (canAccessVA && canAccessVB && canAccessVC && canAccessVD && _userRole == 'admin') _buildMergeButton(),
      ],
    );
  }

  Widget _buildTopButton(String text, IconData icon, int index) {
    return ElevatedButton.icon(
      onPressed: () {
        setState(() {
          _selectedIndex = index;
        });
        
        if (index == 0) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const PartVA(),
            ),
          );
        } else if (index == 1) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const PartVB()));
        } else if (index == 2) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const PartVCFormPage(documentId: 'document')));
        } else if (index == 3) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const PartVDFormPage(documentId: 'document')));
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

  Widget _buildMergeButton() {
    if (_isMerging) {
      return const CircularProgressIndicator();
    }
    
    return ElevatedButton.icon(
      onPressed: _mergeAllPartsV,
      icon: const Icon(Icons.merge_type),
      label: const Text('Merge All Parts V'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xff021e84),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Future<void> _mergeAllPartsV() async {
    setState(() => _isMerging = true);
    
    try {
      final sections = ['V.A', 'V.B', 'V.C', 'V.D'];
      final sectionDocs = <String, DocumentSnapshot>{};
      
      for (final section in sections) {
        final doc = await _firestore
            .collection('issp_documents')
            .doc(_yearRange)
            .collection('sections')
            .doc(section)
            .get();
        sectionDocs[section] = doc;
      }

      final notFinalized = <String>[];
      for (final section in sections) {
        final doc = sectionDocs[section]!;
        final data = doc.data() as Map<String, dynamic>?;
        
        if (data == null) {
          notFinalized.add(section);
          continue;
        }
        
        final isFinalized = (data['isFinalized'] as bool? ?? false) || (data['screening'] as bool? ?? false);
        if (!isFinalized) {
          notFinalized.add(section);
        }
      }

      if (notFinalized.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please finalize the following sections first: ${notFinalized.join(", ")}'))
        );
        return;
      }

      final missingDocuments = <String>[];
      for (final section in sections) {
        final doc = sectionDocs[section]!;
        final data = doc.data() as Map<String, dynamic>?;
        
        bool hasDocument = false;
        if (data != null) {
          if (section == 'V.A' || section == 'V.B') {
            hasDocument = data['docxUrl'] != null;
          } else {
            hasDocument = data['fileUrl'] != null;
          }
        }
        
        if (!hasDocument) {
          missingDocuments.add(section);
        }
      }

      if (missingDocuments.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Documents are missing for the following sections: ${missingDocuments.join(", ")}'))
        );
        return;
      }

      final documents = <String, Uint8List>{};
      for (final section in sections) {
        final doc = sectionDocs[section]!;
        final data = doc.data() as Map<String, dynamic>;
        
        String? fileUrl;
        if (section == 'V.A' || section == 'V.B') {
          fileUrl = data['docxUrl'] as String?;
        } else {
          fileUrl = data['fileUrl'] as String?;
        }

        if (fileUrl == null) {
          throw Exception('Could not find document URL for $section');
        }

        String storagePath;
        if (fileUrl.contains('firebasestorage.googleapis.com')) {
          final uri = Uri.parse(fileUrl);
          final pathSegments = uri.pathSegments;
          final oIndex = pathSegments.indexOf('o');
          if (oIndex != -1 && oIndex + 1 < pathSegments.length) {
            final encodedPath = pathSegments[oIndex + 1];
            storagePath = Uri.decodeComponent(encodedPath);
          } else {
            throw Exception('Invalid Firebase Storage URL format for $section');
          }
        } else {
          final uri = Uri.parse(fileUrl);
          final pathSegments = uri.pathSegments;
          storagePath = pathSegments.sublist(pathSegments.length - 3).join('/');
        }

        final ref = _storage.ref().child(storagePath);

        final bytes = await ref.getData();
        if (bytes != null) {
          documents[section] = bytes;
        } else {
          throw Exception('Could not download document for $section');
        }
      }

      final merge_request = http.MultipartRequest(
        'POST',
        Uri.parse('${Config.serverUrl}/merge-documents-part-v'),
      );

      merge_request.files.add(http.MultipartFile.fromBytes('part_v_a', documents['V.A']!, filename: 'part_v_a.docx'));
      merge_request.files.add(http.MultipartFile.fromBytes('part_v_b', documents['V.B']!, filename: 'part_v_b.docx'));
      merge_request.files.add(http.MultipartFile.fromBytes('part_v_c', documents['V.C']!, filename: 'part_v_c.docx'));
      merge_request.files.add(http.MultipartFile.fromBytes('part_v_d', documents['V.D']!, filename: 'part_v_d.docx'));

      final response = await merge_request.send();
      if (response.statusCode != 200) {
        final error = await response.stream.bytesToString();
        throw Exception('Failed to merge documents: ${response.statusCode} - $error');
      }

      final mergedBytes = await response.stream.toBytes();
      
      final fileName = 'Part_V_Complete_${_yearRange}.docx';
      
      final mergedStoragePath = '$_yearRange/part_v_merged.docx';
      final mergedRef = _storage.ref().child(mergedStoragePath);
      await mergedRef.putData(mergedBytes);

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: fileName,
          bytes: mergedBytes,
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(mergedBytes);
        await FileSaver.instance.saveFile(
          name: fileName,
          file: file,
          mimeType: MimeType.microsoftWord,
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Documents merged successfully'),
        ),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error merging documents: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isMerging = false);
    }
  }
}
