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
import 'package:firebase_storage/firebase_storage.dart';

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
  
  print('Original XML content:');
  print(docXml.substring(0, min(500, docXml.length)));  
  
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
    if (ph != placeholder) {   
      docXml = docXml.replaceAll(ph, xmlEscape(val));
    }
  });

  print('\nModified XML content:');
  print(docXml.substring(0, min(500, docXml.length))); 

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
  
  late TextEditingController totalEmployeesCtl,
      regionalOfficesCtl,
      provincialOfficesCtl,
      otherOfficesCtl;
  
  late TextEditingController coPlantilaCtl,
      coVacantCtl,
      coFilledPlantilaCtl,
      coFilledPhysicalCtl,
      coCoswsCtl,
      coContractualCtl,
      coTotalCtl;

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
  String? _fileUrl;
  final _storage = FirebaseStorage.instance;

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

    totalEmployeesCtl = TextEditingController();
    regionalOfficesCtl = TextEditingController();
    provincialOfficesCtl = TextEditingController();
    otherOfficesCtl = TextEditingController();

    coPlantilaCtl = TextEditingController();
    coVacantCtl = TextEditingController();
    coFilledPlantilaCtl = TextEditingController();
    coFilledPhysicalCtl = TextEditingController();
    coCoswsCtl = TextEditingController();
    coContractualCtl = TextEditingController();
    coTotalCtl = TextEditingController();

    foPlantilaCtl = TextEditingController();
    foVacantCtl = TextEditingController();
    foFilledPlantilaCtl = TextEditingController();
    foFilledPhysicalCtl = TextEditingController();
    foCoswsCtl = TextEditingController();
    foContractualCtl = TextEditingController();
    foTotalCtl = TextEditingController();

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
          
          totalEmployeesCtl.text = data['totalEmployees'] ?? '';
          regionalOfficesCtl.text = data['regionalOffices'] ?? '';
          provincialOfficesCtl.text = data['provincialOffices'] ?? '';
          otherOfficesCtl.text = data['otherOffices'] ?? '';
          
          coPlantilaCtl.text = data['coPlantilaPositions'] ?? '';
          coVacantCtl.text = data['coVacant'] ?? '';
          coFilledPlantilaCtl.text = data['coFilledPlantilaPositions'] ?? '';
          coFilledPhysicalCtl.text = data['coFilledPhysicalPositions'] ?? '';
          coCoswsCtl.text = data['coCosws'] ?? '';
          coContractualCtl.text = data['coContractual'] ?? '';
          coTotalCtl.text = data['coTotal'] ?? '';
          
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
    if (_orgStructureImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload an organizational structure image'))
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final imageRef = _storage.ref().child('${widget.documentId}/I.B/orgStructure.png');
      await imageRef.putData(_orgStructureImage!);

      final replacements = {
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
        'organizationalStructure': _orgStructureImage != null ? base64Encode(_orgStructureImage!) : '',
        'modifiedBy': _userId,
        'totalEmployees': totalEmployeesCtl.text.trim(),
        'regionalOffices': regionalOfficesCtl.text.trim(),
        'provincialOffices': provincialOfficesCtl.text.trim(),
        'otherOffices': otherOfficesCtl.text.trim(),
        'coPlantilaPositions': coPlantilaCtl.text.trim(),
        'coVacant': coVacantCtl.text.trim(),
        'coFilledPlantilaPositions': coFilledPlantilaCtl.text.trim(),
        'coFilledPhysicalPositions': coFilledPhysicalCtl.text.trim(),
        'coCosws': coCoswsCtl.text.trim(),
        'coContractual': coContractualCtl.text.trim(),
        'coTotal': coTotalCtl.text.trim(),
        'foPlantilaPositions': foPlantilaCtl.text.trim(),
        'foVacant': foVacantCtl.text.trim(),
        'foFilledPlantilaPositions': foFilledPlantilaCtl.text.trim(),
        'foFilledPhysicalPositions': foFilledPhysicalCtl.text.trim(),
        'foCosws': foCoswsCtl.text.trim(),
        'foContractual': foContractualCtl.text.trim(),
        'foTotal': foTotalCtl.text.trim(),
      };

      final docxBytes = await generateDocxWithImage(
        assetPath: 'assets/templates_b.docx',
        placeholder: '\${orgStructure}',
        imageBytes: _orgStructureImage!,
        replacements: replacements,
      );

      final docxRef = _storage.ref().child('${widget.documentId}/I.B/document.docx');
      await docxRef.putData(docxBytes);
      final docxUrl = await docxRef.getDownloadURL();

      final payload = {
        ...replacements,
        'fileUrl': docxUrl,
        'modifiedBy': _userId,
        'lastModified': FieldValue.serverTimestamp(),
        'isFinalized': finalize || _isFinalized,
      };

      final doc = await _sectionRef.get();
      if (!doc.exists) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdBy'] = _userId;
      }

      await _sectionRef.set(payload, SetOptions(merge: true));
      setState(() {
        _isFinalized = finalize;
        _fileUrl = docxUrl;
      });
      
      if (finalize) {
        final user = FirebaseAuth.instance.currentUser;
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user!.uid).get();
        final username = userDoc.data()?['username'] ?? user.uid;
        await FirebaseFirestore.instance.collection('notifications').add({
          'title': 'Part I.B Finalized',
          'body': 'Part I.B has been finalized by $username',
          'readBy': {},
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
      
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
    if (_orgStructureImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please upload an organizational structure image first'))
      );
      return;
    }

    setState(() => _compiling = true);
    try {
      try {
        await rootBundle.load('assets/templates_b.docx');
      } catch (e) {
        throw Exception('Failed to load template file: $e\nMake sure assets/templates_b.docx exists and is properly included in pubspec.yaml');
      }

      String formatNumber(String value) {
        if (value.isEmpty) return '0';
        try {
          return NumberFormat('#,##0').format(int.parse(value.replaceAll(',', '')));
        } catch (e) {
          return value;
        }
      }

      final replacements = <String,String>{
        'plannerName'           : plannerNameCtl.text.trim(),
        'plantillaPosition'     : positionCtl.text.trim(),
        'organizationalUnit'    : unitCtl.text.trim(),
        'emailAddress'          : emailCtl.text.trim(),
        'contactNumbers'        : contactCtl.text.trim(),

        'mooe'                  : formatNumber(mooeCtl.text),
        'co'                    : formatNumber(coCtl.text),
        'total'                 : formatNumber(totalCtl.text),
        'nicthsProjectCost'     : formatNumber(nicthsCtl.text),
        'hsdvProjectCost'       : formatNumber(hsdvCtl.text),
        'hecsProjectCost'       : formatNumber(hecsCtl.text),
        
        'totalEmployees'        : formatNumber(totalEmployeesCtl.text),
        'regionalOffices'       : formatNumber(regionalOfficesCtl.text),
        'provincialOffices'     : formatNumber(provincialOfficesCtl.text),
        'otherOffices'         : otherOfficesCtl.text.trim(),

        'coPlantilaPositions'   : formatNumber(coPlantilaCtl.text),
        'coVacant'             : formatNumber(coVacantCtl.text),
        'coFilledPlantilaPositions': formatNumber(coFilledPlantilaCtl.text),
        'coFilledPhysicalPositions': formatNumber(coFilledPhysicalCtl.text),
        'coCosws'              : formatNumber(coCoswsCtl.text),
        'coContractual'        : formatNumber(coContractualCtl.text),
        'coTotal'              : formatNumber(coTotalCtl.text),

        'foPlantilaPositions'   : formatNumber(foPlantilaCtl.text),
        'foVacant'             : formatNumber(foVacantCtl.text),
        'foFilledPlantilaPositions': formatNumber(foFilledPlantilaCtl.text),
        'foFilledPhysicalPositions': formatNumber(foFilledPhysicalCtl.text),
        'foCosws'              : formatNumber(foCoswsCtl.text),
        'foContractual'        : formatNumber(foContractualCtl.text),
        'foTotal'              : formatNumber(foTotalCtl.text),

      };

      print('Replacement map:');
      replacements.forEach((key, value) {
        print('$key: $value');
      });

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
      print('Error details: $e');  
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(
            content: Text('Compile error: ${e.toString()}'),
            duration: Duration(seconds: 5),  
          ));
    } finally {
      setState(() => _compiling = false);
    }
  }

  Widget _buildField(String label, TextEditingController ctrl, {bool multiline = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: ctrl,
        enabled: !_isFinalized,
        maxLines: multiline ? null : 1,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xff021e84)),
          ),
          labelStyle: const TextStyle(color: Color(0xFF4A5568)),
        ),
        validator: (v) => v == null || v.trim().isEmpty ? '$label is required' : null,
      ),
    );
  }

  Widget _buildOrgStructureSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xff021e84).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.image,
                  color: Color(0xff021e84),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Organizational Structure',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3748),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_orgStructureImage != null)
            Container(
              width: double.infinity,
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(_orgStructureImage!, fit: BoxFit.contain),
              ),
            )
          else
            Container(
              width: double.infinity,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey.shade50,
              ),
              child: const Center(
                child: Icon(Icons.image_outlined, size: 64, color: Colors.grey),
              ),
            ),
          const SizedBox(height: 20),
          if (!_isFinalized)
            Center(
              child: ElevatedButton.icon(
                icon: Icon(
                  _orgStructureImage == null ? Icons.upload_file : Icons.edit,
                  color: Colors.white,
                ),
                label: Text(
                  _orgStructureImage == null ? 'Upload Image' : 'Change Image',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: _pickOrgStructureImage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff021e84),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 2,
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
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(4),
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
        const SizedBox(height: 16),
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

  Widget _buildCentralOfficeSection() {
    return Column(
      children: [
        _buildField('Plantilla', coPlantilaCtl),
        _buildField('Vacant', coVacantCtl),
        _buildField('Filled (Plantilla)', coFilledPlantilaCtl),
        _buildField('Filled (Physical)', coFilledPhysicalCtl),
        _buildField('COSWS', coCoswsCtl),
        _buildField('Contractual', coContractualCtl),
        _buildField('Total', coTotalCtl),
      ],
    );
  }

  Widget _buildFieldOfficeSection() {
    return Column(
      children: [
        _buildField('Plantilla', foPlantilaCtl),
        _buildField('Vacant', foVacantCtl),
        _buildField('Filled (Plantilla)', foFilledPlantilaCtl),
        _buildField('Filled (Physical)', foFilledPhysicalCtl),
        _buildField('COSWS', foCoswsCtl),
        _buildField('Contractual', foContractualCtl),
        _buildField('Total', foTotalCtl),
      ],
    );
  }

  Widget _buildContactInfoSection() {
    return Column(
      children: [
        _buildField('Planner Name', plannerNameCtl),
        _buildField('Plantilla Position', positionCtl),
        _buildField('Organizational Unit', unitCtl),
        _buildField('Email Address', emailCtl),
        _buildField('Contact Numbers', contactCtl),
      ],
    );
  }

  Widget _buildBudgetSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Project Cost',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D3748),
          ),
        ),
        const SizedBox(height: 16),
        _buildField('MOOE', mooeCtl),
        _buildField('CO', coCtl),
        _buildField('Total', totalCtl),
        const SizedBox(height: 24),
        const Text(
          'Project Cost by Service',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D3748),
          ),
        ),
        const SizedBox(height: 16),
        _buildField('NICTHS Project Cost', nicthsCtl),
        _buildField('HSDV Project Cost', hsdvCtl),
        _buildField('HECS Project Cost', hecsCtl),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: const Text(
          'Part I.B - Department/Agency Profile',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2D3748),
        actions: [
          if (_saving || _compiling)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: CircularProgressIndicator(
                  color: Color(0xff021e84),
                ),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _isFinalized ? null : () => _saveData(),
              tooltip: 'Save',
              color: const Color(0xff021e84),
            ),
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _isFinalized ? null : () => _saveData(finalize: true),
              tooltip: 'Finalize',
              color: _isFinalized ? Colors.grey : const Color(0xff021e84),
            ),
            IconButton(
              icon: const Icon(Icons.file_download),
              onPressed: _compileDocx,
              tooltip: 'Compile DOCX',
              color: const Color(0xff021e84),
            ),
          ],
        ],
      ),
      body: _isFinalized
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock, size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    'Part I.B - Department/Agency Profile has been finalized.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              spreadRadius: 2,
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xff021e84).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.info_outline,
                                    color: Color(0xff021e84),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Instructions',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2D3748),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Please fill in all the required fields below. Make sure all information is accurate and complete before finalizing.',
                              style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFF4A5568),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              spreadRadius: 2,
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xff021e84).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.person,
                                    color: Color(0xff021e84),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Planner Information',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2D3748),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _buildField('Planner Name', plannerNameCtl),
                            _buildField('Plantilla Position', positionCtl),
                            _buildField('Organizational Unit', unitCtl),
                            _buildField('Email Address', emailCtl),
                            _buildField('Contact Numbers', contactCtl),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              spreadRadius: 2,
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xff021e84).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.attach_money,
                                    color: Color(0xff021e84),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Budget Information',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2D3748),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _buildField('MOOE', mooeCtl),
                            _buildField('CO', coCtl),
                            _buildField('Total', totalCtl),
                            _buildField('NICTHS Project Cost', nicthsCtl),
                            _buildField('HSDV Project Cost', hsdvCtl),
                            _buildField('HECS Project Cost', hecsCtl),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildOrgStructureSection(),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              spreadRadius: 2,
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xff021e84).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.work,
                                    color: Color(0xff021e84),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Employment Status',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2D3748),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _buildPersonnelComplementSection(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
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
    super.dispose();
  }
}
