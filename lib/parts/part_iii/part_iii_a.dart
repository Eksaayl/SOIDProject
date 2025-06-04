import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../main_part.dart';
import '../../utils/user_utils.dart';
import '../../services/notification_service.dart';

class PartIIIA extends StatefulWidget {
  final String documentId;
  const PartIIIA({Key? key, this.documentId = 'document'}) : super(key: key);

  @override
  State<PartIIIA> createState() => _PartIIIAState();
}

class _PartIIIAState extends State<PartIIIA> {
  List<Map<String, TextEditingController>> projectControllers = [];
  bool _generating = false;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _isFinalized = false;
  late DocumentReference _sectionRef;
  final _user = FirebaseAuth.instance.currentUser;
  String get _userId => _user?.displayName ?? _user?.email ?? _user?.uid ?? 'unknown';

  @override
  void initState() {
    super.initState();
    addProject();
    _sectionRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(widget.documentId)
        .collection('sections')
        .doc('III.A');
    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      final doc = await _sectionRef.get();
      final data = doc.data() as Map<String, dynamic>?;
      if (data != null) {
        setState(() {
          _isFinalized = (data['isFinalized'] as bool? ?? false) || (data['screening'] as bool? ?? false);
        });
        if (data['projects'] != null && data['projects'] is List) {
          final List projects = data['projects'];
          projectControllers.clear();
          for (var project in projects) {
            projectControllers.add({
              'name': TextEditingController(text: project['name'] ?? ''),
              'objectives': TextEditingController(text: project['objectives'] ?? ''),
              'duration': TextEditingController(text: project['duration'] ?? ''),
              'deliverables': TextEditingController(text: (project['deliverables'] is List ? (project['deliverables'] as List).join('\n') : (project['deliverables'] ?? ''))),
            });
          }
          if (projectControllers.isEmpty) addProject();
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Load error: $e')),
      );
    }
    setState(() {});
  }

