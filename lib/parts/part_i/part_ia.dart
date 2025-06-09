import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_saver/file_saver.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:test_project/main_part.dart';
import '../../utils/user_utils.dart';
import '../../services/notification_service.dart';
import 'package:http/http.dart' as http;

String xmlEscape(String input) => input
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

Future<Uint8List> generateDocxBySearchReplace({
  required String assetPath,
  required Map<String, String> replacements,
}) async {
  final bytes = (await rootBundle.load(assetPath)).buffer.asUint8List();
  final archive = ZipDecoder().decodeBytes(bytes);
  final docFile = archive.firstWhere((f) => f.name == 'word/document.xml');
  String xmlStr = utf8.decode(docFile.content as List<int>);

  final pattern = RegExp(r'\$\{(.+?)\}');
  final allKeys = pattern.allMatches(xmlStr).map((m) => m.group(1)!).toSet();

  final complete = <String, String>{
    for (var key in allKeys) '\${$key}': replacements[key] ?? '',
  };

  complete.forEach((ph, val) {
    xmlStr = xmlStr.replaceAll(ph, xmlEscape(val));
  });

  final newArchive = Archive();
  for (final file in archive) {
    if (file.name == 'word/document.xml') {
      final data = utf8.encode(xmlStr);
      newArchive.addFile(ArchiveFile(file.name, data.length, data));
    } else {
      newArchive.addFile(file);
    }
  }

  final out = ZipEncoder().encode(newArchive)!;
  return Uint8List.fromList(out);
}

class PartIAFormPage extends StatefulWidget {
  final String documentId;
  const PartIAFormPage({Key? key, required this.documentId}) : super(key: key);
  @override
  _PartIAFormPageState createState() => _PartIAFormPageState();
}

class _PartIAFormPageState extends State<PartIAFormPage> {
  final _formKey = GlobalKey<FormState>();

  final List<QuillController> functionControllers = [];
  
  late TextEditingController docNameCtrl;
  late TextEditingController legalBasisCtrl;
  late TextEditingController visionCtrl;
  late TextEditingController missionCtrl;
  late TextEditingController pillar1Ctrl;
  late TextEditingController pillar2Ctrl;
  late TextEditingController pillar3Ctrl;

  bool _loading = true;
  bool _saving = false;
  bool _compiling = false;
  bool _isFinal = false;

  late DocumentReference _sectionRef;

  void _addNewFunctionEditor() {
    functionControllers.add(QuillController.basic());
    if (mounted) setState(() {});
  }

