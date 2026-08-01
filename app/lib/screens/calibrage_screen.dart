import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

/// CALIBRAGE — mesure les deux seuils de découpage sur la voix du récitateur.
///
/// ── POURQUOI CET ÉCRAN EXISTE ──────────────────────────────────────────────
/// Le graphe porte le défaut depuis le 2026-07-30 : « une falaise entre deux
/// valeurs voisines n'est pas un réglage, c'est un défaut de conception — la
/// chaîne dépend d'un paramètre qui n'a aucune plage stable. Un récitateur qui
/// respire autrement ferait basculer l'app d'un côté ou de l'autre sans que
/// personne comprenne pourquoi. »
///
/// Le seuil RMS a déjà été traité ainsi, et ça a marché : fixe, il s'effondrait
/// à 65,76 % de mots non verts dès qu'on montait le gain de 50 % ; dérivé, il
/// rend 2,03 % à tous les gains. Cet écran applique la même recette au seuil de
/// PAUSE, resté fixe.
///
/// ── CE QUE L'ÉCRAN MONTRE, ET POURQUOI PAS SEULEMENT LE RÉSULTAT ───────────
/// Il affiche la DISTRIBUTION des silences, pas seulement la valeur retenue.
/// C'est délibéré : la valeur seule serait un chiffre qu'on ne peut pas
/// contester. La distribution, elle, dit si le réglage est fiable — deux
/// populations bien séparées (micro-pauses entre mots d'un côté, frontières
/// d'énoncé de l'autre) veulent dire qu'un seuil les sépare proprement ; une
/// distribution étalée veut dire qu'AUCUN seuil ne le fera, et il vaut mieux le
/// voir ici que le découvrir six heures plus tard dans un taux.
///
/// ── LE CALCUL N'EST PAS ICI ────────────────────────────────────────────────
/// Tout se passe dans `recitation2/Calibrage.kt`, côté natif. Refaire
/// l'estimation en Dart aurait dupliqué une logique de seuil dans deux
/// langages — ce que le projet a déjà payé deux fois. Cet écran capture le son
/// et affiche ; il ne décide rien et ne modifie aucun réglage.
class CalibrageScreen extends StatefulWidget {
  const CalibrageScreen({super.key});

  @override
  State<CalibrageScreen> createState() => _CalibrageScreenState();
}

class _CalibrageScreenState extends State<CalibrageScreen> {
  static const _canal = MethodChannel('com.corankarim/fastconformer_ctc');

  /// Durée en dessous de laquelle un percentile ne veut rien dire. Le natif
  /// refuse déjà en dessous de 12 silences ; ici on prévient AVANT, pour ne pas
  /// faire réciter une minute pour rien.
  static const _dureeMini = Duration(seconds: 45);

  /// MÊME source que la chaîne de récitation : paquet `record`, PCM16, 16 kHz,
  /// mono. Ce n'était PAS le cas au premier essai — l'écran utilisait
  /// `AudioRecorderService`, dont le plugin natif n'est enregistré nulle part
  /// (`MainActivity` n'ajoute que `FastConformerCtcPlugin`). `start()` levait
  /// donc `MissingPluginException`, que le service avale volontairement, et
  /// `stop()` rendait une liste VIDE : le chrono tournait, tout avait l'air
  /// normal, et il n'y avait aucune mesure au bout.
  ///
  /// Calibrer sur une autre source que celle de la chaîne serait de toute façon
  /// faux : c'est exactement ce que le projet appelle « le banc mesure autre
  /// chose que l'app ».
  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  bool _enCours = false;
  bool _calcul = false;
  int _blocsRecus = 0;
  int _sessions = 0;
  Duration _ecoule = Duration.zero;
  Timer? _chrono;
  Map<String, dynamic>? _resultat;
  String? _erreur;

