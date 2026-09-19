import 'package:flutter/material.dart';
import 'package:upgrader/upgrader.dart';

/// Toute version plus récente détectée sur le Store impose la mise à jour.
///
/// Masquer « Ignorer » et « Plus tard » ne suffit pas : sans [blocked],
/// upgrader ferme son dialogue après le clic sur « Mettre à jour », puis
/// reporte la prochaine alerte de trois jours, même sans installation.
class ControleMiseAJourObligatoire extends Upgrader {
  ControleMiseAJourObligatoire({super.storeController});

  @override
  bool blocked() => isUpdateAvailable();
}

/// Garde le dialogue au-dessus de l'app lorsque le Store est ouvert, puis
/// au retour sans installation. Une nouvelle instance vérifie aussi au
/// redémarrage, sans tenir compte de la date de la dernière alerte.
///
/// La détection reste celle d'upgrader (fiche publique du Store). Elle ne
/// certifie pas l'éligibilité du compte à un déploiement progressif, et ne
/// découvre aucune nouvelle version sans réseau. Cf. PUBLICATION_PLAY.md.
class MiseAJourObligatoire extends StatefulWidget {
  const MiseAJourObligatoire({super.key, required this.child, this.controle});

  final Widget child;
  final ControleMiseAJourObligatoire? controle;

  @override
  State<MiseAJourObligatoire> createState() => _MiseAJourObligatoireState();
}

class _MiseAJourObligatoireState extends State<MiseAJourObligatoire> {
  late final _controle = widget.controle ?? ControleMiseAJourObligatoire();

  @override
  void dispose() {
    _controle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UpgradeAlert(
    upgrader: _controle,
    showIgnore: false,
    showLater: false,
    barrierDismissible: false,
    shouldPopScope: () => false,
    child: widget.child,
  );
}
