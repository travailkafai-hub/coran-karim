# Glossaire des techniques ASR du projet — et QUAND chacune s'applique

Rédigé le 2026-07-19 (demande utilisateur : explications simples + savoir ce
qui doit être décidé DÈS l'entraînement vs ce qui peut s'ajouter APRÈS).

**La distinction clé** : certaines techniques modifient la façon dont le
modèle APPREND (il faut les choisir avant de lancer le run, impossible de les
ajouter après) ; d'autres modifient seulement la façon dont on LIT ses
sorties (décodage/post-traitement — elles marchent avec n'importe quel
checkpoint existant, y compris epoch14 déployé, sans rien réentraîner).

## Tableau récapitulatif

| Technique | En une phrase | Quand | Statut projet |
|---|---|---|---|
| **Corpus mixed / erreurs TTS** | Montrer au modèle des fautes étiquetées fidèlement pour qu'il arrête de "corriger" vers le canonique | 🏋️ **Entraînement** | Fait (mixed-e14 déployé), extensions décidées (TTS corrects, harakat) |
| **Symboles de règles tajweed** (qalqala...) | Insérer un caractère spécial par règle dans le texte d'entraînement pour que le modèle apprenne à les "entendre" | 🏋️ **Entraînement** (nouveau tokenizer = nouveau run) | Planifié (run hybride, Phase 0-1) |
| **Tête RNNT** | Deuxième décodeur avec mémoire du contexte — meilleur en transcription libre, biaisé vers le canonique | 🏋️ **Entraînement** | Débloquée (NVVM réparé), planifiée au run hybride |
| **Tête CTC tolérante** | Sortie normalisée (sans exigence tajweed) pour le mode débutant | 🏋️ Entraînement léger (après coup, encodeur gelé — heures) | Planifiée (Phase 2) |
| **InterCTC** | Noter aussi une couche intermédiaire de l'encodeur pendant l'entraînement (l'élève corrigé à mi-parcours, pas juste à l'examen) | 🏋️ **Entraînement** (une ligne de config) | 🟡 Au run d'APRÈS le hybride (pas d'empilement de variables) |
| **CR-CTC** | Exiger la même réponse sur deux versions déformées du même audio (robustesse) | 🏋️ **Entraînement** | 🔴 Réserve, si InterCTC ne suffit pas |
| **Rescoring NLL** | Demander au modèle de départager deux textes candidats (attendu vs entendu) en comparant leurs scores de probabilité | 🎯 **Après (décodage)** — marche avec tout checkpoint | ✅ Validé offline (16/07) : lettres 80,8% GO, harakat 49,6% (hasard). **PAS encore branché dans l'app** |
| **Décodage contraint au texte attendu** | Au lieu de "transcris librement", demander "l'audio colle-t-il à CE verset, et où ça diverge ?" | 🎯 **Après (décodage)** | 🟢 Priorité n°1, testable aujourd'hui sur epoch14 |
| **N-gram + KenLM** | Table de fréquences des enchaînements de mots du Coran qui aide à trancher les hésitations (comme le clavier prédictif du téléphone) | 🎯 **Après (décodage)** — le "LM" s'entraîne sur le texte seul, minutes, CPU | 🟡 Côté "Suivre une prière" UNIQUEMENT (aggraverait le biais canonique côté vérification) |
| **Global-match** | Valider un fragment entier quand le décodage libre colle au texte attendu, ne fragmenter mot-par-mot que si mismatch | 🎯 Après (décodage) | ✅ Implémenté et commité (`3fb04c3`), à confirmer sur device |
| **GOP** (système actuel) | Score forced-vs-free par mot — aveugle quand le modèle est convaincu du canonique (forced == free ⇒ score 0 ⇒ vert à tort) | 🎯 Après (décodage) | En prod, **battu par le rescoring NLL sur les lettres** — remplacement/complément à brancher |

## Conséquence pratique : ce qui doit être décidé AVANT de lancer le run hybride

**À figer avant le lancement (irréversible pour ce run)** :
1. Le contenu du corpus (TTS corrects + harakat étendues + voix — cf. plan §3).
2. Le tokenizer (symboles de règles — Phase 0).
3. InterCTC oui/non (décision prise : NON pour ce run, au suivant).
4. Le séquencement 1a/1b et les LR (cf. plan §4bis/5).

**Améliorable à tout moment, sans toucher au training** (donc AUCUNE pression
à les caser dans le run) :
- Rescoring NLL → **à brancher dans l'app dès maintenant** (validé, meilleur
  que le GOP actuel sur les lettres — pas besoin d'attendre le run hybride).
- Décodage contraint → à prototyper offline sur epoch14 dès maintenant.
- KenLM → quand "Suivre une prière" en aura besoin.
- Global-match → déjà en place.

Autrement dit : le run hybride n'est PAS un prérequis pour améliorer la
vérification dans l'app — les deux chantiers avancent en parallèle, et tout
gain de décodage validé sur epoch14 profitera automatiquement au futur modèle
hybride (même architecture de sortie CTC).

## La ligne de partage stratégique (à ne jamais croiser)

Les techniques qui **poussent vers le texte canonique** (KenLM, tête RNNT)
servent la **localisation** ("Suivre une prière" : quel verset est récité ?).
Les techniques qui **restent fidèles à ce qui est réellement dit** (corpus
mixed, rescoring NLL, décodage contraint) servent la **vérification** (y
a-t-il une faute ?). Appliquer une technique du premier groupe à la
vérification recréerait le biais canonique que le chantier mixed a coûté des
semaines à combattre.
