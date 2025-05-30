import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:file_saver/file_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:test_project/parts/part_i/part_ia.dart';
import 'package:test_project/parts/part_i/part_ib.dart';
import 'package:test_project/parts/part_i/part_ic.dart';
import 'package:test_project/parts/part_i/part_id.dart';
import 'package:test_project/parts/part_i/part_ie.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:file_picker/file_picker.dart';
import '../services/document_service.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_storage/firebase_storage.dart';
import '../config.dart';

Future<Uint8List> generateDocxWithTextAndImage({
  required String assetPath,
  required Map<String, String> textReplacements,
  String? imagePlaceholder,
  Uint8List? imageBytes,
}) async {
  final bytes = (await rootBundle.load(assetPath)).buffer.asUint8List();
  final archive = ZipDecoder().decodeBytes(bytes);

  final docFile = archive.firstWhere((f) => f.name == 'word/document.xml');
  String xmlStr = utf8.decode(docFile.content as List<int>);

  if (imagePlaceholder != null && imageBytes != null) {
    const imagePath = 'word/media/image1.png';
    archive.addFile(ArchiveFile(imagePath, imageBytes.length, imageBytes));

    final relsFile = archive.firstWhere((f) => f.name == 'word/_rels/document.xml.rels');
    var relsXml = utf8.decode(relsFile.content as List<int>);
    const rid = 'rIdImage1';
    if (!relsXml.contains(rid)) {
      relsXml = relsXml.replaceFirst(
        '</Relationships>',
        '''<Relationship Id="$rid" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.png"/></Relationships>''',
      );
      archive.addFile(ArchiveFile('word/_rels/document.xml.rels', utf8.encode(relsXml).length, utf8.encode(relsXml)));
    }

    final drawingXml = '''<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="5486400" cy="3200400"/><wp:docPr id="1" name="Picture 1"/><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:blipFill><a:blip r:embed="$rid" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="5486400" cy="3200400"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>''';
    xmlStr = xmlStr.replaceAll(imagePlaceholder, drawingXml);
  }

  final pattern = RegExp(r'\$\{(.+?)\}');
  final allKeys = pattern.allMatches(xmlStr).map((m) => m.group(1)!).toSet();
  final replacements = <String, String>{ for (var k in allKeys) '\${$k}': textReplacements[k] ?? '' };

  replacements.forEach((ph, val) {
    final safe = val
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
    xmlStr = xmlStr.replaceAll(ph, safe);
  });

  final outArchive = Archive();
  for (final f in archive) {
    if (f.name == 'word/document.xml') {
      final data = utf8.encode(xmlStr);
      outArchive.addFile(ArchiveFile(f.name, data.length, data));
    } else {
      outArchive.addFile(f);
    }
  }

  return Uint8List.fromList(ZipEncoder().encode(outArchive)!);
}

Future<Uint8List> generateCompiledDocx(String documentId) async {
  final sections = FirebaseFirestore.instance
      .collection('issp_documents')
      .doc(documentId)
      .collection('sections');

  final snaps = await Future.wait([
    sections.doc('I.A').get(),
    sections.doc('I.B').get(),
    sections.doc('I.C').get(),
  ]);

  final merged = <String, String>{};
  Uint8List? icImage;
  List<String> functionsIA = [];

  for (var s in snaps) {
    final data = s.data() ?? {};
    // Collect functions from I.A for bullet formatting
    if (s.id == 'I.A' && data['functions'] != null) {
      try {
        final List<dynamic> functionsJson = jsonDecode(data['functions']);
        for (var delta in functionsJson) {
          final doc = quill.Document.fromJson(delta);
          final text = doc.toPlainText().trim();
          if (text.isNotEmpty) functionsIA.add(text);
        }
      } catch (_) {}
    }
    data.forEach((k, v) {
      if (v is String) {
        if (k == 'functionalInterface') {
          try {
            icImage = base64Decode(v);
          } catch (_) {}
        } else {
          merged[k] = v;
        }
      }
    });
  }

  String buildWordBulletXml(List<String> items) {
    return items.map((item) => '''<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>${item.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')}</w:t></w:r></w:p>''').join();
  }
  merged['functions_bullets'] = buildWordBulletXml(functionsIA);

  // Use your existing template for compiled parts
  final bytes = await generateDocxWithTextAndImage(
    assetPath: 'assets/templates_compiled.docx',
    textReplacements: merged,
    imagePlaceholder: '{functionalInterface}',
    imageBytes: icImage,
  );
  return bytes;
}

