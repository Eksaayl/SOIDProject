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

class PartIIIB extends StatefulWidget {
  final String documentId;
  const PartIIIB({Key? key, this.documentId = 'document'}) : super(key: key);

  @override
  State<PartIIIB> createState() => _PartIIIBState();
}

class ProjectFormDataB {
  final TextEditingController name;
  final TextEditingController objectives;
  final TextEditingController duration;
  final TextEditingController deliverables;
  final TextEditingController leadAgency;
  final TextEditingController implementingAgencies;
  List<String> savedSubRoles;
  String submittedBy;

  ProjectFormDataB({
    required this.name,
    required this.objectives,
    required this.duration,
    required this.deliverables,
    required this.leadAgency,
    required this.implementingAgencies,
    required this.savedSubRoles,
    required this.submittedBy,
  });
}

class _PartIIIBState extends State<PartIIIB> {
  List<ProjectFormDataB> projectControllers = [];
  bool _generating = false;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _isFinalized = false;
  late DocumentReference _sectionRef;
  final _user = FirebaseAuth.instance.currentUser;
  String get _userId => _user?.displayName ?? _user?.email ?? _user?.uid ?? 'unknown';
  String get _yearRange => context.read<SelectionModel>().yearRange ?? '2729';
  String _userRole = '';
  List<String> _userSubRoles = [];
  bool _userHasProjectInAnySection = false;

  @override
  void initState() {
    super.initState();
    _sectionRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(_yearRange)
        .collection('sections')
        .doc('III.B');
    _loadContent();
    _fetchUserRoleAndCheckBothSections();
  }

