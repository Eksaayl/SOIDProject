import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:test_project/main_part.dart';
import 'package:test_project/state/selection_model.dart';
import 'package:test_project/settings.dart';
import 'admin_dashboard.dart';
import 'History.dart';
import 'login/login.dart';
import 'manage_roles.dart';

class Landing extends StatefulWidget {
  const Landing({super.key});

  @override
  State<Landing> createState() => _LandingState();
}

class _LandingState extends State<Landing> {
  static const double _sidebarWidth = 200.0;
  static const double _breakpoint = 800.0;

  bool _isAdmin = false;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userDocStream;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser!.uid;
    _userDocStream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots();
    _userDocStream.listen((snap) {
      if (!snap.exists) return;
      final role = (snap.data()!['role'] as String?)?.toLowerCase() ?? '';
      setState(() => _isAdmin = role == 'admin');
    });
  }

  void _onItemTap(int idx, List<_NavItemData> mainItems, List<_NavItemData> bottomItems) async {
    final totalMain = mainItems.length;
    if (idx == totalMain + bottomItems.length - 1) {
      await FirebaseAuth.instance.signOut();
      context.read<SelectionModel>().setAll({});
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      return;
    }

    setState(() => _selectedIndex = idx);
    if (MediaQuery.of(context).size.width < _breakpoint) {
      Navigator.of(context).pop();
    }
  }


  Widget _buildSidebar(bool isDrawer) {
    final mainItems = <_NavItemData>[
      _NavItemData(Icons.home, 'Home', const HorizontalTabsPage()),
      if (_isAdmin) _NavItemData(Icons.group, 'Manage Roles', const ManageRolesPage()),
      if (_isAdmin) _NavItemData(Icons.history, 'History', HistoryPage(documentId: 'document',)),
      if (_isAdmin) _NavItemData(Icons.dashboard, 'Admin Dashboard', const AdminDashboard()),
      _NavItemData(Icons.store, 'Store', const Center(child: Text('Store Page'))),
    ];

    final bottomItems = <_NavItemData>[
      _NavItemData(Icons.settings, 'Settings', const SettingsPage()),
      _NavItemData(Icons.logout, 'Logout', null),
    ];

    return Container(
      color: Color(0xff021e84),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Image.asset('assets/images/PSA.png', width: 32, height: 32),
                const SizedBox(width: 8),
                const Text(
                  'Dashboard',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          const Divider(),

          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(top: 8),
              itemCount: mainItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (ctx, i) {
                final item = mainItems[i];
                return _NavItem(
                  icon: item.icon,
                  label: item.label,
                  selected: _selectedIndex == i,
                  onTap: () => _onItemTap(i, mainItems, bottomItems),
                );
              },
            ),
          ),

          const Divider(),

          ...bottomItems.asMap().entries.map((entry) {
            final j = entry.key;
            final item = entry.value;
            final globalIndex = mainItems.length + j;
            return _NavItem(
              icon: item.icon,
              label: item.label,
              selected: _selectedIndex == globalIndex,
              onTap: () => _onItemTap(globalIndex, mainItems, bottomItems),
            );
          }).toList(),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDrawer = width < _breakpoint;

    final mainItems = <_NavItemData>[
      _NavItemData(Icons.home, 'Home', const HorizontalTabsPage()),
      if (_isAdmin) _NavItemData(Icons.group, 'Manage Roles', const ManageRolesPage()),
      if (_isAdmin) _NavItemData(Icons.history, 'History', HistoryPage(documentId: 'document',)),
      if (_isAdmin) _NavItemData(Icons.dashboard, 'Admin Dashboard', const AdminDashboard()),
      _NavItemData(Icons.store, 'Store', const Center(child: Text('Store Page'))),
    ];
    final bottomItems = <_NavItemData>[
      _NavItemData(Icons.settings, 'Settings', const SettingsPage()),
      _NavItemData(Icons.logout, 'Logout', null),
    ];

    final totalMain = mainItems.length;
    late final Widget page;
    if (_selectedIndex < totalMain) {
      page = mainItems[_selectedIndex].page!;
    } else {
      page = bottomItems[_selectedIndex - totalMain].page ?? const SizedBox();
    }

    return Scaffold(
      appBar: isDrawer
          ? AppBar(
        backgroundColor: Color(0xff021e84),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(ctx).openDrawer(),

          ),
        ),
      )
          : null,
      drawer: isDrawer
          ? Drawer(
        backgroundColor: Colors.white,
        child: SafeArea(child: _buildSidebar(true)),
      )
          : null,
      body: Row(
        children: [
          if (!isDrawer)
            SizedBox(
              width: _sidebarWidth,
              child: SafeArea(child: _buildSidebar(false)),
            ),

          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    color: const Color(0xFFF5F5F5),
                    child: page,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final String label;
  final Widget? page;
  const _NavItemData(this.icon, this.label, this.page);
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? Colors.white.withOpacity(0.1)
        : (_hovering ? Colors.white.withOpacity(0.05) : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        color: bg,
        child: ListTile(
          leading: Icon(widget.icon, color: Colors.white54),
          title: Text(widget.label, style: const TextStyle(color: Colors.white)),
          onTap: widget.onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          horizontalTitleGap: 16,
          minLeadingWidth: 32,
        ),
      ),
    );
  }
}
