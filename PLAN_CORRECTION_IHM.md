# Plan de correction IHM (état au 2026-08-01)

Origine : constat utilisateur « tout est éparpillé ». Contrairement à
`REFONTE_IHM.md` (spec écrite le 2026-07-19/20, largement exécutée depuis),
ce document part d'un **inventaire du code réel** (`app/lib/screens/`,
`widgets/`, `providers/`, `main.dart`), pas d'une relecture de la spec. Chaque
point cite fichier + ligne exacts. Aucun correctif n'est appliqué : ce
document est la base de discussion, à trancher point par point avant tout
code (règle CLAUDE.md « proposer et faire valider avant de développer »).

Méthode : agent Explore lancé sur les trois dossiers + `main.dart`, grep
systématique des références pour distinguer actif/orphelin/mort. Détail
complet dans l'historique de conversation ; ce fichier n'en garde que les
constats et les décisions à prendre.

---

## 0. Ce qui N'EST PAS un problème (pour ne pas rouvrir inutilement)

- **FAB « Calibrage » et « Recette » toujours visibles** (`main.dart:139-166`)
  : intentionnel, demande utilisateur du 2026-07-28 (« simplifie l'accès pour
  l'IHM ») — deux téléphones à relancer à chaque itération de mesure, la
  navigation longue ferait varier le protocole. Documenté en commentaire.
  Reste listé en §3 (risque de confusion utilisateur final) mais ce n'est pas
  un oubli.
- **`correctionSensitivityProvider` vs `prayerSensitivityProvider`** (deux
  curseurs de sensibilité séparés) : doublon de concept assumé, documenté en
  commentaire (2026-07-19). Pas un bug.
- **Aucun provider mort** : les 12 fichiers de `providers/` ont tous au moins
  un point d'usage réel, vérifié un par un.
- **Aucun écran mort** : `memorization_screen.dart` et `coach_ai_screen.dart`
  ont bien été supprimés comme annoncé — rien à faire ici.
- **Parité des 3 langues ARB** : `app_ar.arb`/`app_fr.arb`/`app_en.arb` ont
  exactement 437 clés chacun, aucune manquante. Le mécanisme de traduction
  fonctionne ; le problème (§2) est localisé à des écrans précis qui ne
  l'utilisent pas partout, pas au système.

---

## 1. Bloquant / trompeur pour l'utilisateur

### 1.1 Réglage « Tajweed colors » factice
`app/lib/screens/settings_screen.dart:128-131` — switch affiché `value: true`,
`onChanged: (_) {}` (commentaire `// TODO: persist`). L'utilisateur voit un
réglage actif qu'il peut « toucher » sans aucun effet, silencieusement.
→ **Décision à prendre** : implémenter la persistance maintenant (comportement
déjà défini : coloration tajwid on/off) ou retirer le toggle jusqu'à
implémentation. Ne pas laisser un contrôle qui ne fait rien — c'est le genre
de faux signal que le projet a déjà identifié comme pire que l'absence de
fonctionnalité (cf. principe « pas de vert franc sur un problème réel »,
transposé ici à « pas de contrôle qui prétend agir »).

### 1.2 Deux écrans de récitation derrière le même bouton, un geste non documenté
`mushaf_screen.dart:584` (appui long → `KaraokeRecitationScreen`, l'écran
normal) et `mushaf_screen.dart:605` (double-tap → `RecitationScreen`, écran de
**debug interne** avec transcript brut, cf. commentaire lignes 600-603 : «
utilisé en interne pour juger la qualité du modèle »). Un utilisateur normal
qui double-tape par erreur atterrit dans un écran de debug non prévu pour lui.
→ **Décision à prendre** : retirer l'accès par geste (garder l'écran debug
accessible autrement, ex. depuis Recette) ou le documenter/protéger
explicitement (confirmation, ou gate sur un mode dev).

---

## 2. Incohérences de langue (l'IHM mélange les langues dans un même écran)

Constat : le mécanisme ARB est complet (437 clés × 3 langues), mais deux
écrans clés ne l'utilisent pas partout.

- `settings_screen.dart:107-108` — « Horaires de prière », « Adhan programmé,
  rappel avant Sobh » : littéral français, alors que le reste de l'écran passe
  par `t.xxx`.
- `settings_screen.dart:303-305` (`_NoiseSuppressTile`) — « Suppression de
  bruit du micro », « Activée —… » / « Éteinte (recommandé) — … » : idem.
- `tajwid_rules_screen.dart` — écran central du mode tajwid/adulte/enfant :
  le **corps principal reste figé en français** alors que les 17 fiches de
  règles individuelles sont bien traduites (`kTajwidRuleInfo[...].name(t)`,
  ligne 338). Précisément : titre d'écran (`'Vérification de la récitation'`,
  ligne 32), message d'erreur (ligne 37), les deux switches « Harakat exigées »
  / « Tolérer les lettres proches » (lignes 44-54 — ce dernier **mélange
  français et arabe dans la même chaîne**, ص/س ط/ت...), l'en-tête de section
  « RÈGLES DE TAJWID » (ligne 62).
→ **Pas une question ouverte, un travail mécanique** : ajouter les clés ARB
manquantes (probablement ~10) dans les 3 fichiers `.arb`, remplacer les
littéraux. Périmètre limité aux 2 fichiers ci-dessus (le reste de l'app a été
vérifié propre sur les écrans clés).

---

## 3. Architecture / dette de refonte

### 3.1 Le composant partagé planifié n'a jamais été créé
`REFONTE_IHM.md` (ligne 143) décidait un widget générique unique
`widgets/context_settings_sheet.dart` pour toutes les sheets de réglages
contextuels. Il n'existe pas. À la place :
- `karaoke_recitation_screen.dart::_openVerificationSheet` (lignes 1362-1543,
  **181 lignes** de sheet codées en dur dans un fichier qui en fait déjà 2596)
