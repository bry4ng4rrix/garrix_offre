import 'package:flutter/material.dart';

// TODO(agent E) : page provisoire, à remplacer par l'implémentation complète.
class SourceDetailPage extends StatelessWidget {
  const SourceDetailPage({super.key, required this.sourceId});

  final String sourceId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Source')),
    body: const Center(child: Text('À venir')),
  );
}