class Part1 extends StatefulWidget {
  const Part1({Key? key}) : super(key: key);
  @override
  _Part1State createState() => _Part1State();
}

class _Part1State extends State<Part1> {
  int _selectedIndex = -1;
  bool _isCompiling = false;
  static const _docId = 'document';

  Future<void> _compileABCD() async {
    setState(() => _isCompiling = true);

    final sections = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(_docId)
        .collection('sections');

    final snaps = await Future.wait([
      sections.doc('I.A').get(),
      sections.doc('I.B').get(),
      sections.doc('I.C').get(),
      sections.doc('I.D').get(),
    ]);

    final merged = <String, String>{};
    Uint8List? icImage;
    List<String> functionsIA = [];
    List<String> strategicChallenges = [];

    for (var s in snaps) {
      final data = s.data() ?? {};
      // Collect functions from I.A for bullet formatting
      if (s.id == 'I.A' && data['functions'] != null) {
        try {
          final List<dynamic> functionsJson = jsonDecode(data['functions']);
          for (var delta in functionsJson) {
            // Convert delta to Quill Document and extract plain text
            final doc = quill.Document.fromJson(delta);
            final text = doc.toPlainText().trim();
            if (text.isNotEmpty) functionsIA.add(text);
          }
        } catch (_) {}
      }
      // Collect strategic challenges from I.D for bullet formatting
      if (s.id == 'I.D' && data['challenges'] != null) {
        try {
          final List<dynamic> challengesJson = jsonDecode(data['challenges']);
          for (var delta in challengesJson) {
            final doc = quill.Document.fromJson(delta);
            final text = doc.toPlainText().trim();
            if (text.isNotEmpty) strategicChallenges.add(text);
          }
        } catch (_) {}
      }
      data.forEach((k, v) {
        if (v is String) {
          if (k == 'functionalInterface') {
            try {
              icImage = base64Decode(v);
            } catch (_) {}
          } else {
            merged[k] = v;
          }
        }
      });
    }

    String buildWordBulletXml(List<String> items) {
      return items.map((item) => '''<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>${item.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')}</w:t></w:r></w:p>''').join();
    }
    merged['functions_bullets'] = buildWordBulletXml(functionsIA);
    merged['strategicChallenges_bullets'] = buildWordBulletXml(strategicChallenges);

    try {
      final bytes = await generateDocxWithTextAndImage(
        assetPath: 'assets/templates_compiled.docx',
        textReplacements: merged,
        imagePlaceholder: ' {functionalInterface}',
        imageBytes: icImage,
      );

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'Part_I_ABCD',
          bytes: bytes,
          ext: 'docx',
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/Part_I_ABCD_${DateTime.now().millisecondsSinceEpoch}.docx';
        await File(path).writeAsBytes(bytes);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $path')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Compile error: $e')));
    } finally {
      setState(() => _isCompiling = false);
    }
  }

  Future<void> mergeCompiledAndUploadsAndDownload(BuildContext context, String documentId) async {
    try {
      final storage = FirebaseStorage.instance;
      setState(() => _isCompiling = true);

      // Get all Part I documents from storage
      final iaBytes = await storage.ref().child('$documentId/I.A/document.docx').getData();
      final ibBytes = await storage.ref().child('$documentId/I.B/document.docx').getData();
      final icBytes = await storage.ref().child('$documentId/I.C/document.docx').getData();
      final idBytes = await storage.ref().child('$documentId/I.D/document.docx').getData();
      final ieBytes = await storage.ref().child('$documentId/I.E/document.docx').getData();

      if (iaBytes == null || ibBytes == null || icBytes == null || idBytes == null || ieBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('One or more Part I documents are missing. Please ensure all parts are finalized.'))
        );
        return;
      }

      // Create multipart request for merging
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${Config.serverUrl}/merge-documents-part-i-all'),
      );

      // Add all documents
      request.files.add(http.MultipartFile.fromBytes('part_ia', iaBytes, filename: 'part_ia.docx'));
      request.files.add(http.MultipartFile.fromBytes('part_ib', ibBytes, filename: 'part_ib.docx'));
      request.files.add(http.MultipartFile.fromBytes('part_ic', icBytes, filename: 'part_ic.docx'));
      request.files.add(http.MultipartFile.fromBytes('part_id', idBytes, filename: 'part_id.docx'));
      request.files.add(http.MultipartFile.fromBytes('part_ie', ieBytes, filename: 'part_ie.docx'));

      // Send merge request
      var response = await request.send();
      if (response.statusCode != 200) {
        final error = await response.stream.bytesToString();
        throw Exception('Failed to merge documents: ${response.statusCode} - $error');
      }

      // Get merged document
      final responseBytes = await response.stream.toBytes();

      // Save the merged document to storage
      final mergedRef = storage.ref().child('$documentId/part_i_merged.docx');
      await mergedRef.putData(responseBytes);

      // Update Firestore with merged document path
      await FirebaseFirestore.instance.collection('issp_documents').doc(documentId).update({
        'partIMergedPath': '$documentId/part_i_merged.docx',
        'lastModified': FieldValue.serverTimestamp(),
      });

      // Download the merged document
      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'Part_I_Merged_${DateTime.now().millisecondsSinceEpoch}.docx',
          bytes: responseBytes,
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/Part_I_Merged_${DateTime.now().millisecondsSinceEpoch}.docx');
        await file.writeAsBytes(responseBytes);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Documents merged successfully'))
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error merging documents: $e'))
      );
    } finally {
      setState(() => _isCompiling = false);
    }
  }

  Widget _pill(String label, IconData icon, int idx) {
    final sel = _selectedIndex == idx;
    return ElevatedButton.icon(
      onPressed: () {
        setState(() => _selectedIndex = idx);
        switch (idx) {
          case 0:
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => PartIAFormPage(documentId: _docId),
            ));
            break;
          case 1:
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => PartIBFormPage(documentId: _docId),
            ));
            break;
          case 2:
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => PartICFormPage(documentId: _docId),
            ));
            break;
          case 3:
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => PartIDFormPage(documentId: _docId),
            ));
            break;
          case 4:
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => PartIEFormPage(documentId: _docId),
            ));
            break;
        }
      },
      icon: Icon(icon, color: sel ? Colors.white : Colors.black),
      label: Text(label,
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: sel ? Colors.white : Colors.black)),
      style: ElevatedButton.styleFrom(
        backgroundColor: sel ? const Color(0xff021e84) : Colors.transparent,
        side: const BorderSide(color: Colors.black),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ORGANIZATIONAL PROFILE',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  _pill('Part I.A', Icons.article, 0),
                  _pill('Part I.B', Icons.people, 1),
                  _pill('Part I.C', Icons.insert_photo, 2),
                  _pill('Part I.D', Icons.warning, 3),
                  _pill('Part I.E', Icons.computer, 4),
                ],
              ),
              const SizedBox(height: 24),
              if (_isCompiling)
                const CircularProgressIndicator()
              else
                ElevatedButton.icon(
                  onPressed: () => mergeCompiledAndUploadsAndDownload(context, _docId),
                  icon: Icon(Icons.merge_type),
                  label: Text('Merge All Parts I'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff021e84),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

Future<Map<String, dynamic>> pickTemplate() async {
  FilePickerResult? result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['docx'],
    withData: true,
  );

  if (result != null) {
    final file = result.files.single;
    if (kIsWeb) {
      if (file.bytes == null) throw Exception('No file bytes on web');
      return {
        'bytes': file.bytes,
        'name': file.name,
      };
    } else {
      if (file.path == null) throw Exception('No file path on mobile/desktop');
      return {
        'path': file.path,
        'bytes': file.bytes,
        'name': file.name,
      };
    }
  }
  throw Exception('No template selected');
}