import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ManageRolesPage extends StatefulWidget {
  const ManageRolesPage({super.key});

  @override
  State<ManageRolesPage> createState() => _ManageRolesPageState();
}

class _ManageRolesPageState extends State<ManageRolesPage> {
  final int _rowsPerPage = 5;
  final List<String> _allRoles = ['user', 'admin', 'manager'];
  final Map<String, String> _editedRoles = {};
  final DateFormat _fmt = DateFormat.yMd().add_jm();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  String _filterText = '';
  int _currentPage = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _filterText = value.trim().toLowerCase();
        _currentPage = 0; // Reset to page 1 when searching
      });
    });
  }

  List<DocumentSnapshot> _getPagedDocs(List<DocumentSnapshot> docs) {
    final start = _currentPage * _rowsPerPage;
    final end = start + _rowsPerPage;
    return docs.sublist(
      start,
      end > docs.length ? docs.length : end,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isNarrow = width < 1150;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .orderBy('username')
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.active) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = (snap.data?.docs ?? []).where((d) {
          final data = d.data()! as Map<String, dynamic>;
          final name = (data['username'] as String? ?? '').toLowerCase();
          final email = (data['email'] as String? ?? '').toLowerCase();
          return name.contains(_filterText) || email.contains(_filterText);
        }).toList();

        if (_currentPage * _rowsPerPage >= docs.length && _currentPage != 0) {
          _currentPage = 0;
        }

        final pagedDocs = _getPagedDocs(docs);

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Manage Roles', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 28)),
              const SizedBox(height: 12),

              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search users…',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: _onSearchChanged,
                    onSubmitted: _onSearchChanged,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              if (isNarrow)
                Expanded(
                  child: ListView.builder(
                    itemCount: pagedDocs.length,
                    itemBuilder: (ctx, i) {
                      final d = pagedDocs[i];
                      final data = d.data()! as Map<String, dynamic>;
                      final id = d.id;
                      final username = data['username'] as String? ?? '';
                      final email = data['email'] as String? ?? '';
                      final ts = data['createdAt'] as Timestamp?;
                      final createdAt = ts != null ? _fmt.format(ts.toDate()) : '—';
                      final currentRole = data['role'] as String? ?? '';
                      final edited = _editedRoles[id] ?? currentRole;

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(username, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(email, style: const TextStyle(color: Colors.grey, fontSize: 14)),
                              const SizedBox(height: 8),
                              Text('Created: $createdAt', style: const TextStyle(fontSize: 12)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButton<String>(
                                      value: edited,
                                      isExpanded: true,
                                      items: _allRoles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
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
                                      if (newRole != null && newRole != currentRole) {
                                        FirebaseFirestore.instance
                                            .collection('users')
                                            .doc(id)
                                            .update({'role': newRole});
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Role updated')),
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
                Expanded(
                  child: Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 2,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xffF4F6FA),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                          ),
                          child: Row(
                            children: const [
                              _HeaderCell('Username', flex: 3),
                              _HeaderCell('Email', flex: 4),
                              _HeaderCell('Created At', flex: 3),
                              _HeaderCell('Role', flex: 1),
                              Spacer(flex: 1),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Container(
                            color: const Color(0xffF4F6FA),
                            child: ListView.separated(
                              itemCount: pagedDocs.length,
                              separatorBuilder: (_, __) => const Divider(height: 0),
                              itemBuilder: (ctx, i) {
                                final d = pagedDocs[i];
                                final data = d.data()! as Map<String, dynamic>;
                                final id = d.id;
                                final username = data['username'] as String? ?? '';
                                final email = data['email'] as String? ?? '';
                                final ts = data['createdAt'] as Timestamp?;
                                final createdAt = ts != null ? _fmt.format(ts.toDate()) : '—';
                                final currentRole = data['role'] as String? ?? '';
                                final edited = _editedRoles[id] ?? currentRole;

                                return _HoverableRow(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                    child: Row(
                                      children: [
                                        Expanded(flex: 3, child: Text(username)),
                                        Expanded(flex: 4, child: Text(email)),
                                        Expanded(flex: 3, child: Text(createdAt)),
                                        Expanded(
                                          flex: 1,
                                          child: DropdownButton<String>(
                                            value: edited,
                                            underline: const SizedBox(),
                                            isExpanded: true,
                                            items: _allRoles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
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
                                              if (newRole != null && newRole != currentRole) {
                                                FirebaseFirestore.instance
                                                    .collection('users')
                                                    .doc(id)
                                                    .update({'role': newRole});
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('Role updated')),
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
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Page ${_currentPage + 1} of ${((docs.length - 1) ~/ _rowsPerPage) + 1}'),
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: _currentPage > 0
                                        ? () => setState(() => _currentPage--)
                                        : null,
                                    child: const Text('Previous'),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: (_currentPage + 1) * _rowsPerPage < docs.length
                                        ? () => setState(() => _currentPage++)
                                        : null,
                                    child: const Text('Next'),
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

class _HoverableRow extends StatefulWidget {
  final Widget child;

  const _HoverableRow({required this.child});

  @override
  State<_HoverableRow> createState() => _HoverableRowState();
}

class _HoverableRowState extends State<_HoverableRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        color: _hovering ? Colors.grey.withOpacity(0.15) : Colors.transparent,
        child: widget.child,
      ),
    );
  }
}