  @override
  void dispose() {
    _chrono?.cancel();
    _sub?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _demarrer({bool cumuler = false}) async {
    setState(() {
      _resultat = null;
      _erreur = null;
      _ecoule = Duration.zero;
      _blocsRecus = 0;
      if (!cumuler) _sessions = 0;
    });
    try {
      if (!await _recorder.hasPermission()) {
        setState(() => _erreur = 'permission micro refusée');
        return;
      }
      await _canal.invokeMethod('calibrageDemarrer', {'cumuler': cumuler});
      final flux = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _sub = flux.listen((octets) {
        _blocsRecus++;
        // Au fil de l'eau : rien n'est accumulé côté Dart, donc pas de gros
        // transfert final ni de risque de dépasser la taille du canal.
        _canal.invokeMethod('calibrageAlimenter', {'pcm16': octets});
      }, onError: (e) {
        if (mounted) setState(() => _erreur = 'flux micro : $e');
      });
      setState(() => _enCours = true);
    } catch (e) {
      setState(() {
        _enCours = false;
        _erreur = 'micro indisponible : $e';
      });
      return;
    }
    _chrono = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _ecoule += const Duration(seconds: 1));
    });
  }

  Future<void> _terminer() async {
    _chrono?.cancel();
    setState(() {
      _enCours = false;
      _calcul = true;
    });
    try {
      await _sub?.cancel();
      _sub = null;
      await _recorder.stop();
      // Laisse les derniers blocs finir leur aller-retour avant de clôturer.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final s = await _canal.invokeMethod<Map>('calibrageCloturerSession');
      if (s != null) _sessions = (s['sessions'] as num).toInt();
      final r = await _canal.invokeMethod<Map>('calibrageResultat');
      if (!mounted) return;
      setState(() {
        _calcul = false;
        _resultat = r?.map((k, v) => MapEntry(k.toString(), v));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _calcul = false;
        _erreur = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final trop = _ecoule < _dureeMini;
    return Scaffold(
      appBar: AppBar(title: const Text('Calibrage du découpage')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Récitez normalement, comme vous le feriez pour de vrai — '
              'avec vos respirations habituelles. C\'est la durée de VOS pauses '
              'qui est mesurée, pas votre justesse : rien n\'est jugé ici.',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 8),
            Text(
              'Comptez au moins 45 secondes. En dessous, il n\'y a pas assez '
              'de pauses pour que la mesure veuille dire quelque chose.',
              style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                '${_ecoule.inMinutes}:${(_ecoule.inSeconds % 60).toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w300,
                  color: _enCours && trop ? Colors.orange : null,
                ),
              ),
            ),
            // Compteur de blocs : rend visible PENDANT l'enregistrement le cas
            // ou le micro ne rend rien. Sans lui, le premier essai a laisse
            // croire que tout allait bien (chrono qui tourne) pour ne rendre
            // aucune mesure au bout de 45 s.
            if (_enCours || _blocsRecus > 0)
              Center(
                child: Text(
                  _blocsRecus == 0 && _enCours
                      ? 'AUCUN son reçu — le micro ne rend rien'
                      : '$_blocsRecus blocs audio reçus',
                  style: TextStyle(
                    fontSize: 13,
                    color: _blocsRecus == 0 && _enCours
                        ? Colors.red
                        : Theme.of(context).hintColor,
                  ),
                ),
              ),
            const SizedBox(height: 24),
            if (!_enCours && !_calcul) ...[
              FilledButton.icon(
                onPressed: () => _demarrer(cumuler: false),
                icon: const Icon(Icons.mic),
                label: Text(_resultat == null ? 'Démarrer' : 'Tout recommencer'),
              ),
              // AJOUTER une session plutôt que repartir de zéro : l'estimateur
              // des silences est pauvre en données (une minute n'en contient
              // qu'une quarantaine). Le natif ne cumule PAS le signal brut mais
              // les SILENCES — chaque session dérive son propre niveau de
              // parole avant d'être versée au total, sinon deux sessions à des
              // distances différentes du micro se contamineraient.
              if (_sessions > 0) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _demarrer(cumuler: true),
                  icon: const Icon(Icons.add),
                  label: Text('Ajouter une session ($_sessions déjà)'),
                ),
              ],
            ],
            if (_enCours)
              FilledButton.icon(
                onPressed: _terminer,
                icon: const Icon(Icons.stop),
                label: Text(trop ? 'Terminer (un peu court)' : 'Terminer'),
              ),
            if (_calcul)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_erreur != null) ...[
              const SizedBox(height: 16),
              Text(_erreur!, style: const TextStyle(color: Colors.red)),
            ],
            if (_resultat != null) ...[
              const SizedBox(height: 24),
              _resultatVue(_resultat!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resultatVue(Map<String, dynamic> r) {
    final fiable = r['fiable'] == true;
    if (!fiable) {
      return Card(
        color: Colors.orange.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Mesure non fiable',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Text('${r['pourquoi']}'),
              const SizedBox(height: 8),
              const Text(
                'Aucune valeur n\'est proposée : un chiffre calculé sur trop peu '
                'de silences serait précis et faux.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      );
    }

    final sep = (r['separation'] as num).toDouble();
    final pause = (r['pause'] as num).toDouble();
    final actuelle = (r['pauseActuelle'] as num).toDouble();
    final ecart = pause - actuelle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Valeurs dérivées de votre voix',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                _ligne('Seuil de pause',
                    '${pause.toStringAsFixed(3)} s',
                    souligne: true,
                    note: r['pauseBornee'] == true ? 'borne atteinte' : null),
                _ligne('Réglage actuel', '${actuelle.toStringAsFixed(2)} s',
                    note: ecart.abs() < 0.005
                        ? 'identique'
                        : '${ecart > 0 ? '+' : ''}${ecart.toStringAsFixed(3)} s'),
                const Divider(height: 24),
                _ligne('Seuil de silence',
                    (r['seuilRms'] as num).toStringAsFixed(4),
                    note: r['seuilRmsBorne'] == true ? 'borne atteinte' : null),
                _ligne('Niveau de parole',
                    (r['niveauParole'] as num).toStringAsFixed(4)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: sep < 2.0
              ? Colors.orange.withValues(alpha: 0.12)
              : Colors.green.withValues(alpha: 0.10),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sep < 2.0
                      ? 'Vos pauses ne se séparent pas nettement'
                      : 'Vos pauses se séparent nettement',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  sep < 2.0
                      ? 'Écart p90/p25 = ${sep.toStringAsFixed(1)}. Les micro-pauses '
                          'entre mots et les vraies fins de phrase ont des durées '
                          'trop proches : aucun seuil ne les séparera proprement. '
                          'La valeur ci-dessus reste le meilleur compromis, mais '
                          'elle sera fragile.'
                      : 'Écart p90/p25 = ${sep.toStringAsFixed(1)}. Les micro-pauses '
                          'entre mots et les vraies fins de phrase forment deux '
                          'groupes distincts : un seuil les sépare proprement.',
                  style: const TextStyle(height: 1.4),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Distribution de vos ${r['nbSilences']} silences',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  'Le seuil est ancré sur p90 — dominé par les vraies fins de '
                  'phrase. Un ancrage plus bas suivrait votre façon de respirer '
                  'au lieu de votre façon de phraser.',
                  style: TextStyle(
                      color: Theme.of(context).hintColor,
                      fontSize: 12,
                      height: 1.3),
                ),
                const SizedBox(height: 12),
                for (final p in const [10, 25, 50, 75, 90, 95])
                  _barre(p, (r['p$p'] as num).toDouble(),
                      (r['p95'] as num).toDouble(), p == 90),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Rien n\'a été modifié. Cet écran mesure et affiche ; appliquer cette '
          'valeur est une décision distincte, et elle demande une recette pour '
          'être validée.',
          style: TextStyle(
              color: Theme.of(context).hintColor,
              fontSize: 12,
              fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  Widget _ligne(String nom, String valeur, {bool souligne = false, String? note}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(nom)),
          Text(valeur,
              style: TextStyle(
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: souligne ? FontWeight.bold : FontWeight.normal,
                fontSize: souligne ? 18 : 14,
              )),
          if (note != null) ...[
            const SizedBox(width: 8),
            Text(note,
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).hintColor)),
          ],
        ],
      ),
    );
  }

  Widget _barre(int p, double v, double max, bool ancre) {
    final frac = max <= 0 ? 0.0 : (v / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
              width: 38,
              child: Text('p$p',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: ancre ? FontWeight.bold : FontWeight.normal))),
          Expanded(
            child: LinearProgressIndicator(
              value: frac,
              minHeight: ancre ? 10 : 6,
              backgroundColor: Theme.of(context).dividerColor,
            ),
          ),
          SizedBox(
            width: 62,
            child: Text('${v.toStringAsFixed(2)} s',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: ancre ? FontWeight.bold : FontWeight.normal)),
          ),
        ],
      ),
    );
  }
}
