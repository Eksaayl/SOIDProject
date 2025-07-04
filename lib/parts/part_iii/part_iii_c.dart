import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_saver/file_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:test_project/main_part.dart';
import 'package:test_project/utils/user_utils.dart';
import 'package:http/http.dart' as http;
import '../../services/notification_service.dart';
import '../../state/selection_model.dart';
import 'package:provider/provider.dart';

class LogframeProject {
  List<Map<String, TextEditingController>> intermediateRows;
  List<Map<String, TextEditingController>> immediateRows;
  List<Map<String, TextEditingController>> outputRows;
  LogframeProject()
      : intermediateRows = [
          {'hierarchy': TextEditingController(), 'ovi': TextEditingController(), 'baseline': TextEditingController(), 'targets': TextEditingController(), 'methods': TextEditingController(), 'responsibility': TextEditingController()},
        ],
        immediateRows = [
          {'hierarchy': TextEditingController(), 'ovi': TextEditingController(), 'baseline': TextEditingController(), 'targets': TextEditingController(), 'methods': TextEditingController(), 'responsibility': TextEditingController()},
        ],
        outputRows = [
          {'hierarchy': TextEditingController(), 'ovi': TextEditingController(), 'baseline': TextEditingController(), 'targets': TextEditingController(), 'methods': TextEditingController(), 'responsibility': TextEditingController()},
        ];
}

class PartIIIC extends StatefulWidget {
  final String documentId;
  
  const PartIIIC({
    Key? key,
    this.documentId = 'document',
  }) : super(key: key);

  @override
  _PartIIICState createState() => _PartIIICState();
}

class _PartIIICState extends State<PartIIIC> {
  final _formKey = GlobalKey<FormState>();
  Uint8List? _docxBytes;
  String? _fileName;
  bool _loading = true;
  bool _saving = false;
  bool _isFinalized = false;

  late DocumentReference _sectionRef;
  final _user = FirebaseAuth.instance.currentUser;
  String get _userId => _user?.displayName ?? _user?.email ?? _user?.uid ?? 'unknown';
  final _storage = FirebaseStorage.instance;
  String get _yearRange => context.read<SelectionModel>().yearRange ?? '2729';
  String _userRole = '';
  List<String> _userSubRoles = [];
  bool _userHasProjectInAnySection = false;

  final List<Map<String, TextEditingController>> _logframeControllers = List.generate(3, (i) => {
    'hierarchy': TextEditingController(),
    'ovi': TextEditingController(),
    'baseline': TextEditingController(),
    'targets': TextEditingController(),
    'methods': TextEditingController(),
    'responsibility': TextEditingController(),
  });

  final List<String> _defaultHierarchy = [
    '',
    '',
    '',
  ];

  List<LogframeProject> _projects = [LogframeProject()];

  @override
  void initState() {
    super.initState();
    _sectionRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(_yearRange)
        .collection('sections')
        .doc('III.C');
    _loadContent();
    _fetchUserRoleAndCheckBothSections();
    for (int i = 0; i < 3; i++) {
      _logframeControllers[i]['hierarchy']!.text = _defaultHierarchy[i];
    }
  }

