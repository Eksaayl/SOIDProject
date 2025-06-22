import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'state/selection_model.dart';
import 'landing.dart';
import 'startup_time.dart';

class StartupPage extends StatefulWidget {
  final bool fromSettings;
  const StartupPage({super.key, this.fromSettings = false});

  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {
  static const double _minTileWidth = 120;

  final List<_Choice> _choices = const [
    _Choice('COMMUNITY-BASED MONITORING SYSTEM (CBMS)', Icons.map),
    _Choice('CENSUS OF POPULATION AND HOUSING (POPCEN)', Icons.people),
    _Choice('CENSUS OF AGRICULTURE AND FISHERIES (CAF)', Icons.agriculture),
    _Choice('PHILIPPINE IDENTIFICATION SYSTEM (PHILSYS)', Icons.fingerprint),
    _Choice('FAMILY INCOME AND EXPENDITURE SURVEY (FIES)', Icons.attach_money),
    _Choice('FUNCTIONAL LITERACY AND MASS MEDIA SURVEY (FLEMMS)', Icons.menu_book),
    _Choice('PHILIPPINE CIVIL REGISTRATION AND VITAL STATISTICS (CRVS) SYSTEM', Icons.fiber_manual_record),
    _Choice('ANNUAL POVERTY INDICATORS SURVEY (APIS)', Icons.bar_chart),
    _Choice('SURVEY OF TOURISM (STEP)', Icons.beach_access),
    _Choice('DEVELOPMENT/ENHANCEMENT OF THE DESIGN (DEDSSFIGI)', Icons.public),
    _Choice('ANNUAL SURVEY OF PHILIPPINE BUSINESS AND INDUSTRY (ASPBI)', Icons.business),
    _Choice('CENSUS OF PHILIPPINE BUSINESS AND INDUSTRY (CPBI)', Icons.account_balance),
    _Choice('NATIONAL DEMOGRAPHIC AND HEALTH SURVEY (NDHS)', Icons.health_and_safety),
    _Choice('SURVEY ON INFORMATION AND COMMUNICATION (SICT)', Icons.computer),
    _Choice('CONSUMER EXPECTATIONS SURVEY (CES)', Icons.shopping_cart),
    _Choice('REDMINE TRACKING MANAGEMENT SYSTEM (CVS)', Icons.security),
    _Choice('BUSINESS REGISTER INTEGRATED MONITORING (BRIMPS)', Icons.folder_shared),
    _Choice('OWS AND ISLE DATA PROCESSING AND MANAGEMENT SYSTEM (OIDPMS)', Icons.storage),
    _Choice('QUARTERLY SURVEY OF PHILIPPINE (QSPBI)', Icons.query_stats),
    _Choice('WORKPLACE APPLICATION FOR CITY (PSA)', Icons.work),
    _Choice('SOLEMNIZING OFFICERS (SOIS)', Icons.how_to_reg),
    _Choice('SURVEY ON COSTS AND RETURNS (SCR)', Icons.receipt_long),
    _Choice('SURVEY ON FOOD DEMAND (SFD)', Icons.fastfood),
    _Choice('NATIONAL MIGRATION SURVEY (NMS)', Icons.flight),
    _Choice('NATIONAL ICT HOUSEHOLD SURVEY (NICTHS)', Icons.home),
    _Choice('HOUSEHOLD SURVEY ON DOMESTIC VISITORS (HSDV)', Icons.hotel),
    _Choice('HOUSEHOLD ENERGY CONSUMPTION SURVEY (HECS)', Icons.flash_on),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.fromSettings) {
      _syncSelectionWithSubRoles();
    }
  }

  Future<void> _syncSelectionWithSubRoles() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (!userDoc.exists) return;
    final subRoles = List<String>.from(userDoc.data()?['sub_roles'] ?? []);
    final indices = <int>{};
    for (int i = 0; i < _choices.length; i++) {
      if (subRoles.contains(_choices[i].label)) {
        indices.add(i);
      }
    }
    if (mounted) {
      Provider.of<SelectionModel>(context, listen: false).setAll(indices);
    }
  }

  Future<void> _handleGetStarted(BuildContext context) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You must be logged in to continue'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final selection = Provider.of<SelectionModel>(context, listen: false).selected;
      if (selection.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select at least one project'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final selectedProjects = selection.map((index) => _choices[index].label).toSet().toList();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'sub_roles': selectedProjects,
      }, SetOptions(merge: true));

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Projects updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      if (widget.fromSettings) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const Landing()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const StartupTimePage()),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<SelectionModel>().selected;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Color(0xff021e84),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xff021e84).withOpacity(0.2),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose the Project',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.white,
                          size: 24,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Display the selected projects, you can choose more than one!',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white,
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

            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            final selectionModel = context.read<SelectionModel>();
                            if (selectionModel.selected.length == _choices.length) {
                              selectionModel.clear();
                            } else {
                              selectionModel.selectAll(_choices.length);
                            }
                          },
                          icon: Icon(
                            context.watch<SelectionModel>().selected.length == _choices.length
                                ? Icons.deselect
                                : Icons.select_all,
                            color: Colors.white,
                          ),
                          label: Text(
                            context.watch<SelectionModel>().selected.length == _choices.length
                                ? 'Deselect All'
                                : 'Select All',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xff021e84),
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 24),

                    Expanded(
                      child: LayoutBuilder(builder: (ctx, constraints) {
                        final raw = constraints.maxWidth ~/ _minTileWidth;
                        final maxCols = _choices.length < 9 ? _choices.length : 9;
                        final count = raw.clamp(3, maxCols);

                        return GridView.builder(
                          itemCount: _choices.length,
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: count,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.55,
                          ),
                          itemBuilder: (ctx, i) {
                            final c = _choices[i];
                            final sel = selection.contains(i);
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                color: sel ? Color(0xff021e84).withOpacity(0.1) : Colors.white,
                                border: Border.all(
                                  color: sel ? Color(0xff021e84) : Colors.grey.shade200,
                                  width: sel ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: sel 
                                        ? Color(0xff021e84).withOpacity(0.1)
                                        : Colors.black.withOpacity(0.05),
                                    blurRadius: 8,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  context.read<SelectionModel>().toggle(i);
                                },
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: sel 
                                            ? Color(0xff021e84).withOpacity(0.1)
                                            : Colors.grey.shade50,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        c.icon,
                                        size: 32,
                                        color: sel ? Color(0xff021e84) : Colors.grey.shade600,
                                      ),
                                    ),
                                    SizedBox(height: 16),
                                    Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 12),
                                      child: Text(
                                        c.label,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                                          color: sel ? Color(0xff021e84) : Colors.grey.shade800,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      }),
                    ),

                    SizedBox(height: 24),
                    InkWell(
                      onTap: () {
                        _handleGetStarted(context);
                      },
                      child: Container(
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Color(0xff021e84),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Text(
                            'Get Started!',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Choice {
  final String label;
  final IconData icon;
  const _Choice(this.label, this.icon);
}
