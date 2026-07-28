import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/verse.dart';
import '../providers/player_provider.dart';
import '../services/diagnostic_log.dart';
import '../services/quran_api.dart';
import '../providers/recitation_provider.dart';
import 'karaoke_recitation_screen.dart';

/// Harnais de RECETTE — écran unique, pilotable par intent, pour le banc à deux
/// téléphones (décision utilisateur 2026-07-28).
///
/// ── POURQUOI IL EXISTE ──────────────────────────────────────────────────────
/// Chaque test de la chaîne de récitation demandait jusqu'ici une navigation
/// manuelle identique sur DEUX appareils : ouvrir l'app, choisir la sourate,
/// entrer dans l'écran, lancer. Refait à la main à chaque itération, c'est du
/// temps perdu et une source de variations entre deux mesures censées être
/// comparables — or comparer deux sessions n'a de sens que si le protocole est
/// strictement le même.
///
/// Ici : une commande, un écran, aucun tap.
///
///     # le Xiaomi joue le récitateur
///     adb -s <xiaomi> shell am start -n com.corankarim.coran_karim/.MainActivity \
///         --es recette lecture --ei sourate 105
///     # le Samsung écoute et juge
///     adb -s <samsung> shell am start -n com.corankarim.coran_karim/.MainActivity \
///         --es recette ecoute --ei sourate 105
///
/// ── POURQUOI PAS DES `input tap` ────────────────────────────────────────────
/// Les coordonnées dépendent de l'écran, de la langue et de l'état de
/// navigation. Un tap qui rate ne se voit pas dans le log : on analyse alors
/// une session qui n'a jamais démarré, ou pas dans le bon mode. L'intent porte
/// le mode et la sourate explicitement, et [DiagnosticLog] les écrit — la
/// session dit elle-même ce qu'elle teste.
class RecetteScreen extends ConsumerStatefulWidget {
  const RecetteScreen(
      {super.key, this.mode, this.surah = 2, this.limite = 20, this.wav});

  /// `ecoute` (l'app juge) ou `lecture` (l'app joue le récitateur).
  /// Null = l'utilisateur choisit sur place (accès manuel depuis l'accueil).
  final String? mode;

  /// Défaut 2 (Al-Baqara) : c'est le passage sur lequel toutes les mesures de
  /// la chaîne ont été faites jusqu'ici — changer de sourate rendrait les
  /// sessions incomparables entre elles.
  final int surah;

  /// Nombre de versets retenus (défaut 20, demande utilisateur). Al-Baqara en
  /// compte 286 : les charger tous allongerait chaque itération sans rien
  /// apprendre de plus, et l'écran de récitation pagine de toute façon.
  final int limite;

  /// WAV rejoué À LA PLACE du micro, pour une recette DÉTERMINISTE.
  ///
  /// Le banc à deux téléphones passe par haut-parleur → micro : chaque passe
  /// diffère (point de départ, niveau, bruit de pièce). Mesuré : le même
  /// binaire sur la même sourate donne 1,4 % puis 4,3 % de mots non verts, et
  /// les passes vont de 0,0 % à 10,9 %. La variance dépasse alors l'effet
  /// cherché, et tout « gain » annoncé serait du bruit.
  final String? wav;

  @override
  ConsumerState<RecetteScreen> createState() => _RecetteScreenState();
}

class _RecetteScreenState extends ConsumerState<RecetteScreen> {
  List<Verse>? _verses;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final tout = await QuranApi.fetchVerses(widget.surah);
      final v = tout.length > widget.limite ? tout.sublist(0, widget.limite) : tout;
      if (!mounted) return;
      setState(() => _verses = v);
      DiagnosticLog.log('RECETTE',
          'sourate=${widget.surah} versets=${v.length}/${tout.length} '
          'mode=${widget.mode ?? "manuel"}');
      // Mode imposé par l'intent : on enchaîne sans attendre un tap.
      if (widget.mode == 'ecoute') {
        if (widget.wav != null) {
          ref.read(recitationVerifierProvider).wavRejoue = widget.wav;
          DiagnosticLog.log('RECETTE', 'source deterministe : ${widget.wav}');
        }
        _ecouter();
      } else if (widget.mode == 'lecture') {
        _lire();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = '$e');
      DiagnosticLog.log('RECETTE', 'chargement sourate ${widget.surah} echoue : $e');
    }
  }

  void _ecouter() {
    final v = _verses;
    if (v == null || v.isEmpty || !mounted) return;
    DiagnosticLog.log('RECETTE', 'ECOUTE : ouverture de la recitation');
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => KaraokeRecitationScreen(
              verses: v,
              // Piloté par intent : on atterrit DANS la récitation déjà lancée,
              // sans tap. Depuis l'accès manuel (bouton), on laisse l'écran se
              // comporter normalement.
              autoDemarrer: widget.mode == 'ecoute',
              // Le récitateur ne dit pas la Basmala : la garder décalerait les
              // deux téléphones de quatre mots dès le départ.
              sansBasmala: widget.mode == 'ecoute',
            )));
  }

  Future<void> _lire() async {
    final v = _verses;
    if (v == null || v.isEmpty) return;
    DiagnosticLog.log('RECETTE',
        'LECTURE : ${v.length} versets de la sourate ${widget.surah}');
    // Le premier verset amorce la lecture, la liste complète sert de playlist :
    // le lecteur enchaîne alors seul jusqu'au bout de la sourate, ce qui est
    // exactement le protocole voulu (le téléphone récitateur ne doit demander
    // aucune intervention pendant que l'autre juge).
    await ref.read(playerProvider.notifier).play(v.first, v);
  }

  @override
  Widget build(BuildContext context) {
    final v = _verses;
    return Scaffold(
      appBar: AppBar(title: Text('Recette — sourate ${widget.surah}')),
      body: Center(
        child: _erreur != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Chargement impossible :\n$_erreur',
                    textAlign: TextAlign.center))
            : v == null
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${v.length} versets chargés',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 32),
                      FilledButton.icon(
                        onPressed: _ecouter,
                        icon: const Icon(Icons.mic),
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(260, 64)),
                        label: const Text('ÉCOUTER (juge)'),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _lire,
                        icon: const Icon(Icons.play_arrow),
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(260, 64)),
                        label: const Text('LIRE (récitateur)'),
                      ),
                    ],
                  ),
      ),
    );
  }
}