  Future<void> _loadContent() async {
    try {
      final doc = await _sectionRef.get();
      final data = doc.data() as Map<String, dynamic>?;
      _projects.clear();
      
      if (data != null) {
        setState(() {
          _isFinalized = (data['isFinalized'] as bool? ?? false) || (data['screening'] as bool? ?? false);
          _fileName = data['fileName'] as String?;
        });
        
        // Load multiple logframes from Firestore
        if (data['logframes'] is List) {
          for (final logframe in data['logframes']) {
            final project = LogframeProject();
            
            // Populate intermediateRows
            if (logframe['intermediate'] is List) {
              project.intermediateRows = (logframe['intermediate'] as List).map((row) => {
                'hierarchy': TextEditingController(text: row['hierarchy']?.toString() ?? ''),
                'ovi': TextEditingController(text: row['ovi']?.toString() ?? ''),
                'baseline': TextEditingController(text: row['baseline']?.toString() ?? ''),
                'targets': TextEditingController(text: row['targets']?.toString() ?? ''),
                'methods': TextEditingController(text: row['methods']?.toString() ?? ''),
                'responsibility': TextEditingController(text: row['responsibility']?.toString() ?? ''),
              }).toList();
            }
            
            // Populate immediateRows
            if (logframe['immediate'] is List) {
              project.immediateRows = (logframe['immediate'] as List).map((row) => {
                'hierarchy': TextEditingController(text: row['hierarchy']?.toString() ?? ''),
                'ovi': TextEditingController(text: row['ovi']?.toString() ?? ''),
                'baseline': TextEditingController(text: row['baseline']?.toString() ?? ''),
                'targets': TextEditingController(text: row['targets']?.toString() ?? ''),
                'methods': TextEditingController(text: row['methods']?.toString() ?? ''),
                'responsibility': TextEditingController(text: row['responsibility']?.toString() ?? ''),
              }).toList();
            }
            
            // Populate outputRows
            if (logframe['outputs'] is List) {
              project.outputRows = (logframe['outputs'] as List).map((row) => {
                'hierarchy': TextEditingController(text: row['hierarchy']?.toString() ?? ''),
                'ovi': TextEditingController(text: row['ovi']?.toString() ?? ''),
                'baseline': TextEditingController(text: row['baseline']?.toString() ?? ''),
                'targets': TextEditingController(text: row['targets']?.toString() ?? ''),
                'methods': TextEditingController(text: row['methods']?.toString() ?? ''),
                'responsibility': TextEditingController(text: row['responsibility']?.toString() ?? ''),
              }).toList();
            }
            
            _projects.add(project);
          }
        }
        
        // If no logframes found, add a blank one
        if (_projects.isEmpty) {
          _projects.add(LogframeProject());
        }
        
        // Load DOCX if it exists
        try {
          final docxRef = _storage.ref().child('${_yearRange}/III.C/document.docx');
          final docxBytes = await docxRef.getData();
          if (docxBytes != null) {
            setState(() {
              _docxBytes = docxBytes;
            });
          }
        } catch (e) {
          print('Error loading DOCX: $e');
        }
      } else {
        // No data exists, add a blank project
        _projects.add(LogframeProject());
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Load error: $e'))
      );
    } finally {
      setState(() => _loading = false);
    }
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

  // Check if user can edit the logframe
  bool _canEditLogframe() {
    if (_userRole == 'admin') return true;
    if (_userSubRoles.isEmpty) return true;
    
    // Users can edit Part III.C if they have projects in either III.A or III.B
    return _userHasProjectInAnySection;
  }

  Map<String, dynamic> _collectLogframeData() {
    // Convert all projects to plain maps for saving
    final logframes = _projects.map((project) => {
      'intermediate': project.intermediateRows.map((c) => {
        'hierarchy': c['hierarchy']!.text,
        'ovi': c['ovi']!.text,
        'baseline': c['baseline']!.text,
        'targets': c['targets']!.text,
        'methods': c['methods']!.text,
        'responsibility': c['responsibility']!.text,
      }).toList(),
      'immediate': project.immediateRows.map((c) => {
        'hierarchy': c['hierarchy']!.text,
        'ovi': c['ovi']!.text,
        'baseline': c['baseline']!.text,
        'targets': c['targets']!.text,
        'methods': c['methods']!.text,
        'responsibility': c['responsibility']!.text,
      }).toList(),
      'outputs': project.outputRows.map((c) => {
        'hierarchy': c['hierarchy']!.text,
        'ovi': c['ovi']!.text,
        'baseline': c['baseline']!.text,
        'targets': c['targets']!.text,
        'methods': c['methods']!.text,
        'responsibility': c['responsibility']!.text,
      }).toList(),
    }).toList();
    
    return {
      'logframes': logframes,
    };
  }

  Future<void> _generateAndUploadDocx(Map<String, dynamic> logframeData) async {
    final formattedYearRange = formatYearRange(_yearRange);
    final url = Uri.parse('http://localhost:8000/generate-iiic-docx/');
    
    // Debug: Log the data being sent
    print('Part III.C - Sending data to backend:');
    print('Year range: $formattedYearRange');
    print('Data: ${jsonEncode(logframeData)}');
    
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'yearrange': formattedYearRange,
      },
      body: jsonEncode(logframeData),
    );
    
