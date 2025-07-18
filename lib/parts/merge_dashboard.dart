import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:provider/provider.dart';
import '../state/selection_model.dart';
import 'package:file_saver/file_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config.dart';

class MergeDashboard extends StatefulWidget {
  const MergeDashboard({Key? key}) : super(key: key);

  @override
  State<MergeDashboard> createState() => _MergeDashboardState();
}

class _MergeDashboardState extends State<MergeDashboard> {
  Map<String, Map<String, dynamic>> _partStatus = {};
  bool _isLoadingStatus = true;
  bool _isMerging = false;

  @override
  void initState() {
    super.initState();
    _loadPartStatus();
  }

  Future<void> _loadPartStatus() async {
    setState(() => _isLoadingStatus = true);
    try {
      final yearRange = context.read<SelectionModel>().yearRange ?? '2729';
      final firestore = FirebaseFirestore.instance;
      final sections = {
        'Part I': ['I.A', 'I.B', 'I.C', 'I.D', 'I.E'],
        'Part II': ['II.A', 'II.B', 'II.C', 'II.D'],
        'Part III': ['III.A', 'III.B', 'III.C'],
        'Part IV': ['IV.A', 'IV.B'],
        'Part V': ['V.A', 'V.B', 'V.C', 'V.D'],
      };
      final Map<String, Map<String, dynamic>> newStatus = {};
      for (final part in sections.keys) {
        newStatus[part] = {
          'sections': <String, Map<String, dynamic>>{},
          'ready': true,
          'missing': <String>[],
          'notFinalized': <String>[],
        };
        final futures = sections[part]!.map((section) =>
          firestore
            .collection('issp_documents')
            .doc(yearRange)
            .collection('sections')
            .doc(section)
            .get()
            .then((doc) => MapEntry(section, doc))
            .catchError((e) => MapEntry(section, null))
        ).toList();
        final results = await Future.wait(futures);
        for (final entry in results) {
          final section = entry.key;
          final doc = entry.value;
          try {
            final dataRaw = doc?.data();
            final data = (dataRaw == null)
                ? <String, dynamic>{}
                : (dataRaw is Map<String, dynamic> ? dataRaw : Map<String, dynamic>.from(dataRaw));
            final isFinalized = data.isNotEmpty && ((data['isFinalized'] as bool? ?? false));
            bool hasDocument = false;
            if (data.isNotEmpty) {
              if (section == 'III.C') {
                hasDocument = (data['isFinalized'] == true || data['isFinalized'] == 'true');
              } else {
                final possibleFields = ['fileUrl', 'docxUrl', 'url', 'documentUrl'];
                for (final field in possibleFields) {
                  if (data[field] != null) {
                    hasDocument = true;
                    break;
                  }
                }
              }
            }
            newStatus[part]!['sections'][section] = {
              'finalized': isFinalized,
              'hasDocument': hasDocument,
              'ready': isFinalized && hasDocument,
            };
            if (data.containsKey('isFinalized') && data['isFinalized'] == false) {
              (newStatus[part]!['notFinalized'] as List<String>).add(section);
              newStatus[part]!['ready'] = false;
            }
            if (!hasDocument) {
              (newStatus[part]!['missing'] as List<String>).add(section);
              newStatus[part]!['ready'] = false;
            }
          } catch (e) {
            newStatus[part]!['sections'][section] = {
              'finalized': false,
              'hasDocument': false,
              'ready': false,
            };
            (newStatus[part]!['notFinalized'] as List<String>).add(section);
            (newStatus[part]!['missing'] as List<String>).add(section);
            newStatus[part]!['ready'] = false;
          }
        }
      }
      setState(() {
        _partStatus = newStatus;
      });
    } catch (e) {
      print('Error loading part status: $e');
    } finally {
      setState(() => _isLoadingStatus = false);
    }
  }

