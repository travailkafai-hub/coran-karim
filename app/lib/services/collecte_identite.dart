// Qui consent, et sous quel identifiant — rien de plus.
//
// ── POURQUOI UN IDENTIFIANT ALORS QU'ON NE VEUT IDENTIFIER PERSONNE ──────
//
// Il ne sert qu'à UNE chose : pouvoir honorer « je retire mon accord, effacez
// ce qui est parti ». Sans un moyen de retrouver les envois d'une personne, ce
// droit est une phrase vide — on ne peut effacer ni tout (ce serait détruire le
// corpus des autres) ni rien.
//
// Il est donc tiré AU HASARD à la première activation, ne contient aucune
// information sur l'appareil ni sur la personne, et se régénère si les données
// de l'application sont effacées. Ce n'est pas un identifiant publicitaire, ce
// n'est pas l'ANDROID_ID, ce n'est pas l'adresse courriel : c'est un numéro de
// casier.
//
// Il est AFFICHÉ dans les réglages, précisément pour que la personne puisse le
// communiquer si elle demande une suppression.

import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Durée de conservation annoncée. Doit figurer dans l'écran de consentement :
/// une collecte sans durée annoncée est une collecte sans fin.
const int kCollecteConservationMois = 12;

class CollecteIdentite {
  static const _kConsentement = 'collecte_consentement';
  static const _kIdentifiant = 'collecte_identifiant';
  static const _kDateAccord = 'collecte_date_accord';

  /// La personne a-t-elle donné son accord ? FAUX par défaut, et le défaut
  /// compte : un consentement se donne, il ne se présume pas.
  static Future<bool> consentement() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kConsentement) ?? false;
    } catch (_) {
      // Préférences illisibles : on considère qu'il n'y a PAS d'accord. Le
      // repli doit toujours aller vers le moins d'envoi, jamais vers plus.
      return false;
    }
  }

  /// Enregistre l'accord ou son retrait.
  ///
  /// Le retrait ne supprime pas l'identifiant : il faut encore pouvoir le
  /// montrer à la personne pour qu'elle demande l'effacement de ce qui est
  /// déjà parti.
  static Future<void> definirConsentement(bool accorde) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kConsentement, accorde);
    if (accorde) {
      await prefs.setString(_kDateAccord, DateTime.now().toIso8601String());
      await identifiant(); // le crée s'il n'existe pas encore
    }
  }

  /// Date à laquelle l'accord a été donné, ou `null`.
  static Future<DateTime?> dateAccord() async {
    try {
      final brut = (await SharedPreferences.getInstance())
          .getString(_kDateAccord);
      return brut == null ? null : DateTime.tryParse(brut);
    } catch (_) {
      return null;
    }
  }

  /// Identifiant de casier, 32 caractères hexadécimaux. Créé au besoin.
  ///
  /// Le format est imposé par le Worker (`/^[a-f0-9]{32}$/`) : tout envoi qui
  /// n'y répond pas est refusé côté serveur.
  static Future<String> identifiant() async {
    final prefs = await SharedPreferences.getInstance();
    final existant = prefs.getString(_kIdentifiant);
    if (existant != null && existant.length == 32) return existant;

    // `Random.secure` et non `Random()` : un identifiant prévisible
    // permettrait de deviner celui d'autrui et de demander la suppression de
    // ses données à sa place.
    final rnd = Random.secure();
    final hex = StringBuffer();
    for (var i = 0; i < 16; i++) {
      hex.write(rnd.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    final neuf = hex.toString();
    await prefs.setString(_kIdentifiant, neuf);
    return neuf;
  }
}
