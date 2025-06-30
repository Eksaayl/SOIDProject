import 'package:flutter/material.dart';
import 'part_iii/part_iii_a.dart';
import 'part_iii/part_iii_b.dart';
import 'part_iii/part_iii_c.dart';
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

class Part3 extends StatefulWidget {
  const Part3({super.key});

  @override
  _Part3State createState() => _Part3State();
}

class _Part3State extends State<Part3> {
  int _selectedIndex = -1;
  bool _isCompiling = false;
  bool _showProjectTypeSelection = true;
  String? _selectedProjectType;
  bool _hasIIIAForSubRole = false;
  bool _hasIIIBForSubRole = false;
  bool _isLoading = true;
  String get _yearRange => context.read<SelectionModel>().yearRange ?? '2729';
  String _userRole = '';

  @override
  void initState() {
    super.initState();
    _checkExistingData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkExistingData();
  }

  Future<void> _checkExistingData() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final user = await FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() { _isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User not logged in.')),
        );
        return;
      }
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userSubRoles = List<String>.from(userDoc.data()?['sub_roles'] ?? []);
      final userRole = userDoc.data()?['role'] ?? '';
      
      final iiiaDoc = await firestore
          .collection('issp_documents')
          .doc(_yearRange)
          .collection('sections')
          .doc('III.A')
          .get();
      
      final iiibDoc = await firestore
          .collection('issp_documents')
          .doc(_yearRange)
          .collection('sections')
          .doc('III.B')
          .get();

      bool hasIIIAForSubRole = false;
      bool hasIIIBForSubRole = false;
      if (iiiaDoc.exists && iiiaDoc.data() != null) {
        final projects = iiiaDoc.data()?['projects'] as List<dynamic>? ?? [];
        hasIIIAForSubRole = projects.any((proj) {
          final savedSubRoles = List<String>.from(proj['sub_roles'] ?? []);
          return savedSubRoles.any((role) => userSubRoles.contains(role));
        });
      }
      if (iiibDoc.exists && iiibDoc.data() != null) {
        final projects = iiibDoc.data()?['projects'] as List<dynamic>? ?? [];
        hasIIIBForSubRole = projects.any((proj) {
          final savedSubRoles = List<String>.from(proj['sub_roles'] ?? []);
          return savedSubRoles.any((role) => userSubRoles.contains(role));
        });
      }
      setState(() {
        _hasIIIAForSubRole = hasIIIAForSubRole;
        _hasIIIBForSubRole = hasIIIBForSubRole;
        _isLoading = false;
        _userRole = userRole;
      });

      if (_hasIIIAForSubRole && !_hasIIIBForSubRole) {
        setState(() {
          _selectedProjectType = 'internal';
          _showProjectTypeSelection = false;
        });
      } else if (_hasIIIBForSubRole && !_hasIIIAForSubRole) {
        setState(() {
          _selectedProjectType = 'cross-agency';
          _showProjectTypeSelection = false;
        });
      } else if (_hasIIIAForSubRole && _hasIIIBForSubRole) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Both Part III.A and III.B have data for your sub-role. Please choose which one to work with.'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error checking existing data: $e')),
      );
    }
  }

  void _selectProjectType(String projectType) {
    if (projectType == 'internal' && _hasIIIBForSubRole && _userRole != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Part III.B already has data. You cannot switch to Internal projects.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    if (projectType == 'cross-agency' && _hasIIIAForSubRole && _userRole != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Part III.A already has data. You cannot switch to Cross-Agency projects.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _selectedProjectType = projectType;
      _showProjectTypeSelection = false;
    });
  }

  void _goBackToSelection() {
    setState(() {
      _showProjectTypeSelection = true;
      _selectedProjectType = null;
      _selectedIndex = -1;
    });
  }

  Future<void> mergePartIIIDocuments(BuildContext context, String documentId) async {
    try {
      final storage = FirebaseStorage.instance;
      final firestore = FirebaseFirestore.instance;
      setState(() => _isCompiling = true);

      final sectionRefs = await Future.wait([
        firestore.collection('issp_documents').doc(_yearRange).collection('sections').doc('III.A').get(),
        firestore.collection('issp_documents').doc(_yearRange).collection('sections').doc('III.B').get(),
        firestore.collection('issp_documents').doc(_yearRange).collection('sections').doc('III.C').get(),
      ]);

      final notFinalized = <String>[];
      for (var i = 0; i < sectionRefs.length; i++) {
        final data = sectionRefs[i].data();
        if (data == null || !(data['isFinalized'] as bool? ?? false)) {
          notFinalized.add(['III.A', 'III.B', 'III.C'][i]);
        }
      }

      if (notFinalized.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please finalize the following sections first: ${notFinalized.join(", ")}'))
        );
        return;
      }

      final iii_a_bytes = await storage.ref().child('$_yearRange/III.A/document.docx').getData();
      final iii_b_bytes = await storage.ref().child('$_yearRange/III.B/document.docx').getData();
      final iii_c_bytes = await storage.ref().child('$_yearRange/III.C/document.docx').getData();

      if (iii_a_bytes == null || iii_b_bytes == null || iii_c_bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('One or more Part III documents are missing. Please ensure all parts are finalized.'))
        );
        return;
      }

      final merge_request = http.MultipartRequest(
        'POST',
        Uri.parse('${Config.serverUrl}/merge-documents-part-iii'),
      );

      merge_request.files.add(http.MultipartFile.fromBytes('part_iii_a', iii_a_bytes, filename: 'part_iii_a.docx'));
      merge_request.files.add(http.MultipartFile.fromBytes('part_iii_b', iii_b_bytes, filename: 'part_iii_b.docx'));
      merge_request.files.add(http.MultipartFile.fromBytes('part_iii_c', iii_c_bytes, filename: 'part_iii_c.docx'));

      final merge_response = await merge_request.send();
      if (merge_response.statusCode != 200) {
        final error = await merge_response.stream.bytesToString();
        throw Exception('Failed to merge documents: ${merge_response.statusCode} - $error');
      }

      final responseBytes = await merge_response.stream.toBytes();

      final mergedRef = storage.ref().child('$_yearRange/part_iii_merged.docx');
      await mergedRef.putData(responseBytes);

      await firestore.collection('issp_documents').doc(_yearRange).update({
        'partIIIMergedPath': '$_yearRange/part_iii_merged.docx',
        'lastModified': FieldValue.serverTimestamp(),
      });

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'Part_III_Merged_\\${DateTime.now().millisecondsSinceEpoch}.docx',
          bytes: responseBytes,
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/Part_III_Merged_\\${DateTime.now().millisecondsSinceEpoch}.docx');
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

  Future<void> _showDeleteConfirmation() async {
    final part = _selectedProjectType == 'internal' ? 'III.A' : 'III.B';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Part $part?'),
        content: Text('Are you sure you want to delete all data for Part $part? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _deletePart();
    }
  }

  Future<void> _deletePart() async {
    final part = _selectedProjectType == 'internal' ? 'III.A' : 'III.B';
    final firestore = FirebaseFirestore.instance;
    final yearRange = _yearRange;
    try {
      await firestore
          .collection('issp_documents')
          .doc(yearRange)
          .collection('sections')
          .doc(part)
          .delete();
      setState(() {
        if (part == 'III.A') {
          _hasIIIAForSubRole = false;
        } else {
          _hasIIIBForSubRole = false;
        }
        _showProjectTypeSelection = true;
        _selectedProjectType = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Part $part deleted successfully.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete Part $part: $e')),
      );
    }
  }

  Widget _buildProjectTypeSelection() {
    bool isSmallScreen = MediaQuery.of(context).size.width < 650;
    final isAdmin = (() {
      return _userRole == 'admin';
    })();

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xff021e84)),
            const SizedBox(height: 16),
            const Text(
              'Checking existing data...',
              style: TextStyle(fontSize: 16, color: Color(0xFF4A5568)),
            ),
          ],
        ),
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
                    'DETAILED DESCRIPTION OF ICT PROJECTS',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Select your project type:',
                    style: TextStyle(fontSize: 18, color: Color(0xFF4A5568)),
                    textAlign: TextAlign.center,
                  ),
                  if (_hasIIIAForSubRole || _hasIIIBForSubRole) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3CD),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFFEAA7)),
                      ),
                      child: Text(
                        _hasIIIAForSubRole && _hasIIIBForSubRole
                          ? 'Both Part III.A and III.B have existing data for your sub-role. Choose which one to work with.'
                          : _hasIIIAForSubRole
                            ? 'Part III.A has existing data for your sub-role. You can only work with Internal projects.'
                            : _hasIIIBForSubRole
                              ? 'Part III.B has existing data for your sub-role. You can only work with Cross-Agency projects.'
                              : '',
                        style: const TextStyle(fontSize: 14, color: Color(0xFF856404)),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  Column(
                    children: [
                      _buildProjectTypeButton(
                        'Internal Systems Development',
                        Icons.laptop,
                        'internal',
                        'For projects developed within your agency',
                        _hasIIIBForSubRole, 
                        _hasIIIAForSubRole, 
                        isAdmin: isAdmin,
                      ),
                      const SizedBox(height: 16),
                      _buildProjectTypeButton(
                        'Cross-Agency ICT Projects',
                        Icons.link,
                        'cross-agency',
                        'For projects involving multiple agencies',
                        _hasIIIAForSubRole,
                        _hasIIIBForSubRole, 
                        isAdmin: isAdmin,
                      ),
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
                'DETAILED DESCRIPTION OF ICT PROJECTS',
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select your project type:',
                style: TextStyle(fontSize: 20, color: Color(0xFF4A5568)),
              ),
              if (_hasIIIAForSubRole || _hasIIIBForSubRole) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3CD),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFEAA7)),
                  ),
                  child: Text(
                    _hasIIIAForSubRole && _hasIIIBForSubRole
                      ? 'Both Part III.A and III.B have existing data for your sub-role. Choose which one to work with.'
                      : _hasIIIAForSubRole
                        ? 'Part III.A has existing data for your sub-role. You can only work with Internal projects.'
                        : _hasIIIBForSubRole
                          ? 'Part III.B has existing data for your sub-role. You can only work with Cross-Agency projects.'
                          : '',
                    style: const TextStyle(fontSize: 16, color: Color(0xFF856404)),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildProjectTypeButton(
                    'Internal Systems Development Components',
                    Icons.laptop,
                    'internal',
                    'For projects developed within your agency',
                    _hasIIIBForSubRole, 
                    _hasIIIAForSubRole, 
                    isAdmin: isAdmin,
                  ),
                  const SizedBox(width: 32),
                  _buildProjectTypeButton(
                    'Cross-Agency ICT Projects',
                    Icons.link,
                    'cross-agency',
                    'For projects involving multiple agencies',
                    _hasIIIAForSubRole, 
                    _hasIIIBForSubRole, 
                    isAdmin: isAdmin,
                  ),
                ],
              ),
            ],
          );
  }

  Widget _buildProjectTypeButton(String title, IconData icon, String type, String description, bool disabled, bool hasExistingData, {bool isAdmin = false}) {
    return Container(
      width: 300,
      height: 250,
      child: ElevatedButton(
        onPressed: (disabled && !isAdmin) ? null : () => _selectProjectType(type),
        style: ElevatedButton.styleFrom(
          backgroundColor: (disabled && !isAdmin) ? Colors.grey.shade300 : Colors.white,
          foregroundColor: (disabled && !isAdmin) ? Colors.grey.shade600 : const Color(0xFF2D3748),
          side: BorderSide(
            color: (disabled && !isAdmin) ? Colors.grey.shade400 : const Color(0xff021e84),
            width: 2,
          ),
          padding: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: (disabled && !isAdmin) ? 0 : 2,
        ),
        child: Column(
          children: [
            Icon(
              icon, 
              size: 48, 
              color: (disabled && !isAdmin) ? Colors.grey.shade600 : const Color(0xff021e84),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: (disabled && !isAdmin) ? Colors.grey.shade600 : const Color(0xFF2D3748),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                fontSize: 14,
                color: (disabled && !isAdmin) ? Colors.grey.shade500 : const Color(0xFF4A5568),
              ),
              textAlign: TextAlign.center,
            ),
            if (hasExistingData) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4EDDA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Has existing data',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF155724),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            if (disabled && !isAdmin) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8D7DA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Not available',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF721C24),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showProjectTypeSelection) {
      return _buildProjectTypeSelection();
    }

    if (_userRole == 'admin' && !_showProjectTypeSelection) {
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
                      'DETAILED DESCRIPTION OF ICT PROJECTS',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Admin Access - All Parts Available',
                      style: TextStyle(fontSize: 16, color: Color(0xFF4A5568)),
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
                            _buildTopButton('Part III.A', Icons.laptop, 0),
                            const SizedBox(width: 16),
                            _buildTopButton('Part III.B', Icons.link, 1),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildTopButton('Part III.C', Icons.bar_chart, 2),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (_isCompiling)
                      const CircularProgressIndicator()
                    else
                      ElevatedButton.icon(
                        onPressed: () => mergePartIIIDocuments(context, _yearRange),
                        icon: const Icon(Icons.merge_type),
                        label: const Text('Merge All Parts III'),
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
                  'DETAILED DESCRIPTION OF ICT PROJECTS',
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Admin Access - All Parts Available',
                  style: TextStyle(fontSize: 18, color: Color(0xFF4A5568)),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildTopButton('Part III.A', Icons.laptop, 0),
                    const SizedBox(width: 16),
                    _buildTopButton('Part III.B', Icons.link, 1),
                    const SizedBox(width: 16),
                    _buildTopButton('Part III.C', Icons.bar_chart, 2),
                  ],
                ),
                const SizedBox(height: 24),
                if (_isCompiling)
                  const CircularProgressIndicator()
                else
                  ElevatedButton.icon(
                    onPressed: () => mergePartIIIDocuments(context, _yearRange),
                    icon: const Icon(Icons.merge_type),
                    label: const Text('Merge All Parts III'),
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
            if (((_selectedProjectType == 'internal' && _hasIIIAForSubRole) ||
                (_selectedProjectType == 'cross-agency' && _hasIIIBForSubRole)))
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _showDeleteConfirmation,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xffe53935), Color(0xffb71c1c)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.delete_forever, color: Colors.white, size: 28),
                          const SizedBox(width: 16),
                          Text(
                            'Delete ${_selectedProjectType == 'internal' ? 'Part III.A' : 'Part III.B'}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: _goBackToSelection,
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back to project type selection',
                ),
                Expanded(
                  child: Text(
                    'DETAILED DESCRIPTION OF ICT PROJECTS',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 48), 
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Selected: ${_selectedProjectType == 'internal' ? 'Internal Systems Development Components' : 'Cross-Agency ICT Projects'}',
              style: const TextStyle(fontSize: 16, color: Color(0xFF4A5568)),
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
                    if (_selectedProjectType == 'internal') ...[
                      _buildTopButton('Part III.A', Icons.laptop, 0),
                    ] else if (_selectedProjectType == 'cross-agency') ...[
                      _buildTopButton('Part III.B', Icons.link, 1),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildTopButton('Part III.C', Icons.bar_chart, 2),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_isCompiling)
              const CircularProgressIndicator()
            else
              ElevatedButton.icon(
                onPressed: () => mergePartIIIDocuments(context, _yearRange),
                icon: const Icon(Icons.merge_type),
                label: const Text('Merge All Parts III'),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: _goBackToSelection,
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to project type selection',
            ),
            const SizedBox(width: 16),
            const Text(
              'DETAILED DESCRIPTION OF ICT PROJECTS',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (((_selectedProjectType == 'internal' && _hasIIIAForSubRole) ||
            (_selectedProjectType == 'cross-agency' && _hasIIIBForSubRole)))
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _showDeleteConfirmation,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xffe53935), Color(0xffb71c1c)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.delete_forever, color: Colors.white, size: 28),
                      const SizedBox(width: 16),
                      Text(
                        'Delete ${_selectedProjectType == 'internal' ? 'Part III.A' : 'Part III.B'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Text(
          'Selected: ${_selectedProjectType == 'internal' ? 'Internal Systems Development Components' : 'Cross-Agency ICT Projects'}',
          style: const TextStyle(fontSize: 18, color: Color(0xFF4A5568)),
        ),
        const SizedBox(height: 24),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_selectedProjectType == 'internal') ...[
              _buildTopButton('Part III.A', Icons.laptop, 0),
              const SizedBox(width: 16),
            ] else if (_selectedProjectType == 'cross-agency') ...[
              _buildTopButton('Part III.B', Icons.link, 1),
              const SizedBox(width: 16),
            ],
            _buildTopButton('Part III.C', Icons.bar_chart, 2),
          ],
        ),
        const SizedBox(height: 24),
        if (_isCompiling)
          const CircularProgressIndicator()
        else
          ElevatedButton.icon(
            onPressed: () => mergePartIIIDocuments(context, _yearRange),
            icon: const Icon(Icons.merge_type),
            label: const Text('Merge All Parts III'),
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
        setState(() {
          _selectedIndex = index;
        });
        switch (index) {
          case 0:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PartIIIA(),
              ),
            );
            break;
          case 1:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PartIIIB(),
              ),
            );
            break;
          case 2:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PartIIIC(),
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
