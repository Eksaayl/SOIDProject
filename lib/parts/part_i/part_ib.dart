import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_saver/file_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;

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

class PartIBFormPage extends StatefulWidget {
  final String documentId;
  const PartIBFormPage({Key? key, required this.documentId})
      : super(key: key);

  @override
  _PartIBFormPageState createState() => _PartIBFormPageState();
}

class _PartIBFormPageState extends State<PartIBFormPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController plannerNameCtl,
      positionCtl,
      unitCtl,
      emailCtl,
      contactCtl;

  late TextEditingController mooeCtl,
      coCtl,
      totalCtl,
      nicthsCtl,
      hsdvCtl,
      hecsCtl;

  late TextEditingController orgStructCtl;

  bool _loading = true, _saving = false, _isFinalized = false;
  late DocumentReference _sectionRef;
  final _user = FirebaseAuth.instance.currentUser;
  String get _userId =>
      _user?.displayName ?? _user?.email ?? _user?.uid ?? 'unknown';

  @override
  void initState() {
    super.initState();
    plannerNameCtl = TextEditingController();
    positionCtl    = TextEditingController();
    unitCtl        = TextEditingController();
    emailCtl       = TextEditingController();
    contactCtl     = TextEditingController();
    mooeCtl        = TextEditingController();
    coCtl          = TextEditingController();
    totalCtl       = TextEditingController();
    nicthsCtl      = TextEditingController();
    hsdvCtl        = TextEditingController();
    hecsCtl        = TextEditingController();
    orgStructCtl   = TextEditingController();

    _sectionRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(widget.documentId)
        .collection('sections')
        .doc('I.B');

    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final snap = await _sectionRef.get();
      final raw  = snap.data() as Map<dynamic, dynamic>? ?? {};
      final data = raw.cast<String, dynamic>();

      plannerNameCtl.text    = data['plannerName']           ?? '';
      positionCtl.text       = data['plantillaPosition']     ?? '';
      unitCtl.text           = data['organizationalUnit']     ?? '';
      emailCtl.text          = data['emailAddress']          ?? '';
      contactCtl.text        = data['contactNumbers']        ?? '';
      mooeCtl.text           = data['mooe']                  ?? '';
      coCtl.text             = data['co']                    ?? '';
      totalCtl.text          = data['total']                 ?? '';
      nicthsCtl.text         = data['nicthsProjectCost']     ?? '';
      hsdvCtl.text           = data['hsdvProjectCost']       ?? '';
      hecsCtl.text           = data['hecsProjectCost']       ?? '';
      orgStructCtl.text      = data['organizationalStructure'] ?? '';

      _isFinalized = data['isFinalized'] == true;
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Load error: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save({bool finalize = false}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final payload = {
      'plannerName'           : plannerNameCtl.text.trim(),
      'plantillaPosition'     : positionCtl.text.trim(),
      'organizationalUnit'    : unitCtl.text.trim(),
      'emailAddress'          : emailCtl.text.trim(),
      'contactNumbers'        : contactCtl.text.trim(),
      'mooe'                  : mooeCtl.text.trim(),
      'co'                    : coCtl.text.trim(),
      'total'                 : totalCtl.text.trim(),
      'nicthsProjectCost'     : nicthsCtl.text.trim(),
      'hsdvProjectCost'       : hsdvCtl.text.trim(),
      'hecsProjectCost'       : hecsCtl.text.trim(),
      'organizationalStructure': orgStructCtl.text.trim(),
      'modifiedBy'            : _userId,
      'lastModified'          : FieldValue.serverTimestamp(),
      'isFinalized'           : finalize || _isFinalized,
    };
    if (!_isFinalized) {
      payload['createdAt'] = FieldValue.serverTimestamp();
      payload['createdBy'] = _userId;
    }

    try {
      await _sectionRef.set(payload, SetOptions(merge: true));
      setState(() => _isFinalized = true);

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved')));
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save error: $e')));
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _compileDocx() async {
    final replacements = <String,String>{
      'plannerName'           : plannerNameCtl.text.trim(),
      'plantillaPosition'     : positionCtl.text.trim(),
      'organizationalUnit'    : unitCtl.text.trim(),
      'emailAddress'          : emailCtl.text.trim(),
      'contactNumbers'        : contactCtl.text.trim(),
      'mooe'                  : mooeCtl.text.trim(),
      'co'                    : coCtl.text.trim(),
      'total'                 : totalCtl.text.trim(),
      'nicthsProjectCost'     : nicthsCtl.text.trim(),
      'hsdvProjectCost'       : hsdvCtl.text.trim(),
      'hecsProjectCost'       : hecsCtl.text.trim(),
      'organizationalStructure': orgStructCtl.text.trim(),
    };

    setState(() => _saving = true);
    try {
      final bytes = await generateDocxBySearchReplace(
        assetPath: 'assets/templates_b.docx',
        replacements: replacements,
      );

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'Part_I.B',
          bytes: bytes,
          ext: 'docx',
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final dir  = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/Part_I.B_${DateTime.now().millisecondsSinceEpoch}.docx';
        await File(path).writeAsBytes(bytes);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Compiled to $path')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Compile error: $e')));
    } finally {
      setState(() => _saving = false);
    }
  }

  Widget _buildCard(String title, TextEditingController ctrl,
      {bool multiline = false}) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            TextFormField(
              controller: ctrl,
              enabled: !_isFinalized,
              maxLines: multiline ? null : 1,
              decoration: InputDecoration(
                filled: !_isFinalized,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? '$title is required'
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text('Part I.A')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Part I.A'),
        actions: [
          IconButton(
            icon: Icon(Icons.save),
            onPressed: _isFinalized ? null : () => _save(finalize: false),
          ),
          IconButton(
            icon: Icon(Icons.check),
            tooltip: 'Finalize',
            onPressed: _isFinalized ? null : () => _save(finalize: true),
          ),
          IconButton(
            icon: Icon(Icons.picture_as_pdf),
            onPressed: _compileDocx,
          ),
        ],
      ),
      body: _isFinalized
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text('This section has been finalized.',
                  style: TextStyle(fontSize: 16, color: Colors.grey)),
            ],
          ),
        ),
      )
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          children: [
            _buildCard('Name of IS Planner', plannerNameCtl),
            _buildCard('Plantilla Position', positionCtl),
            _buildCard('Organizational Unit', unitCtl),
            _buildCard('E-mail Address', emailCtl),
            _buildCard('Contact Number/s', contactCtl),
            Divider(),
            _buildCard('MOOE', mooeCtl),
            _buildCard('CO', coCtl),
            _buildCard('Total', totalCtl),
            _buildCard('NICTHS Project Cost', nicthsCtl),
            _buildCard('HSDV Project Cost', hsdvCtl),
            _buildCard('HECS Project Cost', hecsCtl),
            Divider(),
            _buildCard('Organizational Structure', orgStructCtl, multiline: true),
            const SizedBox(height: 16),
          ],
        ),
      ),
      floatingActionButton: _isFinalized
          ? null
          : FloatingActionButton(
        child: Icon(Icons.save),
        onPressed: () => _save(finalize: false),
      ),
    );
  }

  @override
  void dispose() {
    plannerNameCtl.dispose();
    positionCtl.dispose();
    unitCtl.dispose();
    emailCtl.dispose();
    contactCtl.dispose();
    mooeCtl.dispose();
    coCtl.dispose();
    totalCtl.dispose();
    nicthsCtl.dispose();
    hsdvCtl.dispose();
    hecsCtl.dispose();
    orgStructCtl.dispose();
    super.dispose();
  }
}
