import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_saver/file_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:archive/archive.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:test_project/main_part.dart';
import '../../utils/user_utils.dart';
import '../../services/notification_service.dart';
import '../../state/selection_model.dart';
import 'package:provider/provider.dart';

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
  print('Loading template from: $assetPath');
  final bytes = (await rootBundle.load(assetPath)).buffer.asUint8List();
  print('Template file size: ${bytes.length} bytes');

  final archive = ZipDecoder().decodeBytes(bytes);
  final docFile = archive.firstWhere((f) => f.name == 'word/document.xml');
  String xmlStr = utf8.decode(docFile.content as List<int>);

  print('Original XML content (first 500 chars):');
  print(xmlStr.substring(0, xmlStr.length > 500 ? 500 : xmlStr.length));

  final cleanXml = xmlStr.replaceAllMapped(
    RegExp(r'\$\{.*?\}', multiLine: true, dotAll: true),
    (match) {
      String placeholder = match.group(0)!;
      placeholder = placeholder.replaceAll(RegExp(r'<[^>]+>'), '');
      placeholder = placeholder.replaceAll(RegExp(r'\s+'), '');
      return placeholder;
    },
  );

  print('Cleaned XML placeholders:');
  print(cleanXml.substring(0, cleanXml.length > 500 ? 500 : cleanXml.length));

  final pattern = RegExp(r'\$\{(.+?)\}');
  final allKeys = pattern.allMatches(cleanXml).map((m) => m.group(1)!).toSet();

  print('Found placeholders: $allKeys');
  print('Provided replacements: ${replacements.keys}');

  final complete = <String, String>{
    for (var key in allKeys) '\${$key}': replacements[key] ?? '',
  };

  print('Final replacements map: $complete');

  String finalXml = cleanXml;
  complete.forEach((ph, val) {
    String processedValue = val;

    if (ph == '\${strategicChallenges}' && val.contains('•')) {
      final bulletCount = '•'.allMatches(val).length;
      if (bulletCount > 1) {
        processedValue = val.replaceAll('\n\n', '\n\n\n');
      }
    }

    print(
      'Replacing $ph with ${processedValue.length > 50 ? "${processedValue.substring(0, 50)}..." : processedValue}',
    );
    finalXml = finalXml.replaceAll(ph, xmlEscape(processedValue));
  });

  final newArchive = Archive();
  for (final file in archive) {
    if (file.name == 'word/document.xml') {
      final data = utf8.encode(finalXml);
      newArchive.addFile(ArchiveFile(file.name, data.length, data));
    } else {
      newArchive.addFile(file);
    }
  }

  final out = ZipEncoder().encode(newArchive)!;
  return Uint8List.fromList(out);
}

class PartIEFormPage extends StatefulWidget {
  final String documentId;
  const PartIEFormPage({Key? key, required this.documentId}) : super(key: key);
  @override
  _PartIEFormPageState createState() => _PartIEFormPageState();
}

class _PartIEFormPageState extends State<PartIEFormPage> {
  final _formKey = GlobalKey<FormState>();
  Uint8List? _uploadedFileBytes;
  String? _fileName;
  String? _fileUrl;
  bool _loading = true;
  bool _saving = false;
  bool _isFinalized = false;
  bool _compiling = false;

  late DocumentReference _sectionRef;
  final _user = FirebaseAuth.instance.currentUser;
  final _storage = FirebaseStorage.instance;
  String get _userId =>
      _user?.displayName ?? _user?.email ?? _user?.uid ?? 'unknown';
  String get _yearRange {
    final yearRange = context.read<SelectionModel>().yearRange ?? '2729';
    print('Getting yearRange (Part I.E): $yearRange');
    return yearRange;
  }

