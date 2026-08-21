/// Radios de dhikr — écoute CONTINUE, distincte des invocations à l'unité.
///
/// ── POURQUOI CES TROIS-LÀ, ET PAS PLUS (2026-08-17) ─────────────────────────
/// Recherche demandée par l'utilisateur : « dans MP3Quran y a-t-il les audio
/// d'invocation ? ». Sur les 177 radios servies par l'API v3, TROIS seulement
/// portent du dhikr ; le reste est de la récitation coranique. Vérifié en
/// interrogeant `/radios?language=ar` et en filtrant sur دعاء/أذكار/رقية.
///
/// ── CE QUE CE N'EST PAS ─────────────────────────────────────────────────────
/// Ce ne sont PAS des invocations à l'unité, et ça ne remplace pas l'audio par
/// dua retiré le 2026-08-10 (clips de hisnmuslim.com redistribués sans
/// licence). Ce sont des FLUX CONTINUS : on ne peut ni sauter à une invocation
/// précise, ni les mettre en cache, ni les découper. Les points d'accès
/// `/duas`, `/adhkar`, `/athkar` et `/audios` ont été essayés le même jour --
/// tous en redirection, aucun ne sert de fichiers individuels.
///
/// ── LICENCE ─────────────────────────────────────────────────────────────────
/// Servis depuis `qurango.net`, nommé avec `mp3quran.net` dans les mêmes
/// conditions permissives (cf. l'en-tête de `Mp3QuranApi` pour le texte
/// arabe cité et sa date de vérification).
///
/// ── VÉRIFICATION FAITE (2026-08-17) ────────────────────────────────────────
/// Les trois URL répondent `HTTP 200`, `Content-Type: audio/mpeg`, et leurs
/// premiers octets portent la signature d'une trame MP3 (`FF FB`). Aucun
/// `Content-Length` : c'est bien un flux, pas un fichier -- d'où l'absence de
/// barre de progression et de mise en cache côté IHM.
class RadioDhikr {
  /// Identifiant chez MP3Quran (`/radios`), conservé pour pouvoir recouper si
  /// une URL change côté serveur.
  final int id;

  final String cleTitre;
  final String url;

  const RadioDhikr({
    required this.id,
    required this.cleTitre,
    required this.url,
  });
}

const kRadiosDhikr = <RadioDhikr>[
  RadioDhikr(
    id: 10906,
    cleTitre: 'matin',
    url: 'https://backup.qurango.net/radio/athkar_sabah',
  ),
  RadioDhikr(
    id: 10907,
    cleTitre: 'soir',
    url: 'https://backup.qurango.net/radio/athkar_masa',
  ),
  RadioDhikr(
    id: 114,
    cleTitre: 'roqya',
    url: 'https://backup.qurango.net/radio/roqiah',
  ),
];
