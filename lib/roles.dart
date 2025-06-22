const List<String> privilegedRoles = ['admin', 'itds', 'editor'];

bool hasAccess(String? role) {
  if (role == null) return false;
  return privilegedRoles.contains(role.toLowerCase());
}

int roleRank(String role) {
  final idx = privilegedRoles.indexOf(role.toLowerCase());
  return idx == -1 ? privilegedRoles.length : idx;
} 