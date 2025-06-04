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
import 'package:flutter_quill/flutter_quill.dart' hide Text;
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

Future<Uint8List> generateDocxWithImage({
  required String assetPath,
  required String placeholder,
  required Uint8List imageBytes,
}) async {
  final bytes = (await rootBundle.load(assetPath)).buffer.asUint8List();
  final archive = ZipDecoder().decodeBytes(bytes);

  const imagePath = 'word/media/image1.png';
  archive.addFile(ArchiveFile(imagePath, imageBytes.length, imageBytes));

  final relsFile = archive.firstWhere((f) => f.name == 'word/_rels/document.xml.rels');
  var relsXml = utf8.decode(relsFile.content as List<int>);
  const rid = 'rId1000';
  if (!relsXml.contains(rid)) {
    relsXml = relsXml.replaceFirst(
      '</Relationships>',
      '''<Relationship Id="$rid" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.png"/></Relationships>''',
    );
    archive.addFile(ArchiveFile('word/_rels/document.xml.rels', utf8.encode(relsXml).length, utf8.encode(relsXml)));
  }

  final doc = archive.firstWhere((f) => f.name == 'word/document.xml');
  var docXml = utf8.decode(doc.content as List<int>);
  final drawingXml = '''
    <w:r>
      <w:drawing>
        <wp:inline distT="0" distB="0" distL="0" distR="0">
          <wp:extent cx="5486400" cy="3200400"/>
          <wp:docPr id="1" name="Picture 1"/>
          <a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
            <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
              <pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
                <pic:blipFill>
                  <a:blip r:embed="$rid" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/>
                  <a:stretch><a:fillRect/></a:stretch>
                </pic:blipFill>
                <pic:spPr>
                  <a:xfrm>
                    <a:off x="0" y="0"/>
                    <a:ext cx="5486400" cy="3200400"/>
                  </a:xfrm>
                  <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
                </pic:spPr>
              </pic:pic>
            </a:graphicData>
          </a:graphic>
        </wp:inline>
      </w:drawing>
    </w:r>
  ''';
  docXml = docXml.replaceAll(placeholder, drawingXml);
  archive.addFile(ArchiveFile('word/document.xml', utf8.encode(docXml).length, utf8.encode(docXml)));

  final out = ZipEncoder().encode(archive)!;
  return Uint8List.fromList(out);
}

class PartICFormPage extends StatefulWidget {
  final String documentId;
  const PartICFormPage({Key? key, required this.documentId}) : super(key: key);
  @override _PartICFormPageState createState() => _PartICFormPageState();
}

class _PartICFormPageState extends State<PartICFormPage> {
  final _formKey = GlobalKey<FormState>();
  Uint8List? _pickedBytes;
  bool _loading = true;
  bool _saving = false;
  bool _compiling = false;
  bool _isFinal = false;
  String? _fileUrl;

  late DocumentReference _sectionRef;
  final _user = FirebaseAuth.instance.currentUser;
  final _storage = FirebaseStorage.instance;
  String get _userId => _user?.displayName ?? _user?.email ?? _user?.uid ?? 'unknown';

  @override
  void initState() {
    super.initState();
    _sectionRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(widget.documentId)
        .collection('sections')
        .doc('I.C');

    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      final doc = await _sectionRef.get();
      final data = doc.data() as Map<String, dynamic>?;
      if (data != null) {
        setState(() {
          _isFinal = (data['isFinalized'] as bool? ?? false) || (data['screening'] as bool? ?? false);
          _fileUrl = data['fileUrl'] as String?;
        });

        try {
          final imageRef = _storage.ref().child('${widget.documentId}/I.C/functionalInterface.png');
          final imageBytes = await imageRef.getData();
          if (imageBytes != null) {
            setState(() {
              _pickedBytes = imageBytes;
            });
          }
        } catch (e) {
          print('Error loading image: $e');
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

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() => _pickedBytes = bytes);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image pick error: $e'))
      );
    }
  }

  Future<void> _saveSection({bool finalize = false}) async {
    if (_pickedBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image first'))
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final imageRef = _storage.ref().child('${widget.documentId}/I.C/functionalInterface.png');
      await imageRef.putData(_pickedBytes!);

      final docxBytes = await generateDocxWithImage(
        assetPath: 'assets/templates_c.docx',
        placeholder: '\${functionalInterface}',
        imageBytes: _pickedBytes!,
      );

      final docxRef = _storage.ref().child('${widget.documentId}/I.C/document.docx');
      await docxRef.putData(docxBytes);
      final docxUrl = await docxRef.getDownloadURL();

      final username = await getCurrentUsername();
      final doc = await _sectionRef.get();
      final payload = {
        'fileUrl': docxUrl,
        'lastModified': FieldValue.serverTimestamp(),
        'lastModifiedBy': username,
        'screening': finalize,
        'sectionTitle': 'Part I.C',
      };

      if (!doc.exists) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdBy'] = username;
      }

      await _sectionRef.set(payload, SetOptions(merge: true));
      setState(() => _isFinal = finalize);
      
      if (finalize) {
        // Use the centralized notification service
        await createSubmissionNotification('Part I.C');
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
    if (_pickedBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image first'))
      );
      return;
    }

    setState(() => _compiling = true);
    try {
      final bytes = await generateDocxWithImage(
        assetPath: 'assets/templates_c.docx',
        placeholder: '\${functionalInterface}',
        imageBytes: _pickedBytes!,
      );

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
          'Part I.C - The Department/Agency and its Environment (Functional Interface Chart)',
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
              onPressed: _isFinal ? null : () => _saveSection(finalize: false),
              tooltip: 'Save',
              color: const Color(0xff021e84),
            ),
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _isFinal ? null : () async {
                final confirmed = await showFinalizeConfirmation(
                  context,
                  'Part I.C - The Department/Agency and its Environment (Functional Interface Chart)'
                );
                if (confirmed) {
                  _saveSection(finalize: true);
                }
              },
              tooltip: 'Finalize',
              color: _isFinal ? Colors.grey : const Color(0xff021e84),
            ),
            IconButton(
              icon: const Icon(Icons.file_download),
              onPressed: _compileDocx,
              tooltip: 'Compile DOCX',
              color: const Color(0xff021e84),
            ),
          ],
        ],
      ),
      body: _isFinal
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock, size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    'Part I.C - The Department/Agency and its Environment (Functional Interface Chart) has been finalized.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            )
          : Form(
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
                            'Please upload the functional interface image. The image should be clear and relevant to the section. You can preview, save, and compile the image into a document.',
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
                                  Icons.image,
                                  color: Color(0xff021e84),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Functional Interface',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2D3748),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          if (_pickedBytes != null)
                            Container(
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
                                  _pickedBytes!,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          const SizedBox(height: 20),
                          Center(
                            child: ElevatedButton.icon(
                              onPressed: _pickImage,
                              icon: Icon(
                                _pickedBytes == null ? Icons.upload_file : Icons.edit,
                                color: Colors.white,
                              ),
                              label: Text(
                                _pickedBytes == null ? 'Upload Image' : 'Change Image',
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
    );
  }
}
