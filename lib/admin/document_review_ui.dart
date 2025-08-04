import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../state/selection_model.dart';
import 'merge_dashboard.dart';
import 'part_iii_checklist.dart';
import 'History.dart';
import '../admin_route_guard.dart';
import '../utils/dialog_utils.dart';

class DocumentReviewUI extends StatelessWidget {
  // UI State
  final TabController tabController;
  final String currentTitle;
  final String currentSubtitle;
  final bool isMerging;

  // Filter State
  final String selectedFilter;
  final List<String> filters;

  // Callbacks
  final VoidCallback onMergeAllParts;
  final VoidCallback onRefresh;
  final Function(String) onFilterChanged;

  // Build Functions
  final Widget Function(BuildContext, DocumentSnapshot, Map<String, dynamic>,
      {bool showReviseButton}) buildSectionCard;
  final bool Function(Map<String, dynamic>) matchesFilter;

  const DocumentReviewUI({
    Key? key,
    required this.tabController,
    required this.currentTitle,
    required this.currentSubtitle,
    required this.isMerging,
    required this.selectedFilter,
    required this.filters,
    required this.onMergeAllParts,
    required this.onRefresh,
    required this.onFilterChanged,
    required this.buildSectionCard,
    required this.matchesFilter,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final yearRange = context.read<SelectionModel>().yearRange ?? '2729';
    return AdminRouteGuard(
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          toolbarHeight: 100,
          title: Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xff021e84).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.dashboard,
                    color: Color(0xff021e84),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentTitle,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A202C),
                        ),
                      ),
                      Text(
                        currentSubtitle,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF718096),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (tabController.index == 3) ...[
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xff021e84), Color(0xff1a365d)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xff021e84).withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: isMerging ? null : onMergeAllParts,
                          icon: isMerging
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.merge_type,
                                  color: Colors.white, size: 20),
                          label: Text(
                              isMerging ? 'Merging...' : 'Merge All Parts'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 16),
                            textStyle: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xff021e84).withOpacity(0.2),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: OutlinedButton.icon(
                          onPressed: onRefresh,
                          icon: const Icon(Icons.refresh,
                              color: Color(0xff021e84), size: 20),
                          label: const Text('Refresh'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xff021e84),
                            side: BorderSide.none,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 16),
                            textStyle: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          centerTitle: false,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(
              height: 1,
              color: const Color(0xFFE2E8F0),
            ),
          ),
        ),
        body: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TabBar(
                controller: tabController,
                indicatorColor: const Color(0xff021e84),
                indicatorWeight: 3,
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: const Color(0xff021e84),
                unselectedLabelColor: const Color(0xFF718096),
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                tabs: const [
                  Tab(text: 'Pending Review'),
                  Tab(text: 'All Sections'),
                  Tab(text: 'History'),
                  Tab(text: 'Merge Dashboard'),
                  Tab(text: 'Part III Checklist'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: tabController,
                children: [
                  _buildPendingReviewTab(yearRange),
                  _buildAllSectionsTab(yearRange),
                  const HistoryPage(),
                  MergeDashboard(
                    onMergeRequested: onMergeAllParts,
                    onRefreshRequested: onRefresh,
                  ),
                  const PartIIIChecklist(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingReviewTab(String yearRange) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('issp_documents')
          .doc(yearRange)
          .collection('sections')
          .where('screening', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Color(0xff021e84)),
                SizedBox(height: 16),
                Text(
                  'Loading pending reviews...',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF4A5568),
                  ),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'Error: ${snapshot.error}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF4A5568),
                  ),
                ),
              ],
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: Colors.green.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No sections pending review',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D3748),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'All sections have been reviewed',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF4A5568),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return buildSectionCard(context, doc, data,
                showReviseButton: false);
          },
        );
      },
    );
  }

  Widget _buildAllSectionsTab(String yearRange) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('issp_documents')
          .doc(yearRange)
          .collection('sections')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xff21e84)));
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'No sections found',
              style: TextStyle(fontSize: 16, color: Color(0xFF4A5568)),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return buildSectionCard(context, doc, data, showReviseButton: true);
          },
        );
      },
    );
  }
}
