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
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;
import '../../config.dart';
import 'package:test_project/main_part.dart';
import '../../utils/user_utils.dart';
import '../../services/notification_service.dart';

Future<Uint8List> generateDocxWithImages({
  required Map<String, Uint8List> images,
}) async {
  try {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${Config.serverUrl}/generate-docx'),
    );

    final templateBytes = await rootBundle.load('assets/templates_II_d.docx');
    request.files.add(
      http.MultipartFile.fromBytes(
        'template',
        templateBytes.buffer.asUint8List(),
        filename: 'templates_II_d.docx',
      ),
    );

    request.files.add(
      http.MultipartFile.fromBytes(
        'images',
        images['NLC']!,
        filename: 'NLC.png',
      ),
    );
    request.files.add(
      http.MultipartFile.fromBytes(
        'images',
        images['PNL']!,
        filename: 'PNL.png',
      ),
    );

    final response = await request.send();
    if (response.statusCode != 200) {
      throw Exception('Failed to generate DOCX: ${response.statusCode}');
    }

    final bytes = await response.stream.toBytes();
    return Uint8List.fromList(bytes);
  } catch (e) {
    print('Error generating DOCX: $e');
    rethrow;
  }
}

class PartIID extends StatefulWidget {
  final String documentId;
  
  const PartIID({
    Key? key,
    this.documentId = 'document',
  }) : super(key: key);

  @override
  _PartIIDState createState() => _PartIIDState();
}

class _PartIIDState extends State<PartIID> {
  final _formKey = GlobalKey<FormState>();
  Uint8List? _nlcImageBytes;
  Uint8List? _pnlImageBytes;
  bool _loading = true;
  bool _saving = false;
  bool _compiling = false;
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
        .doc('II.D');

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

        try {
          final nlcRef = _storage.ref().child('${widget.documentId}/II.D/nlc.png');
          final pnlRef = _storage.ref().child('${widget.documentId}/II.D/pnl.png');
          
          final nlcBytes = await nlcRef.getData();
          final pnlBytes = await pnlRef.getData();
          
          if (nlcBytes != null) {
            setState(() {
              _nlcImageBytes = nlcBytes;
            });
          }
          if (pnlBytes != null) {
            setState(() {
              _pnlImageBytes = pnlBytes;
            });
          }
        } catch (e) {
          print('Error loading images: $e');
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

  Future<void> _pickImage(String type) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null) {
        final bytes = result.files.first.bytes;
        if (bytes != null) {
          final imageRef = _storage.ref().child('${widget.documentId}/II.D/${type.toLowerCase()}.png');
          await imageRef.putData(bytes);
          
          setState(() {
            if (type == 'NLC') {
              _nlcImageBytes = bytes;
            } else {
              _pnlImageBytes = bytes;
            }
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Image uploaded successfully'))
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e'))
      );
    }
  }

  Future<void> _downloadImage(String type) async {
    final bytes = type == 'NLC' ? _nlcImageBytes : _pnlImageBytes;
    if (bytes == null) return;

    try {
      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'Part_II_D_${type}_${widget.documentId}.png',
          bytes: bytes,
          mimeType: MimeType.png,
        );
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/Part_II_D_${type}_${widget.documentId}.png');
        await file.writeAsBytes(bytes);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image downloaded successfully'))
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error downloading image: $e'))
      );
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
        'sectionTitle': 'Part II.D',
      };

      if (!_isFinalized) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdBy'] = username;
      }

      await _sectionRef.set(payload, SetOptions(merge: true));
      setState(() => _isFinalized = finalize);

      if (finalize) {
        await createSubmissionNotification('Part II.D');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save error: $e'))
      );
    } finally {
      setState(() => _saving = false);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(finalize ? 'Finalized' : 'Saved (not finalized)'))
    );
  }

  Future<void> _compileDocx() async {
    if (_nlcImageBytes == null || _pnlImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both images'))
      );
      return;
    }

    setState(() => _compiling = true);
    try {
      final bytes = await generateDocxWithImages(
        images: {
          'NLC': _nlcImageBytes!,
          'PNL': _pnlImageBytes!,
        },
      );

      final docxRef = _storage.ref().child('${widget.documentId}/II.D/document.docx');
      await docxRef.putData(bytes);

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'Part_II_D_${widget.documentId}.docx',
          bytes: bytes,
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final path = '${directory.path}/document.docx';
        final file = File(path);
        await file.writeAsBytes(bytes);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document generated and downloaded successfully'))
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating document: $e'))
      );
    } finally {
      setState(() => _compiling = false);
    }
  }

  Widget _buildImageUploadSection(String type) {
    final bytes = type == 'NLC' ? _nlcImageBytes : _pnlImageBytes;

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
                  Icons.image,
                  color: Color(0xff021e84),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                type,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3748),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (bytes != null)
            Center(
              child: Container(
                height: 250,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            )
          else if (!_isFinalized)
            Center(
              child: ElevatedButton.icon(
                onPressed: () => _pickImage(type),
                icon: const Icon(
                  Icons.upload_file,
                  color: Colors.white,
                ),
                label: const Text(
                  'Upload Image',
                  style: TextStyle(
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
          if (bytes != null && !_isFinalized)
            const SizedBox(height: 20),
          if (bytes != null && !_isFinalized)
            Center(
              child: ElevatedButton.icon(
                onPressed: () => _pickImage(type),
                icon: const Icon(
                  Icons.edit,
                  color: Colors.white,
                ),
                label: const Text(
                  'Change Image',
                  style: TextStyle(
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
          'Part II.D - Network Layout',
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
                if (_nlcImageBytes == null || _pnlImageBytes == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please upload both images before finalizing'))
                  );
                  return;
                }
                final confirmed = await showFinalizeConfirmation(
                  context,
                  'Part II.D - Network Layout'
                );
                if (confirmed) {
                  setState(() => _isFinalized = true);
                  _save(finalize: true);
                }
              },
              tooltip: 'Finalize',
              color: _isFinalized ? Colors.grey : const Color(0xff021e84),
            ),
            IconButton(
              icon: const Icon(Icons.file_download),
              onPressed: _compiling ? null : _compileDocx,
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
                  SizedBox(height: 12),
                  Text(
                    'Part II.D - Network Layout has been finalized.',
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
                              'Please upload two images for Part IID: NLC (National Library of the Philippines) and PNL (Philippine National Library) images. The images should be in PNG format. You can preview, save, and download the images. Click the document icon in the app bar to generate a DOCX file with both images.',
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
                      _buildImageUploadSection('NLC'),
                      const SizedBox(height: 24),
                      _buildImageUploadSection('PNL'),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
} 