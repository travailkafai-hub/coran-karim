# Plan B — Explication par tap (mot ou verset), sans dépendre du LLM

> Objectif : si le tuteur Gemma (QAT ou pas) ne répond pas au besoin en
> production (dégénérescence, latence, taille du modèle sur téléphone 6 Go
> RAM...), avoir une alternative qui n'a **aucune dépendance à la génération
> LLM** — on affiche du texte de tafsir déjà écrit et sourcé, on ne demande
> jamais à un modèle d'inventer une explication. Même philosophie que le
> pilier Récitation : *l'algorithme sert la vérité, il ne la génère pas*
> (cf. `ARCHITECTURE.md`).
>
> Ce document est une proposition à valider avant implémentation (rien n'est
> codé), conformément à la préférence établie : analyser d'abord, coder sur
> feu vert explicite.

---

## 1. L'interaction telle que décrite

Deux niveaux de tap, donc deux granularités de recherche :

1. **Tap sur un verset (aya)** → explication du verset entier. Ressource :
   n'importe quel tafsir classé par verset (tout ce qui est dans
   `data/tafsir/*.jsonl` — 15 sources AR, 4 FR, 6 EN).
2. **Tap sur un mot précis** → explication **ciblée sur ce mot**, plus
   précise qu'une explication de verset entier qui noierait le mot dans le
   contexte. Ressource : les sources **indexées par mot/racine**, pas par
   verset — c'est un jeu de données différent, déjà construit ce mois-ci :
   `data/quran_sciences/ar-mufradat_entries.jsonl` (racine → nuance de sens),
   `ar-nuzhat-ayun_entries.jsonl` (mot → sens multiples selon contexte), et
   `ar-tahlil-kalimat` (déjà décompose chaque verset mot par mot, avec racine
   + nature grammaticale — le plus direct des trois pour ce cas d'usage).

Dans les deux cas : **cascade synthétique → détaillé**, jamais tout d'un
coup. Première réponse = la plus courte/simple disponible pour cette langue,
avec un bouton "en savoir plus" qui déroule une source plus riche, jusqu'à
la plus érudite. Source toujours citée à chaque palier, y compris le
premier.

## 2. ⚠️ Point bloquant à trancher avant tout : les droits d'usage

**Je ne peux pas donner un feu vert juridique fiable ici** — c'est
volontairement le point sur lequel je ne tranche pas à ta place, ça dépasse
ce que je peux garantir avec confiance.

**Mise à jour : l'app sera gratuite, non-commerciale.** Ça retire le risque
le plus explicite trouvé ci-dessous (la clause Quran Foundation vise la
*redistribution commerciale*). Nuance à garder quand même : leurs CGU
autorisent l'usage "personnel, non-commercial", ce qui n'est pas forcément
identique à "distribuer/afficher le contenu à d'autres utilisateurs via une
app publiée" — même gratuite, c'est une distribution, pas un usage
strictement personnel. Et ça ne change rien pour spa5k/turath.io (aucune
licence claire trouvée, indépendamment du caractère commercial). **Le statut
gratuit rend toutefois une demande directe à Quran Foundation beaucoup plus
simple à obtenir** — c'est le genre de dossier qu'ils accordent facilement.
Recommandation : les contacter en le précisant explicitement, plutôt que de
présumer que "gratuit" suffit à lever la question.

Ce que j'ai trouvé en vérifiant les 3 sources utilisées pour construire le
dataset :
- **Quran Foundation / quran.com** (utilisé pour les traductions FR
  Hamidullah/Montada/Rashid Maash, et à l'origine pour Ibn Kathir/Maarif
  EN) : leurs conditions d'utilisation disent explicitement que toute
  **redistribution commerciale** du contenu nécessite un **accord de licence
  commerciale écrit séparé** avec Quran Foundation. Afficher ce texte
  verbatim dans l'app (pas juste s'en servir pour entraîner un modèle en
  interne) est exactement le cas de figure qu'ils encadrent.
- **spa5k/tafsir_api** (la majorité des tafsirs classiques arabes/anglais) :
  agrégateur tiers, aucune licence claire trouvée pour les **données**
  elles-mêmes (le dépôt GitHub a une licence de code, pas forcément un droit
  de redistribuer le contenu qu'il agrège).
- **turath.io** (Mufradat, Nuzhat al-Ayun, Itqan, Burhan) : idem, pas de
  conditions d'utilisation claires trouvées pour le contenu.

Ce qui est **structurellement plus sûr** (mais pas une garantie absolue,
juste un risque nettement plus faible) : le **texte arabe original** des
tafsirs classiques est du domaine public sans ambiguïté dès lors que
l'auteur est mort depuis largement plus de 70 ans (Tabari, Ibn Kathir,
Qurtubi, Zamakhshari, Razi, Baydawi, Alusi, Suyuti, Ar-Raghib, Ibn al-Jawzi
— tous largement anciens). Ce qui reste risqué même en arabe : Ibn Ashur
(mort 1973, probablement encore protégé selon la juridiction). Et
**toute traduction moderne (FR/EN) est une œuvre séparément protégée par son
traducteur/éditeur**, indépendamment de l'ancienneté du texte source — donc
Hamidullah, Montada, Mokhtasar, Rashid Maash, Maarif-ul-Quran, Tazkirul
Qur'an sont tous dans cette zone à clarifier avant affichage public.

