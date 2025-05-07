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

class Part1 extends StatefulWidget {
  const Part1({Key? key}) : super(key: key);
  @override
  _Part1State createState() => _Part1State();
}

class _Part1State extends State<Part1> {
  int _selectedIndex = -1;
  bool _isCompiling = false;
  static const _docId = 'document';

  Future<void> _compileABC() async {
    setState(() => _isCompiling = true);

    final sections = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(_docId)
        .collection('sections');

    final snaps = await Future.wait([
      sections.doc('I.A').get(),
      sections.doc('I.B').get(),
      sections.doc('I.C').get(),
    ]);

    final merged = <String, String>{};
    Uint8List? icImage;

    for (var s in snaps) {
      final data = s.data() ?? {};
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

    try {
      final bytes = await generateDocxWithTextAndImage(
        assetPath: 'assets/templates_compiled.docx',
        textReplacements: merged,
        imagePlaceholder: '\${functionalInterface}',
        imageBytes: icImage,
      );

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'Part_I_ABC',
          bytes: bytes,
          ext: 'docx',
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/Part_I_ABC_${DateTime.now().millisecondsSinceEpoch}.docx';
        await File(path).writeAsBytes(bytes);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $path')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Compile error: $e')));
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
                ],
              ),
              const SizedBox(height: 24),
              if (_isCompiling)
                const CircularProgressIndicator()
              else
                ElevatedButton.icon(
                  onPressed: _compileABC,
                  icon: const Icon(Icons.download),
                  label: const Text('Compile I.A → I.C'),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.black,
                    backgroundColor: Colors.transparent,
                    side: const BorderSide(color: Colors.black),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}