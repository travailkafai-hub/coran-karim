import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coran_karim/widgets/tajweed_text.dart';

void main() {
  const base = TextStyle(color: Colors.black);

  test('parses real <tajweed class=X> markup (verse 1:1, unquoted attrs)', () {
    const html =
        'بِسْمِ <tajweed class=ham_wasl>ٱ</tajweed>للَّهِ <tajweed class=ham_wasl>ٱ</tajweed>'
        '<tajweed class=laam_shamsiyah>ل</tajweed>رَّحْمَ<tajweed class=madda_normal>ـٰ</tajweed>نِ '
        '<tajweed class=ham_wasl>ٱ</tajweed><tajweed class=laam_shamsiyah>ل</tajweed>رَّح'
        '<tajweed class=madda_permissible>ِي</tajweed>مِ <span class=end>١</span>';
    final spans = parseTajweedHtml(html, base);
    final full = spans.map((s) => s.text).join();
    expect(full, html.replaceAll(RegExp(r'<[^>]+>'), ''));

    final colored = spans.where((s) => s.style?.color != base.color).toList();
    expect(colored, isNotEmpty,
        reason: 'au moins un span doit porter une couleur tajwid distincte du texte de base');

    // Le premier "ٱ" (ham_wasl) doit être gris.
    final firstHamWasl = spans.firstWhere((s) => s.text == 'ٱ');
    expect(firstHamWasl.style?.color, const Color(0xFFB3B2A8));

    // Le "ل" (laam_shamsiyah) doit être gris aussi.
    final laam = spans.firstWhere((s) => s.text == 'ل');
    expect(laam.style?.color, const Color(0xFFB3B2A8));

    // Le madd "ـٰ" (madda_normal) doit être orange.
    final maddNormal = spans.firstWhere((s) => s.text == 'ـٰ');
    expect(maddNormal.style?.color, const Color(0xFFF38F43));

    // Le madd "ِي" (madda_permissible) doit être orange aussi.
    final maddPermissible = spans.firstWhere((s) => s.text == 'ِي');
    expect(maddPermissible.style?.color, const Color(0xFFF38F43));

    // Le marqueur de fin "١" (<span class=end>) n'a pas de couleur tajwid dédiée
    // -> reste dans la couleur de base (parentColor null au niveau racine).
    final endMarker = spans.firstWhere((s) => s.text == '١');
    expect(endMarker.style?.color, base.color);
  });

  test('handles a cross-word idgham_ghunnah span (verse 2:7 real sample)', () {
    const html =
        'غِشَ<tajweed class=madda_normal>ـٰ</tajweed>وَ<tajweed class=idgham_ghunnah>ةٌ‌ۖ و</tajweed>َلَهُمْ';
    final words = tajweedSpansPerWord(html, base);
    expect(words.length, 2);
    final w1Text = words[0].map((s) => s.text).join();
    final w2Text = words[1].map((s) => s.text).join();
    expect(w1Text, 'غِشَـٰوَةٌ‌ۖ');
    expect(w2Text, 'وَلَهُمْ');

    final idghamInWord1 = words[0].firstWhere((s) => s.text == 'ةٌ‌ۖ');
    expect(idghamInWord1.style?.color, const Color(0xFF79AB71));
    final idghamInWord2 = words[1].firstWhere((s) => s.text == 'و');
    expect(idghamInWord2.style?.color, const Color(0xFF79AB71));
  });

  test('handles idgham_shafawi, ikhafa, iqlab real sample (verse 2:10)', () {
    const html =
        'فِى قُلُوبِه<tajweed class=idgham_shafawi>ِم م</tajweed>َّرَ<tajweed class=ikhafa>ضٌ ف</tajweed>'
        'َزَادَهُمُ <tajweed class=ham_wasl>ٱ</tajweed>للَّهُ مَرَ<tajweed class=idgham_ghunnah>ضًا‌ۖ و</tajweed>'
        'َلَهُمْ عَذَابٌ أَلِي<tajweed class=iqlab>مُۢ ب</tajweed>ِمَا';
    final spans = parseTajweedHtml(html, base);
    final ikhafaSpan = spans.firstWhere((s) => s.text == 'ضٌ ف');
    expect(ikhafaSpan.style?.color, const Color(0xFF79AB71));
    final idghamShafawiSpan = spans.firstWhere((s) => s.text == 'ِم م');
    expect(idghamShafawiSpan.style?.color, const Color(0xFF79AB71));
    final iqlabSpan = spans.firstWhere((s) => s.text == 'مُۢ ب');
    expect(iqlabSpan.style?.color, const Color(0xFF79AB71));
  });
}
