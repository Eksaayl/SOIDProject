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
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_html/flutter_html.dart';

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

String buildPartIAPreviewHtml({
  required String documentName,
  required String legalBasis,
  required List<String> functions,
  required String vision,
  required String mission,
  required String pillar1,
  required String pillar2,
  required String pillar3,
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
          max-width: 700px;
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
        ul {
          margin: 0 0 0 24px;
          padding: 0;
        }
        li {
          margin-bottom: 6px;
          font-size: 1.05em;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="card">
          <div class="section-title">Document Name</div>
          <div class="value">$documentName</div>
        </div>
        <div class="card">
          <div class="section-title">Legal Basis</div>
          <div class="value">$legalBasis</div>
        </div>
        <div class="card">
          <div class="section-title">Functions</div>
          <ul>
            ${functions.map((f) => '<li>${f.replaceAll('\n', '<br>')}</li>').join()}
          </ul>
        </div>
        <div class="card">
          <div class="section-title">Vision Statement</div>
          <div class="value">$vision</div>
        </div>
        <div class="card">
          <div class="section-title">Mission Statement</div>
          <div class="value">$mission</div>
        </div>
        <div class="card">
          <div class="section-title">Pillar 1</div>
          <div class="value">$pillar1</div>
        </div>
        <div class="card">
          <div class="section-title">Pillar 2</div>
          <div class="value">$pillar2</div>
        </div>
        <div class="card">
          <div class="section-title">Pillar 3</div>
          <div class="value">$pillar3</div>
        </div>
      </div>
    </body>
  </html>
  ''';
}

class HtmlPreviewPage extends StatelessWidget {
  final String html;
  const HtmlPreviewPage({required this.html, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Preview')),
      body: SingleChildScrollView(child: Html(data: html)),
    );
  }
}

class PartIAFormPage extends StatefulWidget {
  final String documentId;
  const PartIAFormPage({Key? key, required this.documentId}) : super(key: key);
  @override
  _PartIAFormPageState createState() => _PartIAFormPageState();
}

class _PartIAFormPageState extends State<PartIAFormPage> {
  final _formKey = GlobalKey<FormState>();

  // List to manage multiple function editors
  final List<QuillController> functionControllers = [];
  
  late TextEditingController docNameCtrl;
  late TextEditingController legalBasisCtrl;
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
  String get _userId => 'temporary_user'; // Temporary user ID

  void _addNewFunctionEditor() {
    functionControllers.add(QuillController.basic());
    if (mounted) setState(() {});
  }

  void _removeFunctionEditor(int index) {
    if (index < functionControllers.length) {
      functionControllers[index].dispose();
      functionControllers.removeAt(index);
      if (mounted) setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    docNameCtrl = TextEditingController();
    legalBasisCtrl = TextEditingController();
    visionCtrl = TextEditingController();
    missionCtrl = TextEditingController();
    pillar1Ctrl = TextEditingController();
    pillar2Ctrl = TextEditingController();
    pillar3Ctrl = TextEditingController();

    // Initialize with one empty function editor
    _addNewFunctionEditor();

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
      
      // Clear existing controllers
      for (var controller in functionControllers) {
        controller.dispose();
      }
      functionControllers.clear();
      
      if (data['functions'] != null) {
        try {
          final List<dynamic> functions = jsonDecode(data['functions']);
          for (var function in functions) {
            final controller = QuillController(
              document: Document.fromJson(function),
              selection: const TextSelection.collapsed(offset: 0),
            );
            functionControllers.add(controller);
          }
        } catch (e) {
          // If loading fails, start with one empty editor
          _addNewFunctionEditor();
        }
      } else {
        // If no data, start with one empty editor
        _addNewFunctionEditor();
      }

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
      'functions': jsonEncode(
        functionControllers.map((ctrl) => ctrl.document.toDelta().toJson()).toList()
      ),
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

    try {
      // Create formatted text with bullet points
      final sb = StringBuffer();
      
      for (var controller in functionControllers) {
        final text = controller.document.toPlainText().trim();
        if (text.isNotEmpty) {
          sb.writeln('• $text');
          sb.writeln(); // Add an extra line break after each bullet point
        }
      }
      
      final map = {
        'documentName': docNameCtrl.text.trim(),
        'legalBasis': legalBasisCtrl.text.trim(),
        'functions': sb.toString().trim(),
        'visionStatement': visionCtrl.text.trim(),
        'missionStatement': missionCtrl.text.trim(),
        'pillar1': pillar1Ctrl.text.trim(),
        'pillar2': pillar2Ctrl.text.trim(),
        'pillar3': pillar3Ctrl.text.trim(),
      };

      // Generate document
      final bytes = await generateDocxBySearchReplace(
        assetPath: 'assets/templates.docx',
        replacements: map,
      );

      // Save the document
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
    final html = buildPartIAPreviewHtml(
      documentName: docNameCtrl.text,
      legalBasis: legalBasisCtrl.text,
      functions: functionControllers.map((c) => c.document.toPlainText().trim()).where((t) => t.isNotEmpty).toList(),
      vision: visionCtrl.text,
      mission: missionCtrl.text,
      pillar1: pillar1Ctrl.text,
      pillar2: pillar2Ctrl.text,
      pillar3: pillar3Ctrl.text,
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HtmlPreviewPage(html: html)),
    );
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

  Widget _buildFunctionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Functions', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...functionControllers.asMap().entries.map((entry) {
          final index = entry.key;
          final controller = entry.value;
          
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text('Function ${index + 1}', 
                          style: TextStyle(fontWeight: FontWeight.w500)),
                      ),
                    ),
                    if (!_isFinal && functionControllers.length > 1)
                      IconButton(
                        icon: Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeFunctionEditor(index),
                      ),
                  ],
                ),
                Container(
                  height: 100,  // Smaller height since it's per function
                  padding: const EdgeInsets.all(8),
                  child: QuillEditor.basic(
                    controller: controller,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        if (!_isFinal)
          Center(
            child: ElevatedButton.icon(
              icon: Icon(Icons.add),
              label: Text('Add Function'),
              onPressed: _addNewFunctionEditor,
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.blue,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ),
      ],
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
        title: const Text('Part I.A - Mandate and Functions'),
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
                icon: const Icon(Icons.file_download),
                onPressed: _compileDocx,
              ),
            IconButton(
              icon: const Icon(Icons.remove_red_eye),
              tooltip: 'Preview as HTML',
              onPressed: _showHtmlPreview,
            ),
          ]
        ],
      ),
      body: _isFinal
          ? Center(child: Text('Section finalized', style: TextStyle(color: Colors.grey)))
          : SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildField('Document Name', docNameCtrl),
                      _buildField('Legal Basis', legalBasisCtrl),
                      const SizedBox(height: 16),
                      _buildFunctionsSection(),
                      const SizedBox(height: 16),
                      _buildField('Vision Statement', visionCtrl),
                      _buildField('Mission Statement', missionCtrl),
                      _buildField('Pillar 1', pillar1Ctrl),
                      _buildField('Pillar 2', pillar2Ctrl),
                      _buildField('Pillar 3', pillar3Ctrl),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    docNameCtrl.dispose();
    legalBasisCtrl.dispose();
    for (var controller in functionControllers) {
      controller.dispose();
    }
    visionCtrl.dispose();
    missionCtrl.dispose();
    pillar1Ctrl.dispose();
    pillar2Ctrl.dispose();
    pillar3Ctrl.dispose();
    super.dispose();
  }
}








