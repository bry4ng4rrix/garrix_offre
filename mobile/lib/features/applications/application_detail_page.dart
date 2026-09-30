import 'package:flutter/material.dart';

// TODO(agent B) : page provisoire, à remplacer par l'implémentation complète.
class ApplicationDetailPage extends StatelessWidget {
  const ApplicationDetailPage({super.key, required this.applicationId});

  final String applicationId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Candidature')),
    body: const Center(child: Text('À venir')),
  );
}
