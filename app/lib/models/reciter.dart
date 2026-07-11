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

// Default built-in reciters (quran.com recitation IDs)
const kReciters = [
  Reciter(id: 7,  nameAr: 'مشاري العفاسي',           nameFr: 'Mishary Al-Afasy',       style: 'Murattal'),
  Reciter(id: 1,  nameAr: 'عبد الباسط — مرتّل',      nameFr: 'Abdul Basit (Murattal)', style: 'Murattal'),
  Reciter(id: 2,  nameAr: 'عبد الباسط — مجوّد',      nameFr: 'Abdul Basit (Mujawwad)', style: 'Mujawwad'),
  Reciter(id: 9,  nameAr: 'محمود خليل الحصري',       nameFr: 'Al-Husary',              style: 'Murattal'),
  Reciter(id: 5,  nameAr: 'أبو بكر الشاطري',         nameFr: 'Abu Bakr Ash-Shaatree', style: 'Murattal'),
  Reciter(id: 10, nameAr: 'ناصر القطامي',             nameFr: 'Nasser Al-Qatami',       style: 'Murattal'),
  Reciter(id: 12, nameAr: 'محمد أيوب',               nameFr: 'Muhammad Ayyoub',        style: 'Murattal'),
  Reciter(id: 11, nameAr: 'عبدالرحمن السديس',        nameFr: 'Al-Sudais',              style: 'Murattal'),
];

const kDefaultReciter = Reciter(id: 7, nameAr: 'مشاري العفاسي', nameFr: 'Mishary Al-Afasy', style: 'Murattal');