**Options concrètes, du plus sûr au plus rapide** :
1. **Contacter Quran Foundation pour une licence** — vu que l'app est
   exactement le cas d'usage qu'ils visent ("Quranic experience"), et que ça
   semble être un projet non-commercial/personnel au départ, la démarche est
   probablement simple. À faire une seule fois, réglerait la question pour
   Hamidullah/Montada/Rashid Maash/Ibn Kathir EN/Maarif EN.
2. **Se limiter à l'arabe classique indiscutablement domaine public** pour
   l'affichage verbatim en production, et garder les traductions FR/EN comme
   contenu d'entraînement du modèle (usage différent, risque différent) mais
   pas comme texte affiché tel quel à l'utilisateur.
3. **Générer nos propres explications courtes** (via le tuteur Gemma
   lui-même, ou manuellement) plutôt que copier une traduction existante —
   plus de travail, mais élimine le problème de fond.

Sans trancher ce point, je ne recommande pas de passer à l'implémentation
sur les sources FR/EN modernes.

## 3. Structure de cascade proposée (par granularité et langue)

### 3.1 Tap sur un MOT

| Palier | Arabe | Français | Anglais |
|---|---|---|---|
| 1 — synthétique | Entrée `ar-mufradat_entries` pour la racine du mot (nuance de sens, ~300-2000 car.) | *aucune ressource mot-à-mot dédiée trouvée* → repli sur la phrase du Mukhtasar FR contenant le mot | idem → repli sur Mukhtasar EN |
| 2 — détail | Entrée `ar-nuzhat-ayun_entries` si le mot a plusieurs sens selon le contexte (wujuh wal-naza'ir) | Montada (verset entier) | Ibn Kathir EN / Maarif EN (verset entier) |
| 3 — érudit | `ar-tahlil-kalimat` (décomposition grammaticale complète du verset) + citation du verset dans Tabari/Razi si besoin | — | — |

**Écart à assumer** : il n'existe pas de vrai dictionnaire mot-par-mot en
français ou en anglais dans ce qu'on a rassemblé (constaté déjà lors de
l'enrichissement — le français en particulier est structurellement pauvre en
ressources de ce type). Le palier 1 en FR/EN sera donc mécaniquement moins
précis qu'en arabe : c'est la phrase pertinente d'un tafsir de *verset*
contenant le mot, pas une entrée de dictionnaire dédiée au mot. À dire
clairement dans l'UI plutôt que de faire semblant d'avoir la même précision
dans les 3 langues.

### 3.2 Tap sur un VERSET (aya)

| Palier | Arabe | Français | Anglais |
|---|---|---|---|
| 1 — synthétique | Muyassar ou Jalalayn (les plus concis, p50 ~250-1000 car.) | Mukhtasar FR | Mukhtasar EN |
| 2 — détail | Saadi, Ibn Kathir, Baghawi, Qurtubi | Montada | Ibn Kathir EN, Maarif EN |
| 3 — érudit | Tabari, Razi, Alusi, Bahr al-Muhit, Shawkani, Durr al-Manthur, Kashshaf, Ibn Ashur | *(rien de plus riche disponible en FR)* | Tazkirul Qur'an (le plus long/réflexif en EN) |

Le classement par palier reprend directement les longueurs médianes déjà
mesurées lors du contrôle qualité de chaque source (fait pendant le
téléchargement) — pas une estimation à l'aveugle.

## 4. Ce que ça implique techniquement (aperçu, pas un plan détaillé)

- **Aucun besoin du LLM pour cette fonctionnalité** : c'est une recherche
  directe par clé (`verse_key` ou racine de mot) dans les fichiers déjà
  téléchargés — rapide, déterministe, zéro risque d'hallucination ou de
  dégénérescence liée à la quantification.
- **Détection du mot tapé → sa racine** : nécessite un lemmatiseur/analyseur
  morphologique arabe (ou : réutiliser directement `ar-tahlil-kalimat`, qui
  a déjà, pour chaque mot de chaque verset, sa racine identifiée — voir
  l'exemple `data/tafsir/ar-tahlil-kalimat.jsonl` : `"• ﴿بِسۡمِ﴾ ... من مادّة
  سمو"`). C'est probablement la meilleure porte d'entrée technique : parser
  ce fichier pour construire un index `(verset, position du mot) → racine`,
  plutôt que ré-implémenter un lemmatiseur.
- **Format de données à préparer** : un fichier d'index unique compilant,
  pour chaque verset et chaque racine de mot, les paliers 1/2/3 déjà
  résolus (pas de recherche à la volée dans l'app) — génération offline,
  comme `gemma_make_islamic_sft.py` mais pour produire un index de lookup
  plutôt qu'un dataset d'entraînement.
- **Complémentarité avec le tuteur Gemma** : cette fonctionnalité couvre le
  cas "expliquer ce qui existe déjà" (tap mot/verset). Le tuteur LLM reste
  utile pour les questions libres/formulées par l'utilisateur qui ne
  correspondent pas à un simple lookup — les deux peuvent coexister, ce
  n'est pas l'un ou l'autre.

## 5. Prochaine étape

Ne rien coder tant que le point 2 (droits d'usage) n'est pas tranché. Une
fois tranché, je peux : (a) construire le script d'index offline
`verset/mot → paliers 1/2/3` à partir des sources retenues, (b) définir le
format JSON exact que l'app consommera, (c) faire un premier prototype sur
une sourate courte (Al-Fatiha ou Al-Ikhlas) pour valider le rendu avant de
généraliser aux 6236 versets.
