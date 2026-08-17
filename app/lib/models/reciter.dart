class Reciter {
  final int id;          // quran.com recitation ID
  final String nameAr;
  final String nameFr;
  final String style;    // Murattal / Mujawwad

  const Reciter({
    required this.id,
    required this.nameAr,
    required this.nameFr,
    required this.style,
  });

  @override
  bool operator ==(Object other) => other is Reciter && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

// App volontairement MONO-RÉCITATEUR (2026-08-16) : seul Al-Afasy dispose
// d'un chemin de lecture et de correction audio SANS dépendance à Quran
// Foundation (audio MP3Quran + `word_segments_mp3quran_afasy.json`
// précalculé, cf. AUDIT_EQUIVALENCES_ECRITURE_2026-08-15.md §3bis). Les 7
// autres récitateurs ci-dessous retomberaient sur l'ancien chemin
// quran.com/QF pour `WordCorrectionAudio` -- exactement la dépendance que ce
// chantier existe à supprimer -- donc retirés de la sélection tant que leur
// propre jeu de données n'est pas généré.
//
// IDs MP3Quran déjà vérifiés (reciter/moshaf, empiriquement via
// /ayat_timing, PAS supposés -- cf. §3ter de l'audit) pour la suite quand la
// demande se présentera : Al-Husary 118, Muhammad Ayyoub 109, Ash-Shaatree
// 4, Abdul Basit Murattal 53 (PIÈGE : != son reciter_id 51, qui pointe le
// Mujawwad 51), Al-Sudais 54, Nasser Al-Qatami 86. Remettre l'entrée
// correspondante ci-dessous une fois `preparer_corpus_mp3quran.py` +
// `generer_predictions_mp3quran.py` rejoués pour ce récitateur et son JSON
// embarqué/hébergé.
const kReciters = [
  Reciter(id: 7,  nameAr: 'مشاري العفاسي',           nameFr: 'Mishary Al-Afasy',       style: 'Murattal'),
];

const kDefaultReciter = Reciter(id: 7, nameAr: 'مشاري العفاسي', nameFr: 'Mishary Al-Afasy', style: 'Murattal');