    print('Part III.C - Response status: ${response.statusCode}');
    if (response.statusCode != 200) {
      print('Part III.C - Response body: ${response.body}');
    }
    
    if (response.statusCode == 200) {
      final bytes = response.bodyBytes;
      final fileName = 'document.docx';
      try {
        final storageRef = _storage.ref().child('${_yearRange}/III.C/$fileName');
        if (kIsWeb) {
          await storageRef.putData(bytes);
        } else {
          final directory = await getApplicationDocumentsDirectory();
          final file = File('${directory.path}/$fileName');
          await file.writeAsBytes(bytes);
          await storageRef.putFile(file);
        }
        setState(() {
          _docxBytes = bytes;
          _fileName = fileName;
        });
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading DOCX: $e')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate DOCX: ${response.statusCode}')),
      );
    }
  }

  Future<void> _saveContent({bool finalize = false}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final username = await getCurrentUsername();
      final logframeData = _collectLogframeData();
      final payload = {
        ...logframeData,
        'modifiedBy': username,
        'lastModified': FieldValue.serverTimestamp(),
        'screening': finalize || _isFinalized,
        'sectionTitle': 'Part III.C',
        'isFinalized': finalize ? false : _isFinalized,
      };
      if (!_isFinalized) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdBy'] = username;
      }
      await _sectionRef.set(payload, SetOptions(merge: true));
      await _generateAndUploadDocx(logframeData);
      setState(() => _isFinalized = finalize);
      if (finalize) {
        await createSubmissionNotification('Part III.C', _yearRange);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Part III.C submitted for admin approval. You will be notified once it is reviewed.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          )
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Part III.C saved successfully (not finalized)'),
            backgroundColor: Colors.green,
          )
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save error: $e'))
      );
    } finally {
      setState(() => _saving = false);
    }
  }

  Widget _buildLogframeForm(bool isSmallScreen) {
    return Column(
      children: [
        for (int i = 0; i < _projects.length; i++)
          _buildLogframeFormForProject(_projects[i], i),
        const SizedBox(height: 24),
        Center(
          child: ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _projects.add(LogframeProject());
              });
            },
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
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _downloadDocx() async {
    if (_docxBytes == null) return;
    try {
      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'document.docx',
          bytes: _docxBytes!,
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final path = '${directory.path}/document.docx';
        await File(path).writeAsBytes(_docxBytes!);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document downloaded successfully'))
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error downloading document: $e'))
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    final isSmallScreen = MediaQuery.of(context).size.width < 1750;
    
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
          title: Text(
            isSmallScreen ? 'Part III.C' : 'Part III.C - Performance Measurement Framework',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: isSmallScreen ? 16 : 20,
            ),
          ),
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF2D3748),
          actions: [
            if (_saving)
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
              if (!_isFinalized)
                IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: _saving ? null : () => _saveContent(finalize: false),
                  tooltip: 'Save',
                  color: const Color(0xff021e84),
                ),
              IconButton(
                icon: const Icon(Icons.check),
                onPressed: _isFinalized ? null : () async {
                  final confirmed = await showFinalizeConfirmation(
                    context,
                    'Part III.C - Performance Measurement Framework'
                  );
                  if (confirmed) {
                    _saveContent(finalize: true);
                  }
                },
                tooltip: 'Finalize',
                color: _isFinalized ? Colors.grey : const Color(0xff021e84),
              ),
              IconButton(
                icon: const Icon(Icons.download),
                onPressed: _docxBytes == null ? null : () async {
                  try {
                    await _downloadDocx();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Download failed: $e')),
                    );
                  }
                },
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
                    SizedBox(height: 12),
                    Text(
                      isSmallScreen 
                        ? 'Part III.C has been finalized.'
                        : 'Part III.C - Performance Measurement Framework has been finalized.',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Padding(
                    padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
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
                                  Expanded(
                                    child: Text(
                                      isSmallScreen ? 'Instructions' : 'Instructions',
                                      style: TextStyle(
                                        fontSize: isSmallScreen ? 16 : 18,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF2D3748),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                isSmallScreen 
                                  ? 'Fill in the logframe table below. Save to generate DOCX for download.'
                                  : 'Please fill in the logframe table below for Part III.C. When you save, a DOCX will be generated and available for download.',
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 14 : 16,
                                  color: const Color(0xFF4A5568),
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 16 : 24),
                        _buildLogframeForm(isSmallScreen),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildLogframeFormForProject(LogframeProject project, int index) {
    final fields = [
      {
        'key': 'ovi',
        'label': 'Objectively verifiable indicators',
        'tooltip': 'Indicators that can be measured to verify achievement of the result.'
      },
      {
        'key': 'baseline',
        'label': 'Baseline data',
        'tooltip': 'The starting value or situation before the intervention.'
      },
      {
        'key': 'targets',
        'label': 'Targets',
        'tooltip': 'The intended value or situation to be achieved.'
      },
      {
        'key': 'methods',
        'label': 'Data collection methods',
        'tooltip': 'How the data will be collected (e.g., survey, report, observation).'
      },
      {
        'key': 'responsibility',
        'label': 'Responsibility to collect data',
        'tooltip': 'Who is responsible for collecting the data.'
      },
    ];
    final cardTitles = [
      'Intermediate Outcome',
      'Immediate Outcome',
      'Outputs',
    ];
    
    return Container(
      margin: const EdgeInsets.only(bottom: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.10),
            spreadRadius: 2,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Table(
        border: TableBorder.all(color: Colors.grey.shade300, width: 1),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: Color(0xfff5f7fa),
            ),
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      'Hierarchy of targeted results',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xff021e84)),
                    ),
                    SizedBox(width: 4),
                    Tooltip(
                      message: 'Describe the result level (e.g., Intermediate Outcome, Immediate Outcome, Outputs).',
                      child: Icon(Icons.info_outline, color: Color(0xff021e84), size: 18),
                    ),
                  ],
                ),
              ),
              ...fields.map((field) => Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      field['label'] ?? '',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xff021e84)),
                    ),
                    SizedBox(width: 4),
                    Tooltip(
                      message: field['tooltip'] ?? '',
                      child: Icon(Icons.info_outline, color: Color(0xff021e84), size: 18),
                    ),
                  ],
                ),
              )),
            ],
          ),
          ...List.generate(project.intermediateRows.length, (rowIdx) {
            final controllers = project.intermediateRows[rowIdx];
            return TableRow(
              decoration: BoxDecoration(
                color: rowIdx % 2 == 0 ? Colors.white : Color(0xfff7fafd),
              ),
              children: [
                Padding(
                  padding: EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rowIdx == 0 ? 'Intermediate Outcome' : '',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xff021e84),
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: controllers['hierarchy'],
                        enabled: !_isFinalized,
                        minLines: 1,
                        maxLines: null,
                        decoration: const InputDecoration(
                          border: UnderlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          hintText: '',
                        ),
                      ),
                      if (rowIdx > 0)
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            icon: Icon(Icons.delete, color: Colors.red),
                            tooltip: 'Remove row',
                            onPressed: () {
                              setState(() {
                                project.intermediateRows.removeAt(rowIdx);
                              });
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                ...fields.map((field) => Padding(
                  padding: EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 23),
                      TextFormField(
                        controller: controllers[field['key'] ?? ''],
                        enabled: !_isFinalized,
                        minLines: 1,
                        maxLines: null,
                        decoration: InputDecoration(
                          border: UnderlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            );
          }),
          TableRow(
            children: [
              Padding(
                padding: EdgeInsets.all(14),
                child: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        project.intermediateRows.add({
                          'hierarchy': TextEditingController(),
                          'ovi': TextEditingController(),
                          'baseline': TextEditingController(),
                          'targets': TextEditingController(),
                          'methods': TextEditingController(),
                          'responsibility': TextEditingController(),
                        });
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xff021e84),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      elevation: 0,
                      textStyle: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 0.2,
                      ),
                    ),
                    child: Text('Add Intermediate Outcome Row'),
                  ),
                ),
              ),
              for (int i = 0; i < fields.length; i++) SizedBox.shrink(),
            ],
          ),
          ...List.generate(project.immediateRows.length, (rowIdx) {
            final controllers = project.immediateRows[rowIdx];
            return TableRow(
              decoration: BoxDecoration(
                color: rowIdx % 2 == 0 ? Colors.white : Color(0xfff7fafd),
              ),
              children: [
                Padding(
                  padding: EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rowIdx == 0 ? 'Immediate Outcome' : '',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xff021e84),
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: controllers['hierarchy'],
                        enabled: !_isFinalized,
                        minLines: 1,
                        maxLines: null,
                        decoration: const InputDecoration(
                          border: UnderlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          hintText: '',
                        ),
                      ),
                      if (rowIdx > 0)
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            icon: Icon(Icons.delete, color: Colors.red),
                            tooltip: 'Remove row',
                            onPressed: () {
                              setState(() {
                                project.immediateRows.removeAt(rowIdx);
                              });
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                ...fields.map((field) => Padding(
                  padding: EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 23),
                      TextFormField(
                        controller: controllers[field['key'] ?? ''],
                        enabled: !_isFinalized,
                        minLines: 1,
                        maxLines: null,
                        decoration: InputDecoration(
                          border: UnderlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            );
          }),
          TableRow(
            children: [
              Padding(
                padding: EdgeInsets.all(14),
                child: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        project.immediateRows.add({
                          'hierarchy': TextEditingController(),
                          'ovi': TextEditingController(),
                          'baseline': TextEditingController(),
                          'targets': TextEditingController(),
                          'methods': TextEditingController(),
                          'responsibility': TextEditingController(),
                        });
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xff021e84),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      elevation: 0,
                      textStyle: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 0.2,
                      ),
                    ),
                    child: Text('Add Immediate Outcome Row'),
                  ),
                ),
              ),
              for (int i = 0; i < fields.length; i++) SizedBox.shrink(),
            ],
          ),
          ...List.generate(project.outputRows.length, (rowIdx) {
            final controllers = project.outputRows[rowIdx];
            return TableRow(
              decoration: BoxDecoration(
                color: rowIdx % 2 == 0 ? Colors.white : Color(0xfff7fafd),
              ),
              children: [
                Padding(
                  padding: EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rowIdx == 0 ? 'Outputs' : '',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xff021e84),
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: controllers['hierarchy'],
                        enabled: !_isFinalized,
                        minLines: 1,
                        maxLines: null,
                        decoration: const InputDecoration(
                          border: UnderlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          hintText: '',
                        ),
                      ),
                      if (rowIdx > 0)
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            icon: Icon(Icons.delete, color: Colors.red),
                            tooltip: 'Remove row',
                            onPressed: () {
                              setState(() {
                                project.outputRows.removeAt(rowIdx);
                              });
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                ...fields.map((field) => Padding(
                  padding: EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 23),
                      TextFormField(
                        controller: controllers[field['key'] ?? ''],
                        enabled: !_isFinalized,
                        minLines: 1,
                        maxLines: null,
                        decoration: InputDecoration(
                          border: UnderlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            );
          }),
          TableRow(
            children: [
              Padding(
                padding: EdgeInsets.all(14),
                child: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        project.outputRows.add({
                          'hierarchy': TextEditingController(),
                          'ovi': TextEditingController(),
                          'baseline': TextEditingController(),
                          'targets': TextEditingController(),
                          'methods': TextEditingController(),
                          'responsibility': TextEditingController(),
                        });
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xff021e84),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      elevation: 0,
                      textStyle: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 0.2,
                      ),
                    ),
                    child: Text('Add Output Row'),
                  ),
                ),
              ),
              for (int i = 0; i < fields.length; i++) SizedBox.shrink(),
            ],
          ),
        ],
      ),
    );
  }
} 