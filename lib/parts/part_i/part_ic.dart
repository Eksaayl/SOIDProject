import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:file_saver/file_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';

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
  final bytes   = (await rootBundle.load(assetPath)).buffer.asUint8List();
  final archive = ZipDecoder().decodeBytes(bytes);

  const imagePath = 'word/media/image1.png';
  archive.addFile(ArchiveFile(imagePath, imageBytes.length, imageBytes));


  final rels = archive.firstWhere((f) => f.name == 'word/_rels/document.xml.rels');
  var relsXml = utf8.decode(rels.content as List<int>);
  const rid = 'rIdImage1';
  relsXml = relsXml.replaceFirst(
    '</Relationships>',
    '''
    <Relationship Id="$rid"
                  Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image"
                  Target="media/image1.png"/>
  </Relationships>''',
  );
  archive.addFile(ArchiveFile('word/_rels/document.xml.rels', utf8.encode(relsXml).length, utf8.encode(relsXml)));

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
  Uint8List? _pickedBytes;
  bool     _loading   = true;
  bool     _saving    = false;
  bool     _compiling = false;
  bool     _isFinal   = false;
  late CollectionReference _sections;
  final _user = FirebaseAuth.instance.currentUser;
  String get _userId =>
      _user?.displayName ?? _user?.email ?? _user?.uid ?? 'unknown';

  @override
  void initState() {
    super.initState();
    _sections = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(widget.documentId)
        .collection('sections');
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await _sections.doc('I.C').get();
      final d = snap.data() as Map<String,dynamic>? ?? {};
      final b64 = d['functionalInterface'] as String?;
      if (b64 != null) _pickedBytes = base64Decode(b64);
      _isFinal = d['isFinalized'] == true;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Load error: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickImage() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x != null) {
      final bytes = await x.readAsBytes();
      setState(() => _pickedBytes = bytes);
    }
  }

  Future<void> _saveSection() async {
    if (_pickedBytes == null) return;
    setState(() => _saving = true);
    try {
      final payload = {
        'functionalInterface': base64Encode(_pickedBytes!),
        'modifiedBy': _userId,
        'lastModified': FieldValue.serverTimestamp(),
        'isFinalized': _isFinal
      };
      if (!_isFinal) {
        payload['createdBy'] = _userId;
        payload['createdAt'] = FieldValue.serverTimestamp();
      }
      await _sections.doc('I.C').set(payload, SetOptions(merge:true));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Section saved')));
    } catch(e){
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _compileDocx() async {
    if (_pickedBytes == null) return;
    setState(() => _compiling = true);
    try {
      final docBytes = await generateDocxWithImage(
        assetPath: 'assets/templates_c.docx',
        placeholder: r'${functionalInterface}',
        imageBytes: _pickedBytes!,
      );

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'Part_I.C',
          bytes: docBytes,
          ext: 'docx',
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/Part_I.C_${DateTime.now().millisecondsSinceEpoch}.docx';
        await File(path).writeAsBytes(docBytes);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $path')));
      }
    } catch(e){
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Compile error: $e')));
    } finally {
      setState(() => _compiling = false);
    }
  }

  @override
  Widget build(BuildContext ctx) {
    if (_loading) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children:[
          _pickedBytes != null
              ? Image.memory(_pickedBytes!, width:200, height:120, fit:BoxFit.cover)
              : Icon(Icons.developer_board, size:100, color:Colors.grey),
          const SizedBox(height:12),

          ElevatedButton.icon(
            icon: Icon(Icons.upload_file),
            label: Text(_pickedBytes==null ? 'Upload Interface' : 'Change Interface'),
            onPressed: _isFinal ? null : _pickImage,
          ),
          const SizedBox(height:24),

          _saving
              ? CircularProgressIndicator()
              : ElevatedButton.icon(
            icon: Icon(Icons.save),
            label: Text('Save Section'),
            onPressed: _isFinal ? null : _saveSection,
          ),
          const SizedBox(height:12),

          _compiling
              ? CircularProgressIndicator()
              : ElevatedButton.icon(
            icon: Icon(Icons.picture_as_pdf),
            label: Text('Compile Part I.C'),
            onPressed: _isFinal ? null : _compileDocx,
          ),
        ]),
      ),
    );
  }
}
