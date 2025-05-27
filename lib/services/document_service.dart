import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;

class DocumentService {
  static const String baseUrl = 'http://localhost:8000'; // Change this in production

  Future<Uint8List?> fetchUploadedFileBytes(String documentId, String section) async {
    final doc = await FirebaseFirestore.instance
        .collection('issp_documents')
        .doc(documentId)
        .collection('sections')
        .doc(section)
        .get();
    final data = doc.data();
    if (data != null && data['uploadedFile'] != null) {
      return base64Decode(data['uploadedFile'] as String);
    }
    return null;
  }

  Future<Uint8List> loadTemplateBytes(String assetPath) async {
    return (await rootBundle.load(assetPath)).buffer.asUint8List();
  }
} 