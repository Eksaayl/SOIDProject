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
import 'package:flutter_quill/flutter_quill.dart' hide Text;
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
  print('Loading template from: $assetPath');
  final bytes = (await rootBundle.load(assetPath)).buffer.asUint8List();
  print('Template file size: ${bytes.length} bytes');

  final archive = ZipDecoder().decodeBytes(bytes);
  final docFile = archive.firstWhere((f) => f.name == 'word/document.xml');
  String xmlStr = utf8.decode(docFile.content as List<int>);

  print('Original XML content (first 500 chars):');
  print(xmlStr.substring(0, xmlStr.length > 500 ? 500 : xmlStr.length));

  // First, clean up the XML by removing Word's internal tags within placeholders
  final cleanXml = xmlStr.replaceAllMapped(
    RegExp(r'\$\{.*?\}', multiLine: true, dotAll: true),
    (match) {
      String placeholder = match.group(0)!;
      // Remove all XML tags within the placeholder
      placeholder = placeholder.replaceAll(RegExp(r'<[^>]+>'), '');
      // Remove any extra whitespace
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
    for (var key in allKeys) '\${$key}': replacements[key] ?? '',
  };

  print('Final replacements map: $complete');

  String finalXml = cleanXml;
  complete.forEach((ph, val) {
    String processedValue = val;

    // Special handling for placeholders with multiple items
    if (ph == '\${strategicChallenges}' && val.contains('•')) {
      // Count the number of bullet points to determine if there are multiple items
      final bulletCount = '•'.allMatches(val).length;
      if (bulletCount > 1) {
        // Format with proper Word XML paragraph breaks between bullet points
        processedValue = val.replaceAll('\n\n', '\n\n\n');
      }
    }

    print(
      'Replacing $ph with ${processedValue.length > 50 ? "${processedValue.substring(0, 50)}..." : processedValue}',
    );
    finalXml = finalXml.replaceAll(ph, xmlEscape(processedValue));
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

class PartIDFormPage extends StatefulWidget {
  final String documentId;
  const PartIDFormPage({Key? key, required this.documentId}) : super(key: key);
  @override
  _PartIDFormPageState createState() => _PartIDFormPageState();
}

class _PartIDFormPageState extends State<PartIDFormPage> {
  final _formKey = GlobalKey<FormState>();

  // List to manage multiple challenge editors
  final List<QuillController> challengeControllers = [];
  late TextEditingController challengesIntroCtrl;

  bool _loading = true;
  bool _saving = false;
  bool _isFinalized = false;
  bool _compiling = false;

  late DocumentReference _sectionRef;
  final _user = FirebaseAuth.instance.currentUser;
  String get _userId =>
      _user?.displayName ?? _user?.email ?? _user?.uid ?? 'unknown';

  void _addNewChallengeSection() {
    challengeControllers.add(QuillController.basic());
    if (mounted) setState(() {});
  }

  void _removeChallengeSection(int index) {
    if (index < challengeControllers.length) {
      challengeControllers[index].dispose();
      challengeControllers.removeAt(index);
      if (mounted) setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    challengesIntroCtrl = TextEditingController();
    // Initialize with one empty challenge section
    _addNewChallengeSection();

    _sectionRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(widget.documentId)
        .collection('sections')
        .doc('I.D');

    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final snap = await _sectionRef.get();
      final data = snap.data() as Map<String, dynamic>? ?? {};

      challengesIntroCtrl.text = data['challengesIntro'] ?? '';
      // Clear existing controllers
      for (var controller in challengeControllers) {
        controller.dispose();
      }
      challengeControllers.clear();

      if (data['challenges'] != null) {
        try {
          final List<dynamic> challenges = jsonDecode(data['challenges']);
          for (var challenge in challenges) {
            final controller = QuillController(
              document: Document.fromJson(challenge),
              selection: const TextSelection.collapsed(offset: 0),
            );
            challengeControllers.add(controller);
          }
        } catch (e) {
          // If loading fails, start with one empty section
          _addNewChallengeSection();
        }
      } else {
        // If no data, start with one empty section
        _addNewChallengeSection();
      }

      _isFinalized = data['isFinalized'] == true;
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Load error: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save({bool finalize = false}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final payload = {
        'challenges': jsonEncode(
          challengeControllers
              .map((ctrl) => ctrl.document.toDelta().toJson())
              .toList(),
        ),
        'challengesIntro': challengesIntroCtrl.text,
        'modifiedBy': _userId,
        'lastModified': FieldValue.serverTimestamp(),
        'isFinalized': finalize || _isFinalized,
      };

      if (!_isFinalized) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdBy'] = _userId;
      }

      await _sectionRef.set(payload, SetOptions(merge: true));
      setState(() => _isFinalized = finalize);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(finalize ? 'Finalized' : 'Saved')));

      if (finalize) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save error: $e')));
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _compileDocx() async {
    setState(() => _compiling = true);
    try {
      final sb = StringBuffer();

      for (var controller in challengeControllers) {
        final text = controller.document.toPlainText().trim();
        if (text.isNotEmpty) {
          sb.writeln('• $text');
        }
      }

      final processedText = sb
          .toString()
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .join('\n\n');

      final replacements = {'strategicChallenges': processedText};

      final bytes = await generateDocxBySearchReplace(
        assetPath: 'assets/templates_d.docx',
        replacements: replacements,
      );

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'Part_I.D',
          bytes: bytes,
          ext: 'docx',
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final path =
            '${dir.path}/Part_I.D_${DateTime.now().millisecondsSinceEpoch}.docx';
        await File(path).writeAsBytes(bytes);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Compiled to $path')));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Compile error: $e')));
    } finally {
      setState(() => _compiling = false);
    }
  }

  void _showHtmlPreview() {
    final html = buildPartIDPreviewHtml(
      challengesIntro: challengesIntroCtrl.text,
      challenges: challengeControllers.map((c) => c.document.toPlainText().trim()).where((t) => t.isNotEmpty).toList(),
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HtmlPreviewPageID(html: html)),
    );
  }

  Widget _buildChallengesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '1. Strategic Challenges',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ...challengeControllers.asMap().entries.map((entry) {
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
                        child: Text(
                          'Challenge ${index + 1}',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                    if (!_isFinalized && challengeControllers.length > 1)
                      IconButton(
                        icon: Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeChallengeSection(index),
                      ),
                  ],
                ),
                Container(
                  height: 100, // Smaller height since it's per challenge
                  padding: const EdgeInsets.all(8),
                  child: QuillEditor.basic(controller: controller),
                ),
              ],
            ),
          );
        }).toList(),
        if (!_isFinalized)
          Center(
            child: ElevatedButton.icon(
              icon: Icon(Icons.add),
              label: Text('Add Challenge'),
              onPressed: _addNewChallengeSection,
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

  Widget _buildField(String label, TextEditingController ctrl, {bool multiline = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: ctrl,
        enabled: !_isFinalized,
        maxLines: multiline ? null : 1,
        decoration: InputDecoration(labelText: label, border: OutlineInputBorder()),
        validator: (v) => v == null || v.trim().isEmpty ? '$label is required' : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Part I.D - Strategic Challenges'),
        actions: [
          if (_saving || _compiling)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _isFinalized ? null : () => _save(finalize: false),
            ),
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Finalize',
              onPressed: _isFinalized ? null : () => _save(finalize: true),
            ),
            IconButton(
              icon: const Icon(Icons.file_download),
              onPressed: _compiling ? null : _compileDocx,
            ),
            IconButton(
              icon: const Icon(Icons.remove_red_eye),
              tooltip: 'Preview as HTML',
              onPressed: _showHtmlPreview,
            ),
          ]
        ],
      ),
      body:
          _isFinalized
              ? Center(
                child: Text(
                  'Section finalized',
                  style: TextStyle(color: Colors.grey),
                ),
              )
              : SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildField('Challenges Introduction', challengesIntroCtrl, multiline: true),
                        _buildChallengesSection(),
                      ],
                    ),
                  ),
                ),
              ),
    );
  }

  @override
  void dispose() {
    challengesIntroCtrl.dispose();
    for (var controller in challengeControllers) {
      controller.dispose();
    }
    super.dispose();
  }
}

class HtmlPreviewPageID extends StatelessWidget {
  final String html;
  const HtmlPreviewPageID({required this.html, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Preview')),
      body: SingleChildScrollView(child: Html(data: html)),
    );
  }
}

String buildPartIDPreviewHtml({
  required String challengesIntro,
  required List<String> challenges,
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
          <div class="section-title">Challenges Introduction</div>
          <div class="value">$challengesIntro</div>
        </div>
        <div class="card">
          <div class="section-title">Strategic Challenges</div>
          <ul>
            ${challenges.map((c) => '<li>${c.replaceAll('\n', '<br>')}</li>').join()}
          </ul>
        </div>
      </div>
    </body>
  </html>
  ''';
}
