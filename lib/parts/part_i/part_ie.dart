import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_saver/file_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:file_picker/file_picker.dart';

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
  bool _loading = true;
  bool _saving = false;
  bool _isFinalized = false;
  bool _compiling = false;

  late DocumentReference _sectionRef;
  final _user = FirebaseAuth.instance.currentUser;
  String get _userId =>
      _user?.displayName ?? _user?.email ?? _user?.uid ?? 'unknown';

  @override
  void initState() {
    super.initState();
    _sectionRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(widget.documentId)
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
          _isFinalized = data['isFinalized'] ?? false;
          if (data['uploadedFile'] != null) {
            _uploadedFileBytes = base64Decode(data['uploadedFile'] as String);
            _fileName = data['fileName'] as String?;
          }
        });
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
          setState(() {
            _uploadedFileBytes = file.bytes;
            _fileName = file.name;
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File pick error: $e'))
      );
    }
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
      final payload = {
        'uploadedFile': base64Encode(_uploadedFileBytes!),
        'fileName': _fileName,
        'modifiedBy': _userId,
        'lastModified': FieldValue.serverTimestamp(),
        'isFinalized': finalize || _isFinalized,
      };
      if (!_isFinalized) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdBy'] = _userId;
      }
      await _sectionRef.set(payload, SetOptions(merge: true));
      setState(() => _isFinalized = finalize);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(finalize ? 'Finalized' : 'Saved'))
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
    if (_uploadedFileBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please upload a document first'))
      );
      return;
    }
    setState(() => _compiling = true);
    try {
      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'Part_I.E',
          bytes: _uploadedFileBytes!,
          ext: 'docx',
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/Part_I.E_${DateTime.now().millisecondsSinceEpoch}.docx';
        await File(path).writeAsBytes(_uploadedFileBytes!);
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Part I.E - Upload Document'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _isFinalized ? null : () => _save(),
            ),
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Finalize',
              onPressed: _isFinalized ? null : () => _save(finalize: true),
            ),
            if (_compiling)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(Icons.file_download),
                onPressed: _compileDocx,
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
                    'This section has been finalized.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 600),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Upload Part I.E Document',
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      color: const Color(0xff021e84),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  if (_uploadedFileBytes != null) ...[
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.grey.shade200),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.description, color: Colors.grey.shade700),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              _fileName ?? 'Document',
                                              style: TextStyle(
                                                color: Colors.grey.shade700,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  ElevatedButton.icon(
                                    onPressed: _pickFile,
                                    icon: Icon(
                                      _uploadedFileBytes == null ? Icons.upload_file : Icons.edit,
                                      color: Colors.white,
                                    ),
                                    label: Text(
                                      _uploadedFileBytes == null ? 'Upload Document' : 'Change Document',
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xff021e84),
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
} 