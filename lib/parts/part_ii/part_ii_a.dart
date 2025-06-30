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

Future<Uint8List> generateDocxWithImages({
  required Map<String, Uint8List> images,
  required Map<String, String> replacements,
}) async {
  try {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${Config.serverUrl}/generate-docx'),
    );

    final templateBytes = await rootBundle.load('assets/II_a.docx');
    request.files.add(
      http.MultipartFile.fromBytes(
        'template',
        templateBytes.buffer.asUint8List(),
        filename: 'II_a.docx',
      ),
    );

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

    final response = await request.send();
    if (response.statusCode != 200) {
      throw Exception('Failed to generate DOCX: ${response.statusCode}');
    }

    final bytes = await response.stream.toBytes();
    
    final archive = ZipDecoder().decodeBytes(bytes);
    
    final headerFiles = archive.where((f) => f.name.contains('header') && f.name.endsWith('.xml')).toList();
    for (final headerFile in headerFiles) {
      var headerXml = utf8.decode(headerFile.content as List<int>);
      
      print('Processing header file: ${headerFile.name}');
      
      final complexPattern = RegExp(
        r'\$\{</w:t></w:r>.*?<w:t>yearRange</w:t>.*?<w:t>\}',
        dotAll: true,
      );
      
      final beforeReplacement = headerXml;
      headerXml = headerXml.replaceAllMapped(complexPattern, (match) {
        print('✓ Matched complex yearRange placeholder in ${headerFile.name}!');
        final yearRange = replacements['yearRange'] ?? '';
        return '''<w:r><w:rPr><w:rFonts w:ascii="Palatino Linotype" w:hAnsi="Palatino Linotype"/><w:b/><w:sz w:val="28"/><w:szCs w:val="28"/><w:color w:val="000000"/></w:rPr><w:t>$yearRange</w:t></w:r>''';
      });
      
      final simplePattern = RegExp(r'\$\{yearRange\}');
      headerXml = headerXml.replaceAllMapped(simplePattern, (match) {
        print('✓ Matched simple yearRange placeholder in ${headerFile.name}!');
        final yearRange = replacements['yearRange'] ?? '';
        return '''<w:r><w:rPr><w:rFonts w:ascii="Palatino Linotype" w:hAnsi="Palatino Linotype"/><w:b/><w:sz w:val="28"/><w:szCs w:val="28"/><w:color w:val="000000"/></w:rPr><w:t>$yearRange</w:t></w:r>''';
      });
      
      if (beforeReplacement != headerXml) {
        print('✓ Header replacement successful for ${headerFile.name}');
      } else {
        print('✗ No yearRange placeholders found in ${headerFile.name}');
      }
      
      archive.addFile(ArchiveFile(headerFile.name, utf8.encode(headerXml).length, utf8.encode(headerXml)));
    }

    final footerFiles = archive.where((f) => f.name.contains('footer') && f.name.endsWith('.xml')).toList();
    for (final footerFile in footerFiles) {
      var footerXml = utf8.decode(footerFile.content as List<int>);
      
      print('Processing footer file: ${footerFile.name}');
      
      final complexPattern = RegExp(
        r'\$\{</w:t></w:r>.*?<w:t>yearRange</w:t>.*?<w:t>\}',
        dotAll: true,
      );
      
      final beforeReplacement = footerXml;
      footerXml = footerXml.replaceAllMapped(complexPattern, (match) {
        print('✓ Matched complex yearRange placeholder in ${footerFile.name}!');
        final yearRange = replacements['yearRange'] ?? '';
        return '''<w:r><w:rPr><w:rFonts w:ascii="Palatino Linotype" w:hAnsi="Palatino Linotype"/><w:b/><w:sz w:val="28"/><w:szCs w:val="28"/><w:color w:val="000000"/></w:rPr><w:t>$yearRange</w:t></w:r>''';
      });
      
      final simplePattern = RegExp(r'\$\{yearRange\}');
      footerXml = footerXml.replaceAllMapped(simplePattern, (match) {
        print('✓ Matched simple yearRange placeholder in ${footerFile.name}!');
        final yearRange = replacements['yearRange'] ?? '';
        return '''<w:r><w:rPr><w:rFonts w:ascii="Palatino Linotype" w:hAnsi="Palatino Linotype"/><w:b/><w:sz w:val="28"/><w:szCs w:val="28"/><w:color w:val="000000"/></w:rPr><w:t>$yearRange</w:t></w:r>''';
      });
      
      if (beforeReplacement != footerXml) {
        print('✓ Footer replacement successful for ${footerFile.name}');
      } else {
        print('✗ No yearRange placeholders found in ${footerFile.name}');
      }
      
      archive.addFile(ArchiveFile(footerFile.name, utf8.encode(footerXml).length, utf8.encode(footerXml)));
    }

    final out = ZipEncoder().encode(archive)!;
    return Uint8List.fromList(out);
    
  } catch (e) {
    print('Error generating DOCX: $e');
    rethrow;
  }
}

