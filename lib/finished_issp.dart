import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_saver/file_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:typed_data';
import 'startup_time.dart';

class FinishedISSPPage extends StatefulWidget {
  final String yearRange;
  
  const FinishedISSPPage({
    super.key,
    required this.yearRange,
  });
  
  String get _yearCode {
    if (yearRange == '2021-2023') return '2123';
    if (yearRange == '2024-2026') return '2426';
    throw Exception('Invalid year range');
  }

  @override
  State<FinishedISSPPage> createState() => _FinishedISSPPageState();
}

class _FinishedISSPPageState extends State<FinishedISSPPage> {
  bool _isDownloading = false;

  Future<void> _downloadISSP() async {
    setState(() {
      _isDownloading = true;
    });

    try {
      final storage = FirebaseStorage.instance;
      
      print('🔍 DEBUG: Year Range = ${widget.yearRange}');
      print('🔍 DEBUG: Year Code = ${widget._yearCode}');
      
      String fileName;
      if (widget.yearRange == '2021-2023') {
        fileName = '2021 - 2023 ISSP.pdf';
      } else if (widget.yearRange == '2024-2026') {
        fileName = '2024 - 2026 ISSP.pdf';
      } else {
        throw Exception('Invalid year range');
      }
      
      print('🔍 DEBUG: File Name = $fileName');
      
      final pdfRef = storage.ref().child('${widget._yearCode}/compiled.pdf');
      
      print('🔍 DEBUG: Firebase Storage Path = ${widget._yearCode}/compiled.pdf');
      print('🔍 DEBUG: Full Storage Reference = ${pdfRef.fullPath}');
      
      try {
        final metadata = await pdfRef.getMetadata();
        print('🔍 DEBUG: File metadata found:');
        print('  - Name: ${metadata.name}');
        print('  - Size: ${metadata.size} bytes');
        print('  - Content Type: ${metadata.contentType}');
        print('  - Updated: ${metadata.updated}');
      } catch (metadataError) {
        print('❌ DEBUG: Failed to get metadata: $metadataError');
      }
      
      print('🔍 DEBUG: Starting file download...');
      
      Uint8List? pdfBytes;
      
      try {
        print('🔍 DEBUG: Attempting direct download...');
        pdfBytes = await pdfRef.getData();
        if (pdfBytes != null) {
          print('🔍 DEBUG: Direct download successful!');
        }
      } catch (directError) {
        print('❌ DEBUG: Direct download failed: $directError');
      }
      
      if (pdfBytes == null) {
        try {
          print('🔍 DEBUG: Attempting download with max size limit...');
          pdfBytes = await pdfRef.getData(1024 * 1024 * 50); 
          if (pdfBytes != null) {
            print('🔍 DEBUG: Download with size limit successful!');
          }
        } catch (sizeLimitError) {
          print('❌ DEBUG: Download with size limit failed: $sizeLimitError');
        }
      }
      
      if (pdfBytes == null) {
        try {
          print('🔍 DEBUG: Attempting download via URL...');
          final downloadUrl = await pdfRef.getDownloadURL();
          print('🔍 DEBUG: Download URL obtained: $downloadUrl');
          
          final response = await http.get(Uri.parse(downloadUrl));
          if (response.statusCode == 200) {
            pdfBytes = response.bodyBytes;
            print('🔍 DEBUG: Download via URL successful!');
          } else {
            print('❌ DEBUG: HTTP download failed with status: ${response.statusCode}');
          }
        } catch (urlError) {
          print('❌ DEBUG: Download via URL failed: $urlError');
        }
      }
      
      if (pdfBytes != null) {
        print('🔍 DEBUG: File downloaded successfully!');
        print('🔍 DEBUG: File size: ${pdfBytes.length} bytes');
        
        if (kIsWeb) {
          print('🔍 DEBUG: Saving file on web platform...');
          await FileSaver.instance.saveFile(
            name: fileName,
            bytes: pdfBytes,
            mimeType: MimeType.pdf,
          );
          print('🔍 DEBUG: File saved successfully on web');
        } else {
          print('🔍 DEBUG: Saving file on mobile platform...');
          final directory = await getApplicationDocumentsDirectory();
          final file = File('${directory.path}/$fileName');
          await file.writeAsBytes(pdfBytes);
          print('🔍 DEBUG: File saved to: ${file.path}');
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ISSP downloaded successfully as $fileName'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        print('❌ DEBUG: File download returned null bytes');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No compiled ISSP file found. Please contact the administrator.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Download error: $e');
      print('❌ DEBUG: Error type: ${e.runtimeType}');
      print('❌ DEBUG: Error stack trace:');
      print(e);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: Text('ISSP ${widget.yearRange}'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2D3748),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const StartupTimePage()),
            );
          },
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xff021e84).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  size: 80,
                  color: Color(0xff021e84),
                ),
              ),
              
              const SizedBox(height: 32),
              
              const Text(
                'ISSP Completed',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xff021e84),
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 16),
              
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Text(
                  'This ISSP has already been finished, you are only able to download the compiled plan.',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.black87,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              
              const SizedBox(height: 32),
              
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isDownloading ? null : _downloadISSP,
                  icon: _isDownloading 
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.download),
                  label: Text(
                    _isDownloading ? 'Downloading...' : 'Download ISSP',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff021e84),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xff021e84).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xff021e84).withOpacity(0.2),
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
                        'The compiled ISSP document contains all completed sections in a single file.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xff021e84),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 