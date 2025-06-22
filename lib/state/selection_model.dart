import 'package:flutter/foundation.dart';

class SelectionModel extends ChangeNotifier {
  final Set<int> _selected = {};
  String? _yearRange;

  Set<int> get selected => _selected;
  String? get yearRange => _yearRange;

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

  void clear() {
    _selected.clear();
    notifyListeners();
  }

  void selectAll(int count) {
    _selected.clear();
    for (int i = 0; i < count; i++) {
      _selected.add(i);
    }
    notifyListeners();
  }

  void setYearRange(String yearCode) {
    _yearRange = yearCode;
    notifyListeners();
  }

  void clearYearRange() {
    _yearRange = null;
    notifyListeners();
  }
}
