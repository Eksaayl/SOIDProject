import 'package:flutter/material.dart';
import 'part_iii/part_iii_a.dart';
import 'part_iii/part_iii_b.dart';
import 'part_iii/part_iii_c.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:file_saver/file_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../config.dart';

class Part3 extends StatefulWidget {
  const Part3({super.key});

  @override
  _Part3State createState() => _Part3State();
}

class _Part3State extends State<Part3> {
  int _selectedIndex = -1;
  bool _isCompiling = false;
  static const _docId = 'document';

  Future<void> mergePartIIIDocuments(BuildContext context, String documentId) async {
    try {
      final storage = FirebaseStorage.instance;
      final firestore = FirebaseFirestore.instance;
      setState(() => _isCompiling = true);

      final sectionRefs = await Future.wait([
        firestore.collection('issp_documents').doc(documentId).collection('sections').doc('III.A').get(),
        firestore.collection('issp_documents').doc(documentId).collection('sections').doc('III.B').get(),
        firestore.collection('issp_documents').doc(documentId).collection('sections').doc('III.C').get(),
      ]);

      final notFinalized = <String>[];
      for (var i = 0; i < sectionRefs.length; i++) {
        final data = sectionRefs[i].data();
        if (data == null || !(data['isFinalized'] as bool? ?? false)) {
          notFinalized.add(['III.A', 'III.B', 'III.C'][i]);
        }
      }

      if (notFinalized.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please finalize the following sections first: \\${notFinalized.join(", ")}'))
        );
        return;
      }

      final iii_a_bytes = await storage.ref().child('$documentId/III.A/document.docx').getData();
      final iii_b_bytes = await storage.ref().child('$documentId/III.B/document.docx').getData();
      final iii_c_bytes = await storage.ref().child('$documentId/III.C/document.docx').getData();

      if (iii_a_bytes == null || iii_b_bytes == null || iii_c_bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('One or more Part III documents are missing. Please ensure all parts are finalized.'))
        );
        return;
      }

      final merge_request = http.MultipartRequest(
        'POST',
        Uri.parse('${Config.serverUrl}/merge-documents-part-iii'),
      );

      merge_request.files.add(http.MultipartFile.fromBytes('part_iii_a', iii_a_bytes, filename: 'part_iii_a.docx'));
      merge_request.files.add(http.MultipartFile.fromBytes('part_iii_b', iii_b_bytes, filename: 'part_iii_b.docx'));
      merge_request.files.add(http.MultipartFile.fromBytes('part_iii_c', iii_c_bytes, filename: 'part_iii_c.docx'));

      final merge_response = await merge_request.send();
      if (merge_response.statusCode != 200) {
        final error = await merge_response.stream.bytesToString();
        throw Exception('Failed to merge documents: \\${merge_response.statusCode} - $error');
      }

      final responseBytes = await merge_response.stream.toBytes();

      final mergedRef = storage.ref().child('$documentId/part_iii_merged.docx');
      await mergedRef.putData(responseBytes);

      await firestore.collection('issp_documents').doc(documentId).update({
        'partIIIMergedPath': '$documentId/part_iii_merged.docx',
        'lastModified': FieldValue.serverTimestamp(),
      });

      if (kIsWeb) {
        await FileSaver.instance.saveFile(
          name: 'Part_III_Merged_\\${DateTime.now().millisecondsSinceEpoch}.docx',
          bytes: responseBytes,
          mimeType: MimeType.microsoftWord,
        );
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/Part_III_Merged_\\${DateTime.now().millisecondsSinceEpoch}.docx');
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

  @override
  Widget build(BuildContext context) {
    bool isSmallScreen = MediaQuery.of(context).size.width < 650;

    return isSmallScreen
        ? Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            const Text(
              'DETAILED DESCRIPTION OF ICT PROJECTS',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildTopButton('Part III.A', Icons.laptop, 0),
                    const SizedBox(width: 16),
                    _buildTopButton('Part III.B', Icons.link, 1),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildTopButton('Part III.C', Icons.bar_chart, 2),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_isCompiling)
              const CircularProgressIndicator()
            else
              ElevatedButton.icon(
                onPressed: () => mergePartIIIDocuments(context, _docId),
                icon: const Icon(Icons.merge_type),
                label: const Text('Merge All Parts III'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff021e84),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
          ],
        ),
      ),
    )
        : Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'DETAILED DESCRIPTION OF ICT PROJECTS',
          style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildTopButton('Part III.A', Icons.laptop, 0),
            const SizedBox(width: 16),
            _buildTopButton('Part III.B', Icons.link, 1),
            const SizedBox(width: 16),
            _buildTopButton('Part III.C', Icons.bar_chart, 2),
          ],
        ),
        const SizedBox(height: 24),
        if (_isCompiling)
          const CircularProgressIndicator()
        else
          ElevatedButton.icon(
            onPressed: () => mergePartIIIDocuments(context, _docId),
            icon: const Icon(Icons.merge_type),
            label: const Text('Merge All Parts III'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff021e84),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTopButton(String text, IconData icon, int index) {
    return ElevatedButton.icon(
      onPressed: () {
        setState(() {
          _selectedIndex = index;
        });
        switch (index) {
          case 0:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PartIIIA(),
              ),
            );
            break;
          case 1:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PartIIIB(),
              ),
            );
            break;
          case 2:
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PartIIIC(),
              ),
            );
            break;
        }
      },
      icon: Icon(icon, color: _selectedIndex == index ? Colors.white : Colors.black),
      label: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: _selectedIndex == index ? Colors.white : Colors.black,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: _selectedIndex == index ? const Color(0xff021e84) : Colors.transparent,
        foregroundColor: Colors.black,
        side: const BorderSide(color: Colors.black),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
