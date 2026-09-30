import 'package:flutter/material.dart';

// TODO(agent A) : page provisoire, à remplacer par l'implémentation complète.
class JobDetailPage extends StatelessWidget {
  const JobDetailPage({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Offre')),
    body: const Center(child: Text('À venir')),
  );
}
