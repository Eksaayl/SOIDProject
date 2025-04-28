import 'package:flutter/foundation.dart';

class SelectionModel extends ChangeNotifier {
  final Set<int> _selected = {};

  /// Read-only view of selected indices
  Set<int> get selected => _selected;

  /// Toggle index in the set
  void toggle(int i) {
    if (_selected.contains(i)) {
      _selected.remove(i);
    } else {
      _selected.add(i);
    }
    notifyListeners();
  }

  /// Replace entire selection
  void setAll(Set<int> indices) {
    _selected
      ..clear()
      ..addAll(indices);
    notifyListeners();
  }
}