class PartIIA extends StatefulWidget {
  final String documentId;
  
  const PartIIA({
    Key? key,
    required this.documentId,
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
  bool _isFinalized = false;

  late DocumentReference _sectionRef;
  final _user = FirebaseAuth.instance.currentUser;
  String get _userId => _user?.displayName ?? _user?.email ?? _user?.uid ?? 'unknown';
  final _storage = FirebaseStorage.instance;
  String get _yearRange {
    final yearRange = context.read<SelectionModel>().yearRange ?? '2729';
    print('Getting yearRange (Part II.A): $yearRange');
    return yearRange;
  }

  @override
  void initState() {
    super.initState();
    print('initState (Part II.A) - yearRange: $_yearRange');
    _sectionRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(_yearRange)
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
          _isFinalized = (data['isFinalized'] as bool? ?? false) || (data['screening'] as bool? ?? false);
        });

        try {
          final isiRef = _storage.ref().child('$_yearRange/II.A/isi.png');
          final isiiRef = _storage.ref().child('$_yearRange/II.A/isii.png');
          final isiiiRef = _storage.ref().child('$_yearRange/II.A/isiii.png');
          
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
          final imageRef = _storage.ref().child('$_yearRange/II.A/${type.toLowerCase()}.png');
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
          name: 'Part_II_A_${type}_$_yearRange.png',
          bytes: bytes,
          mimeType: MimeType.png,
        );
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/Part_II_A_${type}_$_yearRange.png');
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
      final formattedYearRange = formatYearRange(_yearRange);
      final payload = {
        'modifiedBy': username,
        'lastModified': FieldValue.serverTimestamp(),
        'screening': finalize || _isFinalized,
        'sectionTitle': 'Part II.A',
        'isFinalized': finalize ? false : _isFinalized,
        'yearRange': formattedYearRange,
      };

      if (!_isFinalized) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdBy'] = username;
      }

      await _sectionRef.set(payload, SetOptions(merge: true));
      setState(() => _isFinalized = finalize);

      if (_isiBytes != null && _isiiBytes != null && _isiiiBytes != null) {
        try {
          final bytes = await generateDocxWithImages(
            images: {
              'ISI': _isiBytes!,
              'ISII': _isiiBytes!,
              'ISIII': _isiiiBytes!,
            },
            replacements: {
              'yearRange': formattedYearRange,
            },
          );
          final docxRef = _storage.ref().child('$_yearRange/II.A/document.docx');
          await docxRef.putData(bytes, SettableMetadata(contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'));
          final docxUrl = await docxRef.getDownloadURL();
          await _sectionRef.set({'docxUrl': docxUrl}, SetOptions(merge: true));
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error generating/uploading DOCX: ' + e.toString())),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('DOCX not generated: Please upload all three images (ISI, ISII, ISIII)')),
        );
      }

      if (finalize) {
        await createSubmissionNotification('Part II.A', _yearRange);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Part II.A submitted for admin approval. You will be notified once it is reviewed.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          )
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Part II.A saved successfully (not finalized)'),
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

  Future<void> _downloadDocx() async {
    setState(() => _compiling = true);
    try {
      final fileName = 'document.docx';
      final storage = FirebaseStorage.instance;
      final docxRef = storage.ref().child('$_yearRange/II.A/document.docx');
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
            'Part II.A - Conceptual Framework for Information Systems (Diagram of IS Interface)',
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
              if (!_isFinalized)
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
                    'Part II.A - Information Security Policy'
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
                onPressed: _compiling ? null : _downloadDocx,
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
                      'Part II.A - Conceptual Framework for Information Systems (Diagram of IS Interface) has been finalized.',
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
              ),
      ),
    );
  }
} 