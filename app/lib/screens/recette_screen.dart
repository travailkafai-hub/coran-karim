import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/verse.dart';
import '../providers/player_provider.dart';
import '../services/diagnostic_log.dart';
import '../services/quran_api.dart';
import '../providers/recitation_provider.dart';
import '../services/fastconformer_verifier.dart';
// ArabicNormalizer vit dans recitation_verifier.dart : c'est le MEME
// decoupage de mots que la v1, sinon les deux mesures porteraient sur des
// cibles differentes et ne seraient pas comparables.
import '../services/recitation_verifier.dart';
import '../services/recitation_v2_bench.dart';
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
      {super.key,
      this.mode,
      this.surah = 2,
      this.limite = 20,
      this.depart = 1,
      this.wav,
      this.normal = false,
      this.fusion = true,
      this.preuves = 2});

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

  /// PREMIER verset chargé (1 = début de la sourate, comportement historique).
  ///
  /// Ajouté le 2026-07-29 pour LE test que rien d'autre ne tranche (idée
  /// utilisateur). Le décrochage tombe presque toujours sur le même bloc de
  /// mots — 7 passes sur 8, début entre 123 et 129, fin entre 177 et 180, sur
  /// SIX versions de code différentes. Or toutes ces passes démarrent au même
  /// endroit : le point de départ est la seule variable jamais bougée de la
  /// journée, alors que la version, le modèle, la température et la taille de
  /// l'anneau de secours l'ont tous été (sans rien expliquer).
  ///
  ///   décrochage au MÊME rang de mot (~124)  -> la cause est la DURÉE écoulée
  ///                                             ou le nombre de mots traités
  ///   décrochage DÉCALÉ d'autant que le départ -> la cause est le TEXTE de ce
  ///                                             passage (Al-Baqara v13-18)
  ///
  /// Deux hypothèses qu'aucune mesure existante ne sépare, tranchées par une
  /// seule récitation.
  final int depart;

  /// WAV rejoué À LA PLACE du micro, pour une recette DÉTERMINISTE.
  ///
  /// Le banc à deux téléphones passe par haut-parleur → micro : chaque passe
  /// diffère (point de départ, niveau, bruit de pièce). Mesuré : le même
  /// binaire sur la même sourate donne 1,4 % puis 4,3 % de mots non verts, et
  /// les passes vont de 0,0 % à 10,9 %. La variance dépasse alors l'effet
  /// cherché, et tout « gain » annoncé serait du bruit.
  final String? wav;

  /// FORCE le mode normal (CTL) au lieu de la référence habituelle imposée
  /// par la recette (2026-08-05, mesure de diagnostic ponctuelle -- cf.
  /// `_ecouter`). Défaut false : tout appel existant du banc n'est pas
  /// affecté.
  final bool normal;

  /// Bloc de FUSION de la v2 (2e observation d'un énoncé vu avec le précédent).
  /// `false` le désactive, pour mesurer l'hypothèse « les aperçus 2/4
  /// suffisent » en recette RÉELLE. Défaut `true` = comportement en place.
  final bool fusion;

  /// Nombre de preuves concordantes exigées pour figer un verdict
  /// (`Decideur.k`). Défaut 2 = comportement en place. Mesuré au banc JVM sur
  /// Al-Baqara : k=1 ne libère AUCUN vert (la règle `nette` fige déjà un vert
  /// sur une seule observation attestée) et fige des rouges de position plus
  /// tôt — 14,24 % → 15,59 % de mots non verts.
  final int preuves;

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
      // `depart` est un numéro de verset (1 = premier), converti ici en index.
      // Borné des deux côtés : un départ hors sourate doit dégrader vers une
      // session vide et JOURNALISÉE, jamais lever une exception qui laisserait
      // le banc croire à un échec de chargement.
      final debut = (widget.depart - 1).clamp(0, tout.length);
      final fin = (debut + widget.limite).clamp(debut, tout.length);
      final v = tout.sublist(debut, fin);
      if (!mounted) return;
      setState(() => _verses = v);
      DiagnosticLog.log('RECETTE',
          'sourate=${widget.surah} versets=${v.length}/${tout.length} '
          'depart=v${widget.depart} '
          'mode=${widget.mode ?? "manuel"}');
      // Mode imposé par l'intent : on enchaîne sans attendre un tap.
      if (widget.mode == 'ecoute') {
        // AVANT tout démarrage : la chaîne v2 est recréée au prochain bloc
        // audio, donc le drapeau doit être posé avant que la capture s'ouvre.
        await ref
            .read(recitationVerifierProvider)
            .v2SetFusion(widget.fusion, preuves: widget.preuves);
        if (widget.wav != null) {
          ref.read(recitationVerifierProvider).wavRejoue = widget.wav;
          DiagnosticLog.log('RECETTE', 'source deterministe : ${widget.wav}');
        }
        _ecouter();
      } else if (widget.mode == 'lecture') {
        _lire();
      } else if (widget.mode == 'v2') {
        _bancV2(v);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = '$e');
      DiagnosticLog.log('RECETTE', 'chargement sourate ${widget.surah} echoue : $e');
    }
  }

  /// BANC de la chaîne v2 sur un WAV réel (`--es recette v2 --es wav <chemin>`).
  ///
  /// Ne démarre AUCUNE capture et ne touche à rien de la v1 : on rejoue un
  /// fichier dans la chaîne v2 avec le vrai modèle, et on écrit le compte rendu
  /// dans le log de diagnostic. C'est la seule façon d'obtenir un chiffre v2
  /// sur du vrai audio sans brancher la v2 à l'écran — donc sans pouvoir
  /// dégrader ce que l'utilisateur voit.
  ///
  /// Le texte attendu est découpé par `ArabicNormalizer.splitExpectedWords`,
  /// EXACTEMENT comme la v1 : sans ça les deux mesures porteraient sur des
  /// cibles différentes et ne seraient pas comparables.
  Future<void> _bancV2(List<Verse> verses) async {
    final wav = widget.wav;
    if (wav == null) {
      DiagnosticLog.log('RECETTE-V2', 'aucun WAV fourni (--es wav <chemin>)');
      return;
    }
    final mots = <String>[];
    for (final v in verses) {
      mots.addAll(ArabicNormalizer.splitExpectedWords(v.textUthmani));
    }
    DiagnosticLog.log('RECETTE-V2',
        'cible=${mots.length} mots  wav=$wav');
    final pret = await FastConformerVerifier().ensureLoaded();
    if (!pret) {
      DiagnosticLog.log('RECETTE-V2', 'modele non deploye : rien a mesurer');
      return;
    }
    try {
      final r = await RecitationV2Bench.analyserWav(wavPath: wav, mots: mots);
      if (r == null) {
        DiagnosticLog.log('RECETTE-V2', 'le banc n\'a rien rendu');
        return;
      }
      for (final ligne in r.compteRendu.split('\n')) {
        if (ligne.trim().isNotEmpty) DiagnosticLog.log('RECETTE-V2', ligne);
      }
      // Le journal par fenêtre : c'est lui qui dit POURQUOI, pas seulement ce
      // que la chaîne a décidé — le manque exact relevé sur les logs v1.
      for (final ligne in r.journal) {
        DiagnosticLog.log('RECETTE-V2', ligne);
      }
      DiagnosticLog.log('RECETTE-V2', 'FIN DU BANC');
    } catch (e) {
      DiagnosticLog.log('RECETTE-V2', 'echec du banc : $e');
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
              forcerModeNormal: widget.normal,
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
