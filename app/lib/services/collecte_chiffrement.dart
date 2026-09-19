// Chiffrement de bout en bout des envois de collecte.
//
// ── LE CONTRAT, EN UNE PHRASE ────────────────────────────────────────────
// Cette application ne peut que CHIFFRER. Elle ne porte que la clé publique ;
// la clé privée n'existe que sur la machine d'entraînement. Un téléphone perdu,
// un APK décompilé ou un stockage qui fuit ne rendent lisible aucun envoi.
//
// ── LE FORMAT, ET POURQUOI IL EST FIGÉ ──────────────────────────────────
//
//     0..3     "CKR1"    magique + version
//     4..35    clé publique éphémère X25519 (32)
//     36..47   nonce AES-GCM (12, aléatoire)
//     48..     chiffré + tag GCM (16)
//
// Primitives : X25519 pour l'accord de clé, HKDF-SHA256 pour la dérivation,
// AES-256-GCM pour le chiffrement authentifié. Elles ont été choisies parce
// que Dart ET Python les fournissent en standard : le premier jet visait la
// *sealed box* de libsodium, qui aurait imposé de réimplémenter son nonce
// (`blake2b(eph_pk || dest_pk)`) à la main ici. C'est exactement le genre de
// détail dont l'erreur ne se voit pas — on l'apprendrait après avoir collecté
// des milliers de sessions devenues illisibles.
//
// ⚠️ NE PAS MODIFIER CE FORMAT SANS CHANGER LE MAGIQUE. Les paquets déjà
// envoyés restent déchiffrables tant que `CKR1` décrit bien ce qu'il annonce ;
// un format modifié sous le même nom rend le corpus ambigu, et l'ambiguïté se
// découvre toujours trop tard. Le pendant Python est
// `benchmark/collecte_cles.py`, dont l'autotest vérifie l'aller-retour ET les
// refus (paquet abîmé, mauvaise clé).
//
// Une paire éphémère est tirée à CHAQUE envoi : deux sessions du même appareil
// n'ont aucune clé commune, et la compromission d'un envoi n'ouvre pas les
// autres.

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Magique et version du format. Quatre octets ASCII.
const List<int> kCollecteMagique = [0x43, 0x4B, 0x52, 0x31]; // "CKR1"

/// Contexte de dérivation. Il entre dans HKDF avec les DEUX clés publiques :
/// sans elles, un paquet chiffré pour un destinataire pourrait être rejoué
/// vers un autre.
const String kCollecteInfo = 'coran-karim-collecte-v1';

/// Clé publique du destinataire, en hexadécimal (32 octets = 64 caractères).
///
/// ⚠️ VIDE TANT QUE LA PAIRE N'EST PAS GÉNÉRÉE. Tant qu'elle l'est, rien ne
/// peut être chiffré, donc rien ne peut partir — c'est voulu : un envoi en
/// clair serait pire que pas d'envoi du tout. La paire se produit avec
/// `python benchmark/collecte_cles.py generer --dossier <dir>`, et seule la
/// partie publique se recopie ici.
const String kCollecteClePubliqueHex = '';

class CollecteChiffrement {
  /// La collecte peut-elle fonctionner ? Faux tant qu'aucune clé n'est posée.
  static bool get pretAEnvoyer => _clePublique() != null;

  static Uint8List? _clePublique([String? hexFourni]) {
    final hex = (hexFourni ?? kCollecteClePubliqueHex).trim();
    if (hex.length != 64) return null;
    final out = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      final octet = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      if (octet == null) return null;
      out[i] = octet;
    }
    return out;
  }

  /// Chiffre [clair] pour le porteur de la clé privée.
  ///
  /// Rend `null` si aucune clé publique n'est configurée — l'appelant doit
  /// alors NE RIEN ENVOYER, jamais se rabattre sur du clair.
  /// [clePubliqueHex] n'existe QUE pour le test d'interoperabilite avec
  /// `benchmark/collecte_cles.py` : en production l'appelant ne le passe pas,
  /// et c'est la constante ci-dessus qui sert. Sans ce paramètre, il faudrait
  /// écrire une vraie clé en dur dans le dépôt pour pouvoir tester le format.
  static Future<Uint8List?> chiffrer(List<int> clair,
      {String? clePubliqueHex}) async {
    final destination = _clePublique(clePubliqueHex);
    if (destination == null) return null;

    final x25519 = X25519();
    final ephemere = await x25519.newKeyPair();
    final ephemerePub = (await ephemere.extractPublicKey()).bytes;

    final partage = await x25519.sharedSecretKey(
      keyPair: ephemere,
      remotePublicKey: SimplePublicKey(destination, type: KeyPairType.x25519),
    );

    // `info` = contexte || clé éphémère || clé destinataire, exactement comme
    // le pendant Python. Toute divergence ici produit des paquets que PC A ne
    // pourra pas ouvrir, sans aucune erreur visible côté téléphone.
    final info = <int>[
      ...kCollecteInfo.codeUnits,
      ...ephemerePub,
      ...destination,
    ];
    final session = await Hkdf(hmac: Hmac.sha256(), outputLength: 32)
        .deriveKey(secretKey: partage, info: info);

    final aes = AesGcm.with256bits();
    final nonce = aes.newNonce(); // 12 octets aléatoires
    final scelle = await aes.encrypt(
      clair,
      secretKey: session,
      nonce: nonce,
      aad: kCollecteMagique, // l'en-tête est authentifié, pas seulement le corps
    );

    final paquet = BytesBuilder(copy: false)
      ..add(kCollecteMagique)
      ..add(ephemerePub)
      ..add(nonce)
      ..add(scelle.cipherText)
      ..add(scelle.mac.bytes);
    return paquet.toBytes();
  }
}