  Future<String?> _generateAndUploadDocx() async {
    try {
      final projects = projectControllers.map((controllers) {
        return {
          'name': controllers['name']!.text,
          'objectives': controllers['objectives']!.text,
          'duration': controllers['duration']!.text,
          'deliverables': controllers['deliverables']!.text.split('\n').where((e) => e.trim().isNotEmpty).toList(),
        };
      }).toList();

      final url = Uri.parse('http://localhost:8000/generate-iii-a-docx/');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(projects),
      );

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final fileName = 'document.docx';
        
        try {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('document')
              .child('III.A')
              .child(fileName);
          
          final metadata = SettableMetadata(
            contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            customMetadata: {
              'uploadedBy': _userId,
              'documentId': widget.documentId,
              'section': 'III.A',
            },
          );

          if (kIsWeb) {
            await storageRef.putData(bytes, metadata);
          } else {
            final directory = await getApplicationDocumentsDirectory();
            final file = File('${directory.path}/$fileName');
            await file.writeAsBytes(bytes);
            await storageRef.putFile(file, metadata);
          }
          
          return await storageRef.getDownloadURL();
        } catch (storageError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error uploading to storage: $storageError')),
          );
          return null;
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate DOCX: ${response.statusCode}')),
        );
      }
      return null;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      return null;
    }
  }

  Future<void> _save({bool finalize = false}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final username = await getCurrentUsername();
      final doc = await _sectionRef.get();
      final payload = {
        'modifiedBy': username,
        'lastModified': FieldValue.serverTimestamp(),
        'screening': finalize || _isFinalized,
        'sectionTitle': 'Part III.A',
      };

      if (!_isFinalized) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdBy'] = username;
      }

      await _sectionRef.set(payload, SetOptions(merge: true));
      setState(() => _isFinalized = finalize);

      if (finalize) {
        await createSubmissionNotification('Part III.A');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isFinalized ? 'Finalized' : 'Saved (not finalized)'))
      );
    } catch (e) {
      print('Error in saveContent: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save error: $e')),
      );
    } finally {
      setState(() => _saving = false);
    }
  }

  void addProject() {
    projectControllers.add({
      'name': TextEditingController(),
      'objectives': TextEditingController(),
      'duration': TextEditingController(),
      'deliverables': TextEditingController(),
    });
    setState(() {});
  }

  void removeProject(int index) {
    projectControllers.removeAt(index);
    setState(() {});
  }

  Widget projectTableForm(Map<String, TextEditingController> controllers, int index) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Project ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (!_isFinalized && projectControllers.length > 1)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => removeProject(index),
              ),
          ],
        ),
        Table(
          border: TableBorder.all(),
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(5),
          },
          children: [
            TableRow(children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('A.1 NAME/TITLE', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: TextFormField(controller: controllers['name'], enabled: !_isFinalized),
              ),
            ]),
            TableRow(children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('A.2 OBJECTIVES', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: controllers['objectives'],
                        maxLines: 4,
                        enabled: !_isFinalized,
                        decoration: InputDecoration(hintText: 'One per line for bullets'),
                      ),
                    ),
                    if (!_isFinalized)
                      IconButton(
                        icon: Icon(Icons.format_list_bulleted),
                        tooltip: 'Insert bullet',
                        onPressed: () {
                          final controller = controllers['objectives']!;
                          final text = controller.text;
                          final selection = controller.selection;
                          final newText = text.replaceRange(
                            selection.start,
                            selection.end,
                            '• ',
                          );
                          controller.text = newText;
                          controller.selection = TextSelection.collapsed(offset: selection.start + 2);
                        },
                      ),
                  ],
                ),
              ),
            ]),
            TableRow(children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('A.3 DURATION', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: TextFormField(controller: controllers['duration'], enabled: !_isFinalized),
              ),
            ]),
            TableRow(children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('A.4 DELIVERABLES', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: controllers['deliverables'],
                        maxLines: 4,
                        enabled: !_isFinalized,
                        decoration: InputDecoration(hintText: 'One per line for bullets'),
                      ),
                    ),
                    if (!_isFinalized)
                      IconButton(
                        icon: Icon(Icons.format_list_bulleted),
                        tooltip: 'Insert bullet',
                        onPressed: () {
                          final controller = controllers['deliverables']!;
                          final text = controller.text;
                          final selection = controller.selection;
                          final newText = text.replaceRange(
                            selection.start,
                            selection.end,
                            '• ',
                          );
                          controller.text = newText;
                          controller.selection = TextSelection.collapsed(offset: selection.start + 2);
                        },
                      ),
                  ],
                ),
              ),
            ]),
          ],
        ),
      ],
    );
  }

  Future<void> generateAndDownloadDocx() async {
    setState(() => _generating = true);
    List<Map<String, dynamic>> projects = projectControllers.map((controllers) {
      return {
        'name': controllers['name']!.text,
        'objectives': controllers['objectives']!.text,
        'duration': controllers['duration']!.text,
        'deliverables': controllers['deliverables']!.text.split('\n').where((e) => e.trim().isNotEmpty).toList(),
      };
    }).toList();

    final url = Uri.parse('http://localhost:8000/generate-iii-a-docx/');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(projects),
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

          final storageRef = FirebaseStorage.instance
              .ref()
              .child('${widget.documentId}/III.A/$fileName');
          final uploadTask = await storageRef.putFile(file);
          final downloadUrl = await storageRef.getDownloadURL();

          await _sectionRef.set({
            'docxUrl': downloadUrl,
            'docxUploadedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('DOCX uploaded and saved! Download: $downloadUrl')),
          );
        }
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
      setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: const Text('Part III.A - Internal Systems Development Components'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2D3748),
        actions: [
          if (_saving || _generating)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Color(0xff021e84),
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saving ? null : () => _save(finalize: false),
              tooltip: 'Save',
              color: const Color(0xff021e84),
            ),
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _isFinalized ? null : () async {
                final confirmed = await showFinalizeConfirmation(
                  context,
                  'Part III.A - Internal Systems Development Components'
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
              onPressed: _generating ? null : generateAndDownloadDocx,
              tooltip: 'Generate DOCX',
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
                    'Part III.A - Internal Systems Development Components has been finalized.',
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
                              'Please fill in all the required fields for each ICT project. You can add multiple projects as needed. Each project will be exported as a table in the DOCX. Make sure all information is accurate and complete before generating the document.',
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
                      ...projectControllers.asMap().entries.map((entry) =>
                        Container(
                          margin: const EdgeInsets.only(bottom: 24),
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
                          child: projectTableForm(entry.value, entry.key),
                        ),
                      ),
                      if (!_isFinalized)
                        Center(
                          child: ElevatedButton.icon(
                            onPressed: addProject,
                            icon: const Icon(Icons.add, color: Colors.white),
                            label: const Text(
                              'Add Project',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
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
                  ),
                ),
              ),
            ),
    );
  }
} 