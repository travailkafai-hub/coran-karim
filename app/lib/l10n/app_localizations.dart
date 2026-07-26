import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
    Locale('fr'),
  ];

  /// Onglet de navigation principal : lecture du Coran
  ///
  /// In fr, this message translates to:
  /// **'Coran'**
  String get navQuran;

  /// Onglet de navigation : invocations/adhkar
  ///
  /// In fr, this message translates to:
  /// **'Invocations'**
  String get navDuas;

  /// Onglet de navigation : coach IA
  ///
  /// In fr, this message translates to:
  /// **'Coach'**
  String get navCoach;

  /// Onglet de navigation : réglages
  ///
  /// In fr, this message translates to:
  /// **'Réglages'**
  String get navSettings;

  /// Titre de l'application
  ///
  /// In fr, this message translates to:
  /// **'Coran Karim'**
  String get appTitle;

  /// Titre de l'AppBar de l'écran carte mentale
  ///
  /// In fr, this message translates to:
  /// **'Carte mentale — {name}'**
  String mindMapAppBarTitle(String name);

  /// Plage de versets d'une branche
  ///
  /// In fr, this message translates to:
  /// **'Versets {range}'**
  String mindMapVerses(String range);

  /// Nombre de versets sous le nom de la sourate dans le médaillon
  ///
  /// In fr, this message translates to:
  /// **'{count} versets'**
  String mindMapAyahCountBadge(int count);

  /// Lien vers le Mushaf depuis une carte de branche/passage
  ///
  /// In fr, this message translates to:
  /// **'Aller au verset'**
  String get mindMapGoToVerse;

  /// Titre de section dans la feuille d'info de la sourate
  ///
  /// In fr, this message translates to:
  /// **'Fil directeur'**
  String get mindMapThemeLabel;

  /// Titre de section : provenance de la structure et réserves éventuelles
  ///
  /// In fr, this message translates to:
  /// **'Sources et réserves'**
  String get mindMapSourcesLabel;

  /// Écran affiché si le fichier de la carte mentale est absent/illisible
  ///
  /// In fr, this message translates to:
  /// **'Bientôt disponible'**
  String get mindMapNotReadyTitle;

  /// Corps de l'écran "bientôt disponible"
  ///
  /// In fr, this message translates to:
  /// **'La carte mentale de {name} (thèmes, branches, liens vers les versets) est en cours de rédaction.'**
  String mindMapNotReadyBody(String name);

  /// Catégorie carte mentale : récits prophétiques
  ///
  /// In fr, this message translates to:
  /// **'Récits'**
  String get mindMapCatRecits;

  /// Catégorie carte mentale : croyance/tawhid
  ///
  /// In fr, this message translates to:
  /// **'Croyance'**
  String get mindMapCatCroyance;

  /// Catégorie carte mentale : eschatologie
  ///
  /// In fr, this message translates to:
  /// **'Au-delà'**
  String get mindMapCatEschatologie;

  /// Catégorie carte mentale : argumentation/réfutation
  ///
  /// In fr, this message translates to:
  /// **'Argumentation'**
  String get mindMapCatArgumentation;

  /// Catégorie carte mentale : éthique/akhlaq
  ///
  /// In fr, this message translates to:
  /// **'Éthique'**
  String get mindMapCatEthique;

  /// Catégorie carte mentale : législation/ahkam
  ///
  /// In fr, this message translates to:
  /// **'Législation'**
  String get mindMapCatLegislation;

  /// Catégorie carte mentale : signes de la création
  ///
  /// In fr, this message translates to:
  /// **'Signes'**
  String get mindMapCatSignes;

  /// Catégorie carte mentale : adoration/ibadat
  ///
  /// In fr, this message translates to:
  /// **'Adoration'**
  String get mindMapCatAdoration;

  /// Catégorie carte mentale : repli si catégorie inconnue
  ///
  /// In fr, this message translates to:
  /// **'Autre'**
  String get mindMapCatAutre;

  /// Titre de l'AppBar de l'écran réglages
  ///
  /// In fr, this message translates to:
  /// **'Réglages'**
  String get settingsTitle;

  /// En-tête de section réglages
  ///
  /// In fr, this message translates to:
  /// **'Audio'**
  String get settingsSectionAudio;

  /// Réglage : choix du récitateur
  ///
  /// In fr, this message translates to:
  /// **'Récitateur'**
  String get settingsReciterTitle;

  /// Style de récitation : Murattal (rythme régulier)
  ///
  /// In fr, this message translates to:
  /// **'Murattal'**
  String get settingsStyleMurattal;

  /// Style de récitation : Mujawwad (mélismatique)
  ///
  /// In fr, this message translates to:
  /// **'Mujawwad'**
  String get settingsStyleMujawwad;

  /// En-tête de section réglages
  ///
  /// In fr, this message translates to:
  /// **'Prière'**
  String get settingsSectionPrayer;

  /// Réglage : boussole Qibla
  ///
  /// In fr, this message translates to:
  /// **'Direction de la Qibla'**
  String get settingsQiblaTitle;

  /// Sous-titre du réglage Qibla
  ///
  /// In fr, this message translates to:
  /// **'Boussole vers la Mecque depuis ta position'**
  String get settingsQiblaSubtitle;

  /// En-tête de section réglages
  ///
  /// In fr, this message translates to:
  /// **'Personnalisation vocale'**
  String get settingsSectionVoicePersonalization;

  /// Réglage : calibration voix
  ///
  /// In fr, this message translates to:
  /// **'Calibration voix (lettres confusables)'**
  String get settingsVoiceCalibTitle;

  /// Sous-titre du réglage de calibration voix
  ///
  /// In fr, this message translates to:
  /// **'Enregistre ~14 mots exprès bien/mal prononcés (ص/س, ط/ت...) pour affiner ta sensibilité'**
  String get settingsVoiceCalibSubtitle;

  /// Réglage : enregistrements audio conservés pour diagnostic
  ///
  /// In fr, this message translates to:
  /// **'Enregistrements de mes récitations'**
  String get settingsMyClipsTitle;

  /// Sous-titre pendant le comptage des enregistrements
  ///
  /// In fr, this message translates to:
  /// **'Chargement…'**
  String get settingsMyClipsLoading;

  /// Sous-titre quand aucun enregistrement n'existe
  ///
  /// In fr, this message translates to:
  /// **'Aucun enregistrement — ils sont conservés à chaque récitation'**
  String get settingsMyClipsEmpty;

  /// Sous-titre : nombre d'enregistrements audio conservés
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 enregistrement conservé — appuie pour l\'exporter} other{{count} enregistrements conservés — appuie pour les exporter}}'**
  String settingsMyClipsCount(int count);

  /// Snackbar après export réussi des clips vocaux
  ///
  /// In fr, this message translates to:
  /// **'Export lancé — choisis où envoyer le fichier.'**
  String get settingsExportStarted;

  /// Snackbar après export annulé/impossible des clips vocaux
  ///
  /// In fr, this message translates to:
  /// **'Export annulé ou aucun clip disponible.'**
  String get settingsExportCancelled;

  /// En-tête de section réglages
  ///
  /// In fr, this message translates to:
  /// **'Affichage'**
  String get settingsSectionDisplay;

  /// Réglage : coloration tajweed
  ///
  /// In fr, this message translates to:
  /// **'Couleurs Tajweed'**
  String get settingsTajweedColorsTitle;

  /// Sous-titre du réglage couleurs tajweed
  ///
  /// In fr, this message translates to:
  /// **'Coloration selon les règles de récitation'**
  String get settingsTajweedColorsSubtitle;

  /// En-tête de section réglages
  ///
  /// In fr, this message translates to:
  /// **'Application'**
  String get settingsSectionApp;

  /// Réglage + titre de la feuille de choix de langue
  ///
  /// In fr, this message translates to:
  /// **'Langue de l\'application'**
  String get settingsLocaleTitle;

  /// Explique le comportement du choix de langue dans la feuille de sélection
  ///
  /// In fr, this message translates to:
  /// **'En arabe, tout le contenu (menus et Coran) reste en arabe, sans traduction. En français/anglais, le Coran reste toujours en arabe ; seuls les menus et les explications changent de langue.'**
  String get settingsLocaleSheetDescription;

  /// Sous-titre de la tuile "à propos"
  ///
  /// In fr, this message translates to:
  /// **'Version 1.0.0  •  Propulsé par Gemma 4 + Whisper'**
  String get settingsAboutSubtitle;

  /// Bouton de confirmation d'un réglage
  ///
  /// In fr, this message translates to:
  /// **'Valider'**
  String get settingsValidate;

  /// Titre de section des réglages du moteur de répétition incrémentale (étape Répète du Coach)
  ///
  /// In fr, this message translates to:
  /// **'RÉPÉTITION INCRÉMENTALE'**
  String get settingsRepeatEngineSectionTitle;

  /// Titre du réglage de la taille d'un palier en mots, hors mode Enfant
  ///
  /// In fr, this message translates to:
  /// **'Mots par palier (mode Adulte)'**
  String get settingsAdultChunkWordCountTitle;

  /// Explique le réglage du nombre de mots par palier
  ///
  /// In fr, this message translates to:
  /// **'Approxime une ligne du Mushaf (1 à {max} mots). Sans effet en mode Enfant, toujours mot par mot.'**
  String settingsAdultChunkWordCountDescription(int max);

  /// Titre du réglage de la taille fixe de la fenêtre glissante de validation
  ///
  /// In fr, this message translates to:
  /// **'Fenêtre de récitation (curseur)'**
  String get settingsRepeatWindowSizeTitle;

  /// Explique le réglage de la fenêtre glissante
  ///
  /// In fr, this message translates to:
  /// **'Nombre de paliers à réciter ensemble pour valider (1 à {max}). Cette taille reste fixe, la fenêtre glisse au fil des paliers.'**
  String settingsRepeatWindowSizeDescription(int max);

  /// Message d'erreur générique quand une requête réseau échoue
  ///
  /// In fr, this message translates to:
  /// **'Connexion requise'**
  String get commonConnectionRequired;

  /// Bouton générique pour relancer une action après erreur
  ///
  /// In fr, this message translates to:
  /// **'Réessayer'**
  String get commonRetry;

  /// Tooltip de l'icône Shazam coranique sur la page d'accueil
  ///
  /// In fr, this message translates to:
  /// **'Identifier une récitation'**
  String get homeIdentifyTooltip;

  /// Tooltip de l'icône "suivre une prière" sur la page d'accueil
  ///
  /// In fr, this message translates to:
  /// **'Suivre une prière'**
  String get homeFollowPrayerTooltip;

  /// Lieu de révélation d'une sourate : La Mecque
  ///
  /// In fr, this message translates to:
  /// **'Mecquoise'**
  String get surahMeccan;

  /// Lieu de révélation d'une sourate : Médine
  ///
  /// In fr, this message translates to:
  /// **'Médinoise'**
  String get surahMedinan;

  /// Ligne de métadonnées sous le nom d'une sourate dans la liste
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 verset} other{{count} versets}} • {place}'**
  String surahMetaLine(int count, String place);

  /// Titre du sheet Coach IA quand on explique un verset entier depuis la lecture
  ///
  /// In fr, this message translates to:
  /// **'{surah} — verset {ayah}'**
  String mushafExplanationTitleSurahVerse(String surah, int ayah);

  /// Titre du sheet Coach IA quand on explique un mot précis depuis la lecture
  ///
  /// In fr, this message translates to:
  /// **'{surah} {ayah} — {word}'**
  String mushafExplanationTitleSurahVerseWord(
    String surah,
    int ayah,
    String word,
  );

  /// Bouton barre du bas : lancer la lecture audio
  ///
  /// In fr, this message translates to:
  /// **'Lire'**
  String get mushafPlay;

  /// Bouton barre du bas : mettre la lecture audio en pause
  ///
  /// In fr, this message translates to:
  /// **'Pause'**
  String get mushafPause;

  /// Bouton barre du bas : favoris
  ///
  /// In fr, this message translates to:
  /// **'Favoris'**
  String get mushafFavorites;

  /// Bouton barre du bas : travailler ce verset (mémorisation)
  ///
  /// In fr, this message translates to:
  /// **'Mémoriser'**
  String get mushafMemorize;

  /// Bouton barre du bas : afficher/masquer la traduction (abrégé, contrainte de largeur)
  ///
  /// In fr, this message translates to:
  /// **'Trad.'**
  String get mushafTranslation;

  /// Bouton barre du bas : ouvrir le coach IA
  ///
  /// In fr, this message translates to:
  /// **'Coach IA'**
  String get mushafCoachAi;

  /// Bouton barre du bas : plus d'options
  ///
  /// In fr, this message translates to:
  /// **'Plus'**
  String get mushafMore;

  /// Badge flottant : défilement automatique actif
  ///
  /// In fr, this message translates to:
  /// **'Défilement auto'**
  String get mushafAutoScroll;

  /// Bouton générique d'annulation
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get commonCancel;

  /// Bouton générique de fermeture
  ///
  /// In fr, this message translates to:
  /// **'Fermer'**
  String get commonClose;

  /// Feuille Shazam coranique : état écoute en cours
  ///
  /// In fr, this message translates to:
  /// **'Écoute en cours...\nApproche le téléphone du son.'**
  String get shazamListening;

  /// Feuille Shazam coranique : état recherche
  ///
  /// In fr, this message translates to:
  /// **'Recherche dans le Coran...'**
  String get shazamSearching;

  /// Feuille Shazam coranique : état trouvé
  ///
  /// In fr, this message translates to:
  /// **'Passage identifié !'**
  String get shazamFound;

  /// Feuille Shazam coranique : état non trouvé
  ///
  /// In fr, this message translates to:
  /// **'Passage non identifié.\nRapproche-toi du son et réessaie.'**
  String get shazamNotFound;

  /// Feuille Shazam coranique : état erreur
  ///
  /// In fr, this message translates to:
  /// **'Erreur pendant l\'écoute.'**
  String get shazamError;

  /// Résultat Shazam coranique : référence du passage trouvé
  ///
  /// In fr, this message translates to:
  /// **'Sourate {surah}, verset {ayah}'**
  String shazamMatchLabel(int surah, int ayah);

  /// Bouton : ouvrir le passage identifié par le Shazam coranique
  ///
  /// In fr, this message translates to:
  /// **'Y aller'**
  String get shazamGoThere;

  /// En-tête de section dans le tiroir de réglages de lecture
  ///
  /// In fr, this message translates to:
  /// **'AFFICHAGE'**
  String get readingSettingsDisplaySection;

  /// En-tête de section dans le tiroir de réglages de lecture
  ///
  /// In fr, this message translates to:
  /// **'DÉFILEMENT AUTOMATIQUE'**
  String get readingSettingsAutoScrollSection;

  /// Explique le défilement automatique
  ///
  /// In fr, this message translates to:
  /// **'Le texte défile tout seul à la vitesse choisie — pratique pour lire sans les mains. Un glissement manuel l\'arrête.'**
  String get readingSettingsAutoScrollDescription;

  /// En-tête de section dans le tiroir de réglages de lecture
  ///
  /// In fr, this message translates to:
  /// **'VITESSE DE LECTURE (AUDIO)'**
  String get readingSettingsPlaybackSpeedSection;

  /// En-tête de section dans le tiroir de réglages de lecture
  ///
  /// In fr, this message translates to:
  /// **'RÉPÉTITION / BOUCLES'**
  String get readingSettingsRepeatSection;

  /// Explique la répétition/boucles
  ///
  /// In fr, this message translates to:
  /// **'Répète chaque verset (ou toute la sourate) en boucle avant de passer au suivant.'**
  String get readingSettingsRepeatDescription;

  /// Option de répétition : aucune
  ///
  /// In fr, this message translates to:
  /// **'Désactivé'**
  String get readingSettingsRepeatOff;

  /// Option de répétition : verset répété N fois
  ///
  /// In fr, this message translates to:
  /// **'Verset × {count}'**
  String readingSettingsRepeatVerseCount(int count);

  /// Option de répétition : verset répété en boucle infinie
  ///
  /// In fr, this message translates to:
  /// **'Verset × ∞'**
  String get readingSettingsRepeatVerseInfinite;

  /// Option de répétition : sourate entière en boucle
  ///
  /// In fr, this message translates to:
  /// **'Sourate entière'**
  String get readingSettingsRepeatSurah;

  /// Vitesse de défilement automatique : arrêté
  ///
  /// In fr, this message translates to:
  /// **'Arrêté'**
  String get readingSettingsSpeedOff;

  /// Vitesse de défilement automatique : lent
  ///
  /// In fr, this message translates to:
  /// **'Lent'**
  String get readingSettingsSpeedSlow;

  /// Vitesse de défilement automatique : normal
  ///
  /// In fr, this message translates to:
  /// **'Normal'**
  String get readingSettingsSpeedNormal;

  /// Vitesse de défilement automatique : rapide
  ///
  /// In fr, this message translates to:
  /// **'Rapide'**
  String get readingSettingsSpeedFast;

  /// Tooltip : lire l'explication à voix haute
  ///
  /// In fr, this message translates to:
  /// **'Écouter'**
  String get coachExplanationListen;

  /// Tooltip : arrêter la lecture à voix haute
  ///
  /// In fr, this message translates to:
  /// **'Arrêter'**
  String get coachExplanationStop;

  /// Tooltip du sélecteur de langue de l'explication (contenu, pas l'UI)
  ///
  /// In fr, this message translates to:
  /// **'Langue'**
  String get coachExplanationLanguageTooltip;

  /// Message d'erreur de chargement de l'explication
  ///
  /// In fr, this message translates to:
  /// **'Erreur : {error}'**
  String coachExplanationError(String error);

  /// Racine trilitère du mot expliqué
  ///
  /// In fr, this message translates to:
  /// **'Racine : {root}'**
  String coachExplanationRoot(String root);

  /// Bouton : afficher le palier d'explication suivant (plus détaillé)
  ///
  /// In fr, this message translates to:
  /// **'Approfondir'**
  String get coachExplanationExpand;

  /// Repli quand ni la cascade offline ni le tuteur Gemma n'ont de contenu
  ///
  /// In fr, this message translates to:
  /// **'Aucune explication disponible pour ce passage sur cet appareil.'**
  String get coachExplanationNoneAvailable;

  /// En-tête de la fiche d'aide tajwid : référence du verset
  ///
  /// In fr, this message translates to:
  /// **'Verset {key}'**
  String tajwidHelpVerseLabel(String key);

  /// Titre de la légende des règles tajwid présentes dans le verset
  ///
  /// In fr, this message translates to:
  /// **'RÈGLES DANS CE VERSET'**
  String get tajwidHelpRulesInVerse;

  /// Bouton : écouter le verset par ce récitateur
  ///
  /// In fr, this message translates to:
  /// **'Écouter — {name}'**
  String tajwidHelpListenWithReciter(String name);

  /// Titre du contrôle d'écoute par portée de mots
  ///
  /// In fr, this message translates to:
  /// **'ÉCOUTER LA PRONONCIATION'**
  String get tajwidHelpListenPronunciation;

  /// Option de portée d'écoute : seulement le mot tapé
  ///
  /// In fr, this message translates to:
  /// **'Ce mot'**
  String get tajwidHelpThisWord;

  /// Option de portée d'écoute : mot tapé + précédent
  ///
  /// In fr, this message translates to:
  /// **'+ mot précédent'**
  String get tajwidHelpPlusPrevious;

  /// Option de portée d'écoute : mot tapé + précédent + suivant
  ///
  /// In fr, this message translates to:
  /// **'+ précédent et suivant'**
  String get tajwidHelpPlusBoth;

  /// État du bouton d'écoute pendant la lecture audio
  ///
  /// In fr, this message translates to:
  /// **'Lecture…'**
  String get tajwidHelpPlaying;

  /// Titre de la boucle de correction (réenregistrement d'un mot)
  ///
  /// In fr, this message translates to:
  /// **'RÉESSAYER CE MOT'**
  String get tajwidHelpRetryThisWord;

  /// Résultat de la boucle de correction : mot validé
  ///
  /// In fr, this message translates to:
  /// **'Corrigé — entendu : \"{text}\"'**
  String tajwidHelpCorrectedHeard(String text);

  /// Transcription vide après un réenregistrement
  ///
  /// In fr, this message translates to:
  /// **'(rien entendu)'**
  String get tajwidHelpNothingHeard;

  /// Résultat de la boucle de correction : mot pas encore correct
  ///
  /// In fr, this message translates to:
  /// **'Pas encore — entendu : \"{text}\". Réessaie, à ton rythme.'**
  String tajwidHelpNotYetHeard(String text);

  /// État du bouton de correction pendant l'analyse du mot réenregistré
  ///
  /// In fr, this message translates to:
  /// **'Analyse en cours…'**
  String get tajwidHelpAnalyzing;

  /// Bouton : arrêter l'enregistrement du mot
  ///
  /// In fr, this message translates to:
  /// **'Terminer l\'enregistrement'**
  String get tajwidHelpFinishRecording;

  /// Bouton : démarrer l'enregistrement du mot
  ///
  /// In fr, this message translates to:
  /// **'S\'enregistrer sur ce mot'**
  String get tajwidHelpRecordThisWord;

  /// No description provided for @tajwidRuleMaddaNecessaryName.
  ///
  /// In fr, this message translates to:
  /// **'Madd — 6 temps (obligatoire)'**
  String get tajwidRuleMaddaNecessaryName;

  /// No description provided for @tajwidRuleMaddaNecessaryExplanation.
  ///
  /// In fr, this message translates to:
  /// **'Allongement obligatoire de 6 temps (madd lâzim).'**
  String get tajwidRuleMaddaNecessaryExplanation;

  /// No description provided for @tajwidRuleMaddaObligatoryName.
  ///
  /// In fr, this message translates to:
  /// **'Madd — 4 ou 5 temps (obligatoire)'**
  String get tajwidRuleMaddaObligatoryName;

  /// No description provided for @tajwidRuleMaddaObligatoryExplanation.
  ///
  /// In fr, this message translates to:
  /// **'Allongement obligatoire de 4 à 5 temps.'**
  String get tajwidRuleMaddaObligatoryExplanation;

  /// No description provided for @tajwidRuleMaddaPermissibleName.
  ///
  /// In fr, this message translates to:
  /// **'Madd — 2, 4 ou 6 temps (permis)'**
  String get tajwidRuleMaddaPermissibleName;

  /// No description provided for @tajwidRuleMaddaPermissibleExplanation.
  ///
  /// In fr, this message translates to:
  /// **'Allongement de 2, 4 ou 6 temps selon l\'école de lecture.'**
  String get tajwidRuleMaddaPermissibleExplanation;

  /// No description provided for @tajwidRuleGhunnahName.
  ///
  /// In fr, this message translates to:
  /// **'Ghunna / Ikhfâ\''**
  String get tajwidRuleGhunnahName;

  /// No description provided for @tajwidRuleGhunnahExplanation.
  ///
  /// In fr, this message translates to:
  /// **'Son nasal tenu environ 2 temps (noûn/mîm doublé), ou dissimulation avec nasalisation.'**
  String get tajwidRuleGhunnahExplanation;

  /// No description provided for @tajwidRuleIkhafaName.
  ///
  /// In fr, this message translates to:
  /// **'Ikhfâ\' (dissimulation)'**
  String get tajwidRuleIkhafaName;

  /// No description provided for @tajwidRuleIkhafaExplanation.
  ///
  /// In fr, this message translates to:
  /// **'Le noûn sâkin/tanwîn se prononce \"caché\", entre le noûn et la lettre suivante, avec nasalisation.'**
  String get tajwidRuleIkhafaExplanation;

  /// No description provided for @tajwidRuleIkhafaShafawiName.
  ///
  /// In fr, this message translates to:
  /// **'Ikhfâ\' shafawî'**
  String get tajwidRuleIkhafaShafawiName;

  /// No description provided for @tajwidRuleIkhafaShafawiExplanation.
  ///
  /// In fr, this message translates to:
  /// **'Le mîm sâkin devant bâ\' se prononce légèrement dissimulé, avec nasalisation.'**
  String get tajwidRuleIkhafaShafawiExplanation;

  /// No description provided for @tajwidRuleIdghamGhunnahName.
  ///
  /// In fr, this message translates to:
  /// **'Idghâm avec ghunna'**
  String get tajwidRuleIdghamGhunnahName;

  /// No description provided for @tajwidRuleIdghamGhunnahExplanation.
  ///
  /// In fr, this message translates to:
  /// **'Le noûn sâkin/tanwîn s\'assimile à la lettre suivante (ي ن م و) avec nasalisation.'**
  String get tajwidRuleIdghamGhunnahExplanation;

  /// No description provided for @tajwidRuleIdghamShafawiName.
  ///
  /// In fr, this message translates to:
  /// **'Idghâm shafawî'**
  String get tajwidRuleIdghamShafawiName;

  /// No description provided for @tajwidRuleIdghamShafawiExplanation.
  ///
  /// In fr, this message translates to:
  /// **'Le mîm sâkin s\'assimile au mîm suivant, avec nasalisation.'**
  String get tajwidRuleIdghamShafawiExplanation;

  /// No description provided for @tajwidRuleIqlabName.
  ///
  /// In fr, this message translates to:
  /// **'Iqlâb (conversion)'**
  String get tajwidRuleIqlabName;

  /// No description provided for @tajwidRuleIqlabExplanation.
  ///
  /// In fr, this message translates to:
  /// **'Le noûn sâkin/tanwîn devient mîm devant la lettre bâ\', avec nasalisation.'**
  String get tajwidRuleIqlabExplanation;

  /// No description provided for @tajwidRuleIdghamWoGhunnahName.
  ///
  /// In fr, this message translates to:
  /// **'Idghâm sans ghunna'**
  String get tajwidRuleIdghamWoGhunnahName;

  /// No description provided for @tajwidRuleIdghamWoGhunnahExplanation.
  ///
  /// In fr, this message translates to:
  /// **'Le noûn sâkin/tanwîn s\'assimile complètement à la lettre suivante (ل ر), sans nasalisation.'**
  String get tajwidRuleIdghamWoGhunnahExplanation;

  /// No description provided for @tajwidRuleIdghamMutajanisaynName.
  ///
  /// In fr, this message translates to:
  /// **'Idghâm mutajânisayn'**
  String get tajwidRuleIdghamMutajanisaynName;

  /// No description provided for @tajwidRuleIdghamMutajanisaynExplanation.
  ///
  /// In fr, this message translates to:
  /// **'Deux lettres de même point d\'articulation : la première s\'assimile à la seconde.'**
  String get tajwidRuleIdghamMutajanisaynExplanation;

  /// No description provided for @tajwidRuleIdghamMutaqaribaynName.
  ///
  /// In fr, this message translates to:
  /// **'Idghâm mutaqâribayn'**
  String get tajwidRuleIdghamMutaqaribaynName;

  /// No description provided for @tajwidRuleIdghamMutaqaribaynExplanation.
  ///
  /// In fr, this message translates to:
  /// **'Deux lettres proches : la première s\'assimile à la seconde.'**
  String get tajwidRuleIdghamMutaqaribaynExplanation;

  /// No description provided for @tajwidRuleQalaqahName.
  ///
  /// In fr, this message translates to:
  /// **'Qalqala (rebond)'**
  String get tajwidRuleQalaqahName;

  /// No description provided for @tajwidRuleQalaqahExplanation.
  ///
  /// In fr, this message translates to:
  /// **'Rebond sonore sur ق ط ب ج د quand elles portent un soukoûn.'**
  String get tajwidRuleQalaqahExplanation;

  /// No description provided for @tajwidRuleHamWaslName.
  ///
  /// In fr, this message translates to:
  /// **'Hamzat al-wasl'**
  String get tajwidRuleHamWaslName;

  /// No description provided for @tajwidRuleHamWaslExplanation.
  ///
  /// In fr, this message translates to:
  /// **'Ne se prononce qu\'en début de lecture — s\'élide quand on enchaîne depuis le mot précédent.'**
  String get tajwidRuleHamWaslExplanation;

  /// No description provided for @tajwidRuleLaamShamsiyahName.
  ///
  /// In fr, this message translates to:
  /// **'Lâm solaire'**
  String get tajwidRuleLaamShamsiyahName;

  /// No description provided for @tajwidRuleLaamShamsiyahExplanation.
  ///
  /// In fr, this message translates to:
  /// **'Le lâm de \"ال\" ne se prononce pas : la lettre suivante est doublée à la place.'**
  String get tajwidRuleLaamShamsiyahExplanation;

  /// No description provided for @tajwidRuleSlntName.
  ///
  /// In fr, this message translates to:
  /// **'Lettre muette'**
  String get tajwidRuleSlntName;

  /// No description provided for @tajwidRuleSlntExplanation.
  ///
  /// In fr, this message translates to:
  /// **'S\'écrit mais ne se prononce pas.'**
  String get tajwidRuleSlntExplanation;

  /// Titre de l'écran des invocations
  ///
  /// In fr, this message translates to:
  /// **'Invocations & Adhkar'**
  String get duasScreenTitle;

  /// Placeholder du champ de recherche des invocations
  ///
  /// In fr, this message translates to:
  /// **'Chercher une invocation, un mot, une source…'**
  String get duasSearchHint;

  /// Titre de section : parcourir les univers d'invocations
  ///
  /// In fr, this message translates to:
  /// **'Explorer'**
  String get duasExplore;

  /// Titre de section : invocations favorites
  ///
  /// In fr, this message translates to:
  /// **'Mes favoris'**
  String get duasMyFavorites;

  /// Badge de la carte contextuelle (invocation du moment)
  ///
  /// In fr, this message translates to:
  /// **'MAINTENANT'**
  String get duasNow;

  /// Badge : cette collection est un guide pas-à-pas (ex. rite du hajj)
  ///
  /// In fr, this message translates to:
  /// **'GUIDE'**
  String get duasGuideBadge;

  /// Message quand la recherche d'invocation ne donne rien
  ///
  /// In fr, this message translates to:
  /// **'Aucun résultat.'**
  String get duasNoneFound;

  /// Nombre d'invocations dans une collection/un univers
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 invocation} other{{count} invocations}}'**
  String duasInvocationCount(int count);

  /// Tooltip du bouton favori quand l'invocation est déjà favorite
  ///
  /// In fr, this message translates to:
  /// **'Retirer des favoris'**
  String get duaRemoveFavorite;

  /// Tooltip du bouton favori quand l'invocation n'est pas favorite
  ///
  /// In fr, this message translates to:
  /// **'Mettre en favori'**
  String get duaAddFavorite;

  /// Message d'erreur si l'audio du verset associé échoue
  ///
  /// In fr, this message translates to:
  /// **'Lecture impossible : {error}'**
  String duaPlaybackError(String error);

  /// Bouton : replier le texte du mérite de l'invocation
  ///
  /// In fr, this message translates to:
  /// **'Masquer le mérite'**
  String get duaHideVirtue;

  /// Bouton : déplier le texte du mérite de l'invocation
  ///
  /// In fr, this message translates to:
  /// **'Pourquoi la dire'**
  String get duaShowVirtue;

  /// Compteur de répétitions atteint
  ///
  /// In fr, this message translates to:
  /// **'Terminé — {target}/{target}'**
  String duaRepeatComplete(int target);

  /// Tooltip : remettre le compteur de répétitions à zéro
  ///
  /// In fr, this message translates to:
  /// **'Recommencer le compte'**
  String get duaResetCount;

  /// Message quand une collection d'invocations n'a aucune entrée
  ///
  /// In fr, this message translates to:
  /// **'Cette collection est encore vide.'**
  String get duaCollectionEmpty;

  /// Nom de repli d'une sourate quand le nom réel n'est pas chargé
  ///
  /// In fr, this message translates to:
  /// **'Sourate {number}'**
  String coachSurahLabel(int number);

  /// Sur-titre de l'écran Coach (au-dessus du nom du verset)
  ///
  /// In fr, this message translates to:
  /// **'COACH MÉMORISATION'**
  String get coachHeaderLabel;

  /// Tooltip de l'icône réglages tajwid dans l'en-tête Coach
  ///
  /// In fr, this message translates to:
  /// **'Mode de vérification'**
  String get coachVerificationModeTooltip;

  /// Étape 1 du Coach : lecture guidée
  ///
  /// In fr, this message translates to:
  /// **'Lecture'**
  String get coachStepLecture;

  /// Étape 2 du Coach : entraînement/apprentissage
  ///
  /// In fr, this message translates to:
  /// **'Entraîne'**
  String get coachStepTrain;

  /// Étape 3 du Coach : récitation de mémoire
  ///
  /// In fr, this message translates to:
  /// **'Contrôle'**
  String get coachStepControl;

  /// Bandeau d'instruction de l'étape Lecture
  ///
  /// In fr, this message translates to:
  /// **'Lis ce verset à voix haute — l\'app détecte les mots difficiles et mémorise ta voix.'**
  String get coachReadAloudInstruction;

  /// Statut micro pendant l'étape Lecture
  ///
  /// In fr, this message translates to:
  /// **'Je note les mots difficiles…'**
  String get coachListeningLecture;

  /// Statut micro : étape Lecture terminée
  ///
  /// In fr, this message translates to:
  /// **'Lecture analysée'**
  String get coachDoneLecture;

  /// Statut micro : invite à démarrer l'étape Lecture
  ///
  /// In fr, this message translates to:
  /// **'Appuie et lis le verset'**
  String get coachTapToRead;

  /// Bouton : sauter directement au contrôle
  ///
  /// In fr, this message translates to:
  /// **'Je sais déjà'**
  String get coachAlreadyKnow;

  /// Bouton : passer à l'étape d'entraînement
  ///
  /// In fr, this message translates to:
  /// **'S\'entraîner'**
  String get coachTrainButton;

  /// Sous-étape d'entraînement 1/3
  ///
  /// In fr, this message translates to:
  /// **'Écoute'**
  String get coachSubStepListen;

  /// Sous-étape d'entraînement 2/3
  ///
  /// In fr, this message translates to:
  /// **'Imite'**
  String get coachSubStepImitate;

  /// Sous-étape d'entraînement 3/3
  ///
  /// In fr, this message translates to:
  /// **'Répète'**
  String get coachSubStepRepeat;

  /// Bandeau d'instruction sous-étape Écoute
  ///
  /// In fr, this message translates to:
  /// **'Écoute le récitateur. Suis chaque mot avec les yeux.'**
  String get coachListenInstruction;

  /// Statut pendant la lecture audio du récitateur
  ///
  /// In fr, this message translates to:
  /// **'Écoute en cours…'**
  String get coachListeningAudio;

  /// Invite à démarrer l'écoute du récitateur
  ///
  /// In fr, this message translates to:
  /// **'Appuie pour écouter'**
  String get coachTapToListen;

  /// Bouton : passer à la sous-étape Imite
  ///
  /// In fr, this message translates to:
  /// **'Passons à l\'imitation'**
  String get coachMoveToImitation;

  /// Bandeau d'instruction sous-étape Imite
  ///
  /// In fr, this message translates to:
  /// **'Lance l\'audio et parle en même temps. Copie le rythme, les pauses, l\'intonation.'**
  String get coachImitateInstruction;

  /// Statut pendant l'audio à la sous-étape Imite
  ///
  /// In fr, this message translates to:
  /// **'Parle en même temps que l\'audio'**
  String get coachSpeakAlong;

  /// Invite à démarrer la sous-étape Imite
  ///
  /// In fr, this message translates to:
  /// **'Lance l\'audio et imite'**
  String get coachLaunchAndImitate;

  /// Bouton : passer à la sous-étape Répète
  ///
  /// In fr, this message translates to:
  /// **'J\'ai imité — Répéter seul'**
  String get coachImitatedNext;

  /// Bandeau d'instruction de l'étape Répète incrémentale
  ///
  /// In fr, this message translates to:
  /// **'Écoute puis répète. Le palier grandit à chaque réussite.'**
  String get coachIncrementalInstruction;

  /// Libellé affiché pendant le chargement du moteur de vérification (jamais le nom technique du modèle)
  ///
  /// In fr, this message translates to:
  /// **'Préparation…'**
  String get coachIncrementalPreparing;

  /// Statut pendant l'écoute ou la lecture audio d'un palier
  ///
  /// In fr, this message translates to:
  /// **'Écoute en cours…'**
  String get coachIncrementalListening;

  /// Invite à retaper le micro après un échec
  ///
  /// In fr, this message translates to:
  /// **'Appuie pour réessayer'**
  String get coachIncrementalTapToStart;

  /// Progression dans les paliers du verset courant
  ///
  /// In fr, this message translates to:
  /// **'Palier {done}/{total}'**
  String coachIncrementalUnitProgress(int done, int total);

  /// Message bref affiché lors du passage automatique au verset suivant
  ///
  /// In fr, this message translates to:
  /// **'Verset suivant'**
  String get coachIncrementalVerseAdvance;

  /// Bandeau d'instruction de l'étape Contrôle
  ///
  /// In fr, this message translates to:
  /// **'Récite de mémoire — le texte est masqué.'**
  String get coachRecallInstruction;

  /// Badge court affiché sur le verset flouté avant la récitation
  ///
  /// In fr, this message translates to:
  /// **'Récite de mémoire'**
  String get coachRecallBadge;

  /// Statut micro pendant l'étape Contrôle
  ///
  /// In fr, this message translates to:
  /// **'Récite de mémoire…'**
  String get coachListeningControl;

  /// Statut micro : étape Contrôle terminée
  ///
  /// In fr, this message translates to:
  /// **'Récitation terminée'**
  String get coachControlDone;

  /// Invite à démarrer l'étape Contrôle
  ///
  /// In fr, this message translates to:
  /// **'Appuie et récite de mémoire'**
  String get coachTapToRecall;

  /// Bouton : retourner à l'étape d'entraînement depuis le Contrôle
  ///
  /// In fr, this message translates to:
  /// **'Retour entraînement'**
  String get coachBackToTraining;

  /// Titre de l'encart montrant la transcription brute reconnue
  ///
  /// In fr, this message translates to:
  /// **'TRANSCRIPT MODÈLE'**
  String get coachTranscriptLabel;

  /// Statut pendant l'inférence du modèle sur l'audio enregistré
  ///
  /// In fr, this message translates to:
  /// **'Analyse Whisper en cours…'**
  String get coachAnalyzingAudio;

  /// Score de précision affiché après une récitation
  ///
  /// In fr, this message translates to:
  /// **'{pct}% de précision'**
  String coachAccuracyPercent(int pct);

  /// Score de similarité vocale avec la référence enregistrée
  ///
  /// In fr, this message translates to:
  /// **'Empreinte vocale : {pct}%'**
  String coachFingerprintScore(int pct);

  /// Le score de mémoire dépasse la première lecture
  ///
  /// In fr, this message translates to:
  /// **'Mémorisation confirmée !'**
  String get coachMemorizedConfirmed;

  /// Le score de mémoire ne dépasse pas encore la première lecture
  ///
  /// In fr, this message translates to:
  /// **'Continue à t\'entraîner'**
  String get coachKeepTraining;

  /// Comparaison entre le score de première lecture et le score de mémoire
  ///
  /// In fr, this message translates to:
  /// **'1ère lecture : {baseline}%  →  De mémoire : {control}%  ({delta}%)'**
  String coachGapSummary(int baseline, int control, String delta);

  /// Message du coach, étape Lecture, score élevé
  ///
  /// In fr, this message translates to:
  /// **'Excellente lecture ! Tu maîtrises bien la prononciation de ce verset.'**
  String get coachMsgLectureExcellent;

  /// Message du coach, étape Lecture, mots difficiles détectés
  ///
  /// In fr, this message translates to:
  /// **'Ces mots t\'ont posé problème : {words}\n\nConcentre-toi dessus lors de l\'entraînement.'**
  String coachMsgLectureDifficultWords(String words);

  /// Message du coach, étape Lecture, cas générique
  ///
  /// In fr, this message translates to:
  /// **'Quelques hésitations détectées. L\'entraînement va t\'aider à les corriger.'**
  String get coachMsgLectureHesitant;

  /// Message du coach, étape Entraînement, score élevé
  ///
  /// In fr, this message translates to:
  /// **'Très bien ! Tu répètes correctement. Tu peux maintenant tester ta mémorisation sans le texte.'**
  String get coachMsgTrainGreat;

  /// Message du coach, étape Entraînement, score moyen
  ///
  /// In fr, this message translates to:
  /// **'C\'est un bon début. Recommence encore une fois pour ancrer les mots hésitants.'**
  String get coachMsgTrainGoodStart;

  /// Message du coach, étape Entraînement, score faible
  ///
  /// In fr, this message translates to:
  /// **'Reprends l\'écoute et l\'imitation, puis réessaie la répétition.'**
  String get coachMsgTrainRestart;

  /// Message du coach, étape Contrôle, progression confirmée par rapport à la première lecture
  ///
  /// In fr, this message translates to:
  /// **'Ma cha Allah ! Tu récites mieux de mémoire que lors de ta première lecture — le verset est mémorisé !'**
  String get coachMsgControlMashallah;

  /// Message du coach, étape Contrôle, score élevé
  ///
  /// In fr, this message translates to:
  /// **'Très bonne récitation ! Continue à réviser régulièrement pour consolider.'**
  String get coachMsgControlVeryGood;

  /// Message du coach, étape Contrôle, score moyen
  ///
  /// In fr, this message translates to:
  /// **'Tu es sur la bonne voie. Encore quelques répétitions et le verset sera ancré.'**
  String get coachMsgControlGoodPath;

  /// Message du coach, étape Contrôle, score faible
  ///
  /// In fr, this message translates to:
  /// **'Continue à t\'entraîner. Reviens à la phase lecture pour cibler les points faibles.'**
  String get coachMsgControlKeepTraining;

  /// Type d'erreur de récitation : lettre mal prononcée
  ///
  /// In fr, this message translates to:
  /// **'Lettre'**
  String get errorKindLettre;

  /// Type d'erreur de récitation : voyelle brève mal prononcée
  ///
  /// In fr, this message translates to:
  /// **'Harakat'**
  String get errorKindHarakat;

  /// Type d'erreur de récitation : règle de tajwid non respectée (déduction)
  ///
  /// In fr, this message translates to:
  /// **'Tajwid'**
  String get errorKindTajwid;

  /// Type d'erreur de récitation : mot non prononcé
  ///
  /// In fr, this message translates to:
  /// **'Mot sauté'**
  String get errorKindSkippedWord;

  /// Type d'erreur de récitation : cause non identifiée
  ///
  /// In fr, this message translates to:
  /// **'Indéterminé'**
  String get errorKindUnknown;

  /// Titre de l'écran hub Coach
  ///
  /// In fr, this message translates to:
  /// **'Mon coach'**
  String get coachHubTitle;

  /// Titre de la carte "reprendre la dernière session"
  ///
  /// In fr, this message translates to:
  /// **'Reprendre'**
  String get coachHubResumeLabel;

  /// Référence du dernier verset travaillé
  ///
  /// In fr, this message translates to:
  /// **'{surahName} — verset {ayah}'**
  String coachHubResumeVerse(String surahName, int ayah);

  /// Bouton : reprendre la dernière session Coach
  ///
  /// In fr, this message translates to:
  /// **'Continuer'**
  String get coachHubContinue;

  /// Titre de la zone B du hub Coach
  ///
  /// In fr, this message translates to:
  /// **'MÉMORISER'**
  String get coachHubMemorizeSectionTitle;

  /// Sous-titre de la zone B du hub Coach
  ///
  /// In fr, this message translates to:
  /// **'Verset par verset, avec le micro'**
  String get coachHubMemorizeSectionSubtitle;

  /// Bouton d'action de la zone Mémoriser
  ///
  /// In fr, this message translates to:
  /// **'Mémoriser une sourate'**
  String get coachHubMemorizeSurahTitle;

  /// Sous-titre du bouton Mémoriser une sourate
  ///
  /// In fr, this message translates to:
  /// **'Lecture → Apprentissage → Contrôle'**
  String get coachHubMemorizeSurahSubtitle;

  /// Titre de l'écran de choix de sourate pour la mémorisation
  ///
  /// In fr, this message translates to:
  /// **'Mémoriser'**
  String get coachHubPickerMemorizeTitle;

  /// Sous-titre de l'écran de choix de sourate pour la mémorisation
  ///
  /// In fr, this message translates to:
  /// **'Choisis la sourate à travailler'**
  String get coachHubPickerMemorizeSubtitle;

  /// Titre de la grande carte d'action Réciter
  ///
  /// In fr, this message translates to:
  /// **'Réciter une sourate'**
  String get coachHubReciteSurahTitle;

  /// Sous-titre de la grande carte d'action Réciter
  ///
  /// In fr, this message translates to:
  /// **'Suivi mot à mot, correction en direct'**
  String get coachHubReciteSurahSubtitle;

  /// Titre de l'écran de choix de sourate pour la récitation
  ///
  /// In fr, this message translates to:
  /// **'Réciter'**
  String get coachHubPickerReciteTitle;

  /// Sous-titre de l'écran de choix de sourate pour la récitation
  ///
  /// In fr, this message translates to:
  /// **'Choisis la sourate à réciter'**
  String get coachHubPickerReciteSubtitle;

  /// Titre de la zone D du hub Coach
  ///
  /// In fr, this message translates to:
  /// **'MES ERREURS'**
  String get coachHubErrorsSectionTitle;

  /// Sous-titre de la zone D du hub Coach
  ///
  /// In fr, this message translates to:
  /// **'Par type, puis par sourate'**
  String get coachHubErrorsSectionSubtitle;

  /// Erreur de chargement du journal des erreurs de récitation
  ///
  /// In fr, this message translates to:
  /// **'Impossible de charger le journal : {error}'**
  String coachHubLoadErrorLog(String error);

  /// Titre affiché quand le journal d'erreurs est vide
  ///
  /// In fr, this message translates to:
  /// **'Aucune erreur journalisée'**
  String get coachHubNoErrorsTitle;

  /// Corps affiché quand le journal d'erreurs est vide
  ///
  /// In fr, this message translates to:
  /// **'Récite depuis « Réciter » ou « Mémoriser » : les mots repris apparaîtront ici, regroupés par sourate.'**
  String get coachHubNoErrorsBody;

  /// Nombre de versets touchés par des erreurs, sur le total de la sourate
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 verset} other{{count} versets}} sur {total}'**
  String coachHubVersesTouched(int count, int total);

  /// Bouton : ouvrir la carte mentale de la sourate depuis le journal d'erreurs
  ///
  /// In fr, this message translates to:
  /// **'Situer dans la carte mentale'**
  String get coachHubGoToMindMap;

  /// Ligne d'erreur pour un verset donné
  ///
  /// In fr, this message translates to:
  /// **'Verset {ayah}  ·  {count, plural, =1{1 erreur} other{{count} erreurs}}'**
  String coachHubAyahErrorCount(int ayah, int count);

  /// Tooltip : ouvrir l'explication Coach IA pour ce verset
  ///
  /// In fr, this message translates to:
  /// **'Explication'**
  String get coachHubExplanationTooltip;

  /// Tooltip : ouvrir CoachScreen sur ce verset
  ///
  /// In fr, this message translates to:
  /// **'Revoir ce verset'**
  String get coachHubReviewVerseTooltip;

  /// Note explicative sous la répartition des erreurs par type
  ///
  /// In fr, this message translates to:
  /// **'Lettre et Harakat = prononciation. « Tajwid » signifie que ni les lettres ni les voyelles n\'expliquent l\'écart sur un mot porteur d\'une règle — c\'est une déduction, pas une preuve que la règle a été ratée.'**
  String get coachHubErrorNoteExplainer;

  /// Titre de la répartition des erreurs de tajwid par règle précise
  ///
  /// In fr, this message translates to:
  /// **'Détail par règle de tajwid'**
  String get coachHubRuleBreakdownTitle;

  /// Tooltip du bouton de remise à zéro des statistiques d'erreurs
  ///
  /// In fr, this message translates to:
  /// **'Réinitialiser le journal d\'erreurs'**
  String get coachHubResetErrorsTooltip;

  /// Titre de la boîte de dialogue de confirmation avant remise à zéro
  ///
  /// In fr, this message translates to:
  /// **'Réinitialiser les statistiques ?'**
  String get coachHubResetErrorsDialogTitle;

  /// Corps de la boîte de dialogue de confirmation avant remise à zéro
  ///
  /// In fr, this message translates to:
  /// **'Tout l\'historique des erreurs (toutes sourates, tous types) sera effacé définitivement. Cette action est irréversible.'**
  String get coachHubResetErrorsDialogBody;

  /// Bouton de confirmation de la remise à zéro
  ///
  /// In fr, this message translates to:
  /// **'Réinitialiser'**
  String get coachHubResetErrorsDialogConfirm;

  /// Bouton d'annulation de la remise à zéro
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get coachHubResetErrorsDialogCancel;

  /// Confirmation affichée après la remise à zéro
  ///
  /// In fr, this message translates to:
  /// **'Journal d\'erreurs réinitialisé.'**
  String get coachHubResetErrorsDone;

  /// Titre de la zone jeu de mémorisation dans le hub Coach
  ///
  /// In fr, this message translates to:
  /// **'Jouer'**
  String get coachHubGameSectionTitle;

  /// Sous-titre de la zone jeu de mémorisation
  ///
  /// In fr, this message translates to:
  /// **'Rappel progressif, palier par palier'**
  String get coachHubGameSectionSubtitle;

  /// Titre de l'action lançant le jeu de mémorisation
  ///
  /// In fr, this message translates to:
  /// **'Jeu de mémorisation'**
  String get coachHubGameActionTitle;

  /// Sous-titre de l'action lançant le jeu de mémorisation
  ///
  /// In fr, this message translates to:
  /// **'Les mots se dévoilent un à un, à toi de réciter le reste'**
  String get coachHubGameActionSubtitle;

  /// Titre du sélecteur de sourate pour le jeu de mémorisation
  ///
  /// In fr, this message translates to:
  /// **'Jeu de mémorisation'**
  String get coachHubPickerGameTitle;

  /// Sous-titre du sélecteur de sourate pour le jeu de mémorisation
  ///
  /// In fr, this message translates to:
  /// **'Choisis la sourate à mémoriser en jouant'**
  String get coachHubPickerGameSubtitle;

  /// Titre de l'écran du jeu de mémorisation
  ///
  /// In fr, this message translates to:
  /// **'Jeu de mémorisation'**
  String get memorizationGameTitle;

  /// Tooltip du bouton de réinitialisation du verset courant
  ///
  /// In fr, this message translates to:
  /// **'Recommencer ce verset'**
  String get memorizationGameRestartVerseTooltip;

  /// Indicateur de progression dans la sourate
  ///
  /// In fr, this message translates to:
  /// **'Verset {current} sur {total}'**
  String memorizationGameVerseProgress(int current, int total);

  /// Titre affiché à la fin du jeu de mémorisation
  ///
  /// In fr, this message translates to:
  /// **'Sourate terminée !'**
  String get memorizationGameCompleteTitle;

  /// Corps affiché à la fin du jeu de mémorisation
  ///
  /// In fr, this message translates to:
  /// **'Tu as parcouru tous les paliers de {surah}. Recommence pour renforcer ta mémorisation.'**
  String memorizationGameCompleteBody(String surah);

  /// Bouton de retour au hub Coach depuis l'écran de fin de jeu
  ///
  /// In fr, this message translates to:
  /// **'Retour'**
  String get memorizationGameBackToHub;

  /// Titre de l'écran de sélection de l'aya de départ pour le jeu
  ///
  /// In fr, this message translates to:
  /// **'Choisis ton départ'**
  String get memorizationAyahPickerTitle;

  /// Sous-titre de l'étape 1 (choix de la page) expliquant pourquoi on demande un point de départ
  ///
  /// In fr, this message translates to:
  /// **'{surah} est longue : choisis d\'abord la page où tu veux commencer'**
  String memorizationAyahPickerSubtitle(String surah);

  /// Libellé d'une puce de page dans le sélecteur de départ
  ///
  /// In fr, this message translates to:
  /// **'Page {page}'**
  String memorizationAyahPickerPageLabel(int page);

  /// Sous-titre de l'étape 2 (choix du verset dans la page choisie)
  ///
  /// In fr, this message translates to:
  /// **'Page {page} : choisis le verset où tu veux commencer à jouer'**
  String memorizationAyahPickerAyahSubtitle(int page);

  /// Bouton pour revenir de la sélection de verset à la sélection de page
  ///
  /// In fr, this message translates to:
  /// **'Changer de page'**
  String get memorizationAyahPickerBackToPages;

  /// Sous-titre de l'écran boussole Qibla
  ///
  /// In fr, this message translates to:
  /// **'Direction de la Mecque'**
  String get qiblaSubtitle;

  /// Message quand le service de localisation est désactivé
  ///
  /// In fr, this message translates to:
  /// **'Active la localisation pour trouver la Qibla depuis ton emplacement actuel.'**
  String get qiblaEnableLocationMessage;

  /// Bouton : ouvrir les réglages de localisation du système
  ///
  /// In fr, this message translates to:
  /// **'Activer la localisation'**
  String get qiblaEnableLocationAction;

  /// Message quand la permission de localisation est refusée
  ///
  /// In fr, this message translates to:
  /// **'La localisation est refusée pour Coran Karim. Autorise-la dans les réglages du téléphone pour voir la Qibla.'**
  String get qiblaPermissionDeniedMessage;

  /// Bouton : ouvrir les réglages de l'app pour accorder la permission
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir les réglages'**
  String get qiblaOpenSettingsAction;

  /// Message d'erreur de géolocalisation
  ///
  /// In fr, this message translates to:
  /// **'Impossible de déterminer ta position : {error}'**
  String qiblaPositionError(String error);

  /// Message quand l'appareil n'a pas de capteur boussole
  ///
  /// In fr, this message translates to:
  /// **'Cet appareil ne possède pas de boussole. La distance jusqu\'à la Mecque reste disponible ci-dessous.'**
  String get qiblaNoCompassMessage;

  /// Légende sous la distance en kilomètres jusqu'à la Mecque
  ///
  /// In fr, this message translates to:
  /// **'KM JUSQU\'À LA MECQUE'**
  String get qiblaKmToMecca;

  /// Indication : le téléphone est aligné avec la Qibla
  ///
  /// In fr, this message translates to:
  /// **'Tu fais face à la Qibla ✓'**
  String get qiblaFacingQibla;

  /// Indication : le téléphone n'est pas encore aligné avec la Qibla
  ///
  /// In fr, this message translates to:
  /// **'Tourne ton téléphone jusqu\'à ce que l\'aiguille pointe en haut'**
  String get qiblaTurnPhoneHint;

  /// Niveau de sensibilité bas (Suivre une prière)
  ///
  /// In fr, this message translates to:
  /// **'Tolérant'**
  String get prayerFollowSensitivityTolerant;

  /// Niveau de sensibilité haut (Suivre une prière)
  ///
  /// In fr, this message translates to:
  /// **'Strict'**
  String get prayerFollowSensitivityStrict;

  /// Niveau de sensibilité moyen (Suivre une prière)
  ///
  /// In fr, this message translates to:
  /// **'Équilibré (par défaut)'**
  String get prayerFollowSensitivityBalanced;

  /// Titre du réglage de sensibilité dans la feuille Suivre une prière
  ///
  /// In fr, this message translates to:
  /// **'Sensibilité (suivi de prière)'**
  String get prayerFollowSensitivityTitle;

  /// Explique le réglage de sensibilité de Suivre une prière
  ///
  /// In fr, this message translates to:
  /// **'Réglage indépendant de celui de la récitation classique -- plus tolérant accepte des prononciations imprécises en vert, plus strict exige davantage de précision.'**
  String get prayerFollowSensitivityDescription;

  /// Titre du réglage souffleur automatique
  ///
  /// In fr, this message translates to:
  /// **'Souffleur automatique'**
  String get prayerFollowSouffleurTitle;

  /// Explique le réglage souffleur automatique
  ///
  /// In fr, this message translates to:
  /// **'Joue le mot attendu après {seconds}s de silence -- jamais de blocage dans ce mode.'**
  String prayerFollowSouffleurSubtitle(int seconds);

  /// Titre de l'écran Suivre une prière
  ///
  /// In fr, this message translates to:
  /// **'Suivre une prière'**
  String get prayerFollowTitle;

  /// Tooltip de l'icône réglages de l'écran Suivre une prière
  ///
  /// In fr, this message translates to:
  /// **'Réglages'**
  String get prayerFollowSettingsTooltip;

  /// Message avant que la récitation d'Al-Fatiha ne commence
  ///
  /// In fr, this message translates to:
  /// **'En attente du début d\'Al-Fatiha…'**
  String get prayerFollowWaitingFatiha;

  /// Message pendant l'identification automatique de la sourate suivante
  ///
  /// In fr, this message translates to:
  /// **'Al-Fatiha terminée -- identification de la sourate suivante…'**
  String get prayerFollowIdentifying;

  /// Message pendant l'écoute active
  ///
  /// In fr, this message translates to:
  /// **'En écoute…'**
  String get prayerFollowListening;

  /// Message avant de démarrer le suivi de prière
  ///
  /// In fr, this message translates to:
  /// **'Appuyez sur le micro pour commencer à suivre la prière.'**
  String get prayerFollowTapToStart;

  /// Badge de phase : en attente pendant une posture non récitée
  ///
  /// In fr, this message translates to:
  /// **'En attente (rukū\'/sujūd)'**
  String get prayerPhaseStandby;

  /// Badge de phase : récitation d'Al-Fatiha en cours
  ///
  /// In fr, this message translates to:
  /// **'Al-Fatiha'**
  String get prayerPhaseFatiha;

  /// Badge de phase : identification de la sourate en cours
  ///
  /// In fr, this message translates to:
  /// **'Identification…'**
  String get prayerPhaseDetecting;

  /// Badge de phase : sourate identifiée en cours de suivi
  ///
  /// In fr, this message translates to:
  /// **'Sourate suivie'**
  String get prayerPhaseTarget;

  /// Badge de phase : écoute active, aucune phase spécifique
  ///
  /// In fr, this message translates to:
  /// **'En écoute'**
  String get prayerPhaseListening;

  /// Badge de phase : suivi de prière arrêté
  ///
  /// In fr, this message translates to:
  /// **'Arrêté'**
  String get prayerPhaseStopped;

  /// Tooltip : ouvrir la feuille d'essentiels du rite
  ///
  /// In fr, this message translates to:
  /// **'À savoir avant de commencer'**
  String get riteBeforeStartTooltip;

  /// Tooltip : réinitialiser la progression du rite
  ///
  /// In fr, this message translates to:
  /// **'Recommencer le rite'**
  String get riteRestartTooltip;

  /// Titre de la liste d'actions d'une étape de rite
  ///
  /// In fr, this message translates to:
  /// **'CE QUE L\'ON FAIT'**
  String get riteWhatWeDoLabel;

  /// Titre de la liste d'invocations d'une étape de rite
  ///
  /// In fr, this message translates to:
  /// **'CE QUE L\'ON DIT ICI'**
  String get riteWhatWeSayLabel;

  /// Repère "étape N sur M" dans l'en-tête d'une étape de rite
  ///
  /// In fr, this message translates to:
  /// **'ÉTAPE {index} SUR {total}'**
  String riteStepOfTotal(int index, int total);

  /// Titre de la feuille des essentiels du rite
  ///
  /// In fr, this message translates to:
  /// **'Avant de commencer'**
  String get riteBeforeStartTitle;

  /// Avertissement en bas de la feuille des essentiels du rite
  ///
  /// In fr, this message translates to:
  /// **'Ce guide est un aide-mémoire, pas une fatwa. Les écoles juridiques divergent sur plusieurs détails secondaires : en cas de doute sur place, demandez à un guide qualifié ou à l\'encadrement de votre groupe.'**
  String get riteDisclaimer;

  /// Titre de la boîte de dialogue de confirmation de réinitialisation
  ///
  /// In fr, this message translates to:
  /// **'Recommencer ?'**
  String get riteResetConfirmTitle;

  /// Corps de la boîte de dialogue de confirmation de réinitialisation
  ///
  /// In fr, this message translates to:
  /// **'Les étapes validées et tous les compteurs seront remis à zéro.'**
  String get riteResetConfirmBody;

  /// Bouton de confirmation dans la boîte de dialogue de réinitialisation
  ///
  /// In fr, this message translates to:
  /// **'Recommencer'**
  String get riteResetConfirmAction;

  /// Tooltip du bouton étape précédente
  ///
  /// In fr, this message translates to:
  /// **'Étape précédente'**
  String get ritePreviousStepTooltip;

  /// Tooltip du bouton étape suivante
  ///
  /// In fr, this message translates to:
  /// **'Étape suivante'**
  String get riteNextStepTooltip;

  /// Bouton : l'étape courante est marquée comme faite
  ///
  /// In fr, this message translates to:
  /// **'Étape faite'**
  String get riteStepDone;

  /// Bouton : marquer l'étape courante comme faite
  ///
  /// In fr, this message translates to:
  /// **'Marquer comme faite'**
  String get riteMarkAsDone;

  /// Sur-titre de l'écran de récitation continue
  ///
  /// In fr, this message translates to:
  /// **'Mode mémorisation'**
  String get recitationModeLabel;

  /// Titre quand un seul verset est récité
  ///
  /// In fr, this message translates to:
  /// **'Verset {key}'**
  String recitationVerseTitle(String key);

  /// Titre quand plusieurs versets sont récités d'affilée
  ///
  /// In fr, this message translates to:
  /// **'{from} → {to} ({count, plural, =1{1 verset} other{{count} versets}})'**
  String recitationRangeTitle(String from, String to, int count);

  /// Badge : segments audio en attente d'analyse
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 segment en cours d\'analyse…} other{{count} segments en attente d\'analyse…}}'**
  String recitationSegmentAnalyzing(int count);

  /// Titre de l'encart transcript brut
  ///
  /// In fr, this message translates to:
  /// **'Transcript modèle'**
  String get recitationTranscriptLabel;

  /// Statistique : nombre de mots corrects
  ///
  /// In fr, this message translates to:
  /// **'Corrects'**
  String get recitationStatCorrect;

  /// Statistique : nombre d'erreurs
  ///
  /// In fr, this message translates to:
  /// **'Erreurs'**
  String get recitationStatErrors;

  /// Statistique : pourcentage de précision
  ///
  /// In fr, this message translates to:
  /// **'Précision'**
  String get recitationStatAccuracy;

  /// Statut pendant la récitation continue
  ///
  /// In fr, this message translates to:
  /// **'Récite en continu… pause naturelle = verset suivant'**
  String get recitationListeningContinuous;

  /// Statut pendant la finalisation de l'analyse
  ///
  /// In fr, this message translates to:
  /// **'Finalisation de l\'analyse…'**
  String get recitationFinalizing;

  /// Statut une fois la récitation terminée
  ///
  /// In fr, this message translates to:
  /// **'Terminé — appuie pour recommencer'**
  String get recitationFinishedRestart;

  /// Statut avant de démarrer la récitation
  ///
  /// In fr, this message translates to:
  /// **'Appuie et récite (plusieurs versets d\'affilée)'**
  String get recitationTapToStart;

  /// Bandeau de résultat, bonne précision
  ///
  /// In fr, this message translates to:
  /// **'Ma cha Allah ! {pct}% de précision'**
  String recitationMashallahAccuracy(String pct);

  /// Bandeau de résultat, précision à améliorer
  ///
  /// In fr, this message translates to:
  /// **'Continue — {pct}% de précision'**
  String recitationContinueAccuracy(String pct);

  /// Titre de l'écran de choix du récitateur
  ///
  /// In fr, this message translates to:
  /// **'Choisir un réciteur'**
  String get reciterSelectTitle;

  /// Note en haut de l'écran de choix du récitateur
  ///
  /// In fr, this message translates to:
  /// **'Réciteurs intégrés — disponibles en streaming. Téléchargement hors-ligne disponible prochainement.'**
  String get reciterSelectStreamingNote;

  /// Titre du bandeau "à venir" de téléchargement hors-ligne
  ///
  /// In fr, this message translates to:
  /// **'Téléchargement hors-ligne'**
  String get reciterSelectOfflineTitle;

  /// Sous-titre du bandeau "à venir" de téléchargement hors-ligne
  ///
  /// In fr, this message translates to:
  /// **'Disponible dans une prochaine mise à jour.'**
  String get reciterSelectOfflineSubtitle;

  /// Titre de l'écran de calibration voix
  ///
  /// In fr, this message translates to:
  /// **'Calibration voix'**
  String get voiceCalibTitle;

  /// Titre affiché une fois la calibration voix terminée
  ///
  /// In fr, this message translates to:
  /// **'Calibration terminée !'**
  String get voiceCalibDoneTitle;

  /// Corps affiché une fois la calibration voix terminée
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 clip enregistré.} other{{count} clips enregistrés.}} Ils rejoignent tes clips vérifiés — exporte-les depuis Réglages pour lancer la personnalisation.'**
  String voiceCalibDoneBody(int count);

  /// Bouton : sauvegarder les clips de calibration
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer'**
  String get voiceCalibSave;

  /// Progression dans la liste de mots de calibration
  ///
  /// In fr, this message translates to:
  /// **'Mot {index}/{total} — {reference}'**
  String voiceCalibWordProgress(int index, int total, String reference);

  /// Instruction pour la prononciation volontairement fautive
  ///
  /// In fr, this message translates to:
  /// **'Dis ce mot en remplaçant EXPRÈS le \"{target}\" par un \"{confused}\" — une faute volontaire, pas une vraie récitation.'**
  String voiceCalibWrongInstruction(String target, String confused);

  /// Instruction pour la prononciation correcte
  ///
  /// In fr, this message translates to:
  /// **'Dis ce mot correctement, comme d\'habitude.'**
  String get voiceCalibCorrectInstruction;

  /// Statut pendant l'enregistrement d'un mot de calibration
  ///
  /// In fr, this message translates to:
  /// **'Enregistrement… touche pour arrêter'**
  String get voiceCalibRecording;

  /// Invite à démarrer l'enregistrement d'un mot de calibration
  ///
  /// In fr, this message translates to:
  /// **'Touche pour enregistrer'**
  String get voiceCalibTapToRecord;

  /// Snackbar de confirmation après sauvegarde des clips de calibration
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 clip de calibration enregistré} other{{count} clips de calibration enregistrés}} — exporte-les depuis Réglages pour personnaliser le modèle.'**
  String voiceCalibSavedSnackbar(int count);

  /// Badge de fiabilité d'une règle tajwid : fiable, sans pourcentage mesuré
  ///
  /// In fr, this message translates to:
  /// **'fiable'**
  String get ruleReliableLabel;

  /// Badge de fiabilité d'une règle tajwid : fiable, avec pourcentage de rappel mesuré
  ///
  /// In fr, this message translates to:
  /// **'fiable · {pct}%'**
  String ruleReliableLabelWithPct(int pct);

  /// Badge de fiabilité d'une règle tajwid : peu fiable, sans pourcentage mesuré
  ///
  /// In fr, this message translates to:
  /// **'peu fiable'**
  String get ruleUnreliableLabel;

  /// Badge de fiabilité d'une règle tajwid : peu fiable, avec pourcentage de rappel mesuré
  ///
  /// In fr, this message translates to:
  /// **'peu fiable · {pct}%'**
  String ruleUnreliableLabelWithPct(int pct);

  /// Badge de fiabilité d'une règle tajwid : données insuffisantes
  ///
  /// In fr, this message translates to:
  /// **'non mesurée'**
  String get ruleNotMeasuredLabel;

  /// Titre de l'écran de sélection des règles tajwid
  ///
  /// In fr, this message translates to:
  /// **'Vérification de la récitation'**
  String get tajwidRulesTitle;

  /// Erreur de chargement des données de fiabilité des règles
  ///
  /// In fr, this message translates to:
  /// **'Erreur : {error}'**
  String tajwidRulesLoadError(String error);

  /// Réglage : exiger les voyelles courtes
  ///
  /// In fr, this message translates to:
  /// **'Harakat exigées'**
  String get tajwidRulesHarakatTitle;

  /// Explique le réglage harakat exigées
  ///
  /// In fr, this message translates to:
  /// **'Désactivé : les voyelles courtes ne comptent pas comme erreur'**
  String get tajwidRulesHarakatSubtitle;

  /// Réglage : tolérer les lettres confusables
  ///
  /// In fr, this message translates to:
  /// **'Tolérer les lettres proches'**
  String get tajwidRulesConfusablesTitle;

  /// Explique le réglage tolérance des lettres confusables
  ///
  /// In fr, this message translates to:
  /// **'ص/س, ط/ت, ض/د, ذ/ز, ح/ه, ق/ك, ع/ء comptées équivalentes (mode enfant)'**
  String get tajwidRulesConfusablesSubtitle;

  /// Titre de la liste des règles tajwid activables
  ///
  /// In fr, this message translates to:
  /// **'RÈGLES DE TAJWID'**
  String get tajwidRulesSectionTitle;

  /// Explique la liste des règles tajwid activables
  ///
  /// In fr, this message translates to:
  /// **'Choisissez les règles que l\'app doit vérifier pendant votre récitation.'**
  String get tajwidRulesSectionSubtitle;

  /// Note sous une règle dont la détection est encore imprécise
  ///
  /// In fr, this message translates to:
  /// **'Détection encore imprécise : cette règle peut signaler un doute, mais ne validera jamais un mot en vert à elle seule.'**
  String get tajwidRulesImpreciseNote;

  /// Preset de vérification : tajwid strict
  ///
  /// In fr, this message translates to:
  /// **'Tajwid'**
  String get tajwidPresetTajwid;

  /// Preset de vérification : adulte tolérant
  ///
  /// In fr, this message translates to:
  /// **'Adulte'**
  String get tajwidPresetAdult;

  /// Preset de vérification : enfant tolérant lettres
  ///
  /// In fr, this message translates to:
  /// **'Enfant'**
  String get tajwidPresetChild;

  /// Erreur de chargement des versets d'une sourate choisie
  ///
  /// In fr, this message translates to:
  /// **'Chargement impossible : {error}'**
  String surahPickerLoadVersesError(String error);

  /// Erreur de chargement de la liste des sourates
  ///
  /// In fr, this message translates to:
  /// **'Impossible de charger les sourates : {error}'**
  String surahPickerLoadListError(String error);

  /// Nombre de versets affiché sous le nom d'une sourate dans le sélecteur
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 verset} other{{count} versets}}'**
  String surahPickerVerseCount(int count);

  /// Snackbar : l'audio de correction n'a pas pu être joué
  ///
  /// In fr, this message translates to:
  /// **'Audio indisponible pour ce mot'**
  String get karaokeAudioUnavailable;

  /// Snackbar après une correction automatique
  ///
  /// In fr, this message translates to:
  /// **'Répète le mot indiqué ↓'**
  String get karaokeRepeatIndicated;

  /// Titre du dialogue proposant une session de référence
  ///
  /// In fr, this message translates to:
  /// **'Première récitation de ce passage'**
  String get karaokeFirstRecitationTitle;

  /// Corps du dialogue proposant une session de référence
  ///
  /// In fr, this message translates to:
  /// **'Veux-tu que cette récitation serve de référence pour ton rythme naturel (pauses mesurées, sans correction automatique), ou réciter normalement dès maintenant (avec correction automatique) ?'**
  String get karaokeFirstRecitationBody;

  /// Bouton : réciter sans créer de référence
  ///
  /// In fr, this message translates to:
  /// **'Réciter normalement'**
  String get karaokeReciteNormally;

  /// Bouton : démarrer une session de référence
  ///
  /// In fr, this message translates to:
  /// **'Faire une référence'**
  String get karaokeMakeReference;

  /// Message quand une session de référence est rejetée pour score insuffisant
  ///
  /// In fr, this message translates to:
  /// **'Référence non enregistrée : seulement {pct}% des mots ont été bien reconnus ({correct}/{total} corrects{extra}). Une référence doit refléter une récitation fiable — rapproche-toi du micro, réduis le bruit ambiant, et réessaie à ton rythme naturel.'**
  String karaokeReferenceNotSaved(
    int pct,
    int correct,
    int total,
    String extra,
  );

  /// Fragment ajouté au détail du score si des mots sont imprécis
  ///
  /// In fr, this message translates to:
  /// **', {count} imprécis'**
  String karaokeUnclearSuffix(int count);

  /// Fragment ajouté au détail du score si des mots ne sont pas reconnus
  ///
  /// In fr, this message translates to:
  /// **', {count} non reconnus'**
  String karaokeMissedSuffix(int count);

  /// Message quand une session de référence est validée
  ///
  /// In fr, this message translates to:
  /// **'Ta manière de réciter ce passage est mémorisée ✓ ({pct}% de reconnaissance, {pauseCount} pauses apprises)'**
  String karaokeReferenceSaved(int pct, int pauseCount);

  /// Titre de la feuille des paramètres de vérification
  ///
  /// In fr, this message translates to:
  /// **'Paramètres de vérification'**
  String get karaokeVerificationSettingsTitle;

  /// Réglage : ouvrir l'écran des règles/presets tajwid
  ///
  /// In fr, this message translates to:
  /// **'Mode de vérification'**
  String get karaokeVerificationModeTitle;

  /// Sous-titre du réglage mode de vérification
  ///
  /// In fr, this message translates to:
  /// **'Presets tajwid / adulte / enfant, 17 règles'**
  String get karaokeVerificationModeSubtitle;

  /// Titre du réglage de sensibilité dans la feuille de vérification karaoké
  ///
  /// In fr, this message translates to:
  /// **'Sensibilité de la correction'**
  String get karaokeSensitivityTitle;

  /// Explique le réglage de sensibilité
  ///
  /// In fr, this message translates to:
  /// **'Plus tolérant : accepte des harakat/prononciations imprécises en vert. Plus strict : exige une prononciation plus proche du modèle.'**
  String get karaokeSensitivityDescription;

  /// Réglage : moteur de jugement gop vs texte
  ///
  /// In fr, this message translates to:
  /// **'Moteur : alignement forcé (gop)'**
  String get karaokeEngineTitle;

  /// Sous-titre quand le moteur gop est actif
  ///
  /// In fr, this message translates to:
  /// **'Actif — sensible aux harakat, parfois trop sévère sur certains mots'**
  String get karaokeEngineActiveSubtitle;

  /// Sous-titre quand le moteur gop est désactivé
  ///
  /// In fr, this message translates to:
  /// **'Désactivé — comparaison texte (historique), moins fine sur les harakat'**
  String get karaokeEngineInactiveSubtitle;

  /// Réglage : correction automatique activée/désactivée
  ///
  /// In fr, this message translates to:
  /// **'Correction automatique'**
  String get karaokeAutoCorrectionTitle;

  /// Explique le réglage de correction automatique
  ///
  /// In fr, this message translates to:
  /// **'Mot rouge → pause, le récitateur corrige, reprise auto'**
  String get karaokeAutoCorrectionSubtitle;

  /// Réglage : rigueur de la correction automatique
  ///
  /// In fr, this message translates to:
  /// **'Rigueur de la correction'**
  String get karaokeStrictnessTitle;

  /// Sous-titre quand la rigueur est stricte
  ///
  /// In fr, this message translates to:
  /// **'Strict — rouge ET orange (imprécis) sont repris'**
  String get karaokeStrictnessStrictSubtitle;

  /// Sous-titre quand la rigueur est tolérante
  ///
  /// In fr, this message translates to:
  /// **'Tolérant — seul le rouge (mot faux) est repris'**
  String get karaokeStrictnessTolerantSubtitle;

  /// Réglage : suivre sans bloquer sur une reprise ratée
  ///
  /// In fr, this message translates to:
  /// **'Suivre sans bloquer'**
  String get karaokeFollowFreeTitle;

  /// Sous-titre quand suivre sans bloquer est actif
  ///
  /// In fr, this message translates to:
  /// **'Avance librement même sans reprise exacte'**
  String get karaokeFollowFreeOnSubtitle;

  /// Sous-titre quand suivre sans bloquer est désactivé
  ///
  /// In fr, this message translates to:
  /// **'Chaque échec force à reprendre le mot'**
  String get karaokeFollowFreeOffSubtitle;

  /// Snackbar après avoir demandé à refaire la référence
  ///
  /// In fr, this message translates to:
  /// **'La prochaine récitation redéfinira ta référence pour ce passage.'**
  String get karaokeNewReferenceSnackbar;

  /// Tooltip : souffleur, jouer le mot attendu
  ///
  /// In fr, this message translates to:
  /// **'Entendre le mot attendu'**
  String get karaokeHearExpectedWordTooltip;

  /// Tooltip : reprendre la capture après une pause manuelle
  ///
  /// In fr, this message translates to:
  /// **'Reprendre'**
  String get karaokeResumeTooltip;

  /// Tooltip : mettre la capture en pause manuellement
  ///
  /// In fr, this message translates to:
  /// **'Mettre en pause'**
  String get karaokePauseTooltip;

  /// Tooltip : redemander une session de référence
  ///
  /// In fr, this message translates to:
  /// **'Refaire ma récitation de référence'**
  String get karaokeRedoReferenceTooltip;

  /// Titre du bandeau annonçant une session de référence à venir
  ///
  /// In fr, this message translates to:
  /// **'Récitation de référence'**
  String get karaokeReferenceRecordingTitle;

  /// Corps du bandeau annonçant une session de référence à venir
  ///
  /// In fr, this message translates to:
  /// **'Première récitation de ce passage : récite à ton rythme naturel — ta manière de réciter (pauses, tempo) sera mémorisée et respectée pour toutes tes prochaines récitations.'**
  String get karaokeReferenceRecordingBody;

  /// Titre du bandeau pendant l'enregistrement de la référence
  ///
  /// In fr, this message translates to:
  /// **'Référence en cours d\'enregistrement'**
  String get karaokeReferenceInProgressTitle;

  /// Corps du bandeau pendant l'enregistrement de la référence
  ///
  /// In fr, this message translates to:
  /// **'Récite naturellement, à ton rythme.'**
  String get karaokeReferenceInProgressBody;

  /// Étiquette au-dessus de l'extrait de transcript entendu
  ///
  /// In fr, this message translates to:
  /// **'entendu'**
  String get karaokeHeardLabel;

  /// Titre de la feuille affichant le transcript complet
  ///
  /// In fr, this message translates to:
  /// **'TRANSCRIPT COMPLET'**
  String get karaokeTranscriptFullTitle;

  /// Message quand le transcript est encore vide
  ///
  /// In fr, this message translates to:
  /// **'Rien entendu pour l\'instant.'**
  String get karaokeNothingHeardYet;

  /// Indication en bas d'écran pendant la finalisation de l'analyse
  ///
  /// In fr, this message translates to:
  /// **'Finalisation…'**
  String get karaokeFinalizing;

  /// Indication en bas d'écran quand la capture est en pause manuelle
  ///
  /// In fr, this message translates to:
  /// **'En pause — touche ⏸ pour reprendre'**
  String get karaokePausedHint;

  /// Indication en bas d'écran pendant l'écoute active
  ///
  /// In fr, this message translates to:
  /// **'À l\'écoute — touche le cercle pour t\'arrêter'**
  String get karaokeListeningHint;

  /// Indication en bas d'écran une fois la récitation terminée
  ///
  /// In fr, this message translates to:
  /// **'Touche l\'écran pour recommencer'**
  String get karaokeFinishedHint;

  /// Indication en bas d'écran avant de démarrer une session de référence
  ///
  /// In fr, this message translates to:
  /// **'Touche l\'écran pour enregistrer ta récitation de référence'**
  String get karaokeReferenceStartHint;

  /// Indication en bas d'écran avant de démarrer une récitation normale
  ///
  /// In fr, this message translates to:
  /// **'Touche l\'écran pour commencer'**
  String get karaokeTapToStartHint;

  /// Message affiché pendant le préchargement du modèle causal
  ///
  /// In fr, this message translates to:
  /// **'Chargement du modèle de récitation…'**
  String get karaokeLoadingModel;

  /// Instruction affichée pendant le compte à rebours
  ///
  /// In fr, this message translates to:
  /// **'Prépare-toi'**
  String get karaokeGetReady;

  /// Message entre le compte à rebours et l'ouverture effective du micro
  ///
  /// In fr, this message translates to:
  /// **'Préparation du micro…'**
  String get karaokePreparingMicrophone;

  /// Signal indiquant que l'utilisateur peut commencer à réciter
  ///
  /// In fr, this message translates to:
  /// **'GO !'**
  String get karaokeGo;

  /// Erreur affichée quand aucun modèle continu ne peut être chargé
  ///
  /// In fr, this message translates to:
  /// **'Le modèle de récitation est indisponible.'**
  String get karaokeModelUnavailable;

  /// Erreur affichée si l'ouverture du micro ou de la session échoue
  ///
  /// In fr, this message translates to:
  /// **'Impossible de démarrer l’écoute.'**
  String get karaokeStartFailed;

  /// Métadonnées sous le nom arabe dans le bandeau de transition entre sourates
  ///
  /// In fr, this message translates to:
  /// **'{number} · {name} · {count, plural, =1{1 verset} other{{count} versets}}'**
  String karaokeSurahTransitionMeta(int number, String name, int count);

  /// Métadonnées sous le titre du bandeau ornemental de sourate (lieu de révélation + nombre de versets)
  ///
  /// In fr, this message translates to:
  /// **'{place} · {count, plural, =1{1 verset} other{{count} versets}}'**
  String surahOrnamentMeta(String place, int count);

  /// Bouton répétition de la barre de lecture : désactivée
  ///
  /// In fr, this message translates to:
  /// **'Répéter'**
  String get miniPlayerRepeatOff;

  /// Bouton répétition de la barre de lecture : verset répété N fois
  ///
  /// In fr, this message translates to:
  /// **'×{count} verset'**
  String miniPlayerRepeatVerse(int count);

  /// Bouton répétition de la barre de lecture : sourate en boucle infinie
  ///
  /// In fr, this message translates to:
  /// **'Sourate ∞'**
  String get miniPlayerRepeatSurah;

  /// Tooltip de l'icône carte mentale dans l'en-tête du Mushaf
  ///
  /// In fr, this message translates to:
  /// **'Carte mentale'**
  String get mushafMindMapTooltip;

  /// Bandeau prière : compte à rebours avant la prochaine prière (donnée provisoire, pas encore branchée sur l'heure réelle)
  ///
  /// In fr, this message translates to:
  /// **'Dhuhr dans 2h 14m'**
  String get mushafPrayerNextIn;

  /// Bandeau prière : heure de la prochaine prière (donnée provisoire, pas encore branchée sur l'heure réelle)
  ///
  /// In fr, this message translates to:
  /// **'Dhuhr 13:30'**
  String get mushafPrayerTimeLabel;

  /// Pastille de navigation : numéro du juz courant
  ///
  /// In fr, this message translates to:
  /// **'JUZ {n}'**
  String mushafJuzChip(int n);

  /// Section header for diagnostic settings
  ///
  /// In fr, this message translates to:
  /// **'Diagnostic'**
  String get settingsSectionDiagnostic;

  /// Toggle title: diagnostic log file + WAV capture
  ///
  /// In fr, this message translates to:
  /// **'Journal et audio de diagnostic'**
  String get settingsDiagnosticTitle;

  /// Subtitle when diagnostics are enabled
  ///
  /// In fr, this message translates to:
  /// **'Actif — écrit le journal et garde les extraits audio'**
  String get settingsDiagnosticSubtitleOn;

  /// Subtitle when diagnostics are disabled
  ///
  /// In fr, this message translates to:
  /// **'Désactivé — aucune écriture pendant la récitation'**
  String get settingsDiagnosticSubtitleOff;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
