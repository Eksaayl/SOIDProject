import 'package:flutter/material.dart';
import 'part_iv/part_iv_a.dart';
import 'part_iv/part_iv_b.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:file_saver/file_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../config.dart';
import '../state/selection_model.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Part4 extends StatefulWidget {
  const Part4({super.key});

  @override
  _Part4State createState() => _Part4State();
}

class _Part4State extends State<Part4> with TickerProviderStateMixin {
  int _selectedIndex = -1;
  bool _isCompiling = false;
  String get _yearRange => context.read<SelectionModel>().yearRange ?? '2729';
  String _userRole = '';
  bool _hasLoadedRole = false;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    _fetchUserRole();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _fetchUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      setState(() {
        _userRole = userDoc.data()?['role'] ?? '';
        _hasLoadedRole = true;
      });
    }
  }

  bool _canAccessSection(String section) {
    if (!_hasLoadedRole) return false;

    final role = _userRole.toLowerCase();

    if (section == 'IV.A') {
      return role == 'admin' || role == 'itds';
    }

    if (section == 'IV.B') {
      return role == 'admin';
    }

    return false;
  }

  Future<void> mergePartIVDocuments(
      BuildContext context, String documentId) async {
    try {
      final storage = FirebaseStorage.instance;
      final firestore = FirebaseFirestore.instance;
      setState(() => _isCompiling = true);

      final sectionRefs = await Future.wait([
        firestore
            .collection('issp_documents')
            .doc(_yearRange)
            .collection('sections')
            .doc('IV.A')
            .get(),
        firestore
            .collection('issp_documents')
            .doc(_yearRange)
            .collection('sections')
            .doc('IV.B')
            .get(),
      ]);

      final notFinalized = <String>[];
      for (var i = 0; i < sectionRefs.length; i++) {
        final data = sectionRefs[i].data();
        if (data == null || !(data['isFinalized'] as bool? ?? false)) {
          notFinalized.add(['IV.A', 'IV.B'][i]);
        }
      }

      if (notFinalized.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Please finalize the following sections first: ${notFinalized.join(", ")}')));
        return;
      }

      final iv_a_bytes =
          await storage.ref().child('$_yearRange/IV.A/document.docx').getData();
      final iv_b_bytes =
          await storage.ref().child('$_yearRange/IV.B/document.docx').getData();

      if (iv_a_bytes == null || iv_b_bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'One or more Part IV documents are missing. Please ensure all parts are finalized.')));
        return;
      }

      final merge_request = http.MultipartRequest(
        'POST',
        Uri.parse('${Config.serverUrl}/merge-documents-part-iv'),
      );

      merge_request.files.add(http.MultipartFile.fromBytes(
          'part_iv_a', iv_a_bytes,
          filename: 'part_iv_a.docx'));
      merge_request.files.add(http.MultipartFile.fromBytes(
          'part_iv_b', iv_b_bytes,
          filename: 'part_iv_b.docx'));

      final response = await merge_request.send();
      if (response.statusCode != 200) {
        final error = await response.stream.bytesToString();
        throw Exception(
            'Failed to merge documents: ${response.statusCode} - $error');
      }

      final mergedBytes = await response.stream.toBytes();

      final mergedRef = storage.ref().child('$_yearRange/part_iv_merged.docx');
      await mergedRef.putData(mergedBytes);

      await firestore.collection('issp_documents').doc(_yearRange).update({
        'partIVMergedPath': '$_yearRange/part_iv_merged.docx',
        'lastModified': FieldValue.serverTimestamp(),
      });

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'Part_IV_Merged_${DateTime.now().millisecondsSinceEpoch}.docx',
          bytes: mergedBytes,
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File(
            '${directory.path}/Part_IV_Merged_${DateTime.now().millisecondsSinceEpoch}.docx');
        await file.writeAsBytes(mergedBytes);
      }

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Documents merged successfully')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error merging documents: $e')));
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

    if (_userRole.toLowerCase() == 'editor') {
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
                        angle: _controller.value * 3.1416,
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
                  'You do not have permission to access Part IV. Please contact your system administrator if you need access.',
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

    final canAccessIVA = _canAccessSection('IV.A');
    final canAccessIVB = _canAccessSection('IV.B');

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
                    'RESOURCE REQUIREMENTS',
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
                          if (canAccessIVA)
                            _buildTopButton('Part IV.A', Icons.computer, 0),
                          if (canAccessIVA && canAccessIVB)
                            const SizedBox(width: 16),
                          if (canAccessIVB)
                            _buildTopButton('Part IV.B', Icons.business, 1),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_isCompiling)
                    const CircularProgressIndicator()
                  else if (canAccessIVA && canAccessIVB && _userRole == 'admin')
                    ElevatedButton.icon(
                      onPressed: () =>
                          mergePartIVDocuments(context, _yearRange),
                      icon: const Icon(Icons.merge_type),
                      label: const Text('Merge All Parts IV'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xff021e84),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
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
                'RESOURCE REQUIREMENTS',
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (canAccessIVA)
                    _buildTopButton('Part IV.A', Icons.computer, 0),
                  if (canAccessIVA && canAccessIVB) const SizedBox(width: 16),
                  if (canAccessIVB)
                    _buildTopButton('Part IV.B', Icons.business, 1),
                ],
              ),
              const SizedBox(height: 24),
              if (_isCompiling)
                const CircularProgressIndicator()
              else if (canAccessIVA && canAccessIVB && _userRole == 'admin')
                ElevatedButton.icon(
                  onPressed: () => mergePartIVDocuments(context, _yearRange),
                  icon: const Icon(Icons.merge_type),
                  label: const Text('Merge All Parts IV'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff021e84),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
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
        setState(() {
          _selectedIndex = index;
        });
        switch (index) {
          case 0:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartIVAFormPage(documentId: _yearRange),
              ),
            );
            break;
          case 1:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartIVB(documentId: _yearRange),
              ),
            );
            break;
        }
      },
      icon: Icon(icon,
          color: _selectedIndex == index ? Colors.white : Colors.black),
      label: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: _selectedIndex == index ? Colors.white : Colors.black,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: _selectedIndex == index
            ? const Color(0xff021e84)
            : Colors.transparent,
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
