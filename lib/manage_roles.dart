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
  final int _rowsPerPage = 10;
  final List<String> _allRoles = ['user', 'admin', 'manager'];
  final Map<String, String> _editedRoles = {};
  final DateFormat _fmt = DateFormat.yMd().add_jm();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  String _filterText = '';
  int _currentPage = 0;
  bool _createdAtAscending = true;

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
        _currentPage = 0; 
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

        docs.sort((a, b) {
          final aData = a.data()! as Map<String, dynamic>;
          final bData = b.data()! as Map<String, dynamic>;
          final aIsAdmin = (aData['role'] ?? '').toString().toLowerCase() == 'admin';
          final bIsAdmin = (bData['role'] ?? '').toString().toLowerCase() == 'admin';
          if (aIsAdmin && !bIsAdmin) return -1;
          if (!aIsAdmin && bIsAdmin) return 1;
          final aCreated = aData['createdAt'] as Timestamp?;
          final bCreated = bData['createdAt'] as Timestamp?;
          if (aCreated != null && bCreated != null) {
            return _createdAtAscending
                ? aCreated.compareTo(bCreated)
                : bCreated.compareTo(aCreated);
          }
          return 0;
        });

        if (_currentPage * _rowsPerPage >= docs.length && _currentPage != 0) {
          _currentPage = 0;
        }

        final pagedDocs = _getPagedDocs(docs);

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Manage Roles', style: const TextStyle(
                fontWeight: FontWeight.bold, 
                fontSize: 28,
                color: Color(0xff021e84),
              )),
              const SizedBox(height: 12),

              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search users…',
                      prefixIcon: const Icon(Icons.search, color: Color(0xff021e84)),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: Color(0xff021e84)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: Color(0xff021e84)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: Color(0xff021e84), width: 2),
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xff021e84), width: 1),
                        ),
                        elevation: 0,
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                username,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xff021e84),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                email,
                                style: const TextStyle(color: Colors.grey, fontSize: 14),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Created: $createdAt',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: const Color(0xff021e84)),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: DropdownButton<String>(
                                        value: edited,
                                        isExpanded: true,
                                        underline: const SizedBox(),
                                        items: _allRoles.map((r) => DropdownMenuItem(
                                          value: r,
                                          child: Text(
                                            r,
                                            style: const TextStyle(color: Color(0xff021e84)),
                                          ),
                                        )).toList(),
                                        onChanged: (v) {
                                          if (v == null) return;
                                          setState(() => _editedRoles[id] = v);
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.save, color: Color(0xff021e84)),
                                    onPressed: () {
                                      final newRole = _editedRoles[id];
                                      if (newRole != null && newRole != currentRole) {
                                        FirebaseFirestore.instance
                                            .collection('users')
                                            .doc(id)
                                            .update({'role': newRole});
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Role updated'),
                                            backgroundColor: Color(0xff021e84),
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
                Expanded(
                  child: Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 2,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          decoration: const BoxDecoration(
                            color: Color(0xff021e84),
                            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                          ),
                          child: Row(
                            children: [
                              const _HeaderCell('Username', flex: 3, textColor: Colors.white),
                              const _HeaderCell('Email', flex: 4, textColor: Colors.white),
                              Expanded(
                                flex: 3,
                                child: Row(
                                  children: [
                                    const Text(
                                      'Created At',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      icon: Icon(
                                        _createdAtAscending ? Icons.arrow_upward : Icons.arrow_downward,
                                        color: Colors.yellow,
                                        size: 18,
                                      ),
                                      tooltip: _createdAtAscending ? 'Sort by newest' : 'Sort by oldest',
                                      onPressed: () {
                                        setState(() => _createdAtAscending = !_createdAtAscending);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const _HeaderCell('Role', flex: 1, textColor: Colors.white),
                              const Spacer(flex: 1),
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
                          decoration: const BoxDecoration(
                            color: Color(0xfff4f6fa),
                            borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              RichText(
                                text: TextSpan(
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black87),
                                  children: [
                                    const TextSpan(text: 'Page '),
                                    TextSpan(
                                      text: '${_currentPage + 1}',
                                      style: const TextStyle(
                                        color: Color(0xff021e84),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    TextSpan(text: ' of ${((docs.length - 1) ~/ _rowsPerPage) + 1}'),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  _PrettyNavButton(
                                    label: 'Previous',
                                    enabled: _currentPage > 0,
                                    onTap: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
                                  ),
                                  const SizedBox(width: 8),
                                  _PrettyNavButton(
                                    label: 'Next',
                                    enabled: (_currentPage + 1) * _rowsPerPage < docs.length,
                                    onTap: (_currentPage + 1) * _rowsPerPage < docs.length ? () => setState(() => _currentPage++) : null,
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
  final String text;
  final int flex;
  final Color textColor;

  const _HeaderCell(this.text, {required this.flex, this.textColor = const Color(0xff021e84)});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }
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
      child: Container(
        color: _hovering ? const Color(0xff021e84).withOpacity(0.05) : Colors.white,
        child: widget.child,
      ),
    );
  }
}

class _PrettyNavButton extends StatefulWidget {
  final String label;
  final bool enabled;
  final VoidCallback? onTap;
  const _PrettyNavButton({required this.label, required this.enabled, this.onTap});

  @override
  State<_PrettyNavButton> createState() => _PrettyNavButtonState();
}

class _PrettyNavButtonState extends State<_PrettyNavButton> {
  bool _hovering = false;
  @override
  Widget build(BuildContext context) {
    final color = widget.enabled
        ? (_hovering ? const Color(0xff021e84).withOpacity(0.85) : const Color(0xff021e84))
        : Colors.grey.shade400;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: widget.enabled ? color.withOpacity(0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}
