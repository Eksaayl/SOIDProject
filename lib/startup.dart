import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/selection_model.dart';
import 'landing.dart';

class StartupPage extends StatelessWidget {
  const StartupPage({super.key});

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
  Widget build(BuildContext context) {
    final selection = context.watch<SelectionModel>().selected;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose the Project',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall!
                    .copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Display the selected projects, you can choose more than one!',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium!
                    .copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),

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
                          color: sel
                              ? Colors.lightBlue.shade50
                              : Colors.white,
                          border: Border.all(
                            color: sel
                                ? Color(0xff021e84)
                                : Colors.grey.shade300,
                            width: sel ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            context.read<SelectionModel>().toggle(i);
                          },
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                c.icon,
                                size: 32,
                                color: sel
                                    ? Color(0xff021e84)
                                    : Colors.black54,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                c.label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: sel
                                      ? Color(0xff021e84)
                                      : Colors.black87,
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

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xff021e84),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: selection.isEmpty
                      ? null
                      : () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const Landing()),
                    );
                  },
                  child: const Text(
                    'Get Started!',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
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