- `prayer_follow_screen.dart::_openSettingsSheet` (même pattern, inline)

Conséquence concrète du non-respect du plan : toute évolution de la sheet de
vérification (ajout d'un réglage, correction d'un bug d'affichage) se fait
dans un fichier de 2596 lignes au lieu d'un composant isolé et testable.
C'est probablement la source principale du sentiment d'éparpillement — pas le
nombre d'écrans (chacun a un rôle disjoint, cf. §3.3), mais le fait que deux
gros écrans portent chacun leur propre système de réglages non factorisé.
→ **Décision à prendre** : extraire maintenant (`context_settings_sheet.dart`,
tel que spécifié en 2026-07-19) ou accepter le statu quo et corriger la spec
pour refléter la réalité (ne plus prétendre que ce composant existe). Vu la
taille des deux fichiers concernés, l'extraction est un chantier à part
entière — à chiffrer avant de trancher.

### 3.2 Deux notions de « langue » non réconciliées
`app_settings_provider.dart:301` (`appLocaleProvider`, pilote toute l'IHM +
RTL) et `app_settings_provider.dart:159` (`explanationLanguageProvider`,
pilote uniquement la langue des explications Coach). Le code documente déjà
lui-même l'écart en commentaire (lignes 293-295 : « les deux coexistent pour
l'instant ; la réconciliation… reste à faire »). Un utilisateur peut avoir une
IHM en français et des explications forcées en arabe sans lien entre les deux.
→ **Question ouverte pour l'utilisateur** (§7bis de `REFONTE_IHM.md` avait déjà
tranché la logique par langue pour l'IHM/texte coranique/traductions, mais pas
ce cas précis) : `explanationLanguageProvider` doit-il **suivre**
`appLocaleProvider` par défaut (avec override manuel possible), ou rester
indépendant par design (ex. un utilisateur en IHM arabe qui veut quand même
des explications en français) ?

### 3.3 Nommage prêtant à confusion
`calibrage_screen.dart` (outil dev : seuils de découpage audio) et
`voice_calibration_screen.dart` (utilisateur final : calibration voix
personnelle, mots confusables) — deux fonctions sans rapport, noms presque
identiques en français (« calibrage » / « calibration »). Aucun impact
fonctionnel, mais gêne la lecture du code et contribue à l'impression de
désordre. → Renommage simple si validé (ex. `dev_calibrage_seuils_screen.dart`
pour lever l'ambiguïté), aucune décision de design nécessaire.

### 3.4 Widget mort
`widgets/mini_player_bar.dart` (246 lignes) — zéro référence ailleurs dans
`lib/`. `REFONTE_IHM.md` §3 point 3 prévoyait qu'il reste visible en overlay
pendant la lecture plein écran du mushaf ; ça n'a jamais été branché.
→ **Décision à prendre** : le brancher (le plein écran mushaf n'a aujourd'hui
aucun mini-lecteur audio visible, écart au plan) ou le supprimer si le besoin
n'existe plus.

---

## 4. Points de réglage — état réel, pas un problème en soi

7 points d'entrée qui modifient un état de réglage, tous à périmètre
disjoint (vérifié, aucun chevauchement de contenu) :

| Écran/sheet | Domaine |
|---|---|
| `settings_screen.dart` | transverse (récitateur, prière, Qibla, langue, à-propos) |
| `prayer_times_settings_screen.dart` | horaires/adhan |
| `reading_settings_sheet.dart` | affichage/défilement de lecture |
| `tajwid_rules_screen.dart` | presets + 17 règles tajwid |
| sheet inline `karaoke_recitation_screen.dart` | vérification (sensibilité, rigueur, correction auto) |
| sheet inline `prayer_follow_screen.dart` | sensibilité + souffleur, suivre-prière |
| `voice_calibration_screen.dart` | calibration voix perso |

Le nombre n'est pas le problème (chaque domaine a une seule maison, conforme
à la règle verrouillée « pas de redondance »). Ce qui est signalé ailleurs
(§3.1) est *comment* deux d'entre eux sont codés, pas leur existence.

---

## 5. Priorisation proposée (à valider/réordonner)

| # | Item | Effort estimé | Bloque quoi |
|---|---|---|---|
| 1 | §1.1 Tajweed colors factice | petit | confiance utilisateur (contrôle qui ment) |
| 2 | §1.2 Double-tap vers écran debug | petit | un utilisateur normal peut atterrir en debug |
| 3 | §2 Littéraux non traduits (2 écrans) | petit-moyen | cohérence multilingue déjà promise |
| 4 | §3.4 `mini_player_bar` mort | petit (décision) | écart au plan plein écran |
| 5 | §3.3 Renommage calibrage/calibration | trivial | lisibilité code seulement |
| 6 | §3.2 Réconciliation langue IHM / explications | nécessite arbitrage produit | cohérence UX multilingue |
| 7 | §3.1 Extraction `context_settings_sheet.dart` | chantier (à chiffrer) | dette structurelle principale |

---

## 6. Questions à trancher avant tout code

1. §1.1 : implémenter la persistance du toggle tajweed colors, ou le retirer
   en attendant ?
2. §1.2 : retirer le double-tap vers l'écran debug, ou le garder sous une
   protection explicite ?
3. §3.1 : extraire `context_settings_sheet.dart` maintenant (chantier
   conséquent) ou corriger la spec pour acter le statu quo ?
4. §3.2 : `explanationLanguageProvider` doit-il suivre `appLocaleProvider` par
   défaut ?
5. §3.4 : rebrancher `mini_player_bar.dart` en overlay plein écran, ou le
   supprimer ?
