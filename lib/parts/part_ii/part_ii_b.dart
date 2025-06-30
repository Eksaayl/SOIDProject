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
import '../../state/selection_model.dart';
import 'package:provider/provider.dart';

class PartIIB extends StatefulWidget {
  final String documentId;
  const PartIIB({Key? key, required this.documentId}) : super(key: key);

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
  String get _yearRange {
    final yearRange = context.read<SelectionModel>().yearRange ?? '2729';
    print('Getting yearRange (Part II.B): $yearRange');
    return yearRange;
  }

  @override
  void initState() {
    super.initState();
    print('initState (Part II.B) - yearRange: $_yearRange');
    addSystem();
    _sectionRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(_yearRange)
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

  Future<void> _save({bool finalize = false}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final username = await getCurrentUsername();
      final doc = await _sectionRef.get();
      final formattedYearRange = formatYearRange(_yearRange);
      final payload = {
        'modifiedBy': username,
        'lastModified': FieldValue.serverTimestamp(),
        'screening': finalize || _isFinalized,
        'sectionTitle': 'Part II.B',
        'isFinalized': finalize ? false : _isFinalized,
        'yearRange': formattedYearRange,
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
          body: jsonEncode({
            'systems': systems,
            'yearRange': formatYearRange(_yearRange),
          }),
        );

        if (response.statusCode == 200) {
          final bytes = response.bodyBytes;
          final docxRef = FirebaseStorage.instance
              .ref()
              .child('$_yearRange/II.B/document.docx');
          await docxRef.putData(bytes, SettableMetadata(contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'));
          final docxUrl = await docxRef.getDownloadURL();
          await _sectionRef.set({'docxUrl': docxUrl}, SetOptions(merge: true));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to generate DOCX: ${response.statusCode}')),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating/uploading DOCX: ' + e.toString())),
        );
      }

      if (finalize) {
        await createSubmissionNotification('Part II.B', _yearRange);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Part II.B submitted for admin approval. You will be notified once it is reviewed.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          )
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Part II.B saved successfully (not finalized)'),
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

  Future<void> _showRemoveConfirmation(int index) async {
    final confirmed = await showDialog<bool>(
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
                  child: const Icon(Icons.delete_forever, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Remove Information System',
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
                    color: const Color.fromARGB(255, 132, 2, 2).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color.fromARGB(255, 132, 2, 2).withOpacity(0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber,
                        color: Color.fromARGB(255, 132, 2, 2),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Are you sure you want to remove Information System ${index + 1}? This action cannot be undone.',
                          style: const TextStyle(
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
                  'Cancel',
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
                    color: const Color.fromARGB(255, 132, 2, 2).withOpacity(0.3),
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
                  'Remove',
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
    
    if (confirmed == true) {
      removeSystem(index);
    }
  }

  Widget systemTableForm(Map<String, TextEditingController> controllers, int index) {
    final systemNumber = 'IS${(index + 1).toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$systemNumber - Information System ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (!_isFinalized && systemControllers.length > 1)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _showRemoveConfirmation(index),
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('NAME OF INFORMATION SYSTEM/ SUB-SYSTEM', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(width: 4),
                    Tooltip(
                      message: 'Enter the name of the information system or sub-system. Example: $systemNumber - Enterprise Resource Planning System',
                      child: Icon(Icons.help_outline, size: 18, color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: TextFormField(
                  controller: controllers['name_of_system'],
                  enabled: !_isFinalized,
                  decoration: InputDecoration(
                    hintText: 'Enter system name (IS number will be added automatically)',
                  ),
                  onChanged: (value) {
                    if (!value.startsWith(systemNumber)) {
                      final cleanValue = value.replaceAll(systemNumber, '').trim();
                      controllers['name_of_system']!.text = '$systemNumber. $cleanValue';
                      controllers['name_of_system']!.selection = TextSelection.fromPosition(
                        TextPosition(offset: controllers['name_of_system']!.text.length),
                      );
                    }
                  },
                ),
              ),
            ]),
            TableRow(children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('DESCRIPTION', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(width: 4),
                    Tooltip(
                      message: 'Provide a brief description. Use one line per bullet.',
                      child: Icon(Icons.help_outline, size: 18, color: Colors.blueGrey),
                    ),
                  ],
                ),
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('STATUS', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(width: 4),
                    Tooltip(
                      message: 'Indicate the current status (e.g., For Enhancement, For Development, etc.).',
                      child: Icon(Icons.help_outline, size: 18, color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: TextFormField(controller: controllers['status'], enabled: !_isFinalized),
              ),
            ]),
            TableRow(children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('DEVELOPMENT STRATEGY', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(width: 4),
                    Tooltip(
                      message: 'Indicate if the system is In-house, Outsourced, or Both (In-house and Outsourced).',
                      child: Icon(Icons.help_outline, size: 18, color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: TextFormField(controller: controllers['development_strategy'], enabled: !_isFinalized),
              ),
            ]),
            TableRow(children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('COMPUTING SCHEME', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(width: 4),
                    Tooltip(
                      message: 'Describe the computing scheme (e.g., Standalone, Networked, Cloud-based).',
                      child: Icon(Icons.help_outline, size: 18, color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: TextFormField(controller: controllers['computing_scheme'], enabled: !_isFinalized),
              ),
            ]),
            TableRow(children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('USERS (INTERNAL)', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(width: 4),
                    Tooltip(
                      message: 'List internal users (one per line).',
                      child: Icon(Icons.help_outline, size: 18, color: Colors.blueGrey),
                    ),
                  ],
                ),
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('USERS (EXTERNAL)', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(width: 4),
                    Tooltip(
                      message: 'List external users (one per line).',
                      child: Icon(Icons.help_outline, size: 18, color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: TextFormField(controller: controllers['users_external'], enabled: !_isFinalized),
              ),
            ]),
            TableRow(children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('OWNER', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(width: 4),
                    Tooltip(
                      message: 'Indicate the owner or responsible office/person.',
                      child: Icon(Icons.help_outline, size: 18, color: Colors.blueGrey),
                    ),
                  ],
                ),
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

  Future<void> _downloadDocx() async {
    setState(() => _generating = true);
    try {
      final fileName = 'document.docx';
      final storage = FirebaseStorage.instance;
      final docxRef = storage.ref().child('$_yearRange/II.B/document.docx');
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
          final file = File('${directory.path}/$fileName');
          await file.writeAsBytes(docxBytes);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('DOCX downloaded from storage!')),
        );
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
      setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                onPressed: _generating ? null : _downloadDocx,
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
      ),
    );
  }
} 