import 'dart:convert';
import 'dart:io';

// ChGPT: structural audit and full before/after inventory, not linguistic proof.
// Run from app/: dart run tool/audit_arabic_copy.dart
void main() {
  const baseline = '0a6b0bd';
  final root = Directory.current.path;
  final arabic = _readJson(File('$root/lib/l10n/app_ar.arb').readAsStringSync());
  final french = _readJson(File('$root/lib/l10n/app_fr.arb').readAsStringSync());
  final snapshot = Process.runSync(
    'git', ['show', '$baseline:app/lib/l10n/app_ar.arb'],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (snapshot.exitCode != 0) {
    throw StateError('Cannot read checkpoint $baseline: ${snapshot.stderr}');
  }
  final before = _readJson(snapshot.stdout as String);
  final keys = french.keys.where((k) => !k.startsWith('@')).toList()..sort();
  final failures = <String>[];
  for (final key in keys) {
    final value = arabic[key];
    if (value is! String || value.trim().isEmpty) {
      failures.add('$key: missing Arabic text');
      continue;
    }
    if (value.contains('\uFFFD')) failures.add('$key: replacement character');
    final metadata = french['@$key'] as Map<String, dynamic>?;
    final parameters = metadata?['placeholders'] as Map<String, dynamic>?;
    final expected = parameters?.keys.toSet() ?? <String>{};
    final actual = _arguments(value);
    if (expected.length != actual.length || !expected.containsAll(actual)) {
      failures.add('$key: arguments differ: $expected / $actual');
    }
  }
  for (final key in arabic.keys.where((k) => !k.startsWith('@'))) {
    if (!french.containsKey(key)) failures.add('$key: not in the template');
  }
  if (failures.isNotEmpty) {
    stderr.writeln(failures.join('\n'));
    exitCode = 1;
    return;
  }

  const protected = {
    'duaPourNousDeceasedArabic',
    'duaPourNousDeceasedTranslation',
    'duaPourNousDeceasedSource',
    'duaPourNousForYouArabic',
  };
  for (final key in protected) {
    if (before[key] != arabic[key]) {
      throw StateError('Religious quotation changed: $key');
    }
  }
  var changed = 0;
  var added = 0;
  final csv = StringBuffer('\uFEFF');
  csv.writeln('cle;statut;arabe_avant;arabe_apres;reference_francaise');
  for (final key in keys) {
    final isNew = !before.containsKey(key);
    final modified = !isNew && before[key] != arabic[key];
    if (isNew) added++;
    if (modified) changed++;
    final status = protected.contains(key)
        ? 'citation_preservee_non_reformulee'
        : isNew ? 'nouveau_relu'
        : modified ? 'reformule' : 'relu_conserve';
    csv.writeln([
      key, status, before[key] ?? '', arabic[key], french[key],
    ].map((v) => '"${v.toString().replaceAll('"', '""')}"').join(';'));
  }
  final output = File('$root/../AUDIT_ARABE_CHGPT_2026-09-14.csv');
  output.writeAsStringSync(csv.toString());
  stdout.writeln('${keys.length} Arabic messages, $changed revised, $added added since $baseline.');
  stdout.writeln('Keys, argument names and protected quotations: OK.');
  stdout.writeln('CSV: ${output.absolute.path}');
  stdout.writeln('ICU grammar/types must also pass flutter gen-l10n and analyze.');
}

Map<String, dynamic> _readJson(String value) =>
    jsonDecode(value) as Map<String, dynamic>;

// Only inventories argument names. Flutter's generator validates ICU grammar.
Set<String> _arguments(String message) => RegExp(r'\{([A-Za-z_]\w*)\s*[,}]')
    .allMatches(message).map((match) => match[1]!).toSet();
