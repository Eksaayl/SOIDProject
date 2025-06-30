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
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../state/selection_model.dart';

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
  late TextEditingController frameworkCtrl;
  final List<TextEditingController> pillarControllers = [];

  bool _loading = true;
  bool _saving = false;
  bool _compiling = false;
  bool _isFinalized = false;

  late DocumentReference _sectionRef;
  String get _yearRange => context.read<SelectionModel>().yearRange ?? '2729';

  Uint8List? _uploadedDocxBytes;
  String? _uploadedDocxName;

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
    frameworkCtrl = TextEditingController();
    for (int i = 0; i < 1; i++) {
      pillarControllers.add(TextEditingController());
    }

    _addNewFunctionEditor();

    _sectionRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(_yearRange)
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
      frameworkCtrl.text = data['framework'] ?? '';
      
      for (var controller in pillarControllers) {
        controller.dispose();
      }
      pillarControllers.clear();
      
      if (data['pillar'] != null) {
        final String pillarText = data['pillar'];
        final List<String> pillars = pillarText.split('\n');
        for (var pillar in pillars) {
          if (pillar.trim().isNotEmpty) {
            final controller = TextEditingController();
            final match = RegExp(r'Pillar \d+: (.+)$').firstMatch(pillar);
            if (match != null) {
              controller.text = match.group(1)?.trim() ?? '';
            }
            pillarControllers.add(controller);
          }
        }
      }
      
      if (pillarControllers.isEmpty) {
        pillarControllers.add(TextEditingController());
      }
      
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
      setState(() {
        _isFinalized = (data['isFinalized'] as bool? ?? false) || (data['screening'] as bool? ?? false);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Load error: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickDocxFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['docx'],
      );
      if (result != null) {
        final file = result.files.first;
        if (file.bytes != null) {
          setState(() {
            _uploadedDocxBytes = file.bytes;
            _uploadedDocxName = file.name;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('DOCX file selected. Click Save to upload.'))
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File pick error: $e'))
      );
    }
  }

  Future<void> _save({bool finalize = false}) async {
    if (_uploadedDocxBytes == null && !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      String? docxUrl;
      final storage = FirebaseStorage.instance;
      final docxRef = storage.ref().child('$_yearRange/I.A/document.docx');
      if (_uploadedDocxBytes != null) {
        await docxRef.putData(_uploadedDocxBytes!, SettableMetadata(contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'));
        docxUrl = await docxRef.getDownloadURL();
      } else {
        final data = {
          'documentName': docNameCtrl.text.trim(),
          'legalBasis': legalBasisCtrl.text.trim(),
          'visionStatement': visionCtrl.text.trim(),
          'missionStatement': missionCtrl.text.trim(),
          'framework': frameworkCtrl.text.trim(),
          'pillar': pillarControllers
              .asMap()
              .entries
              .map((entry) => 'Pillar ${entry.key + 1}: ${entry.value.text.trim()}')
              .where((text) => text.isNotEmpty)
              .join('\n'),
          'yearRange': formatYearRange(_yearRange),
        };
        final url = Uri.parse('http://localhost:8000/generate-ia-docx/');
        final response = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'yearRange': formatYearRange(_yearRange),
          },
          body: jsonEncode(data),
        );
        if (response.statusCode != 200) {
          throw Exception('Failed to generate DOCX: ${response.statusCode}');
        }
        final docxBytes = response.bodyBytes;
        await docxRef.putData(docxBytes, SettableMetadata(contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'));
        docxUrl = await docxRef.getDownloadURL();
      }

      final username = await getCurrentUsername();
      final payload = {
        'documentName': docNameCtrl.text.trim(),
        'legalBasis': legalBasisCtrl.text.trim(),
        'framework': frameworkCtrl.text.trim(),
        'visionStatement': visionCtrl.text.trim(),
        'missionStatement': missionCtrl.text.trim(),
        'pillar': pillarControllers
            .asMap()
            .entries
            .map((entry) => 'Pillar ${entry.key + 1}: ${entry.value.text.trim()}')
            .where((text) => text.isNotEmpty)
            .join('\n'),
        'fileUrl': docxUrl,
        'modifiedBy': username,
        'lastModified': FieldValue.serverTimestamp(),
        'screening': finalize || _isFinalized,
        'sectionTitle': 'Part I.A',
        'isFinalized': finalize ? false : _isFinalized,
      };
      if (!finalize) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdBy'] = username;
      }
      await _sectionRef.set(payload, SetOptions(merge: true));
      setState(() {
        _isFinalized = finalize;
        _uploadedDocxBytes = null;
        _uploadedDocxName = null;
      });
      if (finalize) {
        await createSubmissionNotification('Part I.A', _yearRange);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Part I.A submitted for admin approval. You will be notified once it is reviewed.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          )
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Part I.A saved successfully (not finalized)'),
            backgroundColor: Colors.green,
          )
        );
      }
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
        'pillar': pillarControllers
            .asMap()
            .entries
            .map((entry) => 'Pillar ${entry.key + 1}: ${entry.value.text.trim()}')
            .where((text) => text.isNotEmpty)
            .join('\n'),
      };

      final bytes = await generateDocxBySearchReplace(
        assetPath: 'assets/a.docx',
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

  Future<void> _downloadDocx() async {
    setState(() => _compiling = true);
    try {
      final fileName = 'document.docx';
      if (_uploadedDocxBytes != null) {
        if (kIsWeb) {
          await FileSaver.instance.saveFile(
            name: fileName,
            bytes: _uploadedDocxBytes!,
            mimeType: MimeType.microsoftWord,
          );
        } else {
          final directory = await getApplicationDocumentsDirectory();
          final file = File('$_yearRange/$fileName');
          await file.writeAsBytes(_uploadedDocxBytes!);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('DOCX downloaded (from uploaded file, not yet saved)!')),
        );
        return;
      }
      final storage = FirebaseStorage.instance;
      final docxRef = storage.ref().child('$_yearRange/I.A/document.docx');
      final docxBytes = await docxRef.getData();
      if (docxBytes != null) {
        if (kIsWeb) {
          await FileSaver.instance.saveFile(
            name: fileName,
            bytes: docxBytes,
            mimeType: MimeType.microsoftWord,
          );
        } else {
          final directory = await getApplicationDocumentsDirectory();
          final file = File('$_yearRange/$fileName');
          await file.writeAsBytes(docxBytes);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('DOCX downloaded from storage!')),
        );
        return;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No DOCX file found in storage. Please save or finalize first.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download error: ${e.toString()}')),
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

    return WillPopScope(
      onWillPop: () async {
        final shouldPop = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: Colors.white,
              elevation: 20,
              title: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xff021e84), Color(0xff1e40af)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.warning_amber, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Save Before Leaving',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              content: Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xff021e84).withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xff021e84).withOpacity(0.1),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Color(0xff021e84),
                            size: 20,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Make sure to save before leaving to avoid losing your work.',
                              style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFF4A5568),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: const Text(
                      'Stay',
                      style: TextStyle(
                        color: Color(0xFF4A5568),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color.fromARGB(255, 132, 2, 2), Color.fromARGB(255, 175, 30, 30)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xff021e84).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text(
                      'Leave Anyway',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
        return shouldPop ?? false;
      },
      child: Scaffold(
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
                onPressed: _isFinalized ? null : () => _save(finalize: false),
                tooltip: 'Save',
                color: const Color(0xff021e84),
              ),
              IconButton(
                icon: const Icon(Icons.check),
                onPressed: _isFinalized ? null : () async {
                  final confirmed = await showFinalizeConfirmation(
                    context,
                    'Part I.A - Department/Agency Vision/Mission Statement'
                  );
                  if (confirmed) {
                    _save(finalize: true);
                  }
                },
                tooltip: 'Finalize',
                color: _isFinalized ? Colors.grey : const Color(0xff021e84),
              ),
              IconButton(
                icon: const Icon(Icons.file_download),
                onPressed: _compiling ? null : _downloadDocx,
                tooltip: 'Download DOCX',
                color: const Color(0xff021e84),
              ),
            ],
          ],
        ),
        body: _isFinalized
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
                                'Please fill in all the required fields below. You can add multiple functions as needed. Alternatively, you may upload a DOCX file directly instead of using the form. Make sure all information is accurate and complete before finalizing. If you upload a DOCX, it will be saved and used for this section.',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFF4A5568),
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.08),
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
                                      color: const Color(0xff021e84).withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.upload_file,
                                      color: Color(0xff021e84),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'Upload DOCX (optional)',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2D3748),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'You may upload a DOCX file directly instead of using the form. If you upload a DOCX, it will be saved and used for this section.',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Color(0xFF4A5568),
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: _isFinalized ? null : _pickDocxFile,
                                    icon: const Icon(Icons.upload_file),
                                    label: const Text('Upload DOCX'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xff021e84),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  if (_uploadedDocxName != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xff021e84).withOpacity(0.07),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.description, color: Color(0xff021e84), size: 20),
                                          const SizedBox(width: 6),
                                          Text(_uploadedDocxName!, style: const TextStyle(fontSize: 15, color: Color(0xFF2D3748))),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        buildSectionCard(
                          icon: Icons.gavel,
                          title: 'Legal Basis',
                          child: _buildField('Legal Basis', legalBasisCtrl, multiline: true),
                        ),
                        const SizedBox(height: 24),
                        buildSectionCard(
                          icon: Icons.visibility,
                          title: 'Vision and Mission',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildField('Vision Statement', visionCtrl, multiline: true),
                              _buildField('Mission Statement', missionCtrl, multiline: true),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        buildSectionCard(
                          icon: Icons.architecture,
                          title: 'Framework',
                          child: _buildField('Framework', frameworkCtrl, multiline: true),
                        ),
                        const SizedBox(height: 24),
                        buildSectionCard(
                          icon: Icons.architecture,
                          title: 'Pillars',
                          child: _buildPillarSection(),
                        ),
                      ],
                    ),
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
        enabled: !_isFinalized,
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

  Widget _buildPillarSection() {
    return Column(
      children: [
        ...pillarControllers.asMap().entries.map((entry) {
          final idx = entry.key;
          final ctrl = entry.value;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: TextFormField(
              controller: ctrl,
              enabled: !_isFinalized,
              maxLines: null,
              decoration: InputDecoration(
                labelText: 'Pillar ${idx + 1}',
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
              validator: (v) => v == null || v.trim().isEmpty ? 'Pillar ${idx + 1} is required' : null,
            ),
          );
        }),
        if (!_isFinalized)
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add Pillar',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              onPressed: () {
                setState(() {
                  pillarControllers.add(TextEditingController());
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff021e84),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
    frameworkCtrl.dispose();
    for (var ctrl in pillarControllers) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Widget buildSectionCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
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
                child: Icon(icon, color: const Color(0xff021e84)),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3748),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}








