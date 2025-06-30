import 'package:flutter/material.dart';
import 'landing.dart';
import 'package:provider/provider.dart';
import 'state/selection_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StartupTimePage extends StatefulWidget {
  final bool fromSettings;
  const StartupTimePage({super.key, this.fromSettings = false});

  @override
  State<StartupTimePage> createState() => _StartupTimePageState();
}

class _StartupTimePageState extends State<StartupTimePage> {
  static const double _minTileWidth = 120;

  final List<String> _timeRanges = List.generate(9, (i) {
    final start = 2027 + i * 3;
    final end = start + 2;
    return '$start-$end';
  });

  int? _selected;

  String _getYearCode(int index) {
    final start = 2027 + index * 3;
    return '${start.toString().substring(2)}${(start + 2).toString().substring(2)}';
  }

  @override
  void initState() {
    super.initState();
    if (widget.fromSettings) {
      _syncSelectionWithYearRange();
    }
  }

  Future<void> _syncSelectionWithYearRange() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (!userDoc.exists) return;
    
    final yearRange = userDoc.data()?['year_range'] as String?;
    if (yearRange != null) {
      for (int i = 0; i < _timeRanges.length; i++) {
        if (_getYearCode(i) == yearRange) {
          if (mounted) {
            setState(() {
              _selected = i;
            });
          }
          break;
        }
      }
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

      if (_selected == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a time range'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final yearCode = _getYearCode(_selected!);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'year_range': yearCode,
      }, SetOptions(merge: true));

      context.read<SelectionModel>().setYearRange(yearCode);

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Time range updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      if (widget.fromSettings) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const Landing()),
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
                    'Choose the Time Range',
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
                            widget.fromSettings 
                                ? 'Select one time range to update your preference.'
                                : 'Select one time range to proceed.',
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
                    SizedBox(height: 24),

                    Expanded(
                      child: LayoutBuilder(builder: (ctx, constraints) {
                        final raw = constraints.maxWidth ~/ _minTileWidth;
                        final maxCols = _timeRanges.length < 9 ? _timeRanges.length : 9;
                        final count = raw.clamp(3, maxCols);

                        return GridView.builder(
                          itemCount: _timeRanges.length,
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: count,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.8,
                          ),
                          itemBuilder: (ctx, i) {
                            final label = _timeRanges[i];
                            final sel = _selected == i;
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
                                  setState(() {
                                    if (_selected == i) {
                                      _selected = null;
                                    } else {
                                      _selected = i;
                                    }
                                  });
                                },
                                child: Center(
                                  child: Text(
                                    label,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                                      color: sel ? Color(0xff021e84) : Colors.grey.shade800,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      }),
                    ),

                    SizedBox(height: 24),
                    InkWell(
                      onTap: () => _handleGetStarted(context),
                      child: Container(
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Color(0xff021e84),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            widget.fromSettings ? 'Update Time Range!' : 'Get Started!',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
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