  void _removeFunctionEditor(int index) {
    if (index < functionControllers.length) {
      functionControllers[index].dispose();
      functionControllers.removeAt(index);
      if (mounted) setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    docNameCtrl = TextEditingController();
    legalBasisCtrl = TextEditingController();
    visionCtrl = TextEditingController();
    missionCtrl = TextEditingController();
    pillar1Ctrl = TextEditingController();
    pillar2Ctrl = TextEditingController();
    pillar3Ctrl = TextEditingController();

    _addNewFunctionEditor();

    _sectionRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(widget.documentId)
        .collection('sections')
        .doc('I.A');

    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      final snap = await _sectionRef.get();
      final data = snap.data() as Map<String, dynamic>? ?? {};

      docNameCtrl.text = data['documentName'] ?? '';
      legalBasisCtrl.text = data['legalBasis'] ?? '';
      
      for (var controller in functionControllers) {
        controller.dispose();
      }
      functionControllers.clear();
      
      if (data['functions'] != null) {
        try {
          final List<dynamic> functions = jsonDecode(data['functions']);
          for (var function in functions) {
            final controller = QuillController(
              document: Document.fromJson(function),
              selection: const TextSelection.collapsed(offset: 0),
            );
            functionControllers.add(controller);
          }
        } catch (e) {
          _addNewFunctionEditor();
        }
      } else {
        _addNewFunctionEditor();
      }

      visionCtrl.text = data['visionStatement'] ?? '';
      missionCtrl.text = data['missionStatement'] ?? '';
      pillar1Ctrl.text = data['pillar1'] ?? '';
      pillar2Ctrl.text = data['pillar2'] ?? '';
      pillar3Ctrl.text = data['pillar3'] ?? '';
      setState(() {
        _isFinal = (data['isFinalized'] as bool? ?? false) || (data['screening'] as bool? ?? false);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Load error: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save({bool finalize = false}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      // Extract bullet list from Quill controllers
      List<String> functions = functionControllers
          .map((controller) => controller.document.toPlainText().trim())
          .where((text) => text.isNotEmpty)
          .toList();

      final data = {
        'documentName': docNameCtrl.text.trim(),
        'legalBasis': legalBasisCtrl.text.trim(),
        'functions': functions,
        'visionStatement': visionCtrl.text.trim(),
        'missionStatement': missionCtrl.text.trim(),
        'pillar1': pillar1Ctrl.text.trim(),
        'pillar2': pillar2Ctrl.text.trim(),
        'pillar3': pillar3Ctrl.text.trim(),
      };

      // Generate DOCX using the backend endpoint
      final url = Uri.parse('http://localhost:8000/generate-ia-docx/');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to generate DOCX: ${response.statusCode}');
      }

      final docxBytes = response.bodyBytes;

      final storage = FirebaseStorage.instance;
      final docxRef = storage.ref().child('${widget.documentId}/I.A/document.docx');
      await docxRef.putData(docxBytes);
      final docxUrl = await docxRef.getDownloadURL();

      final username = await getCurrentUsername();
      final payload = {
        ...data,
        'functions': jsonEncode(
          functionControllers.map((ctrl) => ctrl.document.toDelta().toJson()).toList()
        ),
        'fileUrl': docxUrl,
        'modifiedBy': username,
        'lastModified': FieldValue.serverTimestamp(),
        'screening': finalize || _isFinal,
        'sectionTitle': 'Part I.A',
      };

      if (!_isFinal) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdBy'] = username;
      }

      await _sectionRef.set(payload, SetOptions(merge: true));
      setState(() => _isFinal = finalize);
      
      if (finalize) {
        await createSubmissionNotification('Part I.A');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(finalize ? 'Finalized' : 'Saved (not finalized)'))
      );
      
      if (finalize) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save error: $e'))
      );
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _compileDocx() async {
    setState(() => _compiling = true);

    try {
      final sb = StringBuffer();
      
      for (var controller in functionControllers) {
        final text = controller.document.toPlainText().trim();
        if (text.isNotEmpty) {
          sb.writeln('• $text');
          sb.writeln(); 
        }
      }
      
      final map = {
        'documentName': docNameCtrl.text.trim(),
        'legalBasis': legalBasisCtrl.text.trim(),
        'functions': sb.toString().trim(),
        'visionStatement': visionCtrl.text.trim(),
        'missionStatement': missionCtrl.text.trim(),
        'pillar1': pillar1Ctrl.text.trim(),
        'pillar2': pillar2Ctrl.text.trim(),
        'pillar3': pillar3Ctrl.text.trim(),
      };

      final bytes = await generateDocxBySearchReplace(
        assetPath: 'assets/templates.docx',
        replacements: map,
      );

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'document.docx',
          bytes: bytes,
          ext: 'docx',
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/document.docx';
        await File(path).writeAsBytes(bytes);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Compiled to $path'))
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Compile error: $e'))
      );
    } finally {
      setState(() => _compiling = false);
    }
  }

