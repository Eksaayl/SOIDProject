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
import '../../homepage.dart';
import '../../utils/user_utils.dart';
import '../../services/notification_service.dart';
import '../../state/selection_model.dart';
import 'package:provider/provider.dart';
import '../../utils/dialog_utils.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';

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

Future<Uint8List> generateDocxBySearchReplaceFromBytes({
  required Uint8List templateBytes,
  required Map<String, String> replacements,
}) async {
  final archive = ZipDecoder().decodeBytes(templateBytes);
  final docFile = archive.firstWhere((f) => f.name == 'word/document.xml');
  String xmlStr = utf8.decode(docFile.content as List<int>);

  final cleanXml = xmlStr.replaceAllMapped(
    RegExp(r'\$\{.*?\}', multiLine: true, dotAll: true),
    (match) {
      String placeholder = match.group(0)!;
      placeholder = placeholder.replaceAll(RegExp(r'<[^>]+>'), '');
      placeholder = placeholder.replaceAll(RegExp(r'\s+'), '');
      return placeholder;
    },
  );

  final pattern = RegExp(r'\$\{(.+?)\}');
  final allKeys = pattern.allMatches(cleanXml).map((m) => m.group(1)!).toSet();

  final complete = <String, String>{
    for (var key in allKeys) '${key}': replacements[key] ?? '',
  };

  String finalXml = cleanXml;
  complete.forEach((ph, val) {
    String processedValue = val;
    if (ph == 'yearRange') {
      final escapedValue = xmlEscape(processedValue);
      final formattedValue = '<w:r><w:rPr><w:rFonts w:ascii="Palatino Linotype" w:hAnsi="Palatino Linotype"/><w:b/><w:sz w:val="28"/><w:szCs w:val="28"/><w:color w:val="000000"/></w:rPr><w:t>$escapedValue</w:t></w:r>';
      finalXml = finalXml.replaceAll('yearRange', formattedValue);
    } else {
      finalXml = finalXml.replaceAll(ph, xmlEscape(processedValue));
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

class PartVDFormPage extends StatefulWidget {
  final String documentId;
  const PartVDFormPage({Key? key, required this.documentId}) : super(key: key);
  @override
  _PartVDFormPageState createState() => _PartVDFormPageState();
}

class _PartVDFormPageState extends State<PartVDFormPage> {
  final _formKey = GlobalKey<FormState>();
  Uint8List? _uploadedFileBytes;
  String? _fileName;
  String? _fileUrl;
  bool _loading = true;
  bool _saving = false;
  bool _isFinalized = false;
  bool _compiling = false;
  bool _hasUnsavedChanges = false;

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
        .doc('V.D');

    _loadData();
  }

  void _markUnsaved() {
    if (!_hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = true;
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
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
          final docxRef = _storage.ref().child('$_yearRange/V.D/document.docx');
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
      setState(() {
        _hasUnsavedChanges = false;
      });
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
          setState(() => _compiling = true);
          
          try {
            final docxRef = _storage.ref().child('$_yearRange/V.D/document.docx');
            await docxRef.putData(file.bytes!);
            
            await _sectionRef.set({
              'docxBytes': base64Encode(file.bytes!),
              'fileName': file.name,
              'lastModified': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            
            setState(() {
              _uploadedFileBytes = file.bytes;
              _fileName = file.name;
              _compiling = false;
            });
            _markUnsaved();
          } catch (uploadError) {
            setState(() => _compiling = false);
          }
        }
      }
    } catch (e) {
      setState(() => _compiling = false);
    }
  }

  Future<String> _uploadToStorage() async {
    if (_uploadedFileBytes == null) throw Exception('No file to upload');
    
    final storageRef = _storage.ref()
        .child('$_yearRange/V.D/document.docx');

    final uploadTask = storageRef.putData(_uploadedFileBytes!);
    final snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }

  Future<void> _generateAndUploadDocx() async {
    try {
      final storage = FirebaseStorage.instance;
      final templateRef = storage.ref().child('$_yearRange/V.D/V_d.docx');
      final templateBytes = await templateRef.getData();

      if (templateBytes == null) {
        return;
      }

      final formattedYearRange = formatYearRange(_yearRange);
      final replacements = {
        'yearRange': formattedYearRange,
      };

      final generatedBytes = await generateDocxBySearchReplaceFromBytes(
        templateBytes: templateBytes,
        replacements: replacements,
      );

      final docxRef = _storage.ref().child('$_yearRange/V.D/document.docx');
      await docxRef.putData(generatedBytes);

      setState(() {
        _uploadedFileBytes = generatedBytes;
        _fileName = 'Part_V_D.docx';
      });

    } catch (e) {
      print('❌ DEBUG: Error type: ${e.runtimeType}');
    }
  }

  Future<void> _save({bool finalize = false}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
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
        'sectionTitle': 'Part V.D',
      };
      if (!_isFinalized) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdBy'] = username;
      }
      await _sectionRef.set(payload, SetOptions(merge: true));
      setState(() => _isFinalized = finalize);
      setState(() {
        _hasUnsavedChanges = false;
      });
      if (finalize) {
        await createSubmissionNotification('Part V.D', _yearRange);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Part V.D submitted for admin approval. You will be notified once it is reviewed.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          )
        );
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Part V.D saved successfully (not finalized)'),
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
      final fileName = _fileName ?? 'Part_V_D_Summary_of_Budget.docx';
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

  Future<void> _downloadTemplate() async {
    setState(() => _compiling = true);
    try {
      final storage = FirebaseStorage.instance;
      final templateRef = storage.ref().child('$_yearRange/V.D/V_d.docx');
      final templateBytes = await templateRef.getData();
      
      if (templateBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template not found in storage. Please contact administrator.')),
        );
        return;
      }

      final fileName = 'V_d_template.docx';
      
      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: fileName,
          bytes: templateBytes,
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(templateBytes);
        await FileSaver.instance.saveFile(
          name: fileName,
          file: file,
          mimeType: MimeType.microsoftWord,
        );
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('V_d.docx template downloaded successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Template download error: ${e.toString()}')),
      );
    } finally {
      setState(() => _compiling = false);
    }
  }

  Future<void> _openGoogleSheets() async {
    String url;
    switch (_yearRange) {
      case '2729':
        url = 'https://docs.google.com/spreadsheets/d/1-9K0UeP3elWExeoC1uiC8VfOfirZodMo/edit?usp=sharing&ouid=105049319277397400729&rtpof=true&sd=true';
        break;
      case '3032':
        url = 'https://docs.google.com/spreadsheets/d/1QfWrNCEUgdQi_4uh6g6Ag4XB-lU6nI4Gr8GMSA7Lcfc/edit?usp=sharing';
        break;
      case '3335':
        url = 'https://docs.google.com/spreadsheets/d/11tFKOmiXexMIMXIUNJkn2D3HZrQBHC9zWOs4SOsl0ok/edit?usp=sharing';
        break;
      case '3638':
        url = 'https://docs.google.com/spreadsheets/d/1N2ZazAUbhkXclTd2mwBJC6ncg77dYzbSOYM9aHUQDnQ/edit?usp=sharing';
        break;
      case '3941':
        url = 'https://docs.google.com/spreadsheets/d/1jtGszUx-WvViTyCalnio0pol4ruMNReyCAYBx0-_k-E/edit?usp=sharing';
        break;
      case '4244':
        url = 'https://docs.google.com/spreadsheets/d/1k6NUNqYPkGHY_3HoON5eO2XOOKCmabKshPamnLcD7Ok/edit?usp=sharing';
        break;
      case '4547':
        url = 'https://docs.google.com/spreadsheets/d/1MpcDkaLmXUg7uhPnVtCFncbwv1oNkcgPnxgUKoj9i7Q/edit?usp=sharing';
        break;
      case '4850':
        url = 'https://docs.google.com/spreadsheets/d/1AXrRTx0Q5ADuqH8khDFoXN4cv2FTnMwsF-KHFcanFr4/edit?usp=sharing';
        break;
      case '5153':
        url = 'https://docs.google.com/spreadsheets/d/14KXFAf0TZz18SdRSKIgwJqrNQENPjCuFCQgOQZ1l0PY/edit?usp=sharing';
        break;
      default:
        url = 'https://docs.google.com/spreadsheets/d/1QfWrNCEUgdQi_4uh6g6Ag4XB-lU6nI4Gr8GMSA7Lcfc/edit?usp=sharing';
        break;
    }
    
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Sheets')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening Google Sheets: $e')),
      );
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
        if (_hasUnsavedChanges) {
          final shouldPop = await DialogUtils.showSaveBeforeLeavingDialog(
            context: context,
          );
          return shouldPop ?? false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FAFC),
        appBar: AppBar(
          title: const Text(
            'Part V.D - Summary of Budget',
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
                    'Part V.D - Summary of Budget'
                  );
                  if (confirmed) {
                    _save(finalize: true);
                  }
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
                    const SizedBox(height: 12),
                    const Text(
                      'Part V.D - Summary of Budget has been finalized.',
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
                                'Please upload a DOCX document for Part V.D. The document should contain all necessary information for the Summary of Budget section. You can download the template, fill it out, and then upload your completed document.',
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
                                    onPressed: _downloadTemplate,
                                    icon: const Icon(Icons.download),
                                    label: const Text('Download V_d.docx Template'),
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
                                  const SizedBox(width: 16),
                                  ElevatedButton.icon(
                                    onPressed: _openGoogleSheets,
                                    icon: const Icon(Icons.table_chart),
                                    label: const Text('Open Google Sheets'),
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