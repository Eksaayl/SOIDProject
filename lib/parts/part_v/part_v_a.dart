import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../homepage.dart';
import '../../utils/user_utils.dart';
import '../../services/notification_service.dart';
import '../../state/selection_model.dart';
import 'package:provider/provider.dart';
import '../../utils/dialog_utils.dart';
import '../../config.dart';

class PartVA extends StatefulWidget {
  final String documentId;
  const PartVA({Key? key, this.documentId = 'document'}) : super(key: key);

  @override
  State<PartVA> createState() => _PartVAState();
}

class _PartVAState extends State<PartVA> {
  final _formKey = GlobalKey<FormState>();
  Uint8List? _ipisBytes;
  bool _loading = true;
  bool _saving = false;
  bool _compiling = false;
  bool _isFinalized = false;
  bool _hasUnsavedChanges = false;
  late DocumentReference _sectionRef;
  final _user = FirebaseAuth.instance.currentUser;
  String get _userId => _user?.displayName ?? _user?.email ?? _user?.uid ?? 'unknown';
  String get _yearRange => context.read<SelectionModel>().yearRange ?? '2729';
  final _storage = FirebaseStorage.instance;

  @override
  void initState() {
    super.initState();
    _sectionRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(_yearRange)
        .collection('sections')
        .doc('V.A');
    _loadContent();
  }

  void _markUnsaved() {
    if (!_hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = true;
      });
    }
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
          final ipisRef = _storage.ref().child('$_yearRange/V.A/ipis.png');
          final ipisBytes = await ipisRef.getData();
          if (ipisBytes != null) {
            setState(() {
              _ipisBytes = ipisBytes;
            });
          }
        } catch (e) {
          print('Error loading ICT Projects Implementation Schedule image: $e');
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

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null) {
        final file = result.files.first;
        final fileName = file.name.toLowerCase();
        if (!fileName.endsWith('.jpg') && !fileName.endsWith('.jpeg') && !fileName.endsWith('.png')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select only JPEG (.jpg/.jpeg) or PNG (.png) files.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        final bytes = file.bytes;
        if (bytes != null) {
          final imageRef = _storage.ref().child('$_yearRange/V.A/ipis.png');
          await imageRef.putData(bytes);
          setState(() {
            _ipisBytes = bytes;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ICT Projects Implementation Schedule image uploaded successfully'))
          );
          _markUnsaved();
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e'))
      );
    }
  }

  Future<void> _downloadImage() async {
    if (_ipisBytes == null) return;

    try {
      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'Part_V_A_$_yearRange.png',
          bytes: _ipisBytes!,
          mimeType: MimeType.png,
        );
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/Part_V_A_$_yearRange.png');
        await file.writeAsBytes(_ipisBytes!);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ICT Projects Implementation Schedule image downloaded successfully'))
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error downloading image: $e'))
      );
    }
  }

  Future<String?> _generateAndUploadDocx() async {
    try {
      if (_ipisBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please upload an ICT Projects Implementation Schedule image first')),
        );
        return null;
      }

      final url = Uri.parse('${Config.serverUrl}/generate-va-docx/');
      final request = http.MultipartRequest('POST', url);
      
      request.files.add(http.MultipartFile.fromBytes(
        'ipis_image',
        _ipisBytes!,
        filename: 'ipis.png',
      ));
      
      request.fields['yearRange'] = formatYearRange(_yearRange);

      final response = await request.send();
      if (response.statusCode == 200) {
        final bytes = await response.stream.toBytes();
        final fileName = 'document.docx';
        
        try {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child(_yearRange)
              .child('V.A')
              .child(fileName);
          
          final metadata = SettableMetadata(
            contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            customMetadata: {
              'uploadedBy': _userId,
              'documentId': _yearRange,
              'section': 'V.A',
            },
          );

          if (kIsWeb) {
            await storageRef.putData(bytes, metadata);
          } else {
            final directory = await getApplicationDocumentsDirectory();
            final file = File('${directory.path}/$fileName');
            await file.writeAsBytes(bytes);
            await storageRef.putFile(file, metadata);
          }
          
          return await storageRef.getDownloadURL();
        } catch (storageError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error uploading to storage: $storageError')),
          );
          return null;
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate DOCX: ${response.statusCode}')),
        );
      }
      return null;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      return null;
    }
  }

  Future<void> _save({bool finalize = false}) async {
    if (_ipisBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload an ICT Projects Implementation Schedule image first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final username = await getCurrentUsername();
      final doc = await _sectionRef.get();
      final payload = {
        'modifiedBy': username,
        'lastModified': FieldValue.serverTimestamp(),
        'screening': finalize || _isFinalized,
        'sectionTitle': 'Part V.A',
        'isFinalized': finalize ? false : _isFinalized,
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

      final docxUrl = await _generateAndUploadDocx();
      if (docxUrl != null) {
        await _sectionRef.set({'docxUrl': docxUrl}, SetOptions(merge: true));
      }

      if (finalize) {
        await createSubmissionNotification('Part V.A', _yearRange);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Part V.A submitted for admin approval. You will be notified once it is reviewed.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          )
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Part V.A saved successfully (not finalized)'),
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
      final fileName = 'Part_VA.docx';
      final storage = FirebaseStorage.instance;
      final docxRef = storage.ref().child('$_yearRange/V.A/document.docx');
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

  Widget _buildImageUploadSection() {
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
              const Text(
                'ICT Projects Implementation Schedule Image',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3748),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_ipisBytes != null)
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
                    _ipisBytes!,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            )
          else if (!_isFinalized)
            Center(
              child: ElevatedButton.icon(
                onPressed: _pickImage,
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
          if (_ipisBytes != null && !_isFinalized)
            const SizedBox(height: 20),
          if (_ipisBytes != null && !_isFinalized)
            Center(
              child: ElevatedButton.icon(
                onPressed: _pickImage,
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
            'Part V.A - ICT Projects Implementation Schedule',
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
                    'Part V.A - ICT Projects Implementation Schedule'
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
                      'Part V.A - ICT Projects Implementation Schedule has been finalized.',
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
                                'Please upload an ICT Projects Implementation Schedule image for Part V.A. The image will be displayed in the generated DOCX document. Make sure the image is clear and properly formatted before finalizing. Click the download icon in the app bar to generate a DOCX file with the uploaded image.',
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
                        _buildImageUploadSection(),
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
