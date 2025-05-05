import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:file_saver/file_saver.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Escapes special XML characters for use in the XML content
String xmlEscape(String input) {
  return input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('\"', '&quot;')
      .replaceAll("'", '&apos;');
}

Future<Uint8List> generateDocxBySearchReplace({
  required String assetPath,
  required Map<String, String> replacements,
}) async {
  final bytes = (await rootBundle.load(assetPath)).buffer.asUint8List();
  final archive = ZipDecoder().decodeBytes(bytes);

  // Pull out the main document XML
  final original = archive.firstWhere((f) => f.name == 'word/document.xml');
  String xmlStr = utf8.decode(original.content as List<int>);

  // Apply every replacement from the provided map
  for (final entry in replacements.entries) {
    xmlStr = xmlStr.replaceAll(entry.key, xmlEscape(entry.value));
  }

  // Build a fresh archive with the updated document.xml
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

class IsspSectionEditor extends StatefulWidget {
  final String sectionId;
  final String sectionTitle;
  final String documentId;
  final VoidCallback onBackPressed;

  const IsspSectionEditor({
    Key? key,
    required this.sectionId,
    required this.sectionTitle,
    required this.documentId,
    required this.onBackPressed,
  }) : super(key: key);

  @override
  _IsspSectionEditorState createState() => _IsspSectionEditorState();
}

class _IsspSectionEditorState extends State<IsspSectionEditor> {
  late QuillController _controller;
  bool _loading = true;
  bool _saving = false;
  bool _isFinalized = false;
  late DocumentReference _sectionRef;

  final User? _currentUser = FirebaseAuth.instance.currentUser;

  String get _userId =>
      _currentUser?.displayName ??
      _currentUser?.email ??
      _currentUser?.uid ??
      'unknown';

  @override
  void initState() {
    super.initState();
    _sectionRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(widget.documentId)
        .collection('sections')
        .doc(widget.sectionId);
    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      final snap = await _sectionRef.get();
      final data = snap.data() as Map<String, dynamic>?;

      if (snap.exists && data != null && data.containsKey('content')) {
        final delta = Delta.fromJson(jsonDecode(data['content'] as String));
        _controller = QuillController(
          document: Document.fromDelta(delta),
          selection: const TextSelection.collapsed(offset: 0),
        );
        _isFinalized = data['isFinalized'] ?? false;
        // Set readOnly based on isFinalized value
        _controller.readOnly = _isFinalized;
      } else {
        _controller = QuillController.basic();
        await _saveContent(initialSave: true);
      }
    } catch (e) {
      _controller = QuillController.basic();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Load error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveContent({bool initialSave = false}) async {
    if (_saving || _isFinalized) return;

    setState(() {
      _saving = true; // Show loading indicator
    });

    try {
      final contentJson = jsonEncode(_controller.document.toDelta().toJson());
      final map = <String, dynamic>{
        'content': contentJson,
        'lastModified': FieldValue.serverTimestamp(),
        'modifiedBy': _userId,
      };

      if (initialSave) {
        map.addAll({
          'sectionId': widget.sectionId,
          'sectionTitle': widget.sectionTitle,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': _userId,
          'isFinalized': false,
        });
      }

      await _sectionRef.set(map, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('issp_documents')
          .doc(widget.documentId)
          .set({
            'sections': {
              widget.sectionId: {
                'lastModified': FieldValue.serverTimestamp(),
                'status': 'in_progress',
              },
            },
            'lastModified': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${widget.sectionTitle} saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false); // Hide loading indicator
    }
  }

  Future<void> _exportDocx() async {
    setState(() => _saving = true);

    try {
      final docname =
          _controller.document.toPlainText().split('\n').first.trim();
      final content = _controller.document.toPlainText();

      final replacements = {
        r'${docname}': docname, // docname placeholder
        r'${content}': content, // content placeholder
      };

      final outBytes = await generateDocxBySearchReplace(
        assetPath: 'assets/templates.docx',
        replacements: replacements,
      );

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: docname,
          bytes: outBytes,
          ext: 'docx',
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final path =
            '${dir.path}/${docname}_${DateTime.now().millisecondsSinceEpoch}.docx';
        await File(path).writeAsBytes(outBytes);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Exported to $path')));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false); // Hide loading indicator
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBackPressed,
          color: Colors.white,
        ),
        title: Text(
          'Editing ${widget.sectionTitle}',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blue[900],
        actions: [
          if (_saving)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Colors.white),
                strokeWidth: 2,
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saving || _isFinalized ? null : () => _saveContent(),
              color: Colors.white,
            ),
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: _exportDocx,
              color: Colors.white,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (!_isFinalized) QuillSimpleToolbar(controller: _controller, config: QuillSimpleToolbarConfig(showAlignmentButtons: !_isFinalized, showBoldButton: !_isFinalized, showItalicButton: !_isFinalized, showUnderLineButton: !_isFinalized)),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                  ),
                ],
              ),
              child: QuillEditor.basic(controller: _controller),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.check),
        onPressed: _saving || _isFinalized ? null : () => _saveContent(),
        // Disable during saving or if finalized
        backgroundColor: Colors.blue[900],
      ),
    );
  }
}
