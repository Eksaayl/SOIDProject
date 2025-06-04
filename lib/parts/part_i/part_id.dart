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

class PartIDFormPage extends StatefulWidget {
  final String documentId;
  const PartIDFormPage({Key? key, required this.documentId}) : super(key: key);
  @override
  _PartIDFormPageState createState() => _PartIDFormPageState();
}

class _PartIDFormPageState extends State<PartIDFormPage> {
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

  @override
  void initState() {
    super.initState();
    _sectionRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(widget.documentId)
        .collection('sections')
        .doc('I.D');

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
          final docxRef = _storage.ref().child('${widget.documentId}/I.D/document.docx');
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
          final docxRef = _storage.ref().child('${widget.documentId}/I.D/document.docx');
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
        .child('${widget.documentId}/I.D/document.docx');

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
      final payload = {
        'fileName': _fileName,
        'fileUrl': fileUrl,
        'modifiedBy': username,
        'lastModified': FieldValue.serverTimestamp(),
        'isFinalized': _isFinalized,
        'screening': finalize || _isFinalized,
        'sectionTitle': 'Part I.D',
      };

      if (!_isFinalized) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdBy'] = username;
      }

      await _sectionRef.set(payload, SetOptions(merge: true));
      setState(() => _isFinalized = finalize);

      if (finalize) {
        await createSubmissionNotification('Part I.D');
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
    if (_fileUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please upload a document first'))
      );
      return;
    }

    setState(() => _compiling = true);
    try {
      final ref = _storage.refFromURL(_fileUrl!);
      final bytes = await ref.getData();
      
      if (bytes == null) throw Exception('Failed to download file');

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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: const Text(
          'Part I.D - Present ICT Situation (Strategic Challenges)',
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
                  'Part I.D - Present ICT Situation (Strategic Challenges)'
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
                    'Part I.D - Present ICT Situation (Strategic Challenges) has been finalized.',
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
                              'Please upload a DOCX document for Part I.D. The document should contain all necessary information about strategic challenges. You can preview, save, and download the document.',
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
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
