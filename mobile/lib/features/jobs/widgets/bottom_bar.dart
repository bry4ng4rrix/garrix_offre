import 'package:flutter/material.dart';

import '../../../core/widgets/ui.dart';

/// [BottomActionBar] utilisable dans `Scaffold.bottomNavigationBar`.
///
/// Le Scaffold donne à cet emplacement toute la hauteur de l'écran comme contrainte
/// maximale ; l'`Align` interne de `PageBody` prendrait alors toute la hauteur. La colonne
/// « taille minimale » ramène la barre à sa hauteur naturelle.
class BottomBar extends StatelessWidget {
  const BottomBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [BottomActionBar(children: children)],
  );
}
