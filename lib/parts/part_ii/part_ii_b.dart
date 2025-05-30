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

class PartIIB extends StatefulWidget {
  final String documentId;
  
  const PartIIB({
    Key? key,
    this.documentId = 'document',
  }) : super(key: key);

  @override
  _PartIIBState createState() => _PartIIBState();
}

class _PartIIBState extends State<PartIIB> {
  final _formKey = GlobalKey<FormState>();
  Uint8List? _docxBytes;
  bool _loading = true;
  bool _saving = false;
  bool _isFinalized = false;

  late DocumentReference _sectionRef;
  final _user = FirebaseAuth.instance.currentUser;
  String get _userId => _user?.displayName ?? _user?.email ?? _user?.uid ?? 'unknown';
  final _storage = FirebaseStorage.instance;

  @override
  void initState() {
    super.initState();
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
          _isFinalized = data['isFinalized'] as bool? ?? false;
        });

        try {
          final docxRef = _storage.ref().child('${widget.documentId}/II.B/document.docx');
          final docxBytes = await docxRef.getData();
          if (docxBytes != null) {
            setState(() {
              _docxBytes = docxBytes;
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

  Future<void> _pickDocx() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['docx'],
      );

      if (result != null) {
        final bytes = result.files.first.bytes;
        if (bytes != null) {
          final docxRef = _storage.ref().child('${widget.documentId}/II.B/document.docx');
          await docxRef.putData(bytes);
          
          await _sectionRef.set({
            'docxBytes': base64Encode(bytes),
            'lastModified': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          
          setState(() {
            _docxBytes = bytes;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Document uploaded and saved successfully'))
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking document: $e'))
      );
    }
  }

  Future<void> _downloadDocx() async {
    if (_docxBytes == null) return;

    try {
      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'Part_II_B_${widget.documentId}.docx',
          bytes: _docxBytes!,
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/Part_II_B_${widget.documentId}.docx');
        await file.writeAsBytes(_docxBytes!);
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

  Future<void> _saveContent() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      await _sectionRef.set({
        'sectionTitle': 'Part II.B - Document Upload',
        'createdBy': _userId,
        'createdAt': FieldValue.serverTimestamp(),
        'lastModified': FieldValue.serverTimestamp(),
        'isFinalized': _isFinalized,
        'content': {
          'docx': _docxBytes != null ? true : false,
        }
      }, SetOptions(merge: true));

      final user = FirebaseAuth.instance.currentUser;
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user!.uid).get();
      final username = userDoc.data()?['username'] ?? user.uid;
      await FirebaseFirestore.instance.collection('notifications').add({
        'title': 'Part II.B Finalized',
        'body': 'Part II.B has been finalized by $username',
        'readBy': {},
        'timestamp': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finalized'))
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save error: $e'))
      );
    } finally {
      setState(() => _saving = false);
    }
  }

  Widget _buildDocxUploadSection() {
    return Container(
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
          if (_docxBytes != null)
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
                  const Expanded(
                    child: Text(
                      'Document uploaded',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF2D3748),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download),
                    onPressed: _downloadDocx,
                    color: const Color(0xff021e84),
                    tooltip: 'Download Document',
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          Center(
            child: ElevatedButton.icon(
              onPressed: _isFinalized ? null : _pickDocx,
              icon: Icon(
                _docxBytes == null ? Icons.upload_file : Icons.edit,
                color: Colors.white,
              ),
              label: Text(
                _docxBytes == null ? 'Upload Document' : 'Change Document',
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
    );
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

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: const Text(
          'Part II.B - Detailed Description of Proposed Information Systems',
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
                onPressed: _saving ? null : _saveContent,
                tooltip: 'Save',
                color: const Color(0xff021e84),
              ),
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _isFinalized ? null : () {
                if (_docxBytes == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please upload a document before finalizing'))
                  );
                  return;
                }
                setState(() => _isFinalized = true);
                _saveContent();
              },
              tooltip: 'Finalize',
              color: _isFinalized ? Colors.grey : const Color(0xff021e84),
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
                              'Please upload a DOCX document for Part IIB. The document should contain all necessary information for this section. You can preview, save, and download the document.',
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
                      _buildDocxUploadSection(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
} 