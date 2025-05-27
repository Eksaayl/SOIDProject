import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_saver/file_saver.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:docx_template/docx_template.dart';
import 'package:file_picker/file_picker.dart';
import '../../config.dart';

String xmlEscape(String input) => input
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

Future<Uint8List> generateDocxWithImages({
  required Map<String, Uint8List> images,
}) async {
  try {
    // Create multipart request
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${Config.serverUrl}/generate-docx'),
    );

    // Add template file
    final templateBytes = await rootBundle.load('assets/templates_II_a.docx');
    request.files.add(
      http.MultipartFile.fromBytes(
        'template',
        templateBytes.buffer.asUint8List(),
        filename: 'templates_II_a.docx',
      ),
    );

    // Add images with specific names
    request.files.add(
      http.MultipartFile.fromBytes(
        'images',
        images['ISI']!,
        filename: 'ISI.png',
      ),
    );
    request.files.add(
      http.MultipartFile.fromBytes(
        'images',
        images['ISII']!,
        filename: 'ISII.png',
      ),
    );
    request.files.add(
      http.MultipartFile.fromBytes(
        'images',
        images['ISIII']!,
        filename: 'ISIII.png',
      ),
    );

    // Send request
    final response = await request.send();
    if (response.statusCode != 200) {
      throw Exception('Failed to generate DOCX: ${response.statusCode}');
    }

    // Get response bytes directly
    final bytes = await response.stream.toBytes();
    return Uint8List.fromList(bytes);
  } catch (e) {
    print('Error generating DOCX: $e');
    rethrow;
  }
}

class PartIIA extends StatefulWidget {
  final String documentId;
  
  const PartIIA({
    Key? key,
    this.documentId = 'document',
  }) : super(key: key);

  @override
  _PartIIAState createState() => _PartIIAState();
}

class _PartIIAState extends State<PartIIA> {
  final _formKey = GlobalKey<FormState>();
  Uint8List? _isiBytes;
  Uint8List? _isiiBytes;
  Uint8List? _isiiiBytes;
  bool _loading = true;
  bool _saving = false;
  bool _compiling = false;
  bool _isFinal = false;

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
        .doc('II.A');

    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      final doc = await _sectionRef.get();
      final data = doc.data() as Map<String, dynamic>?;
      if (data != null) {
        setState(() {
          _isFinal = data['finalized'] as bool? ?? false;
        });

        // Load images from Firebase Storage
        try {
          final isiRef = _storage.ref().child('${widget.documentId}/II.A/isi.png');
          final isiiRef = _storage.ref().child('${widget.documentId}/II.A/isii.png');
          final isiiiRef = _storage.ref().child('${widget.documentId}/II.A/isiii.png');
          
          final isiBytes = await isiRef.getData();
          final isiiBytes = await isiiRef.getData();
          final isiiiBytes = await isiiiRef.getData();
          
          if (isiBytes != null) {
            setState(() {
              _isiBytes = isiBytes;
            });
          }
          if (isiiBytes != null) {
            setState(() {
              _isiiBytes = isiiBytes;
            });
          }
          if (isiiiBytes != null) {
            setState(() {
              _isiiiBytes = isiiiBytes;
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
          // Upload to Firebase Storage
          final imageRef = _storage.ref().child('${widget.documentId}/II.A/${type.toLowerCase()}.png');
          await imageRef.putData(bytes);
          
          setState(() {
            switch (type) {
              case 'ISI':
                _isiBytes = bytes;
                break;
              case 'ISII':
                _isiiBytes = bytes;
                break;
              case 'ISIII':
                _isiiiBytes = bytes;
                break;
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
    final bytes = type == 'ISI' ? _isiBytes : 
                 type == 'ISII' ? _isiiBytes : 
                 _isiiiBytes;
    if (bytes == null) return;

    try {
      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'Part_II_A_${type}_${widget.documentId}.png',
          bytes: bytes,
          mimeType: MimeType.png,
        );
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/Part_II_A_${type}_${widget.documentId}.png');
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

  Future<void> _saveContent() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      // Generate DOCX if all images are present
      if (_isiBytes != null && _isiiBytes != null && _isiiiBytes != null) {
        final bytes = await generateDocxWithImages(
          images: {
            'ISI': _isiBytes!,
            'ISII': _isiiBytes!,
            'ISIII': _isiiiBytes!,
          },
        );

        // Upload DOCX to Firebase Storage
        final docxRef = _storage.ref().child('${widget.documentId}/II.A/document.docx');
        await docxRef.putData(bytes);

        // Save metadata to Firestore
        await _sectionRef.set({
          'finalized': _isFinal,
          'lastModified': FieldValue.serverTimestamp(),
          'lastModifiedBy': _userId,
          'docxPath': '${widget.documentId}/II.A/document.docx',
        }, SetOptions(merge: true));
      } else {
        // If not all images are present, just save the metadata
        await _sectionRef.set({
          'finalized': _isFinal,
          'lastModified': FieldValue.serverTimestamp(),
          'lastModifiedBy': _userId,
        }, SetOptions(merge: true));
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Content saved successfully'))
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save error: $e'))
      );
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _compileDocx() async {
    if (_isiBytes == null || _isiiBytes == null || _isiiiBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select all three images'))
      );
      return;
    }

    setState(() => _compiling = true);
    try {
      final bytes = await generateDocxWithImages(
        images: {
          'ISI': _isiBytes!,
          'ISII': _isiiBytes!,
          'ISIII': _isiiiBytes!,
        },
      );

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'Part_II_A_${widget.documentId}.docx',
          bytes: bytes,
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/Part_II_A_${widget.documentId}.docx');
        await file.writeAsBytes(bytes);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('DOCX generated successfully'))
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating DOCX: $e'))
      );
    } finally {
      setState(() => _compiling = false);
    }
  }

  Widget _buildImageUploadSection(String type) {
    final bytes = type == 'ISI' ? _isiBytes : 
                 type == 'ISII' ? _isiiBytes : 
                 _isiiiBytes;

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
          else if (!_isFinal)
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
          if (bytes != null && !_isFinal)
            const SizedBox(height: 20),
          if (bytes != null && !_isFinal)
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
          'Part II.A - Image Uploads',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2D3748),
        actions: [
          if (_saving || _compiling)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: CircularProgressIndicator(
                  color: Color(0xff021e84),
                ),
              ),
            )
          else ...[
            if (!_isFinal)
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: _saving ? null : _saveContent,
                tooltip: 'Save',
                color: const Color(0xff021e84),
              ),
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _isFinal ? null : () {
                if (_isiBytes == null || _isiiBytes == null || _isiiiBytes == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please upload all three images before finalizing'))
                  );
                  return;
                }
                setState(() => _isFinal = true);
                _saveContent();
              },
              tooltip: 'Finalize',
              color: _isFinal ? Colors.grey : const Color(0xff021e84),
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
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
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
                      'Please upload three images for Part IIA: ISI, ISII, and ISIII. The images should be in PNG format. You can preview, save, and download the images. Click the document icon in the app bar to generate a DOCX file with all three images.',
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
              _buildImageUploadSection('ISI'),
              const SizedBox(height: 24),
              _buildImageUploadSection('ISII'),
              const SizedBox(height: 24),
              _buildImageUploadSection('ISIII'),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
} 