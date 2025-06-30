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
    for (var key in allKeys) '${key}': replacements[key] ?? '',
  };

  print('Final replacements map: $complete');

  String finalXml = cleanXml;
  complete.forEach((ph, val) {
    String processedValue = val;

    if (ph == 'yearRange') {
      final escapedValue = xmlEscape(processedValue);
      final formattedValue = '<w:r><w:rPr><w:rFonts w:ascii="Palatino Linotype" w:hAnsi="Palatino Linotype"/><w:b/><w:sz w:val="28"/><w:szCs w:val="28"/><w:color w:val="000000"/></w:rPr><w:t>$escapedValue</w:t></w:r>';
      print('Replacing $ph with formatted black text');
      finalXml = finalXml.replaceAll('${ph}', formattedValue);
    } else {
      print(
        'Replacing $ph with ${processedValue.length > 50 ? "${processedValue.substring(0, 50)}..." : processedValue}',
      );
      finalXml = finalXml.replaceAll('${ph}', xmlEscape(processedValue));
    }
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

Future<Uint8List> generateDocxBySearchReplaceFromFile({
  required String filePath,
  required Map<String, String> replacements,
}) async {
  print('Loading template from file: $filePath');
  final bytes = await File(filePath).readAsBytes();
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
    for (var key in allKeys) '${key}': replacements[key] ?? '',
  };

  print('Final replacements map: $complete');

  String finalXml = cleanXml;
  complete.forEach((ph, val) {
    String processedValue = val;

    if (ph == 'yearRange') {
      final escapedValue = xmlEscape(processedValue);
      final formattedValue = '<w:r><w:rPr><w:rFonts w:ascii="Palatino Linotype" w:hAnsi="Palatino Linotype"/><w:b/><w:sz w:val="28"/><w:szCs w:val="28"/><w:color w:val="000000"/></w:rPr><w:t>$escapedValue</w:t></w:r>';
      print('Replacing $ph with formatted black text');
      finalXml = finalXml.replaceAll('${ph}', formattedValue);
    } else {
      print(
        'Replacing $ph with ${processedValue.length > 50 ? "${processedValue.substring(0, 50)}..." : processedValue}',
      );
      finalXml = finalXml.replaceAll('${ph}', xmlEscape(processedValue));
    }
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

class PartIVAFormPage extends StatefulWidget {
  final String documentId;
  const PartIVAFormPage({Key? key, required this.documentId}) : super(key: key);
  @override
  _PartIVAFormPageState createState() => _PartIVAFormPageState();
}

class _PartIVAFormPageState extends State<PartIVAFormPage> {
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
  String get _yearRange => context.read<SelectionModel>().yearRange ?? '2729';

  @override
  void initState() {
    super.initState();
    _sectionRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(_yearRange)
        .collection('sections')
        .doc('IV.A');

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
          final docxRef = _storage.ref().child('$_yearRange/IV.A/document.docx');
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
          final docxRef = _storage.ref().child('$_yearRange/IV.A/document.docx');
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
        .child('$_yearRange/IV.A/document.docx');

    final uploadTask = storageRef.putData(_uploadedFileBytes!);
    final snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }

  Future<void> _generateAndUploadDocx() async {
    try {
      // Get the year-specific template from Firebase Storage
      final storage = FirebaseStorage.instance;
      final templateRef = storage.ref().child('$_yearRange/IV.A/IV_a.docx');
      final templateBytes = await templateRef.getData();
      
      if (templateBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template not found. Please upload a template first.')),
        );
        return;
      }

      // Create a temporary file for the template
      final tempDir = await getTemporaryDirectory();
      final tempTemplatePath = '${tempDir.path}/temp_iv_a_template_${DateTime.now().millisecondsSinceEpoch}.docx';
      await File(tempTemplatePath).writeAsBytes(templateBytes);

      // Prepare replacements
      final formattedYearRange = formatYearRange(_yearRange);
      final replacements = {
        'yearRange': formattedYearRange,
        // Add other placeholders as needed
      };

      // Generate DOCX using the template
      final generatedBytes = await generateDocxBySearchReplaceFromFile(
        filePath: tempTemplatePath,
        replacements: replacements,
      );

      // Upload the generated DOCX to Firebase Storage
      final docxRef = storage.ref().child('$_yearRange/IV.A/document.docx');
      await docxRef.putData(generatedBytes);
      
      // Clean up temporary file
      await File(tempTemplatePath).delete();

      setState(() {
        _uploadedFileBytes = generatedBytes;
        _fileName = 'Part_IV_A_Deployment_of_ICT_Equipment_and_Services.docx';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('DOCX generated and uploaded successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating DOCX: $e')),
      );
    }
  }

  Future<void> _save({bool finalize = false}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      // Generate DOCX from template
      await _generateAndUploadDocx();
      final fileUrl = await _uploadToStorage();
      final username = await getCurrentUsername();
      final doc = await _sectionRef.get();
      final payload = {
        'fileName': _fileName,
        'fileUrl': fileUrl,
        'modifiedBy': username,
        'lastModified': FieldValue.serverTimestamp(),
        'isFinalized': finalize ? false : _isFinalized,
        'screening': finalize || _isFinalized,
        'sectionTitle': 'Part IV.A',
      };
      if (!_isFinalized) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdBy'] = username;
      }
      await _sectionRef.set(payload, SetOptions(merge: true));
      setState(() => _isFinalized = finalize);
      if (finalize) {
        await createSubmissionNotification('Part IV.A', _yearRange);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Part IV.A submitted for admin approval. You will be notified once it is reviewed.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          )
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Part IV.A saved successfully (not finalized)'),
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

  Future<void> _compileDocx() async {
    if (_fileUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please upload a document first'))
      );
      return;
    }

    setState(() => _compiling = true);
    try {
      final fileName = _fileName ?? 'Part_IV_A_Deployment_of_ICT_Equipment_and_Services.docx';
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
      final docxRef = storage.ref().child('$_yearRange/IV.A/document.docx');
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
            'Part IV.A - Deployment of ICT Equipment and Services',
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
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: _isFinalized ? null : () => _save(finalize: false),
                tooltip: 'Save',
                color: const Color(0xff021e84),
              ),
              IconButton(
                icon: const Icon(Icons.check),
                onPressed: _isFinalized ? null : () async {
                  final confirmed = await showFinalizeConfirmation(
                    context,
                    'Part IV.A - Deployment of ICT Equipment and Services'
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
                    const SizedBox(height: 12),
                    const Text(
                      'Part IV.A - Deployment of ICT Equipment and Services has been finalized.',
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
                                'Please upload a DOCX document for Part IV.A. The document should contain all necessary information for this section. You can preview, save, and download the document.',
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
                                    label: const Text('Download Part IV.A Template'),
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