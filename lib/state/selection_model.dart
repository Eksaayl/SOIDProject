import 'package:flutter/foundation.dart';

class SelectionModel extends ChangeNotifier {
  final Set<int> _selected = {};

  Set<int> get selected => _selected;

  void toggle(int i) {
    if (_selected.contains(i)) {
      _selected.remove(i);
    } else {
      _selected.add(i);
    }
    notifyListeners();
  }

  void setAll(Set<int> indices) {
    _selected
      ..clear()
      ..addAll(indices);
    notifyListeners();
  }
}