  @override
  void initState() {
    super.initState();
    print('initState (Part I.E) - yearRange: $_yearRange');
    _sectionRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(_yearRange)
        .collection('sections')
        .doc('I.E');

    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final doc = await _sectionRef.get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _isFinalized = (data['isFinalized'] as bool? ?? false) || (data['screening'] as bool? ?? false);
          _fileName = data['fileName'] as String?;
          _fileUrl = data['fileUrl'] as String?;
        });

        try {
          final docxRef = _storage.ref().child('$_yearRange/I.E/document.docx');
          final docxBytes = await docxRef.getData();
          if (docxBytes != null) {
            setState(() {
              _uploadedFileBytes = docxBytes;
            });
          }
        } catch (e) {
          print('Error loading DOCX: $e');
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Load error: $e'))
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['docx'],
      );

      if (result != null) {
        final file = result.files.first;
        if (file.bytes != null) {
          final docxRef = _storage.ref().child('$_yearRange/I.E/document.docx');
          await docxRef.putData(file.bytes!);
          
          await _sectionRef.set({
            'docxBytes': base64Encode(file.bytes!),
            'lastModified': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          
          setState(() {
            _uploadedFileBytes = file.bytes;
            _fileName = file.name;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Document uploaded and saved successfully'))
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File pick error: $e'))
      );
    }
  }

  Future<String> _uploadToStorage() async {
    if (_uploadedFileBytes == null) throw Exception('No file to upload');
    
    final storageRef = _storage.ref()
        .child('$_yearRange/I.E/document.docx');

    final uploadTask = storageRef.putData(_uploadedFileBytes!);
    final snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }

  Future<void> _save({bool finalize = false}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_uploadedFileBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please upload a document'))
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final fileUrl = await _uploadToStorage();

      final username = await getCurrentUsername();
      final doc = await _sectionRef.get();
      final yearRange = context.read<SelectionModel>().yearRange ?? '2729';
      final formattedYearRange = formatYearRange(yearRange);
      final payload = {
        'fileName': _fileName,
        'fileUrl': fileUrl,
        'modifiedBy': username,
        'lastModified': FieldValue.serverTimestamp(),
        'isFinalized': finalize ? false : _isFinalized,
        'screening': finalize || _isFinalized,
        'sectionTitle': 'Part I.E',
        'yearRange': formattedYearRange,
      };

      if (!_isFinalized) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdBy'] = username;
      }

      await _sectionRef.set(payload, SetOptions(merge: true));
      setState(() => _isFinalized = finalize);

      if (finalize) {
        await createSubmissionNotification('Part I.E', _yearRange);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Part I.E submitted for admin approval. You will be notified once it is reviewed.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          )
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Part I.E saved successfully (not finalized)'),
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
    if (_uploadedFileBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No document to compile'))
      );
      return;
    }

    setState(() => _compiling = true);
    try {
      final fileName = _fileName ?? 'Part_I_E_Strategic_Concerns.docx';
      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: fileName,
          bytes: _uploadedFileBytes!,
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(_uploadedFileBytes!);
        await FileSaver.instance.saveFile(
          name: fileName,
          file: file,
          mimeType: MimeType.microsoftWord,
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document downloaded successfully'))
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download error: $e'))
      );
    } finally {
      setState(() => _compiling = false);
    }
  }

  Future<void> _downloadDocx() async {
    setState(() => _compiling = true);
    try {
      final fileName = 'document.docx';
      final storage = FirebaseStorage.instance;
      final docxRef = storage.ref().child('$_yearRange/I.E/document.docx');
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
      setState(() => _compiling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
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
            'Part I.E - Strategic Concerns for ICT Use',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
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
                  child: CircularProgressIndicator(
                    color: Color(0xff021e84),
                  ),
                ),
              )
            else ...[
              if (!_isFinalized)
                IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: _saving ? null : () => _save(),
                  tooltip: 'Save',
                  color: const Color(0xff021e84),
                ),
              IconButton(
                icon: const Icon(Icons.check),
                onPressed: _isFinalized ? null : () async {
                  final confirmed = await showFinalizeConfirmation(
                    context,
                    'Part I.E'
                  );
                  if (confirmed) {
                    _save(finalize: true);
                  }
                },
                tooltip: 'Finalize',
                color: _isFinalized ? Colors.grey : const Color(0xff021e84),
              ),
            ]
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
                      'Part I.E - Strategic Concerns for ICT Use has been finalized.',
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
                                'Please upload a DOCX document for Part I.E. The document should contain all necessary information for this section. You can preview, save, and download the document.',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFF4A5568),
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: _downloadDocx,
                                    icon: const Icon(Icons.download),
                                    label: const Text('Download DOCX'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Color(0xff021e84),
                                      foregroundColor: Colors.white,
                                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                      textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 10),
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
                                    'Document Upload',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2D3748),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              if (_uploadedFileBytes != null)
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xff021e84).withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xff021e84).withOpacity(0.2),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.insert_drive_file,
                                        color: Color(0xff021e84),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _fileName ?? 'Document',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            color: Color(0xFF2D3748),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.download),
                                        onPressed: _compileDocx,
                                        color: const Color(0xff021e84),
                                        tooltip: 'Download Document',
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 20),
                              Center(
                                child: ElevatedButton.icon(
                                  onPressed: _isFinalized ? null : _pickFile,
                                  icon: Icon(
                                    _uploadedFileBytes == null ? Icons.upload_file : Icons.edit,
                                    color: Colors.white,
                                  ),
                                  label: Text(
                                    _uploadedFileBytes == null ? 'Upload Document' : 'Change Document',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
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