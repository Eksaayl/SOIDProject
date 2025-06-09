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

class PartIIB extends StatefulWidget {
  final String documentId;
  const PartIIB({Key? key, this.documentId = 'document'}) : super(key: key);

  @override
  State<PartIIB> createState() => _PartIIBState();
}

class _PartIIBState extends State<PartIIB> {
  List<Map<String, TextEditingController>> systemControllers = [];
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
    addSystem();
    _sectionRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(widget.documentId)
        .collection('sections')
        .doc('II.B');
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
        if (data['systems'] != null && data['systems'] is List) {
          final List systems = data['systems'];
          systemControllers.clear();
          for (var sys in systems) {
            systemControllers.add({
              'name_of_system': TextEditingController(text: sys['name_of_system'] ?? ''),
              'description': TextEditingController(text: (sys['description'] is List ? (sys['description'] as List).join('\n') : (sys['description'] ?? ''))),
              'status': TextEditingController(text: sys['status'] ?? ''),
              'development_strategy': TextEditingController(text: sys['development_strategy'] ?? ''),
              'computing_scheme': TextEditingController(text: sys['computing_scheme'] ?? ''),
              'users_internal': TextEditingController(text: (sys['users_internal'] is List ? (sys['users_internal'] as List).join('\n') : (sys['users_internal'] ?? ''))),
              'users_external': TextEditingController(text: sys['users_external'] ?? ''),
              'owner': TextEditingController(text: sys['owner'] ?? ''),
            });
          }
          if (systemControllers.isEmpty) addSystem();
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
      final systems = systemControllers.map((controllers) {
        return {
          'name_of_system': controllers['name_of_system']!.text,
          'description': controllers['description']!.text.split('\n').where((e) => e.trim().isNotEmpty).toList(),
          'status': controllers['status']!.text,
          'development_strategy': controllers['development_strategy']!.text,
          'computing_scheme': controllers['computing_scheme']!.text,
          'users_internal': controllers['users_internal']!.text.split('\n').where((e) => e.trim().isNotEmpty).toList(),
          'users_external': controllers['users_external']!.text,
          'owner': controllers['owner']!.text,
        };
      }).toList();

      final url = Uri.parse('http://localhost:8000/generate-iib-docx/');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(systems),
      );

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final fileName = 'document.docx';
        try {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child(widget.documentId)
              .child('II.B')
              .child(fileName);
          final metadata = SettableMetadata(
            contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            customMetadata: {
              'uploadedBy': _userId,
              'documentId': widget.documentId,
              'section': 'II.B',
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
          SnackBar(content: Text('Failed to generate DOCX: \\${response.statusCode}')),
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
        'sectionTitle': 'Part II.B',
      };
      if (!_isFinalized) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdBy'] = username;
      }
      payload['systems'] = systemControllers.map((controllers) {
        return {
          'name_of_system': controllers['name_of_system']!.text,
          'description': controllers['description']!.text.split('\n').where((e) => e.trim().isNotEmpty).toList(),
          'status': controllers['status']!.text,
          'development_strategy': controllers['development_strategy']!.text,
          'computing_scheme': controllers['computing_scheme']!.text,
          'users_internal': controllers['users_internal']!.text.split('\n').where((e) => e.trim().isNotEmpty).toList(),
          'users_external': controllers['users_external']!.text,
          'owner': controllers['owner']!.text,
        };
      }).toList();
      await _sectionRef.set(payload, SetOptions(merge: true));
      setState(() => _isFinalized = finalize);
      if (finalize) {
        await createSubmissionNotification('Part II.B');
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

  void addSystem() {
    systemControllers.add({
      'name_of_system': TextEditingController(),
      'description': TextEditingController(),
      'status': TextEditingController(),
      'development_strategy': TextEditingController(),
      'computing_scheme': TextEditingController(),
      'users_internal': TextEditingController(),
      'users_external': TextEditingController(),
      'owner': TextEditingController(),
    });
    setState(() {});
  }

  void removeSystem(int index) {
    systemControllers.removeAt(index);
    setState(() {});
  }

  Widget systemTableForm(Map<String, TextEditingController> controllers, int index) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Information System ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (!_isFinalized && systemControllers.length > 1)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => removeSystem(index),
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
                child: Text('NAME OF INFORMATION SYSTEM/ SUB-SYSTEM', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: TextFormField(controller: controllers['name_of_system'], enabled: !_isFinalized),
              ),
            ]),
            TableRow(children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('DESCRIPTION', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: controllers['description'],
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
                          final controller = controllers['description']!;
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
                child: Text('STATUS', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: TextFormField(controller: controllers['status'], enabled: !_isFinalized),
              ),
            ]),
            TableRow(children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('DEVELOPMENT STRATEGY', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: TextFormField(controller: controllers['development_strategy'], enabled: !_isFinalized),
              ),
            ]),
            TableRow(children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('COMPUTING SCHEME', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: TextFormField(controller: controllers['computing_scheme'], enabled: !_isFinalized),
              ),
            ]),
            TableRow(children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('USERS (INTERNAL)', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: TextFormField(
                  controller: controllers['users_internal'],
                  maxLines: 3,
                  enabled: !_isFinalized,
                  decoration: InputDecoration(hintText: 'One per line'),
                ),
              ),
            ]),
            TableRow(children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('USERS (EXTERNAL)', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: TextFormField(controller: controllers['users_external'], enabled: !_isFinalized),
              ),
            ]),
            TableRow(children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('OWNER', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: TextFormField(controller: controllers['owner'], enabled: !_isFinalized),
              ),
            ]),
          ],
        ),
      ],
    );
  }

  Future<void> generateAndDownloadDocx() async {
    setState(() => _generating = true);
    List<Map<String, dynamic>> systems = systemControllers.map((controllers) {
      return {
        'name_of_system': controllers['name_of_system']!.text,
        'description': controllers['description']!.text.split('\n').where((e) => e.trim().isNotEmpty).toList(),
        'status': controllers['status']!.text,
        'development_strategy': controllers['development_strategy']!.text,
        'computing_scheme': controllers['computing_scheme']!.text,
        'users_internal': controllers['users_internal']!.text.split('\n').where((e) => e.trim().isNotEmpty).toList(),
        'users_external': controllers['users_external']!.text,
        'owner': controllers['owner']!.text,
      };
    }).toList();
    final url = Uri.parse('http://localhost:8000/generate-iib-docx/');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(systems),
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
              .child('${widget.documentId}/II.B/$fileName');
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
        title: const Text('Part II.B - Detailed Description of Proposed Information Systems'),
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
                  'Part II.B - Detailed Description of Proposed Information Systems'
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
                    'Part II.B - Detailed Description of Proposed Information Systems has been finalized.',
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
                              'Please fill in all the required fields for each information system. You can add multiple systems as needed. Each system will be exported as a table in the DOCX. Make sure all information is accurate and complete before generating the document.',
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
                      ...systemControllers.asMap().entries.map((entry) =>
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
                          child: systemTableForm(entry.value, entry.key),
                        ),
                      ),
                      if (!_isFinalized)
                        Center(
                          child: ElevatedButton.icon(
                            onPressed: addSystem,
                            icon: const Icon(Icons.add, color: Colors.white),
                            label: const Text(
                              'Add Information System',
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