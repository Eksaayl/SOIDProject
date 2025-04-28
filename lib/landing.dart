// lib/landing.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'login.dart';
import 'manage_roles.dart';

class Landing extends StatefulWidget {
  const Landing({Key? key}) : super(key: key);

  @override
  State<Landing> createState() => _LandingState();
}

class _LandingState extends State<Landing> {
  static const double _sidebarWidth = 200.0;
  static const double _breakpoint   = 800.0;

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
    // logout is last bottom
    if (idx == totalMain + bottomItems.length - 1) {
      await FirebaseAuth.instance.signOut();
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
      return;
    }

    setState(() => _selectedIndex = idx);
    if (MediaQuery.of(context).size.width < _breakpoint) {
      Navigator.of(context).pop();
    }
  }

  Widget _buildSidebar(bool isDrawer) {
    final mainItems = <_NavItemData>[
      _NavItemData(Icons.home, 'Home', const Center(child: Text('Home Page'))),
      if (_isAdmin)
        _NavItemData(Icons.group, 'Manage Roles', const ManageRolesPage()),
      _NavItemData(Icons.devices, 'Devices', const Center(child: Text('Devices Page'))),
      _NavItemData(Icons.apps, 'Applications', const Center(child: Text('Applications Page'))),
      _NavItemData(Icons.shopping_basket, 'Orders', const Center(child: Text('Orders Page'))),
      _NavItemData(Icons.store, 'Store', const Center(child: Text('Store Page'))),
    ];

    final bottomItems = <_NavItemData>[
      _NavItemData(Icons.settings, 'Settings', const Center(child: Text('Settings Page'))),
      _NavItemData(Icons.logout, 'Logout', null),
    ];

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo + Title
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Image.asset('assets/images/PSA.png', width: 32, height: 32),
                const SizedBox(width: 8),
                const Text(
                  'Dashboard',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          const Divider(),

          // Main nav
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

          // Bottom nav
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

    // recompute so pages line up
    final mainItems = <_NavItemData>[
      _NavItemData(Icons.home, 'Home', const Center(child: Text('Home Page'))),
      if (_isAdmin)
        _NavItemData(Icons.group, 'Manage Roles', const ManageRolesPage()),
      _NavItemData(Icons.devices, 'Devices', const Center(child: Text('Devices Page'))),
      _NavItemData(Icons.apps, 'Applications', const Center(child: Text('Applications Page'))),
      _NavItemData(Icons.shopping_basket, 'Orders', const Center(child: Text('Orders Page'))),
      _NavItemData(Icons.store, 'Store', const Center(child: Text('Store Page'))),
    ];
    final bottomItems = <_NavItemData>[
      _NavItemData(Icons.settings, 'Settings', const Center(child: Text('Settings Page'))),
      _NavItemData(Icons.logout, 'Logout', null),
    ];

    final totalMain = mainItems.length;
    Widget page;
    if (_selectedIndex < totalMain) {
      page = mainItems[_selectedIndex].page!;
    } else {
      page = bottomItems[_selectedIndex - totalMain].page ?? const SizedBox();
    }

    return Scaffold(
      appBar: isDrawer
          ? AppBar(
        title: const Text('Dashboard'),
        leading: Builder(builder: (ctx) {
          return IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          );
        }),
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
                // Top bar
                Container(
                  height: 64,
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (!isDrawer) const SizedBox(width: 12),
                      if (!isDrawer)
                        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: _userDocStream,
                          builder: (ctx, snap) {
                            if (!snap.hasData) return const Text('Loading…');
                            final data = snap.data!.data()!;
                            final role = (data['role'] as String?)?.toLowerCase() ?? '';
                            final rawUsername = data['username'] as String? ?? '';
                            final displayName = role == 'admin' ? 'Admin' : rawUsername;
                            final email = data['email'] as String? ?? '';
                            return Row(
                              children: [
                                const SizedBox(width: 12),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(displayName,
                                        style: const TextStyle(fontWeight: FontWeight.bold)),
                                    if (email.isNotEmpty)
                                      Text(email, style: const TextStyle(color: Colors.grey)),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                    ],
                  ),
                ),

                Expanded(child: Container(color: const Color(0xFFF5F5F5), child: page)),
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
        ? Colors.blue.shade50
        : (_hovering ? Colors.grey.shade200 : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        color: bg,
        child: ListTile(
          leading: Icon(widget.icon, color: Colors.black54),
          title: Text(widget.label, style: const TextStyle(color: Colors.black87)),
          onTap: widget.onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          horizontalTitleGap: 16,
          minLeadingWidth: 32,
        ),
      ),
    );
  }
}
