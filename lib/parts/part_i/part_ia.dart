// (Full PartIAFormPage code without Quill integration)
// This is the pre-Quill version using only TextEditingController for functionsSub

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
  final bytes = (await rootBundle.load(assetPath)).buffer.asUint8List();
  final archive = ZipDecoder().decodeBytes(bytes);
  final docFile = archive.firstWhere((f) => f.name == 'word/document.xml');
  String xmlStr = utf8.decode(docFile.content as List<int>);

  final pattern = RegExp(r'\$\{(.+?)\}');
  final allKeys = pattern.allMatches(xmlStr).map((m) => m.group(1)!).toSet();

  final complete = <String, String>{
    for (var key in allKeys) '\${$key}': replacements[key] ?? '',
  };

  complete.forEach((ph, val) {
    xmlStr = xmlStr.replaceAll(ph, xmlEscape(val));
  });

  final newArchive = Archive();
  for (final file in archive) {
    if (file.name == 'word/document.xml') {
      final data = utf8.encode(xmlStr);
      newArchive.addFile(ArchiveFile(file.name, data.length, data));
    } else {
      newArchive.addFile(file);
    }
  }

  final out = ZipEncoder().encode(newArchive)!;
  return Uint8List.fromList(out);
}

class PartIAFormPage extends StatefulWidget {
  final String documentId;
  const PartIAFormPage({Key? key, required this.documentId}) : super(key: key);
  @override
  _PartIAFormPageState createState() => _PartIAFormPageState();
}

class _PartIAFormPageState extends State<PartIAFormPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController docNameCtrl;
  late TextEditingController legalBasisCtrl;
  late TextEditingController functionsSubCtrl;
  late TextEditingController visionCtrl;
  late TextEditingController missionCtrl;
  late TextEditingController pillar1Ctrl;
  late TextEditingController pillar2Ctrl;
  late TextEditingController pillar3Ctrl;

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
    docNameCtrl = TextEditingController();
    legalBasisCtrl = TextEditingController();
    functionsSubCtrl = TextEditingController();
    visionCtrl = TextEditingController();
    missionCtrl = TextEditingController();
    pillar1Ctrl = TextEditingController();
    pillar2Ctrl = TextEditingController();
    pillar3Ctrl = TextEditingController();

    _sectionRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(widget.documentId)
        .collection('sections')
        .doc('I.A');

    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      final snap = await _sectionRef.get();
      final data = snap.data() as Map<String, dynamic>? ?? {};

      docNameCtrl.text = data['documentName'] ?? '';
      legalBasisCtrl.text = data['legalBasis'] ?? '';
      functionsSubCtrl.text = data['functionsSub'] ?? '';
      visionCtrl.text = data['visionStatement'] ?? '';
      missionCtrl.text = data['missionStatement'] ?? '';
      pillar1Ctrl.text = data['pillar1'] ?? '';
      pillar2Ctrl.text = data['pillar2'] ?? '';
      pillar3Ctrl.text = data['pillar3'] ?? '';
      _isFinal = data['isFinalized'] == true;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Load error: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save({bool finalize = false}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final payload = {
      'documentName': docNameCtrl.text.trim(),
      'legalBasis': legalBasisCtrl.text.trim(),
      'functionsSub': functionsSubCtrl.text.trim(),
      'visionStatement': visionCtrl.text.trim(),
      'missionStatement': missionCtrl.text.trim(),
      'pillar1': pillar1Ctrl.text.trim(),
      'pillar2': pillar2Ctrl.text.trim(),
      'pillar3': pillar3Ctrl.text.trim(),
      'modifiedBy': _userId,
      'lastModified': FieldValue.serverTimestamp(),
      'isFinalized': finalize || _isFinal,
    };

    if (!_isFinal) {
      payload['createdAt'] = FieldValue.serverTimestamp();
      payload['createdBy'] = _userId;
    }

    try {
      await _sectionRef.set(payload, SetOptions(merge: true));
      setState(() => _isFinal = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved')));
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save error: $e')));
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _compileDocx() async {
    setState(() => _compiling = true);

    final map = {
      'documentName': docNameCtrl.text.trim(),
      'legalBasis': legalBasisCtrl.text.trim(),
      'functionsSub': functionsSubCtrl.text.trim(),
      'visionStatement': visionCtrl.text.trim(),
      'missionStatement': missionCtrl.text.trim(),
      'pillar1': pillar1Ctrl.text.trim(),
      'pillar2': pillar2Ctrl.text.trim(),
      'pillar3': pillar3Ctrl.text.trim(),
    };

    try {
      final bytes = await generateDocxBySearchReplace(
        assetPath: 'assets/templates.docx',
        replacements: map,
      );

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'Part_I.A',
          bytes: bytes,
          ext: 'docx',
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/Part_I.A_${DateTime.now().millisecondsSinceEpoch}.docx';
        await File(path).writeAsBytes(bytes);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Compiled to $path')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Compile error: $e')));
    } finally {
      setState(() => _compiling = false);
    }
  }

  Widget _buildField(String label, TextEditingController ctrl, {bool multiline = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: ctrl,
        enabled: !_isFinal,
        maxLines: multiline ? null : 1,
        decoration: InputDecoration(labelText: label, border: OutlineInputBorder()),
        validator: (v) => v == null || v.trim().isEmpty ? '$label is required' : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Part I.A'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _isFinal ? null : () => _save(finalize: false),
            ),
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Finalize',
              onPressed: _isFinal ? null : () => _save(finalize: true),
            ),
            if (_compiling)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(Icons.picture_as_pdf),
                onPressed: _compileDocx,
              ),
          ]
        ],
      ),
      body: _isFinal
          ? Center(child: Text('Section finalized', style: TextStyle(color: Colors.grey)))
          : Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              _buildField('Document Name', docNameCtrl),
              _buildField('Legal Basis', legalBasisCtrl),
              _buildField('Functions', functionsSubCtrl, multiline: true),
              _buildField('Vision Statement', visionCtrl),
              _buildField('Mission Statement', missionCtrl),
              _buildField('Pillar 1', pillar1Ctrl),
              _buildField('Pillar 2', pillar2Ctrl),
              _buildField('Pillar 3', pillar3Ctrl),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    docNameCtrl.dispose();
    legalBasisCtrl.dispose();
    functionsSubCtrl.dispose();
    visionCtrl.dispose();
    missionCtrl.dispose();
    pillar1Ctrl.dispose();
    pillar2Ctrl.dispose();
    pillar3Ctrl.dispose();
    super.dispose();
  }
}
