import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/selection_model.dart';

class SummaryPage extends StatelessWidget {
  const SummaryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final selected = context.watch<SelectionModel>().selected.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Your Selections')),
      body: ListView.builder(
        itemCount: selected.length,
        itemBuilder: (_, i) {
          final idx = selected[i];
          return ListTile(
            title: Text('Chosen: Option #${idx + 1}'),
          );
        },
      ),
    );
  }
}
