import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import 'about_screen.dart' show kContactEmail;

/// "Nous contacter" (2026-08-09, demande utilisateur) : écran de composition
/// DANS l'app -- pas un simple lien qui bascule directement sur l'appli mail,
/// ni la première version (copie presse-papiers, jugée insuffisante : « tu
/// n'as que affiché mon mail, moi je veux une fenêtre pour écrire »). Au
/// moment d'"Envoyer", ouvre l'appli mail du téléphone déjà entièrement
/// remplie (destinataire/objet/message) via `mailto:` -- pas de backend, pas
/// de compte Firebase à créer, l'appli mail fait le transport. Cohérent avec
/// le reste de l'app (calcul des horaires de prière, ASR... tout tourne déjà
/// sur l'appareil sans dépendance à un serveur qu'on maintiendrait).
///
/// `kContactEmail` réutilisée depuis `about_screen.dart` : une seule adresse
/// à surveiller pour le signalement IA et le contact général.

class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    final message = _messageCtrl.text.trim();
    if (message.isEmpty) return;
    setState(() => _sending = true);
    try {
      // Version/build ajoutés en silence en pied de message -- utile pour le
      // support (savoir de quelle version part le retour) sans demander à
      // l'utilisateur de les recopier lui-même.
      final info = await PackageInfo.fromPlatform();
      final subject = _subjectCtrl.text.trim().isEmpty
          ? 'Coran Karim — message'
          : _subjectCtrl.text.trim();
      final corps = '$message\n\n'
          '—\n'
          'Coran Karim ${info.version} (build ${info.buildNumber})';
      final uri = Uri(
        scheme: 'mailto',
        path: kContactEmail,
        query: 'subject=${Uri.encodeComponent(subject)}'
            '&body=${Uri.encodeComponent(corps)}',
      );
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        _snack('Aucune application mail trouvée sur cet appareil.');
      } else if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) _snack('Impossible d\'ouvrir l\'application mail.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _messageCtrl.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.green900,
        foregroundColor: AppColors.cream,
        elevation: 0,
        title: Text('Nous contacter',
            style: GoogleFonts.scheherazadeNew(fontSize: 22, color: AppColors.brassLight)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.green50,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.mail_outline_rounded, color: AppColors.green700, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Une question, un bug à signaler, une suggestion ? Écris ton message ici -- '
                    'l\'appli mail s\'ouvrira ensuite avec tout déjà rempli, il ne restera qu\'à '
                    'l\'envoyer.',
                    style: GoogleFonts.manrope(fontSize: 12, color: AppColors.ink, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('OBJET (facultatif)',
              style: GoogleFonts.manrope(
                  fontSize: 10, color: AppColors.green700, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          TextField(
            controller: _subjectCtrl,
            style: GoogleFonts.manrope(fontSize: 14, color: AppColors.ink),
            decoration: InputDecoration(
              hintText: 'Coran Karim — message',
              hintStyle: GoogleFonts.manrope(fontSize: 13, color: AppColors.inkLight),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.cream300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.cream300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.green700, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text('MESSAGE',
              style: GoogleFonts.manrope(
                  fontSize: 10, color: AppColors.green700, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          TextField(
            controller: _messageCtrl,
            onChanged: (_) => setState(() {}),
            minLines: 8,
            maxLines: 14,
            style: GoogleFonts.manrope(fontSize: 14, color: AppColors.ink, height: 1.5),
            decoration: InputDecoration(
              hintText: 'Écris ton message…',
              hintStyle: GoogleFonts.manrope(fontSize: 13, color: AppColors.inkLight),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.cream300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.cream300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.green700, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.green700,
              foregroundColor: AppColors.cream,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: (canSend && !_sending) ? _envoyer : null,
            child: _sending
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cream))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.send_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text('Envoyer',
                          style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 14)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
