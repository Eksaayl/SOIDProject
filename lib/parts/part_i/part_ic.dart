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
import 'package:flutter_html/flutter_html.dart';

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

  // Add image to media folder
  const imagePath = 'word/media/image1.png';
  archive.addFile(ArchiveFile(imagePath, imageBytes.length, imageBytes));

  // Add relationship
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

  // Replace placeholder with image
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

  late DocumentReference _sectionRef;
  final _user = FirebaseAuth.instance.currentUser;
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
        if (data['functionalInterface'] != null) {
          setState(() {
            _pickedBytes = base64Decode(data['functionalInterface'] as String);
            _isFinal = data['finalized'] as bool? ?? false;
          });
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
      final payload = {
        'functionalInterface': base64Encode(_pickedBytes!),
        'lastModified': FieldValue.serverTimestamp(),
        'lastModifiedBy': _userId,
        'finalized': finalize,
      };

      await _sectionRef.set(payload, SetOptions(merge: true));
      setState(() => _isFinal = finalize);
      
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
          name: 'Part_I.C',
          bytes: bytes,
          ext: 'docx',
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/Part_I.C_${DateTime.now().millisecondsSinceEpoch}.docx';
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

  void _showHtmlPreview() {
    final html = buildPartICPreviewHtml(
      functionalInterface: _pickedBytes != null ? base64Encode(_pickedBytes!) : '',
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HtmlPreviewPageIC(html: html)),
    );
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
        title: const Text('Part I.C - Functional Interface'),
        actions: [
          if (_saving || _compiling)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _isFinal ? null : () => _saveSection(finalize: false),
              tooltip: 'Save',
            ),
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _isFinal ? null : () => _saveSection(finalize: true),
              tooltip: 'Finalize',
            ),
            IconButton(
              icon: const Icon(Icons.file_download),
              onPressed: _compiling ? null : _compileDocx,
              tooltip: 'Compile DOCX',
            ),
            IconButton(
              icon: const Icon(Icons.remove_red_eye),
              tooltip: 'Preview as HTML',
              onPressed: _showHtmlPreview,
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
                  'This section has been finalized.',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          )
        : Form(
            key: _formKey,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_pickedBytes != null)
                    Container(
                      width: 400,
                      height: 240,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 2,
                          style: BorderStyle.solid,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Image.memory(
                        _pickedBytes!,
                        fit: BoxFit.contain,
                      ),
                    )
                  else
                    Container(
                      width: 400,
                      height: 240,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 2,
                          style: BorderStyle.solid,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.image_outlined, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No image selected',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(height: 24),
                  ElevatedButton.icon(
                    icon: Icon(Icons.upload_file),
                    label: Text(_pickedBytes == null ? 'Upload Interface' : 'Change Interface'),
                    onPressed: _isFinal ? null : _pickImage,
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

class HtmlPreviewPageIC extends StatelessWidget {
  final String html;
  const HtmlPreviewPageIC({required this.html, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Preview')),
      body: SingleChildScrollView(child: Html(data: html)),
    );
  }
}

String buildPartICPreviewHtml({
  required String functionalInterface,
}) {
  return '''
  <html>
    <head>
      <style>
        @import url('https://fonts.googleapis.com/css2?family=Poppins:wght@500&display=swap');
        body {
          font-family: 'Poppins', Arial, sans-serif;
          background: #f6f8fa;
          margin: 0;
          padding: 0;
        }
        .container {
          max-width: 800px;
          margin: 32px auto;
          background-color: #fff;
        }
        .card {
          background: #fff;
          border-radius: 14px;
          box-shadow: 0 2px 12px rgba(2,30,132,0.10);
          padding: 24px 28px 20px 28px;
          margin-bottom: 28px;
          border: 1px solid #e0e4ea;
        }
        .section-title {
          color: #021e84;
          font-size: 1.1em;
          margin-bottom: 8px;
          font-weight: 600;
          letter-spacing: 0.5px;
        }
        .value {
          margin-bottom: 4px;
          font-size: 1.05em;
        }
        img {
          max-width: 100%;
          height: auto;
          border-radius: 8px;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="card">
          <div class="section-title">Functional Interface</div>
          <div class="value">
            <img src="data:image/png;base64,$functionalInterface" alt="Functional Interface" />
          </div>
        </div>
      </div>
    </body>
  </html>
  ''';
}