  Future<void> generateAndDownloadDocx() async {
    setState(() => _compiling = true);
    try {
      // Extract bullet list from Quill controllers
      List<String> functions = functionControllers
          .map((controller) => controller.document.toPlainText().trim())
          .where((text) => text.isNotEmpty)
          .toList();

      final data = {
        'documentName': docNameCtrl.text.trim(),
        'legalBasis': legalBasisCtrl.text.trim(),
        'functions': functions,
        'visionStatement': visionCtrl.text.trim(),
        'missionStatement': missionCtrl.text.trim(),
        'pillar1': pillar1Ctrl.text.trim(),
        'pillar2': pillar2Ctrl.text.trim(),
        'pillar3': pillar3Ctrl.text.trim(),
      };

      final url = Uri.parse('http://localhost:8000/generate-ia-docx/');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final fileName = 'document.docx';
        if (kIsWeb) {
          await FileSaver.instance.saveFile(
            name: fileName,
            bytes: bytes,
            mimeType: MimeType.microsoftWord,
          );
        } else {
          final directory = await getApplicationDocumentsDirectory();
          final file = File('${directory.path}/$fileName');
          await file.writeAsBytes(bytes);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('DOCX generated and saved!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate DOCX: \\${response.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: \\${e.toString()}')),
      );
    } finally {
      setState(() => _compiling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: const Text(
          'Part I.A - Department/Agency Vision/Mission Statement',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2D3748),
        actions: [
          if (_saving || _compiling)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: CircularProgressIndicator(
                  color: Color(0xff021e84),
                ),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _isFinal ? null : () => _save(finalize: false),
              tooltip: 'Save',
              color: const Color(0xff021e84),
            ),
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _isFinal ? null : () async {
                final confirmed = await showFinalizeConfirmation(
                  context,
                  'Part I.A - Department/Agency Vision/Mission Statement'
                );
                if (confirmed) {
                  _save(finalize: true);
                }
              },
              tooltip: 'Finalize',
              color: _isFinal ? Colors.grey : const Color(0xff021e84),
            ),
            IconButton(
              icon: const Icon(Icons.file_download),
              onPressed: _compiling ? null : generateAndDownloadDocx,
              tooltip: 'Download DOCX',
              color: const Color(0xff021e84),
            ),
          ],
        ],
      ),
      body: _isFinal
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text(
                    'Part I.A - Department/Agency Vision/Mission Statement has been finalized.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
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
                                  'Instructions',
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
                              'Please fill in all the required fields below. You can add multiple functions as needed. Make sure all information is accurate and complete before finalizing.',
                              style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFF4A5568),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
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
                          border: Border.all(color: Colors.grey.shade200),
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
                                    Icons.description,
                                    color: Color(0xff021e84),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Basic Information',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2D3748),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _buildField('Document Name', docNameCtrl),
                            _buildField('Legal Basis', legalBasisCtrl, multiline: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
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
                          border: Border.all(color: Colors.grey.shade200),
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
                                    Icons.list_alt,
                                    color: Color(0xff021e84),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Functions',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2D3748),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _buildFunctionsSection(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
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
                          border: Border.all(color: Colors.grey.shade200),
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
                                    Icons.visibility,
                                    color: Color(0xff021e84),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Vision and Mission',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2D3748),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _buildField('Vision Statement', visionCtrl, multiline: true),
                            _buildField('Mission Statement', missionCtrl, multiline: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
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
                          border: Border.all(color: Colors.grey.shade200),
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
                                    Icons.architecture,
                                    color: Color(0xff021e84),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Strategic Pillars',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2D3748),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _buildField('Pillar 1', pillar1Ctrl, multiline: true),
                            _buildField('Pillar 2', pillar2Ctrl, multiline: true),
                            _buildField('Pillar 3', pillar3Ctrl, multiline: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, {bool multiline = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: ctrl,
        enabled: !_isFinal,
        maxLines: multiline ? null : 1,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xff021e84)),
          ),
          labelStyle: const TextStyle(color: Color(0xFF4A5568)),
        ),
        validator: (v) => v == null || v.trim().isEmpty ? '$label is required' : null,
      ),
    );
  }

  Widget _buildFunctionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...functionControllers.asMap().entries.map((entry) {
          final index = entry.key;
          final controller = entry.value;
          
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Function ${index + 1}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF2D3748),
                          ),
                        ),
                      ),
                    ),
                    if (!_isFinal && functionControllers.length > 1)
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeFunctionEditor(index),
                      ),
                  ],
                ),
                Container(
                  height: 100,
                  padding: const EdgeInsets.all(8),
                  child: QuillEditor.basic(
                    controller: controller,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        if (!_isFinal)
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add Function',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: _addNewFunctionEditor,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff021e84),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 2,
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    docNameCtrl.dispose();
    legalBasisCtrl.dispose();
    for (var controller in functionControllers) {
      controller.dispose();
    }
    visionCtrl.dispose();
    missionCtrl.dispose();
    pillar1Ctrl.dispose();
    pillar2Ctrl.dispose();
    pillar3Ctrl.dispose();
    super.dispose();
  }
}








