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
import 'package:test_project/main_part.dart';
import '../../utils/user_utils.dart';
import '../../services/notification_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../state/selection_model.dart';

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
  
  Uint8List? _uploadedDocxBytes;
  String? _uploadedDocxName;
  
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
      totalCtl;

  final List<Map<String, TextEditingController>> otherFundsControllers = [];
  bool _showOtherFunds = false;

  bool _loading = true, _saving = false, _isFinalized = false;
  late DocumentReference _sectionRef;
  final _user = FirebaseAuth.instance.currentUser;
  String get _userId =>
      _user?.displayName ?? _user?.email ?? _user?.uid ?? 'unknown';

  bool _compiling = false;
  String? _fileUrl;
  final _storage = FirebaseStorage.instance;

  late TextEditingController totalProjectCostCtrl;
  late TextEditingController otrFundCtrl;
  late TextEditingController otherFundsCtrl;
  late TextEditingController currDateCtl;

  String get _yearRange => context.read<SelectionModel>().yearRange ?? '2729';

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

    otrFundCtrl = TextEditingController();
    otherFundsCtrl = TextEditingController();
    currDateCtl = TextEditingController(text: DateFormat('MMMM dd, yyyy').format(DateTime.now()));
    
    _sectionRef = FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(_yearRange)
        .collection('sections')
        .doc('I.B');

    mooeCtl.addListener(_updateTotal);
    coCtl.addListener(_updateTotal);

    coPlantilaCtl.addListener(_updatePersonnelTotals);
    coVacantCtl.addListener(_updatePersonnelTotals);
    coFilledPlantilaCtl.addListener(_updatePersonnelTotals);
    coFilledPhysicalCtl.addListener(_updatePersonnelTotals);
    coCoswsCtl.addListener(_updatePersonnelTotals);
    coContractualCtl.addListener(_updatePersonnelTotals);

    foPlantilaCtl.addListener(_updatePersonnelTotals);
    foVacantCtl.addListener(_updatePersonnelTotals);
    foFilledPlantilaCtl.addListener(_updatePersonnelTotals);
    foFilledPhysicalCtl.addListener(_updatePersonnelTotals);
    foCoswsCtl.addListener(_updatePersonnelTotals);
    foContractualCtl.addListener(_updatePersonnelTotals);

    _loadData();
  }

  void _updateTotal() {
    final mooe = double.tryParse(mooeCtl.text.replaceAll(',', '')) ?? 0;
    final co = double.tryParse(coCtl.text.replaceAll(',', '')) ?? 0;
    final total = mooe + co;
    final formatted = total == 0 ? '' : total.toStringAsFixed(2);
    if (totalCtl.text != formatted) {
      totalCtl.text = formatted;
    }
  }

  void _updatePersonnelTotals() {
    final coFields = [
      coPlantilaCtl,
      coVacantCtl,
      coFilledPlantilaCtl,
      coFilledPhysicalCtl,
      coCoswsCtl,
      coContractualCtl,
    ];
    final coTotal = coFields.fold<double>(0, (sum, ctl) => sum + (double.tryParse(ctl.text.replaceAll(',', '')) ?? 0));
    final coFormatted = coTotal == 0 ? '' : coTotal.toStringAsFixed(2);
    if (coTotalCtl.text != coFormatted) {
      coTotalCtl.text = coFormatted;
    }
    final foFields = [
      foPlantilaCtl,
      foVacantCtl,
      foFilledPlantilaCtl,
      foFilledPhysicalCtl,
      foCoswsCtl,
      foContractualCtl,
    ];
    final foTotal = foFields.fold<double>(0, (sum, ctl) => sum + (double.tryParse(ctl.text.replaceAll(',', '')) ?? 0));
    final foFormatted = foTotal == 0 ? '' : foTotal.toStringAsFixed(2);
    if (foTotalCtl.text != foFormatted) {
      foTotalCtl.text = foFormatted;
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      _sectionRef = FirebaseFirestore.instance
          .collection('issp_documents')
          .doc(_yearRange)
          .collection('sections')
          .doc('I.B');

      final doc = await _sectionRef.get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _isFinalized = (data['isFinalized'] as bool? ?? false) || (data['screening'] as bool? ?? false);
          
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
          currDateCtl.text        = data['currDate'] ?? DateFormat('MMMM dd, yyyy').format(DateTime.now());
        });

        final orgStructureUrl = data['orgStructureUrl'] as String?;
        if (orgStructureUrl != null) {
          try {
            final ref = FirebaseStorage.instance.refFromURL(orgStructureUrl);
            final bytes = await ref.getData();
            if (bytes != null) {
              setState(() {
                _orgStructureImage = bytes;
              });
            }
          } catch (e) {
            print('Failed to load org structure image: $e');
          }
        }
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

  Future<void> _pickDocxFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['docx'],
      );
      if (result != null) {
        final file = result.files.first;
        if (file.bytes != null) {
          setState(() {
            _uploadedDocxBytes = file.bytes;
            _uploadedDocxName = file.name;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('DOCX file selected. Click Save to upload.'))
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File pick error: $e'))
      );
    }
  }

  void _addOtherFund() {
    setState(() {
      otherFundsControllers.add({
        'projectName': TextEditingController(),
        'projectCost': TextEditingController(),
      });
    });
  }

  void _removeOtherFund(int index) {
    setState(() {
      otherFundsControllers[index]['projectName']?.dispose();
      otherFundsControllers[index]['projectCost']?.dispose();
      otherFundsControllers.removeAt(index);
    });
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
    totalEmployeesCtl.dispose();
    regionalOfficesCtl.dispose();
    provincialOfficesCtl.dispose();
    otherOfficesCtl.dispose();
    coPlantilaCtl.dispose();
    coVacantCtl.dispose();
    coFilledPlantilaCtl.dispose();
    coFilledPhysicalCtl.dispose();
    coCoswsCtl.dispose();
    coContractualCtl.dispose();
    coTotalCtl.dispose();
    foPlantilaCtl.dispose();
    foVacantCtl.dispose();
    foFilledPlantilaCtl.dispose();
    foFilledPhysicalCtl.dispose();
    foCoswsCtl.dispose();
    foContractualCtl.dispose();
    foTotalCtl.dispose();

    for (var controllers in otherFundsControllers) {
      controllers['projectName']?.dispose();
      controllers['projectCost']?.dispose();
    }
    
    totalProjectCostCtrl.dispose();
    otrFundCtrl.dispose();
    otherFundsCtrl.dispose();
    currDateCtl.dispose();
    
    super.dispose();
  }

  Future<void> _saveData({bool finalize = false}) async {
    if (_uploadedDocxBytes == null && !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      String? docxUrl;
      String? orgStructureUrl;
      final storage = FirebaseStorage.instance;
      final docxRef = storage.ref().child('$_yearRange/I.B/document.docx');

      if (_orgStructureImage != null) {
        try {
          final orgStructureRef = storage.ref().child('$_yearRange/I.B/org_structure.png');
          await orgStructureRef.putData(_orgStructureImage!, SettableMetadata(contentType: 'image/png'));
          orgStructureUrl = await orgStructureRef.getDownloadURL();
        } catch (e) {
          print('Error uploading org structure image: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error uploading image: $e'))
          );
        }
      }

      String otherFundsText = '';
      if (_showOtherFunds && otherFundsControllers.isNotEmpty) {
        otherFundsText = '• Other Sources of Funds:\n';
        otherFundsText += otherFundsControllers.map((controllers) {
          final projectName = controllers['projectName']?.text.trim() ?? '';
          final projectCost = controllers['projectCost']?.text.trim() ?? '';
          return '  $projectName - Project Cost: PhP ${projectCost}';  // Two spaces for indentation, no bullet
        }).join('\n');
      }

      if (_uploadedDocxBytes != null) {
        await docxRef.putData(_uploadedDocxBytes!, SettableMetadata(contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'));
        docxUrl = await docxRef.getDownloadURL();
      } else {
        final yearRange = context.read<SelectionModel>().yearRange ?? '2729';
        final formattedYearRange = formatYearRange(yearRange);
        final data = {
          'plannerName': plannerNameCtl.text.trim(),
          'plantillaPosition': positionCtl.text.trim(),
          'organizationalUnit': unitCtl.text.trim(),
          'emailAddress': emailCtl.text.trim(),
          'contactNumbers': contactCtl.text.trim(),
          'mooe': mooeCtl.text.trim(),
          'co': coCtl.text.trim(),
          'total': totalCtl.text.trim(),
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
          'otrFund': otherFundsText,
          'currDate': currDateCtl.text.trim(),
          'organizationalStructure': _orgStructureImage != null 
              ? base64Encode(_orgStructureImage!)
              : null,
          'yearRange': formattedYearRange,
        };

        final url = Uri.parse('http://localhost:8000/generate-ib-docx/');
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(data),
        );
        if (response.statusCode != 200) {
          throw Exception('Failed to generate DOCX: ${response.statusCode}');
        }
        final docxBytes = response.bodyBytes;
        await docxRef.putData(docxBytes, SettableMetadata(contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'));
        docxUrl = await docxRef.getDownloadURL();
      }

      final username = await getCurrentUsername();
      final otherFunds = otherFundsControllers.map((controllers) {
        return {
          'projectName': controllers['projectName']?.text.trim() ?? '',
          'cost': controllers['projectCost']?.text.trim() ?? '',
        };
      }).toList();

      final payload = {
        'plannerName': plannerNameCtl.text.trim(),
        'plantillaPosition': positionCtl.text.trim(),
        'organizationalUnit': unitCtl.text.trim(),
        'emailAddress': emailCtl.text.trim(),
        'contactNumbers': contactCtl.text.trim(),
        'mooe': mooeCtl.text.trim(),
        'co': coCtl.text.trim(),
        'total': totalCtl.text.trim(),
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
        'otrFund': otherFundsText,
        'fileUrl': docxUrl,
        'orgStructureUrl': orgStructureUrl,
        'otherFunds': otherFunds,
        'otherFundsTotal': otherFundsCtrl.text.trim(),
        'modifiedBy': username,
        'lastModified': FieldValue.serverTimestamp(),
        'screening': finalize || _isFinalized,
        'sectionTitle': 'Part I.B',
        'isFinalized': finalize ? false : _isFinalized,
        'currDate': currDateCtl.text.trim(),
      };
      if (!_isFinalized) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdBy'] = username;
      }
      await _sectionRef.set(payload, SetOptions(merge: true));
      setState(() {
        _isFinalized = finalize;
        _uploadedDocxBytes = null;
        _uploadedDocxName = null;
      });
      if (finalize) {
        await createSubmissionNotification('Part I.B', _yearRange);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Part I.B submitted for admin approval. You will be notified once it is reviewed.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          )
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Part I.B saved successfully (not finalized)'),
            backgroundColor: Colors.green,
          )
        );
      }
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

  Future<void> _downloadDocx() async {
    setState(() => _compiling = true);
    try {
      final fileName = 'document.docx';
      final storage = FirebaseStorage.instance;
      final docxRef = storage.ref().child('$_yearRange/I.B/document.docx');
      final docxBytes = await docxRef.getData();
      if (docxBytes != null) {
        if (kIsWeb) {
          await FileSaver.instance.saveFile(
            name: fileName,
            bytes: docxBytes,
            mimeType: MimeType.microsoftWord,
          );
        } else {
          final directory = await getApplicationDocumentsDirectory();
          final file = File('${directory.path}/$fileName');
          await file.writeAsBytes(docxBytes);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('DOCX downloaded from storage!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No DOCX file found in storage. Please save or finalize first.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download error: ${e.toString()}')),
      );
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
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: _isFinalized
                ? null
                : () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateFormat('MMMM dd, yyyy').parse(currDateCtl.text),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() {
                        currDateCtl.text = DateFormat('MMMM dd, yyyy').format(picked);
                      });
                    }
                  },
            child: AbsorbPointer(
              absorbing: true,
              child: TextFormField(
                controller: currDateCtl,
                enabled: !_isFinalized,
                decoration: InputDecoration(
                  labelText: 'Date',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Date is required' : null,
              ),
            ),
          ),
        ),
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
          child: isTotal
              ? TextFormField(
                  controller: centralCtl,
                  enabled: false,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  style: style,
                )
              : TextFormField(
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
          child: isTotal
              ? TextFormField(
                  controller: fieldCtl,
                  enabled: false,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  style: style,
                )
              : TextFormField(
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

  Widget buildSectionCard(IconData icon, String title, Widget child) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildOtherFundsSection() {
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
                  Icons.account_balance_wallet,
                  color: Color(0xff021e84),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Other Sources of Funds',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3748),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...otherFundsControllers.asMap().entries.map((entry) {
            final idx = entry.key;
            final controllers = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: _buildField('Project Name', controllers['projectName']!),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField('Cost', controllers['projectCost']!),
                  ),
                  if (!_isFinalized) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _removeOtherFund(idx),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
          if (!_isFinalized)
            Center(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text(
                  'Add Other Fund',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                onPressed: _addOtherFund,
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        final shouldPop = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: Colors.white,
              elevation: 20,
              title: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xff021e84), Color(0xff1e40af)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.warning_amber, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Save Before Leaving',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              content: Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xff021e84).withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xff021e84).withOpacity(0.1),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Color(0xff021e84),
                            size: 20,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Make sure to save before leaving to avoid losing your work.',
                              style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFF4A5568),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: const Text(
                      'Stay',
                      style: TextStyle(
                        color: Color(0xFF4A5568),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color.fromARGB(255, 132, 2, 2), Color.fromARGB(255, 175, 30, 30)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xff021e84).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text(
                      'Leave Anyway',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
        return shouldPop ?? false;
      },
      child: Scaffold(
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
                onPressed: _isFinalized ? null : () async {
                  final confirmed = await showFinalizeConfirmation(
                    context,
                    'Part I.B - Department/Agency Profile'
                  );
                  if (confirmed) {
                    _saveData(finalize: true);
                  }
                },
                tooltip: 'Finalize',
                color: _isFinalized ? Colors.grey : const Color(0xff021e84),
              ),
              IconButton(
                icon: const Icon(Icons.file_download),
                onPressed: _downloadDocx,
                tooltip: 'Download DOCX',
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
                    const SizedBox(height: 12),
                    const Text(
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
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.08),
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
                                      color: const Color(0xff021e84).withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.upload_file,
                                      color: Color(0xff021e84),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'Upload DOCX (optional)',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2D3748),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'You may upload a DOCX file directly instead of using the form. If you upload a DOCX, it will be saved and used for this section.',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Color(0xFF4A5568),
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: _isFinalized ? null : _pickDocxFile,
                                    icon: const Icon(Icons.upload_file),
                                    label: const Text('Upload DOCX'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xff021e84),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  if (_uploadedDocxName != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xff021e84).withOpacity(0.07),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.description, color: Color(0xff021e84), size: 20),
                                          const SizedBox(width: 6),
                                          Text(_uploadedDocxName!, style: const TextStyle(fontSize: 15, color: Color(0xFF2D3748))),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
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
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: TextFormField(
                                  controller: totalCtl,
                                  enabled: false,
                                  maxLines: 1,
                                  decoration: InputDecoration(
                                    labelText: 'Total',
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
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Checkbox(
                                    value: _showOtherFunds,
                                    onChanged: _isFinalized ? null : (value) {
                                      setState(() {
                                        _showOtherFunds = value ?? false;
                                        if (!_showOtherFunds) {
                                          for (var controllers in otherFundsControllers) {
                                            controllers['projectName']?.dispose();
                                            controllers['projectCost']?.dispose();
                                          }
                                          otherFundsControllers.clear();
                                        }
                                      });
                                    },
                                  ),
                                  const Text(
                                    'Include Other Sources of Funds',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Color(0xFF2D3748),
                                    ),
                                  ),
                                ],
                              ),
                              if (_showOtherFunds) ...[
                                const SizedBox(height: 16),
                                _buildOtherFundsSection(),
                              ],
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
      ),
    );
  }
}