  Future<void> _fetchUserRoleAndCheckBothSections() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      setState(() {
        _userRole = userDoc.data()?['role'] ?? '';
        _userSubRoles = List<String>.from(userDoc.data()?['sub_roles'] ?? []);
      });
      await _checkUserHasProjectInAnySection();
      _AddBlankProject();
    }
  }

  Future<void> _checkUserHasProjectInAnySection() async {
    final firestore = FirebaseFirestore.instance;
    final iiiA = await firestore.collection('issp_documents').doc(_yearRange).collection('sections').doc('III.A').get();
    final iiiB = await firestore.collection('issp_documents').doc(_yearRange).collection('sections').doc('III.B').get();
    bool found = false;
    for (final doc in [iiiA, iiiB]) {
      if (doc.exists && doc.data() != null) {
        final projects = doc.data()!['projects'] as List<dynamic>? ?? [];
        for (final proj in projects) {
          final savedSubRoles = List<String>.from(proj['sub_roles'] ?? []);
          if (savedSubRoles.isNotEmpty && _userSubRoles.any((userSubRole) => savedSubRoles.contains(userSubRole))) {
            found = true;
            break;
          }
        }
      }
      if (found) break;
    }
    setState(() {
      _userHasProjectInAnySection = found;
    });
  }

  bool _canEditProject(ProjectFormDataB project) {
    if (_userRole == 'admin') return true;
    if (_userSubRoles.isEmpty) return true;
    
    return project.savedSubRoles.isNotEmpty && 
           _userSubRoles.any((userSubRole) => project.savedSubRoles.contains(userSubRole));
  }

  bool _canAddProject() {
    if (_userRole == 'admin') return true;
    if (_userSubRoles.isEmpty) return true;
    
    final userProjectsInThisSection = projectControllers.where((project) => 
      _canEditProject(project)
    ).length;
    
    return userProjectsInThisSection == 0;
  }

  // Get projects that user can edit
  List<ProjectFormDataB> get _editableProjects {
    if (_userRole == 'admin') return projectControllers;
    if (_userSubRoles.isEmpty) return projectControllers;
    
    return projectControllers.where((project) => _canEditProject(project)).toList();
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
            projectControllers.add(ProjectFormDataB(
              name: TextEditingController(text: project['name'] ?? ''),
              objectives: TextEditingController(text: project['objectives'] ?? ''),
              duration: TextEditingController(text: project['duration'] ?? ''),
              deliverables: TextEditingController(text: (project['deliverables'] is List ? (project['deliverables'] as List).join('\n') : (project['deliverables'] ?? ''))),
              leadAgency: TextEditingController(text: project['lead_agency'] ?? ''),
              implementingAgencies: TextEditingController(text: project['implementing_agencies'] ?? ''),
              savedSubRoles: List<String>.from(project['sub_roles'] ?? []),
              submittedBy: project['submitted_by'] ?? '',
            ));
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Load error: $e')),
      );
    }
    setState(() {});
    _AddBlankProject();
  }

  void _AddBlankProject() {
    if (projectControllers.isEmpty && (_userRole == 'admin' || _userSubRoles.isEmpty)) {
      addProject();
    }
  }

  Future<String?> _generateAndUploadDocx() async {
    try {
      final projects = projectControllers.map((controllers) {
        return {
          'name': controllers.name.text,
          'objectives': controllers.objectives.text,
          'duration': controllers.duration.text,
          'deliverables': controllers.deliverables.text.split('\n').where((e) => e.trim().isNotEmpty).toList(),
          'lead_agency': controllers.leadAgency.text,
          'implementing_agencies': controllers.implementingAgencies.text,
          'sub_roles': controllers.savedSubRoles,
          'submitted_by': controllers.submittedBy,
        };
      }).toList();

      final formattedYearRange = formatYearRange(_yearRange);
      final url = Uri.parse('http://localhost:8000/generate-iii-b-docx/');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'yearrange': formattedYearRange,
        },
        body: jsonEncode(projects),
      );

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final fileName = 'document.docx';
        
        try {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child(_yearRange)
              .child('III.B')
              .child(fileName);
          
          final metadata = SettableMetadata(
            contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            customMetadata: {
              'uploadedBy': _userId,
              'documentId': _yearRange,
              'section': 'III.B',
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
      
      final projects = projectControllers.map((controllers) {
        return {
          'name': controllers.name.text,
          'objectives': controllers.objectives.text,
          'duration': controllers.duration.text,
          'deliverables': controllers.deliverables.text.split('\n').where((e) => e.trim().isNotEmpty).toList(),
          'lead_agency': controllers.leadAgency.text,
          'implementing_agencies': controllers.implementingAgencies.text,
          'sub_roles': controllers.savedSubRoles,
          'submitted_by': controllers.submittedBy,
        };
      }).toList();
      
      final payload = {
        'projects': projects,
        'modifiedBy': username,
        'lastModified': FieldValue.serverTimestamp(),
        'screening': finalize || _isFinalized,
        'sectionTitle': 'Part III.B',
        'isFinalized': finalize ? false : _isFinalized,
      };

      if (!_isFinalized) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdBy'] = username;
      }

      final docxUrl = await _generateAndUploadDocx();
      if (docxUrl != null) {
        payload['docxUrl'] = docxUrl;
        payload['docxUploadedAt'] = FieldValue.serverTimestamp();
      }

      await _sectionRef.set(payload, SetOptions(merge: true));
      setState(() => _isFinalized = finalize);

      if (finalize) {
        await createSubmissionNotification('Part III.B', _yearRange);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Part III.B submitted for admin approval. You will be notified once it is reviewed.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          )
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Part III.B saved successfully (not finalized)'),
            backgroundColor: Colors.green,
          )
        );
      }
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
    if (!_canAddProject()) return;
    projectControllers.add(ProjectFormDataB(
      name: TextEditingController(),
      objectives: TextEditingController(),
      duration: TextEditingController(),
      deliverables: TextEditingController(),
      leadAgency: TextEditingController(),
      implementingAgencies: TextEditingController(),
      savedSubRoles: List<String>.from(_userSubRoles),
      submittedBy: _userId,
    ));
    setState(() {});
  }

  void removeProject(int index) {
    final project = projectControllers[index];
    if (!_canEditProject(project)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can only remove projects that belong to your sub-role.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    projectControllers.removeAt(index);
    setState(() {});
    _updateProjectsInFirestore();
  }

  Future<void> _updateProjectsInFirestore() async {
    final projects = projectControllers.map((controllers) {
      return {
        'name': controllers.name.text,
        'objectives': controllers.objectives.text,
        'duration': controllers.duration.text,
        'deliverables': controllers.deliverables.text.split('\n').where((e) => e.trim().isNotEmpty).toList(),
        'lead_agency': controllers.leadAgency.text,
        'implementing_agencies': controllers.implementingAgencies.text,
        'sub_roles': controllers.savedSubRoles,
        'submitted_by': controllers.submittedBy,
      };
    }).toList();
    await _sectionRef.set({'projects': projects}, SetOptions(merge: true));
  }

  Widget projectTableForm(ProjectFormDataB controllers, int index) {
    final savedSubRoles = controllers.savedSubRoles;
    final canEdit = _userRole == 'admin' ||
        _userSubRoles.isEmpty ||
        (savedSubRoles.isNotEmpty && savedSubRoles.any((savedSubRole) => _userSubRoles.contains(savedSubRole)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Project ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (!_isFinalized && projectControllers.length > 1 && canEdit)
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('A.1 NAME/TITLE', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(width: 4),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: TextFormField(
                  controller: controllers.name,
                  enabled: !_isFinalized && canEdit,
                ),
              ),
            ]),
            TableRow(children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('A.2 OBJECTIVES', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(width: 4),
                    Tooltip(
                      message: 'List the main objectives of the project. Use bullet points for clarity.',
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
                        controller: controllers.objectives,
                        maxLines: 4,
                        enabled: !_isFinalized && canEdit,
                        decoration: InputDecoration(
                          hintText: 'One per line for bullets',
                        ),
                      ),
                    ),
                    if (!_isFinalized && canEdit)
                      IconButton(
                        icon: Icon(Icons.format_list_bulleted),
                        tooltip: 'Insert bullet',
                        onPressed: () {
                          final controller = controllers.objectives;
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
                    Text('A.3 DURATION', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(width: 4),
                    Tooltip(
                      message: 'Enter the project duration. Example: 2024 - 2025',
                      child: Icon(Icons.help_outline, size: 18, color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: TextFormField(
                  controller: controllers.duration,
                  enabled: !_isFinalized && canEdit,
                  decoration: InputDecoration(
                    hintText: 'Enter the project duration',
                  ),
                ),
              ),
            ]),
            TableRow(children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('A.4 DELIVERABLES', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(width: 4),
                    Tooltip(
                      message: 'List the expected outputs or deliverables of the project. Use bullet points for clarity.',
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
                        controller: controllers.deliverables,
                        maxLines: 4,
                        enabled: !_isFinalized && canEdit,
                        decoration: InputDecoration(
                          hintText: 'One per line for bullets',
                        ),
                      ),
                    ),
                    if (!_isFinalized && canEdit)
                      IconButton(
                        icon: Icon(Icons.format_list_bulleted),
                        tooltip: 'Insert bullet',
                        onPressed: () {
                          final controller = controllers.deliverables;
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
                    Text('A.5 LEAD AGENCY', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(width: 4),
                    Tooltip(
                      message: 'Enter the main agency responsible for the project.',
                      child: Icon(Icons.help_outline, size: 18, color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: TextFormField(
                  controller: controllers.leadAgency,
                  enabled: !_isFinalized && canEdit,
                  decoration: InputDecoration(
                    hintText: 'Enter the lead agency',
                  ),
                ),
              ),
            ]),
            TableRow(children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('A.6 IMPLEMENTING AGENCIES', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(width: 4),
                    Tooltip(
                      message: 'Enter the agencies involved in implementing the project.',
                      child: Icon(Icons.help_outline, size: 18, color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: TextFormField(
                  controller: controllers.implementingAgencies,
                  enabled: !_isFinalized && canEdit,
                  decoration: InputDecoration(
                    hintText: 'Enter the implementing agencies',
                  ),
                ),
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
      final docxRef = storage.ref().child('$_yearRange/III.B/document.docx');
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
          title: const Text('Part III.B - Cross-Agency ICT Projects'),
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
                    'Part III.B - Cross-Agency ICT Projects'
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
                      'Part III.B - Cross-Agency ICT Projects has been finalized.',
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
                                'Please fill in all the required fields for each ICT project. You can add multiple projects as needed. Each project can be dragged and placed wherever you want to change its order (admin only). The top project will be Rank 1, the next will be Rank 2, and so on. Each project will be exported as a table in the DOCX. Make sure all information is accurate and complete before generating the document.',
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
                        if (_userRole == 'admin')
                          ReorderableListView(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            onReorder: (oldIndex, newIndex) {
                              setState(() {
                                if (newIndex > oldIndex) newIndex -= 1;
                                final item = projectControllers.removeAt(oldIndex);
                                projectControllers.insert(newIndex, item);
                              });
                            },
                            children: [
                              for (final entry in projectControllers.asMap().entries)
                                Container(
                                  key: ValueKey('project_${entry.key}'),
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
                            ],
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: projectControllers.length,
                            itemBuilder: (context, index) {
                              final controllers = projectControllers[index];
                              return Container(
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
                                child: projectTableForm(controllers, index),
                              );
                            },
                          ),
                        if (!_isFinalized)
                          Center(
                            child: Tooltip(
                              message: (_userRole != 'admin' && _userSubRoles.isNotEmpty && _userHasProjectInAnySection)
                                  ? 'You can only add one project as a focal person tied to a project unless you are an admin.'
                                  : '',
                              child: ElevatedButton.icon(
                                onPressed: _canAddProject() ? addProject : null,
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