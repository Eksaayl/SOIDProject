import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_html/flutter_html.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../admin_route_guard.dart';
import '../services/notification_service.dart';
import '../utils/user_utils.dart';
import '../utils/dialog_utils.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../state/selection_model.dart';
import '../config.dart';
import 'merge_dashboard.dart';
import 'part_iii_checklist.dart';
import 'History.dart';
import 'document_review_ui.dart';

class DocumentReview extends StatefulWidget {
  const DocumentReview({Key? key}) : super(key: key);

  @override
  State<DocumentReview> createState() => _DocumentReviewState();
}

class _DocumentReviewState extends State<DocumentReview>
    with TickerProviderStateMixin {
  late TabController _tabController;

  String _currentTitle = 'Document Review';
  String _currentSubtitle = 'Review and manage submissions';
  bool _isMerging = false;

  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Pending', 'Approved', 'Rejected'];

  Future<void> _handleMergeAllParts() async {
    if (_tabController.index == 3) {
      setState(() => _isMerging = true);
      try {
        final yearRange = context.read<SelectionModel>().yearRange ?? '2729';
        final storage = FirebaseStorage.instance;
        final mergedFilenames = [
          'part_i_merged.docx',
          'part_ii_merged.docx',
          'part_iii_merged.docx',
          'part_iv_merged.docx',
          'part_v_merged.docx',
        ];
        final missingParts = <String>[];
        final mergedFiles = <String, Uint8List>{};

        for (final filename in mergedFilenames) {
          final storagePath = '$yearRange/$filename';
          try {
            final ref = storage.ref().child(storagePath);
            final bytes = await ref.getData();
            if (bytes == null) {
              missingParts.add(filename);
            } else {
              mergedFiles[filename] = bytes;
            }
          } catch (e) {
            missingParts.add(filename);
          }
        }

        if (missingParts.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Missing merged files for: ${missingParts.join(", ")}'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        final mergeRequest = http.MultipartRequest(
          'POST',
          Uri.parse('${Config.serverUrl}/merge-all-parts'),
        );

        final partKeys = ['i', 'ii', 'iii', 'iv', 'v'];
        for (int idx = 0; idx < mergedFilenames.length; idx++) {
          final filename = mergedFilenames[idx];
          final partKey = partKeys[idx];
          mergeRequest.files.add(http.MultipartFile.fromBytes(
            partKey,
            mergedFiles[filename]!,
            filename: filename,
          ));
        }

        final response = await mergeRequest.send();
        if (response.statusCode != 200) {
          final error = await response.stream.bytesToString();
          throw Exception(
              'Failed to merge documents: ${response.statusCode} - $error');
        }

        final mergedBytes = await response.stream.toBytes();
        final fileName = 'Complete_ISSP_${yearRange}.docx';

        if (kIsWeb) {
          await FileSaver.instance.saveFile(
            name: fileName,
            bytes: mergedBytes,
            mimeType: MimeType.microsoftWord,
          );
        } else {
          final directory = await getApplicationDocumentsDirectory();
          final file = File('${directory.path}/$fileName');
          await file.writeAsBytes(mergedBytes);
          await FileSaver.instance.saveFile(
            name: fileName,
            file: file,
            mimeType: MimeType.microsoftWord,
          );
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All parts merged successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error merging documents: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        setState(() => _isMerging = false);
      }
    }
  }

  Future<void> _handleRefresh() async {
    if (_tabController.index == 3) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_updateTitle);
  }

  @override
  void dispose() {
    _tabController.removeListener(_updateTitle);
    _tabController.dispose();
    super.dispose();
  }

  void _updateTitle() {
    if (!_tabController.indexIsChanging) {
      setState(() {
        final yearRange = context.read<SelectionModel>().yearRange ?? '2729';
        final formattedYearRange = formatYearRange(yearRange);

        switch (_tabController.index) {
          case 0:
            _currentTitle = 'Document Review';
            _currentSubtitle = 'Review and manage submissions';
            break;
          case 1:
            _currentTitle = 'All Sections';
            _currentSubtitle = 'View and manage all document sections';
            break;
          case 2:
            _currentTitle = 'History';
            _currentSubtitle = formattedYearRange;
            break;
          case 3:
            _currentTitle = 'Merge Dashboard';
            _currentSubtitle = 'Monitor and merge document parts';
            break;
          case 4:
            _currentTitle = 'Part III Checklist';
            _currentSubtitle = 'Track project status and completion';
            break;
        }
      });
    }
  }

  Future<String?> _convertDocxToHtml(Uint8List bytes, String filename) async {
    final uri = Uri.parse('${Config.serverUrl}/convert-docx');
    final request = http.MultipartRequest('POST', uri)
      ..files
          .add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final response = await request.send();
    final respStr = await response.stream.bytesToString();
    if (response.statusCode == 200) {
      final data = json.decode(respStr);
      return data['html'] as String?;
    } else {
      return null;
    }
  }

  Future<void> _viewDocument(
      BuildContext context, String documentId, String sectionId) async {
    try {
      final storage = FirebaseStorage.instance;
      final ref = storage.ref().child('$documentId/$sectionId/document.docx');
      final bytes = await ref.getData();
      if (bytes != null) {
        final htmlContent = await _convertDocxToHtml(bytes, '$sectionId.docx');
        if (htmlContent != null) {
          showDialog(
            context: context,
            builder: (context) => Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.9,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white,
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xff021e84), Color(0xff1e40af)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.visibility,
                                    color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Preview: $sectionId',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        child: SingleChildScrollView(
                          child: Html(data: htmlContent),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to convert DOCX to HTML.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading document: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _downloadDocument(
      BuildContext context, String documentId, String sectionId) async {
    try {
      final storage = FirebaseStorage.instance;
      final downloadPath = '$documentId/$sectionId/document.docx';
      final ref = storage.ref().child(downloadPath);
      
      try {
        await ref.getMetadata();
      } catch (metadataError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Document not found in storage: $sectionId'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      final bytes = await ref.getData();
      if (bytes != null) {
        final downloadFileName = '${sectionId}_document.docx';
        
        if (kIsWeb) {
          await FileSaver.instance.saveFile(
            name: downloadFileName,
            bytes: bytes,
            mimeType: MimeType.microsoftWord,
          );
        } else {
          final directory = await getApplicationDocumentsDirectory();
          final file = File('${directory.path}/$downloadFileName');
          await file.writeAsBytes(bytes);
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Document downloaded successfully from storage: $sectionId'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download document: No data received from storage'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error downloading document from storage: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _updateScreeningStatus(
      BuildContext context, DocumentSnapshot section, bool approved,
      {String? rejectionMessage}) async {
    try {
      final data = section.data() as Map<String, dynamic>;
      final sectionName = data['sectionTitle'] as String? ?? 'Unknown Section';
      final createdBy = data['createdBy'] as String? ?? 'Unknown User';
      final yearRange = context.read<SelectionModel>().yearRange ?? '2729';

      if (approved) {
        await section.reference.update({
          'screening': FieldValue.delete(),
          'isFinalized': true,
          'screeningDate': FieldValue.serverTimestamp(),
          'screenedBy': await getCurrentUsername(),
        });
        await createFinalizationNotification(sectionName, yearRange);
      } else {
        await section.reference.update({
          'isFinalized': false,
          'screening': false,
          'screeningDate': FieldValue.serverTimestamp(),
          'screenedBy': await getCurrentUsername(),
          'rejectionMessage': rejectionMessage,
        });
        await createRejectionNotification(
            sectionName, rejectionMessage ?? 'No reason provided', yearRange);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approved
              ? 'Section approved and finalized successfully'
              : 'Section rejected successfully'),
          backgroundColor: approved ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _finalizeSection(
      BuildContext context, String sectionId, String sectionName) async {
    try {
      final yearRange = context.read<SelectionModel>().yearRange ?? '2729';
      await FirebaseFirestore.instance
          .collection('issp_documents')
          .doc(yearRange)
          .collection('sections')
          .doc(sectionId)
          .update({
        'isFinalized': true,
        'finalizedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error finalizing section: $e');
    }
  }

  Future<void> _showRejectionDialog(
      BuildContext context, DocumentSnapshot section) async {
    final TextEditingController _controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _PrettyRejectionDialog(controller: _controller),
    );
    if (result != null && result.isNotEmpty) {
      await _updateScreeningStatus(context, section, false,
          rejectionMessage: result);
    }
  }

  Future<void> _showReviseDialog(BuildContext context, DocumentSnapshot doc,
      Map<String, dynamic> data) async {
    try {
      final sectionName = data['sectionTitle'] as String? ?? 'Unknown Section';
      final sectionId = doc.id;
      final yearRange = context.read<SelectionModel>().yearRange ?? '2729';

      print(
          'Revise dialog called for section: $sectionName, ID: $sectionId, Year: $yearRange');

      final result = await showDialog<bool>(
        context: context,
        builder: (context) => _ReviseDialog(sectionName: sectionName),
      );

      print('Dialog result: $result');

      if (result == true) {
        await _uploadRevisedDocument(
            context, sectionId, sectionName, yearRange);
      }
    } catch (e) {
      print('Error in _showReviseDialog: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening revise dialog: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } 

  Future<void> _uploadRevisedDocument(BuildContext context, String sectionId,
      String sectionName, String yearRange) async {
    try {
      print(
          'Starting upload for section: $sectionName, ID: $sectionId, Year: $yearRange');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecting new document...'),
          backgroundColor: Color(0xff021e84),
        ),
      );

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['docx'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No file selected'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final file = result.files.first;
      if (!file.extension!.toLowerCase().contains('docx')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a DOCX file'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Uploading revised document...'),
          backgroundColor: Color(0xff021e84),
        ),
      );

      final storage = FirebaseStorage.instance;
      final storagePath = '$yearRange/$sectionId/document.docx';
      final storageRef = storage.ref().child(storagePath);

      Uint8List fileBytes;
      if (kIsWeb) {
        fileBytes = file.bytes!;
      } else {
        final filePath = file.path!;
        final fileObj = File(filePath);
        fileBytes = await fileObj.readAsBytes();
      }

      final uploadTask = storageRef.putData(fileBytes);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('issp_documents')
          .doc(yearRange)
          .collection('sections')
          .doc(sectionId)
          .update({
        'fileUrl': downloadUrl,
        'fileName': 'document.docx',
        'uploadedAt': FieldValue.serverTimestamp(),
        'uploadedBy': await getCurrentUsername(),
        'isFinalized': false,
        'screening': true,
        'screenedBy': null,
        'screeningDate': null,
        'rejectionMessage': null,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Document revised successfully for $sectionName and set for screening'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Error in _uploadRevisedDocument: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error revising document: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildStatusChip(String status) {
    Color color;
    IconData icon;
    Color backgroundColor;
    Color borderColor;

    switch (status.toLowerCase()) {
      case 'pending':
        color = const Color(0xFFF59E0B);
        backgroundColor = const Color(0xFFFFFBEB);
        borderColor = const Color(0xFFFCD34D);
        icon = Icons.schedule;
        break;
      case 'approved':
        color = const Color(0xFF059669);
        backgroundColor = const Color(0xFFECFDF5);
        borderColor = const Color(0xFF6EE7B7);
        icon = Icons.check_circle;
        break;
      case 'rejected':
        color = const Color(0xFFDC2626);
        backgroundColor = const Color(0xFFFEF2F2);
        borderColor = const Color(0xFFFCA5A5);
        icon = Icons.cancel;
        break;
      default:
        color = const Color(0xFF6B7280);
        backgroundColor = const Color(0xFFF9FAFB);
        borderColor = const Color(0xFFD1D5DB);
        icon = Icons.help;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            status,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
      BuildContext context, DocumentSnapshot doc, Map<String, dynamic> data,
      {bool showReviseButton = true}) {
    final sectionName = data['sectionTitle'] as String? ?? 'Unknown Section';
    final createdBy = data['createdBy'] as String? ?? 'Unknown';
    final submittedAt = data['submittedAt'] as Timestamp?;
    final isFinalized = data['isFinalized'] as bool? ?? false;
    final screening = data['screening'];
    final screenedBy = data['screenedBy'];

    String status = 'Pending';
    if (isFinalized) {
      status = 'Approved';
    } else if (screening == false && screenedBy != null) {
      status = 'Rejected';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            const Color(0xFFF8FAFC),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff021e84).withOpacity(0.08),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.grey.withOpacity(0.06),
            spreadRadius: 0,
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
        border: Border.all(
          color: const Color(0xff021e84).withOpacity(0.08),
          width: 1.5,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.9),
              Colors.white.withOpacity(0.7),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xff021e84), Color(0xff1e40af)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xff021e84).withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.description,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sectionName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A202C),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.person_outline,
                                    size: 14,
                                    color: const Color(0xFF4A5568),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    createdBy,
                                    style: const TextStyle(
                                      color: Color(0xFF4A5568),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (submittedAt != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule_outlined,
                                size: 14,
                                color: const Color(0xFF718096),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatDate(submittedAt.toDate()),
                                style: const TextStyle(
                                  color: Color(0xFF718096),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  _buildStatusChip(status),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: showReviseButton ? 141 : 290,
                          child: _buildActionButton(
                            icon: Icons.download,
                            label: 'Download',
                            color: const Color(0xff021e84),
                            onPressed: () => _downloadDocument(
                                context,
                                context.read<SelectionModel>().yearRange ??
                                    '2729',
                                doc.id),
                          ),
                        ),
                        if (showReviseButton) ...[
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 141,
                            child: Tooltip(
                              message: isFinalized ? 'Click to revise this document' : 'Document must be approved before revision',
                              child: _buildActionButton(
                                icon: Icons.edit,
                                label: 'Revise',
                                color: isFinalized ? const Color(0xff021e84) : Colors.grey,
                                onPressed: isFinalized ? () {
                                  print(
                                      'Revise button pressed for section: ${doc.id}');
                                  _showReviseDialog(context, doc, data);
                                } : null,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (screening == true) ...[
                      const SizedBox(height: 16),
                      Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              const Color(0xFFE2E8F0),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 140,
                            child: _buildActionButton(
                              icon: Icons.cancel,
                              label: 'Reject',
                              color: Colors.red,
                              onPressed: () =>
                                  _showRejectionDialog(context, doc),
                            ),
                          ),
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 140,
                            child: _buildActionButton(
                              icon: Icons.check_circle,
                              label: 'Approve',
                              color: Colors.green,
                              onPressed: () async {
                                final confirmed = await DialogUtils
                                    .showApprovalConfirmationDialog(
                                  context: context,
                                  sectionName: sectionName,
                                );
                                if (confirmed == true) {
                                  await _updateScreeningStatus(
                                      context, doc, true);
                                  if (!isFinalized) {
                                    await _finalizeSection(
                                        context, doc.id, sectionName);
                                  }
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: onPressed != null ? Colors.white : Colors.white.withOpacity(0.5),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  bool _matchesFilter(Map<String, dynamic> data) {
    if (_selectedFilter == 'All') return true;

    final isFinalized = data['isFinalized'] as bool? ?? false;
    final screening = data['screening'];
    final screenedBy = data['screenedBy'];

    String status = 'Pending';
    if (isFinalized) {
      status = 'Approved';
    } else if (screening == false && screenedBy != null) {
      status = 'Rejected';
    }

    return status == _selectedFilter;
  }

  @override
  Widget build(BuildContext context) {
    return DocumentReviewUI(
      tabController: _tabController,
      currentTitle: _currentTitle,
      currentSubtitle: _currentSubtitle,
      isMerging: _isMerging,
      selectedFilter: _selectedFilter,
      filters: _filters,
      onMergeAllParts: _handleMergeAllParts,
      onRefresh: _handleRefresh,
      onFilterChanged: (filter) {
        setState(() {
          _selectedFilter = filter;
        });
      },
      buildSectionCard: _buildSectionCard,
      matchesFilter: _matchesFilter,
    );
  }
}

class _PrettyRejectionDialog extends StatelessWidget {
  final TextEditingController controller;
  const _PrettyRejectionDialog({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      elevation: 20,
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xff021e84), Color(0xff1e40af)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:
                        const Icon(Icons.cancel, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Reject Section',
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
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFECACA),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Color.fromARGB(255, 132, 2, 2),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Please provide a reason for rejecting this section. The submitter will be notified.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF7F1D1D),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Reason for rejection',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xff021e84)),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color.fromARGB(255, 132, 2, 2),
                          Color.fromARGB(255, 175, 30, 30)
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color:
                              Color.fromARGB(255, 175, 30, 30).withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(controller.text.trim()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Reject',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviseDialog extends StatelessWidget {
  final String sectionName;

  const _ReviseDialog({required this.sectionName});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      elevation: 20,
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xff021e84), Color(0xff1e40af)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:
                        const Icon(Icons.edit, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Revise Section',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFBFDBFE),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDBEAFE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.info_outline,
                      color: Color(0xFF1E40AF),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'You are about to replace the current document for "$sectionName". This will reset the approval status and require re-review.',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFF1E40AF),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xff021e84), Color(0xff1e40af)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xff021e84).withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Upload New Document',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