  Future<void> _mergeAllParts() async {
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
            content: Text('Missing merged files for: ${missingParts.join(", ")}'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isMerging = false);
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
        throw Exception('Failed to merge documents: ${response.statusCode} - $error');
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

  @override
  Widget build(BuildContext context) {
    if (_isLoadingStatus) {
      return const Center(child: CircularProgressIndicator());
    }
    final allReady = _partStatus.values.every((part) => part['ready'] as bool);
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;
    return Container(
      color: const Color(0xFFF7FAFC),
      child: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _DashboardHeader(
              allReady: allReady,
              isMerging: _isMerging,
              onMerge: allReady && !_isMerging ? _mergeAllParts : null,
              onRefresh: _loadPartStatus,
              isSmallScreen: isSmallScreen,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 4 : 16, vertical: isSmallScreen ? 4 : 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: isSmallScreen ? 8 : 16),
                  Text(
                    'Part Status',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 16 : 20,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2D3748),
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 8 : 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      int crossAxisCount = isSmallScreen ? 1 : 2;
                      if (!isSmallScreen && constraints.maxWidth > 1000) crossAxisCount = 3;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: isSmallScreen ? 1.1 : 1.5,
                          crossAxisSpacing: isSmallScreen ? 10 : 24,
                          mainAxisSpacing: isSmallScreen ? 10 : 24,
                        ),
                        itemCount: _partStatus.length,
                        itemBuilder: (context, index) {
                          final partName = _partStatus.keys.elementAt(index);
                          final partData = _partStatus[partName]!;
                          return _buildStatusCard(partName, partData, isSmallScreen: isSmallScreen);
                        },
                      );
                    },
                  ),
                  SizedBox(height: isSmallScreen ? 16 : 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(String partName, Map<String, dynamic> partData, {bool isSmallScreen = false}) {
    final sections = (partData['sections'] as Map).cast<String, Map<String, dynamic>>();
    final ready = partData['ready'] as bool;
    final missing = partData['missing'] as List<String>;
    final notFinalized = partData['notFinalized'] as List<String>;

    final Color accentColor = ready ? Colors.green : const Color.fromARGB(255, 255, 0, 0);
    final Color accentBg = ready ? Colors.green.withOpacity(0.08) : const Color.fromARGB(255, 255, 0, 0).withOpacity(0.08);
    final Color borderColor = ready ? Colors.green : const Color.fromARGB(255, 255, 0, 0);
    final Color cardBg = Colors.white;

    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: EdgeInsets.all(isSmallScreen ? 4 : 8),
      padding: const EdgeInsets.all(0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(isSmallScreen ? 10 : 16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.13),
            spreadRadius: 2,
            blurRadius: isSmallScreen ? 8 : 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: borderColor,
          width: isSmallScreen ? 1.5 : 2.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: isSmallScreen ? 5 : 8,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isSmallScreen ? 10 : 16),
                bottomLeft: Radius.circular(isSmallScreen ? 10 : 16),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(isSmallScreen ? 10 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(isSmallScreen ? 6 : 10),
                        decoration: BoxDecoration(
                          color: accentBg,
                          borderRadius: BorderRadius.circular(isSmallScreen ? 8 : 12),
                          boxShadow: [
                            BoxShadow(
                              color: accentColor.withOpacity(0.18),
                              blurRadius: isSmallScreen ? 6 : 12,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          ready ? Icons.check_circle : Icons.warning,
                          color: accentColor,
                          size: isSmallScreen ? 22 : 32,
                        ),
                      ),
                      SizedBox(width: isSmallScreen ? 8 : 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              partName,
                              style: TextStyle(
                                fontSize: isSmallScreen ? 16 : 22,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF2D3748),
                              ),
                            ),
                            Text(
                              ready ? 'Ready to merge' : 'Not ready',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 12 : 15,
                                color: accentColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: isSmallScreen ? 10 : 18),
                  Wrap(
                    spacing: isSmallScreen ? 6 : 10,
                    runSpacing: isSmallScreen ? 6 : 10,
                    children: sections.entries.map((entry) {
                      final sectionName = entry.key;
                      final sectionData = entry.value;
                      final finalized = sectionData['finalized'] == true || sectionData['finalized'] == 'true';
                      final hasDocument = sectionData['hasDocument'] == true;
                      Color chipColor;
                      Color chipBg;
                      IconData chipIcon;
                      if (finalized && hasDocument) {
                        chipColor = Colors.green;
                        chipBg = Colors.green.withOpacity(0.13);
                        chipIcon = Icons.check_circle;
                      } else if (finalized && !hasDocument) {
                        chipColor = Colors.blue;
                        chipBg = Colors.blue.withOpacity(0.13);
                        chipIcon = Icons.info;
                      } else {
                        chipColor = const Color.fromARGB(255, 255, 0, 0);
                        chipBg = const Color.fromARGB(255, 255, 0, 0).withOpacity(0.13);
                        chipIcon = Icons.error;
                      }
                      return Container(
                        padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 10 : 14, vertical: isSmallScreen ? 4 : 7),
                        decoration: BoxDecoration(
                          color: chipBg,
                          borderRadius: BorderRadius.circular(isSmallScreen ? 18 : 30),
                          boxShadow: [
                            if (finalized && hasDocument)
                              BoxShadow(
                                color: chipColor.withOpacity(0.18),
                                blurRadius: isSmallScreen ? 4 : 8,
                                offset: const Offset(0, 2),
                              ),
                          ],
                          border: Border.all(
                            color: chipColor,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              chipIcon,
                              size: isSmallScreen ? 13 : 18,
                              color: chipColor,
                            ),
                            SizedBox(width: isSmallScreen ? 4 : 6),
                            Text(
                              sectionName,
                              style: TextStyle(
                                fontSize: isSmallScreen ? 10 : 13,
                                fontWeight: FontWeight.w600,
                                color: chipColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  if (!ready) ...[
                    SizedBox(height: isSmallScreen ? 8 : 16),
                    if (notFinalized.isNotEmpty)
                      Row(
                        children: [
                          Icon(Icons.warning, color: const Color.fromARGB(255, 255, 0, 0), size: isSmallScreen ? 13 : 18),
                          SizedBox(width: isSmallScreen ? 4 : 6),
                          Expanded(
                            child: Text(
                              'Not finalized: ${notFinalized.join(", ")}',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 10 : 13,
                                color: const Color.fromARGB(255, 255, 0, 0),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (missing.isNotEmpty)
                      Row(
                        children: [
                          Icon(Icons.description, color: Colors.red, size: isSmallScreen ? 13 : 18),
                          SizedBox(width: isSmallScreen ? 4 : 6),
                          Expanded(
                            child: Text(
                              'Missing documents: ${missing.join(", ")}',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 10 : 13,
                                color: Colors.red,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() {}),
      onExit: (_) => setState(() {}),
      child: card,
    );
  }
}

class _DashboardHeader extends SliverPersistentHeaderDelegate {
  final bool allReady;
  final bool isMerging;
  final VoidCallback? onMerge;
  final VoidCallback onRefresh;
  final bool isSmallScreen;
  _DashboardHeader({
    required this.allReady,
    required this.isMerging,
    required this.onMerge,
    required this.onRefresh,
    required this.isSmallScreen,
  });
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xff021e84).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.dashboard,
                  color: Color(0xff021e84),
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Merge Dashboard',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3748),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: onMerge,
                icon: isMerging
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.merge_type, color: Colors.white, size: 20),
                label: Text(isMerging ? 'Merging...' : 'Merge All Parts'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff021e84),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 2,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, color: Color(0xff021e84), size: 20),
                label: const Text('Refresh Status'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xff021e84),
                  side: const BorderSide(color: Color(0xff021e84), width: 1.2),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Monitor the status of all document parts and merge them into a complete ISSP document.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF4A5568),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
  @override
  double get maxExtent => 90;
  @override
  double get minExtent => 90;
  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => true;
} 