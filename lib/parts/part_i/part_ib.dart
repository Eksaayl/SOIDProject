import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_saver/file_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_quill/flutter_quill.dart' hide Text;
import 'package:flutter_quill/quill_delta.dart';
import 'package:intl/intl.dart';
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

Future<Uint8List> generateDocxWithImage({
  required String assetPath,
  required String placeholder,
  required Uint8List imageBytes,
  required Map<String, String> replacements,
}) async {
  final bytes = (await rootBundle.load(assetPath)).buffer.asUint8List();
  final archive = ZipDecoder().decodeBytes(bytes);

  // Add the image to the archive
  const imagePath = 'word/media/image1.png';
  archive.addFile(ArchiveFile(imagePath, imageBytes.length, imageBytes));

  // Update relationships
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

  // Update document XML
  final doc = archive.firstWhere((f) => f.name == 'word/document.xml');
  var docXml = utf8.decode(doc.content as List<int>);
  
  print('Original XML content:');
  print(docXml.substring(0, min(500, docXml.length)));  // Print first 500 chars
  
  // Replace text placeholders
  final pattern = RegExp(r'\$\{(.+?)\}');
  final allKeys = pattern.allMatches(docXml).map((m) => m.group(1)!).toSet();

  print('\nFound placeholders:');
  print(allKeys.join(', '));

  final complete = <String, String>{
    for (var key in allKeys) '\${$key}': replacements[key] ?? '',
  };

  print('\nReplacement map:');
  replacements.forEach((key, value) {
    print('$key: $value');
  });

  complete.forEach((ph, val) {
    if (ph != placeholder) {  // Skip the image placeholder
      docXml = docXml.replaceAll(ph, xmlEscape(val));
    }
  });

  print('\nModified XML content:');
  print(docXml.substring(0, min(500, docXml.length)));  // Print first 500 chars

  // Replace image placeholder
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

class PartIBFormPage extends StatefulWidget {
  final String documentId;
  const PartIBFormPage({Key? key, required this.documentId})
      : super(key: key);

  @override
  _PartIBFormPageState createState() => _PartIBFormPageState();
}

class _PartIBFormPageState extends State<PartIBFormPage> {
  final _formKey = GlobalKey<FormState>();
  Uint8List? _orgStructureImage;
  
  // List to manage multiple function editors
  final List<QuillController> functionControllers = [];

  // Personnel Complement Controllers
  late TextEditingController totalEmployeesCtl,
      regionalOfficesCtl,
      provincialOfficesCtl,
      otherOfficesCtl;
  
  // Central Office Controllers
  late TextEditingController coPlantilaCtl,
      coVacantCtl,
      coFilledPlantilaCtl,
      coFilledPhysicalCtl,
      coCoswsCtl,
      coContractualCtl,
      coTotalCtl;

  // Field Office Controllers
  late TextEditingController foPlantilaCtl,
      foVacantCtl,
      foFilledPlantilaCtl,
      foFilledPhysicalCtl,
      foCoswsCtl,
      foContractualCtl,
      foTotalCtl;

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

  bool _loading = true, _saving = false, _isFinalized = false;
  late DocumentReference _sectionRef;
  final _user = FirebaseAuth.instance.currentUser;
  String get _userId =>
      _user?.displayName ?? _user?.email ?? _user?.uid ?? 'unknown';

  bool _compiling = false;

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

    // Initialize Personnel Complement Controllers
    totalEmployeesCtl = TextEditingController();
    regionalOfficesCtl = TextEditingController();
    provincialOfficesCtl = TextEditingController();
    otherOfficesCtl = TextEditingController();

    // Initialize Central Office Controllers
    coPlantilaCtl = TextEditingController();
    coVacantCtl = TextEditingController();
    coFilledPlantilaCtl = TextEditingController();
    coFilledPhysicalCtl = TextEditingController();
    coCoswsCtl = TextEditingController();
    coContractualCtl = TextEditingController();
    coTotalCtl = TextEditingController();

    // Initialize Field Office Controllers
    foPlantilaCtl = TextEditingController();
    foVacantCtl = TextEditingController();
    foFilledPlantilaCtl = TextEditingController();
    foFilledPhysicalCtl = TextEditingController();
    foCoswsCtl = TextEditingController();
    foContractualCtl = TextEditingController();
    foTotalCtl = TextEditingController();

    // Initialize with one empty function editor
    _addNewFunctionEditor();

    _sectionRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(widget.documentId)
        .collection('sections')
        .doc('I.B');

    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      _sectionRef = FirebaseFirestore.instance
          .collection('issp_documents')
          .doc(widget.documentId)
          .collection('sections')
          .doc('I.B');

      final doc = await _sectionRef.get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _isFinalized = data['isFinalized'] ?? false;
          
          // Load Personnel Complement Data
          totalEmployeesCtl.text = data['totalEmployees'] ?? '';
          regionalOfficesCtl.text = data['regionalOffices'] ?? '';
          provincialOfficesCtl.text = data['provincialOffices'] ?? '';
          otherOfficesCtl.text = data['otherOffices'] ?? '';
          
          // Load Central Office Data
          coPlantilaCtl.text = data['coPlantilaPositions'] ?? '';
          coVacantCtl.text = data['coVacant'] ?? '';
          coFilledPlantilaCtl.text = data['coFilledPlantilaPositions'] ?? '';
          coFilledPhysicalCtl.text = data['coFilledPhysicalPositions'] ?? '';
          coCoswsCtl.text = data['coCosws'] ?? '';
          coContractualCtl.text = data['coContractual'] ?? '';
          coTotalCtl.text = data['coTotal'] ?? '';
          
          // Load Field Office Data
          foPlantilaCtl.text = data['foPlantilaPositions'] ?? '';
          foVacantCtl.text = data['foVacant'] ?? '';
          foFilledPlantilaCtl.text = data['foFilledPlantilaPositions'] ?? '';
          foFilledPhysicalCtl.text = data['foFilledPhysicalPositions'] ?? '';
          foCoswsCtl.text = data['foCosws'] ?? '';
          foContractualCtl.text = data['foContractual'] ?? '';
          foTotalCtl.text = data['foTotal'] ?? '';

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

          final orgStructB64 = data['organizationalStructure'] as String?;
          if (orgStructB64 != null) {
            _orgStructureImage = base64Decode(orgStructB64);
          }

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
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading data: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickOrgStructureImage() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x != null) {
      final bytes = await x.readAsBytes();
      setState(() => _orgStructureImage = bytes);
    }
  }

  Future<void> _saveData({bool finalize = false}) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      // Update _isFinalized state if finalizing
      if (finalize) {
        setState(() => _isFinalized = true);
      }
      
      await _sectionRef.set({
        // Personnel Complement Data
        'totalEmployees': totalEmployeesCtl.text,
        'regionalOffices': regionalOfficesCtl.text,
        'provincialOffices': provincialOfficesCtl.text,
        'otherOffices': otherOfficesCtl.text,
        
        // Central Office Data
        'coPlantilaPositions': coPlantilaCtl.text,
        'coVacant': coVacantCtl.text,
        'coFilledPlantilaPositions': coFilledPlantilaCtl.text,
        'coFilledPhysicalPositions': coFilledPhysicalCtl.text,
        'coCosws': coCoswsCtl.text,
        'coContractual': coContractualCtl.text,
        'coTotal': coTotalCtl.text,
        
        // Field Office Data
        'foPlantilaPositions': foPlantilaCtl.text,
        'foVacant': foVacantCtl.text,
        'foFilledPlantilaPositions': foFilledPlantilaCtl.text,
        'foFilledPhysicalPositions': foFilledPhysicalCtl.text,
        'foCosws': foCoswsCtl.text,
        'foContractual': foContractualCtl.text,
        'foTotal': foTotalCtl.text,

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
        'organizationalStructure': _orgStructureImage != null ? base64Encode(_orgStructureImage!) : null,
        'functions': jsonEncode(
          functionControllers.map((ctrl) => ctrl.document.toDelta().toJson()).toList()
        ),
        'modifiedBy': _userId,
        'lastModified': FieldValue.serverTimestamp(),
        'isFinalized': finalize || _isFinalized, // Use finalize parameter or existing state
      }, SetOptions(merge: true));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(finalize ? 'Data finalized successfully' : 'Data saved successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving data: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _compileDocx() async {
    if (_orgStructureImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please upload an organizational structure image first'))
      );
      return;
    }

    setState(() => _compiling = true);
    try {
      // First try to load the template to verify it exists
      try {
        await rootBundle.load('assets/templates_b.docx');
      } catch (e) {
        throw Exception('Failed to load template file: $e\nMake sure assets/templates_b.docx exists and is properly included in pubspec.yaml');
      }

      // Format numbers for table display
      String formatNumber(String value) {
        if (value.isEmpty) return '0';
        try {
          return NumberFormat('#,##0').format(int.parse(value.replaceAll(',', '')));
        } catch (e) {
          return value;
        }
      }

      final replacements = <String,String>{
        // Basic Information
        'plannerName'           : plannerNameCtl.text.trim(),
        'plantillaPosition'     : positionCtl.text.trim(),
        'organizationalUnit'    : unitCtl.text.trim(),
        'emailAddress'          : emailCtl.text.trim(),
        'contactNumbers'        : contactCtl.text.trim(),
        
        // Personnel Complement
        'totalEmployees'        : formatNumber(totalEmployeesCtl.text),
        'regionalOffices'       : formatNumber(regionalOfficesCtl.text),
        'provincialOffices'     : formatNumber(provincialOfficesCtl.text),
        'otherOffices'         : otherOfficesCtl.text.trim(),

        // Central Office Data
        'coPlantilaPositions'   : formatNumber(coPlantilaCtl.text),
        'coVacant'             : formatNumber(coVacantCtl.text),
        'coFilledPlantilaPositions': formatNumber(coFilledPlantilaCtl.text),
        'coFilledPhysicalPositions': formatNumber(coFilledPhysicalCtl.text),
        'coCosws'              : formatNumber(coCoswsCtl.text),
        'coContractual'        : formatNumber(coContractualCtl.text),
        'coTotal'              : formatNumber(coTotalCtl.text),

        // Field Office Data
        'foPlantilaPositions'   : formatNumber(foPlantilaCtl.text),
        'foVacant'             : formatNumber(foVacantCtl.text),
        'foFilledPlantilaPositions': formatNumber(foFilledPlantilaCtl.text),
        'foFilledPhysicalPositions': formatNumber(foFilledPhysicalCtl.text),
        'foCosws'              : formatNumber(foCoswsCtl.text),
        'foContractual'        : formatNumber(foContractualCtl.text),
        'foTotal'              : formatNumber(foTotalCtl.text),

        // Project Costs
        'mooe'                  : formatNumber(mooeCtl.text),
        'co'                    : formatNumber(coCtl.text),
        'total'                 : formatNumber(totalCtl.text),
        'nicthsProjectCost'     : formatNumber(nicthsCtl.text),
        'hsdvProjectCost'       : formatNumber(hsdvCtl.text),
        'hecsProjectCost'       : formatNumber(hecsCtl.text),
      };

      // Try to generate the document with detailed error handling
      final bytes = await generateDocxWithImage(
        assetPath: 'assets/templates_b.docx',
        placeholder: r'${organizationalStructure}',
        imageBytes: _orgStructureImage!,
        replacements: replacements,
      ).catchError((error) {
        print('Document generation error: $error');
        throw Exception('Failed to generate document: $error');
      });

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'Part_I.B',
          bytes: bytes,
          ext: 'docx',
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/Part_I.B_${DateTime.now().millisecondsSinceEpoch}.docx';
        await File(path).writeAsBytes(bytes);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Compiled to $path')));
      }
    } catch (e) {
      print('Error details: $e');  // Print error details to console for debugging
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(
            content: Text('Compile error: ${e.toString()}'),
            duration: Duration(seconds: 5),  // Show error longer
          ));
    } finally {
      setState(() => _compiling = false);
    }
  }

  void _showHtmlPreview() {
    final html = buildPartIBPreviewHtml(
      plannerName: plannerNameCtl.text,
      plantillaPosition: positionCtl.text,
      organizationalUnit: unitCtl.text,
      emailAddress: emailCtl.text,
      contactNumbers: contactCtl.text,
      functions: functionControllers.map((c) => c.document.toPlainText().trim()).where((t) => t.isNotEmpty).toList(),
      totalEmployees: totalEmployeesCtl.text,
      regionalOffices: regionalOfficesCtl.text,
      provincialOffices: provincialOfficesCtl.text,
      otherOffices: otherOfficesCtl.text,
      coPlantilaPositions: coPlantilaCtl.text,
      coVacant: coVacantCtl.text,
      coFilledPlantilaPositions: coFilledPlantilaCtl.text,
      coFilledPhysicalPositions: coFilledPhysicalCtl.text,
      coCosws: coCoswsCtl.text,
      coContractual: coContractualCtl.text,
      coTotal: coTotalCtl.text,
      foPlantilaPositions: foPlantilaCtl.text,
      foVacant: foVacantCtl.text,
      foFilledPlantilaPositions: foFilledPlantilaCtl.text,
      foFilledPhysicalPositions: foFilledPhysicalCtl.text,
      foCosws: foCoswsCtl.text,
      foContractual: foContractualCtl.text,
      foTotal: foTotalCtl.text,
      mooe: mooeCtl.text,
      co: coCtl.text,
      total: totalCtl.text,
      nicthsProjectCost: nicthsCtl.text,
      hsdvProjectCost: hsdvCtl.text,
      hecsProjectCost: hecsCtl.text,
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HtmlPreviewPageIB(html: html)),
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

  Widget _buildFunctionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Functions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...functionControllers.asMap().entries.map((entry) {
          final index = entry.key;
          final controller = entry.value;
          
          return _buildFunctionEditor(controller, index);
        }).toList(),
        if (!_isFinalized)
          Center(
            child: ElevatedButton.icon(
              icon: Icon(Icons.add),
              label: Text('Add Function'),
              onPressed: _addNewFunctionEditor,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFunctionEditor(QuillController controller, int index) {
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
              if (!_isFinalized && functionControllers.length > 1)
                IconButton(
                  icon: Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _removeFunctionEditor(index),
                ),
            ],
          ),
          if (!_isFinalized)
            Container(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: QuillSimpleToolbar(
                      controller: controller,
                      config: QuillSimpleToolbarConfig(
                        showBoldButton: true,
                        showItalicButton: true,
                        showUnderLineButton: true,
                        showListBullets: true,
                        showListNumbers: true,
                        showHeaderStyle: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 100,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: QuillEditor(
                      controller: controller,
                      focusNode: FocusNode(),
                      scrollController: ScrollController(),
                      config: QuillEditorConfig(
                        autoFocus: false,
                        placeholder: 'Enter function description...',
                        padding: EdgeInsets.zero,
                        scrollable: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOrgStructureSection() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Organizational Structure', 
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          SizedBox(height: 16),
          if (_orgStructureImage != null)
            Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Image.memory(_orgStructureImage!, fit: BoxFit.contain),
            )
          else
            Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Icon(Icons.image_outlined, size: 64, color: Colors.grey),
              ),
            ),
          SizedBox(height: 16),
          if (!_isFinalized)
            Center(
              child: ElevatedButton.icon(
                icon: Icon(Icons.upload_file),
                label: Text(_orgStructureImage == null ? 'Upload Image' : 'Change Image'),
                onPressed: _pickOrgStructureImage,
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPersonnelComplementSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Personnel Complement',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: totalEmployeesCtl,
                decoration: const InputDecoration(
                  labelText: 'Total Number of Employees (Permanent & JO/Contractual)',
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: regionalOfficesCtl,
                decoration: const InputDecoration(
                  labelText: 'Number of Regional/Extension Offices',
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: provincialOfficesCtl,
                decoration: const InputDecoration(
                  labelText: 'Number of Provincial Offices',
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: otherOfficesCtl,
                decoration: const InputDecoration(
                  labelText: 'Number of Other Offices',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Employment Status Table
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
          ),
          child: Table(
            border: TableBorder.all(color: Colors.grey),
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                ),
                children: const [
                  Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('Employment Status', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('Central Office', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('Field Offices', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              _buildTableRow('No. of Plantilla Positions', coPlantilaCtl, foPlantilaCtl),
              _buildTableRow('Vacant', coVacantCtl, foVacantCtl),
              _buildTableRow('No. of Filled Up Positions (Plantilla)', coFilledPlantilaCtl, foFilledPlantilaCtl),
              _buildTableRow('No. of Filled Up Positions (Physical Location)', coFilledPhysicalCtl, foFilledPhysicalCtl),
              _buildTableRow('COSWs (*FO as of 01 July 2022)', coCoswsCtl, foCoswsCtl),
              _buildTableRow('Contractual (Driver I/II)', coContractualCtl, foContractualCtl),
              _buildTableRow('Total', coTotalCtl, foTotalCtl, isTotal: true),
            ],
          ),
        ),
      ],
    );
  }

  TableRow _buildTableRow(String label, TextEditingController centralCtl, TextEditingController fieldCtl, {bool isTotal = false}) {
    final style = isTotal ? const TextStyle(fontWeight: FontWeight.bold) : null;
    
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(label, style: style),
        ),
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: TextFormField(
            controller: centralCtl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            style: style,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: TextFormField(
            controller: fieldCtl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            style: style,
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
        title: const Text('Part I.B - Project Profile'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _isFinalized ? null : () => _saveData(),
            ),
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Finalize',
              onPressed: _isFinalized ? null : () => _saveData(finalize: true),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildField('Planner Name', plannerNameCtl),
              _buildField('Plantilla Position', positionCtl),
              _buildField('Organizational Unit', unitCtl),
              _buildField('Email Address', emailCtl),
              _buildField('Contact Numbers', contactCtl),
              SizedBox(height: 24),
              _buildFunctionsSection(),
              SizedBox(height: 24),
              _buildOrgStructureSection(),
              SizedBox(height: 24),
              _buildPersonnelComplementSection(),
              SizedBox(height: 24),
              Text('Project Cost', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              SizedBox(height: 16),
              _buildField('MOOE', mooeCtl),
              _buildField('CO', coCtl),
              _buildField('Total', totalCtl),
              SizedBox(height: 24),
              Text('Project Cost by Service', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              SizedBox(height: 16),
              _buildField('NICTHS Project Cost', nicthsCtl),
              _buildField('HSDV Project Cost', hsdvCtl),
              _buildField('HECS Project Cost', hecsCtl),
            ],
          ),
        ),
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
    for (var controller in functionControllers) {
      controller.dispose();
    }
    super.dispose();
  }
}

class HtmlPreviewPageIB extends StatelessWidget {
  final String html;
  const HtmlPreviewPageIB({required this.html, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Preview')),
      body: SingleChildScrollView(child: Html(data: html)),
    );
  }
}

String buildPartIBPreviewHtml({
  required String plannerName,
  required String plantillaPosition,
  required String organizationalUnit,
  required String emailAddress,
  required String contactNumbers,
  required List<String> functions,
  required String totalEmployees,
  required String regionalOffices,
  required String provincialOffices,
  required String otherOffices,
  required String coPlantilaPositions,
  required String coVacant,
  required String coFilledPlantilaPositions,
  required String coFilledPhysicalPositions,
  required String coCosws,
  required String coContractual,
  required String coTotal,
  required String foPlantilaPositions,
  required String foVacant,
  required String foFilledPlantilaPositions,
  required String foFilledPhysicalPositions,
  required String foCosws,
  required String foContractual,
  required String foTotal,
  required String mooe,
  required String co,
  required String total,
  required String nicthsProjectCost,
  required String hsdvProjectCost,
  required String hecsProjectCost,
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
        table {
          width: 100%;
          border-collapse: collapse;
          margin-bottom: 12px;
        }
        th, td {
          border: 1px solid #e0e4ea;
          padding: 6px 10px;
          text-align: left;
        }
        th {
          background: #f0f2f8;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="card">
          <div class="section-title">Planner Name</div>
          <div class="value">$plannerName</div>
        </div>
        <div class="card">
          <div class="section-title">Plantilla Position</div>
          <div class="value">$plantillaPosition</div>
        </div>
        <div class="card">
          <div class="section-title">Organizational Unit</div>
          <div class="value">$organizationalUnit</div>
        </div>
        <div class="card">
          <div class="section-title">Email Address</div>
          <div class="value">$emailAddress</div>
        </div>
        <div class="card">
          <div class="section-title">Contact Numbers</div>
          <div class="value">$contactNumbers</div>
        </div>
        <div class="card">
          <div class="section-title">Functions</div>
          <ul>
            ${functions.map((f) => '<li>${f.replaceAll('\n', '<br>')}</li>').join()}
          </ul>
        </div>
        <div class="card">
          <div class="section-title">Personnel Complement</div>
          <table>
            <tr>
              <th></th>
              <th>Central Office</th>
              <th>Field Offices</th>
            </tr>
            <tr>
              <td>No. of Plantilla Positions</td>
              <td>$coPlantilaPositions</td>
              <td>$foPlantilaPositions</td>
            </tr>
            <tr>
              <td>Vacant</td>
              <td>$coVacant</td>
              <td>$foVacant</td>
            </tr>
            <tr>
              <td>No. of Filled Up Positions (Plantilla)</td>
              <td>$coFilledPlantilaPositions</td>
              <td>$foFilledPlantilaPositions</td>
            </tr>
            <tr>
              <td>No. of Filled Up Positions (Physical Location)</td>
              <td>$coFilledPhysicalPositions</td>
              <td>$foFilledPhysicalPositions</td>
            </tr>
            <tr>
              <td>COSWs</td>
              <td>$coCosws</td>
              <td>$foCosws</td>
            </tr>
            <tr>
              <td>Contractual (Driver I/II)</td>
              <td>$coContractual</td>
              <td>$foContractual</td>
            </tr>
            <tr>
              <td>Total</td>
              <td>$coTotal</td>
              <td>$foTotal</td>
            </tr>
          </table>
          <div class="value"><b>Total Employees:</b> $totalEmployees</div>
          <div class="value"><b>Regional Offices:</b> $regionalOffices</div>
          <div class="value"><b>Provincial Offices:</b> $provincialOffices</div>
          <div class="value"><b>Other Offices:</b> $otherOffices</div>
        </div>
        <div class="card">
          <div class="section-title">Project Cost</div>
          <div class="value"><b>MOOE:</b> $mooe</div>
          <div class="value"><b>CO:</b> $co</div>
          <div class="value"><b>Total:</b> $total</div>
        </div>
        <div class="card">
          <div class="section-title">Project Cost by Service</div>
          <div class="value"><b>NICTHS Project Cost:</b> $nicthsProjectCost</div>
          <div class="value"><b>HSDV Project Cost:</b> $hsdvProjectCost</div>
          <div class="value"><b>HECS Project Cost:</b> $hecsProjectCost</div>
        </div>
      </div>
    </body>
  </html>
  ''';
}
