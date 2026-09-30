import 'package:flutter/material.dart';

// TODO(agent A) : page provisoire, à remplacer par l'implémentation complète.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Accueil')),
    body: const Center(child: Text('À venir')),
  );
}
