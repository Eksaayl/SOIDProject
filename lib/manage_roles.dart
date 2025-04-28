// lib/manage_roles.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ManageRolesPage extends StatefulWidget {
  const ManageRolesPage({Key? key}) : super(key: key);

  @override
  State<ManageRolesPage> createState() => _ManageRolesPageState();
}

class _ManageRolesPageState extends State<ManageRolesPage> {
  int _rowsPerPage = 5;
  final List<String> _allRoles = ['user', 'admin', 'manager'];
  final Map<String, String> _editedRoles = {};
  final DateFormat _fmt = DateFormat.yMd().add_jm();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  String _filterText = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    // cancel any pending timer
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    // start a new one
    _debounce = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _filterText = value.trim().toLowerCase();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isNarrow = width < 600;

    return StreamBuilder<QuerySnapshot>(
      stream:
          FirebaseFirestore.instance
              .collection('users')
              .orderBy('username')
              .snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.active)
          return const Center(child: CircularProgressIndicator());

        final docs =
            (snap.data?.docs ?? []).where((d) {
              final data = d.data()! as Map<String, dynamic>;
              final name = (data['username'] as String? ?? '').toLowerCase();
              final email = (data['email'] as String? ?? '').toLowerCase();
              return name.contains(_filterText) || email.contains(_filterText);
            }).toList();

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // header + search
              Text(
                'Manage Roles',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search users…',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: const Color(0xffF4F6FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: _onSearchChanged, // <-- debounce here
                onSubmitted: _onSearchChanged, // also search on enter
              ),
              const SizedBox(height: 16),

              // choose layout
              if (isNarrow)
                // —— NARROW LAYOUT: LIST OF CARDS ——————————————
                Expanded(
                  child: ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (ctx, i) {
                      final d = docs[i];
                      final data = d.data()! as Map<String, dynamic>;
                      final id = d.id;
                      final username = data['username'] as String? ?? '';
                      final email = data['email'] as String? ?? '';
                      final ts = data['createdAt'] as Timestamp?;
                      final createdAt =
                          ts != null ? _fmt.format(ts.toDate()) : '—';
                      final currentRole = data['role'] as String? ?? '';
                      final edited = _editedRoles[id] ?? currentRole;

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                username,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                email,
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Created: $createdAt',
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButton<String>(
                                      value: edited,
                                      isExpanded: true,
                                      items:
                                          _allRoles
                                              .map(
                                                (r) => DropdownMenuItem(
                                                  value: r,
                                                  child: Text(r),
                                                ),
                                              )
                                              .toList(),
                                      onChanged: (v) {
                                        if (v == null) return;
                                        setState(() => _editedRoles[id] = v);
                                      },
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.save),
                                    onPressed: () {
                                      final newRole = _editedRoles[id];
                                      if (newRole != null &&
                                          newRole != currentRole) {
                                        FirebaseFirestore.instance
                                            .collection('users')
                                            .doc(id)
                                            .update({'role': newRole});
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('Role updated'),
                                          ),
                                        );
                                        setState(() {
                                          _editedRoles.remove(id);
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                )
              else
                // —— WIDE LAYOUT: TABLE IN CARD ————————————————
                Expanded(
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                    child: Column(
                      children: [
                        // header row
                        Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xffF4F6FA),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16),
                            ),
                          ),
                          child: Row(
                            children: const [
                              _HeaderCell('Username', flex: 2),
                              _HeaderCell('Email', flex: 3),
                              _HeaderCell('Created At', flex: 2),
                              _HeaderCell('Role', flex: 2),
                              Spacer(flex: 1),
                            ],
                          ),
                        ),
                        // body
                        Expanded(
                          child: ListView.separated(
                            itemCount: docs.length,
                            separatorBuilder:
                                (_, __) => const Divider(height: 0),
                            itemBuilder: (ctx, i) {
                              final d = docs[i];
                              final data = d.data()! as Map<String, dynamic>;
                              final id = d.id;
                              final username =
                                  data['username'] as String? ?? '';
                              final email = data['email'] as String? ?? '';
                              final ts = data['createdAt'] as Timestamp?;
                              final createdAt =
                                  ts != null ? _fmt.format(ts.toDate()) : '—';
                              final currentRole = data['role'] as String? ?? '';
                              final edited = _editedRoles[id] ?? currentRole;

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 16,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(flex: 2, child: Text(username)),
                                    Expanded(flex: 3, child: Text(email)),
                                    Expanded(flex: 2, child: Text(createdAt)),
                                    Expanded(
                                      flex: 2,
                                      child: DropdownButton<String>(
                                        value: edited,
                                        underline: const SizedBox(),
                                        isExpanded: true,
                                        items:
                                            _allRoles
                                                .map(
                                                  (r) => DropdownMenuItem(
                                                    value: r,
                                                    child: Text(r),
                                                  ),
                                                )
                                                .toList(),
                                        onChanged: (v) {
                                          if (v == null) return;
                                          setState(() => _editedRoles[id] = v);
                                        },
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: IconButton(
                                        icon: const Icon(Icons.save),
                                        onPressed: () {
                                          final newRole = _editedRoles[id];
                                          if (newRole != null &&
                                              newRole != currentRole) {
                                            FirebaseFirestore.instance
                                                .collection('users')
                                                .doc(id)
                                                .update({'role': newRole});
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text('Role updated'),
                                              ),
                                            );
                                            setState(() {
                                              _editedRoles.remove(id);
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        // pagination stub
                        Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: const [
                              Text('Page 1 of 1'),
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: null,
                                    child: Text('Previous'),
                                  ),
                                  SizedBox(width: 8),
                                  TextButton(
                                    onPressed: null,
                                    child: Text('Next'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// helpers
class _HeaderCell extends StatelessWidget {
  final String label;
  final int flex;

  const _HeaderCell(this.label, {this.flex = 1});

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(
      label,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        color: Colors.black54,
      ),
    ),
  );
}
