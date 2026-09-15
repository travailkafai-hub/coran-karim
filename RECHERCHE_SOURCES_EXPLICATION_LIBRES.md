# Prompt de recherche — sources d'explication du Coran libres de droits

> Rédigé le 2026-09-12 à la demande de l'utilisateur, pour être donné à une
> instance de Claude disposant d'un accès web. Objectif : débloquer le point 2
> de `WORD_AYAH_EXPLANATION_PLAN.md` (droits d'usage), qui bloque la
> fonctionnalité d'explication des mots depuis sa rédaction — tout le code de
> l'app est prêt, seules les données manquent.
>
> Le prompt est volontairement auto-suffisant : l'instance qui le reçoit n'a
> aucun contexte de ce projet.

---

## Le prompt à copier

**CONTEXTE**

Je développe une application mobile de lecture du Coran (Android, Flutter),
**gratuite, sans publicité**, publiée sur le Play Store, et qui doit
fonctionner **hors ligne**. Je veux y ajouter une fonction : l'utilisateur
touche un mot du Coran, et une explication courte du sens de ce mot apparaît.

**CE QUE JE CHERCHE**

Des sources de contenu explicatif que je puisse **embarquer dans
l'application** et **afficher aux utilisateurs**, avec une licence qui
l'autorise explicitement.

Par ordre de priorité :
1. **Dictionnaires / lexiques coraniques mot à mot ou par racine** (type
   *Mufradat* d'Ar-Rāghib al-Iṣfahānī, *Lisān al-ʿArab*, *Kitāb al-ʿAyn*,
   *Nuzhat al-Aʿyun*) ;
2. **Décompositions grammaticales mot par mot** (iʿrāb) donnant la racine de
   chaque mot ;
3. À défaut : **tafsirs classés par verset**, les plus concis de préférence.

Langues par ordre d'importance : **arabe**, français, anglais.

**CRITÈRES JURIDIQUES — c'est le cœur de la demande**

L'application est gratuite, mais elle **distribue** le contenu à des tiers
(publication sur un magasin d'applications). Donc :

- une autorisation d'« usage personnel, non commercial » **ne suffit pas** ;
- il me faut : **domaine public confirmé**, ou **licence explicite** (CC0,
  CC-BY, CC-BY-SA, MIT/ODbL pour des données…), ou une autorisation écrite ;
- pour **chaque** source, donne-moi **l'URL exacte** de la page de licence ou
  des CGU, et **cite le passage** qui autorise — ou interdit — la
  redistribution dans une application ;
- distingue bien deux choses souvent confondues : un **texte arabe classique**
  peut être dans le domaine public (auteur mort depuis plus de 70 ans) alors
  que sa **numérisation**, son **édition critique** ou sa **traduction
  moderne** restent protégées ;
- signale explicitement si une traduction française ou anglaise moderne
  (Hamidullah, Montada, Mukhtasar, Maarif-ul-Quran, Tazkirul Qur'an…) est une
  œuvre protégée séparément.

**SOURCES DÉJÀ ÉVALUÉES** (ne referais pas le travail, mais corrige-moi si
mes conclusions sont fausses)

- **quran.com / Quran Foundation** (api.quran.com) : leurs CGU encadrent la
  redistribution commerciale et exigent une licence écrite séparée. Statut
  pour une app **gratuite** : pas clair, à trancher.
- **spa5k/tafsir_api** (GitHub) : agrégateur tiers ; licence de code présente,
  mais rien de clair sur les **données** agrégées.
- **turath.io** : aucune condition d'utilisation claire trouvée.
- Sources déjà utilisées par l'app mais **audio uniquement** (pas de tafsir) :
  mp3quran.net, everyayah.com, qurango.net, hisnmuslim.com.

**À VÉRIFIER EN PRIORITÉ**

- **way2quran.com** — proposent-ils du tafsir ou du lexique ? Sous quelle
  licence ? API ou fichier téléchargeable ?
- **Tanzil.net**, **Quranic Arabic Corpus** (corpus.quran.com),
  **KFGQPC / Complexe du Roi Fahd**, **Al-Maktaba Al-Shāmila** (shamela.ws),
  **OpenITI**, **Corpus Coranicum**, **Wikisource arabe**,
  **Internet Archive**.
- Tout projet universitaire publiant des données coraniques ouvertes.

**FORMAT TECHNIQUE ATTENDU**

- Je préfère un **fichier téléchargeable** (JSON, JSONL, CSV, SQLite) à une
  API, puisque l'app doit fonctionner hors ligne.
- Indique le **volume approximatif** de chaque source.
- Indique s'il existe une **clé de jointure** avec le texte coranique
  (numéro de verset, racine, position du mot dans le verset) — sans elle, la
  source est inexploitable pour un tap sur un mot précis.

**RÉPONSE ATTENDUE**

Un tableau avec, pour chaque source :

| source | contenu | langue | granularité (mot / racine / verset) | licence exacte | URL de la licence | citation du passage clé | format | volume | verdict (utilisable / à demander / à écarter) |

Puis, en conclusion :
1. les **2 ou 3 sources les plus sûres** pour un usage **mot à mot en arabe** ;
2. ce qui existe — **ou n'existe pas** — d'équivalent en **français** ;
3. si une démarche d'autorisation est nécessaire, **à qui écrire** et sous
   quelle forme.

**IMPORTANT** : n'invente aucune licence. Si tu ne trouves pas de page de
licence pour une source, écris « licence non trouvée » plutôt que de
supposer. Une conclusion prudente m'est plus utile qu'une conclusion fausse :
je vais publier cette application, et afficher un texte sans droit clair
m'expose réellement.

---

## Pourquoi ces exigences (contexte interne, à ne pas envoyer)

- **« gratuit ne suffit pas »** : le plan initial le notait déjà — les CGU de
  Quran Foundation autorisent l'usage « personnel, non commercial », ce qui
  n'est pas identique à « distribuer le contenu à d'autres utilisateurs via
  une app publiée ». Même gratuite, une publication est une distribution.
- **« clé de jointure »** : sans racine ni position de mot, une source ne peut
  pas servir au tap sur un mot — c'est précisément ce qui rendait
  `ar-tahlil-kalimat` intéressant dans le plan d'origine (il donne déjà, pour
  chaque mot de chaque verset, sa racine).
- **« fichier plutôt qu'API »** : l'app doit marcher hors ligne, et le service
  déjà codé (`quran_sciences_service.dart`) lit un fichier local par offset.
- **« le plus concis de préférence »** : l'utilisateur a explicitement écarté
  la cascade à trois paliers prévue au plan (« pas de cascade ») — on vise
  une explication courte et unique, pas un empilement de sources.

---

# RÉSULTAT — vérifié sur les données réelles (2026-09-12)

La recherche a été faite et ses conclusions ont été **revérifiées à la source**
(licence téléchargée, dump inspecté), pas reprises sur parole.

## La source retenue : Quranpedia.net, fichier `meanings.json.gz`

`https://quranpedia.net/dumps/meanings.json.gz` — titre :
« غريب القرآن — معاني كلمات كلِّ آية » (les sens des mots de chaque verset).

Structure, relevée dans le fichier :

```json
{"surah": 1, "ayah": 1, "meanings": [
  {"book_info": {"name": "...", "author": "...", "edition": "..."},
   "words": [{"text": "بِسْمِ اللهِ", "meaning": "أَيْ: أَبْتَدِئُ قِرَاءَتِي..."}]}]}
```

## Ce qui rend cette piste propre : pas de GPL

La clé est **(verset, texte du mot)** — PAS la racine. On n'a donc aucun besoin
du champ `morphology` de Quranpedia, qui est le seul sous **GNU GPL** (il vient
du Quranic Arabic Corpus de Kais Dukes, et leur licence le dit explicitement :
« Any use must clearly indicate the Quranic Arabic Corpus as the source »).

C'était le vrai risque du dossier : un copyleft dans une app publiée. Il est
contourné non par une astuce juridique, mais parce que la donnée dont on a
besoin ne passe pas par lui.

## Le tri juridique livre par livre — 2 sur 4 sont à écarter

`meanings.json.gz` agrège quatre ouvrages de gharib. Leur statut diffère, et la
licence Quranpedia est explicite : « contemporary works remain the property of
their authors and publishers ».

| livre | auteur | mort | statut |
|---|---|---|---|
| السراج في بيان غريب القرآن | Al-Khudayri | contemporain (éd. 2008) | ⛔ protégé |
| كلمات القرآن | Hasanayn Makhlouf | 1990 | ⛔ protégé (< 70 ans) |
| تذكرة الأريب في تفسير الغريب | Ibn al-Jawzi | 1201 | ✅ domaine public |
| التبيان في تفسير غريب القرآن | Ibn al-Hā'im | 1412 | ✅ domaine public |

## Ce qu'on obtient en ne gardant que les deux classiques

| | |
|---|---|
| versets couverts | **3 689 sur 6 236 — 59 %** |
| entrées mot → sens | **8 237** |
| poids | **~0,2 Mo compressé** (le plan initial prévoyait 305 Mo) |
| dépendance GPL | **aucune** |

Avec les deux livres contemporains, la couverture monterait à 77 % (4 799
versets) — c'est le gain que rapporterait une autorisation écrite de leurs
éditeurs.

## Limites à annoncer, pas à masquer

1. **Le gharib n'explique que les mots DIFFICILES.** C'est sa nature : sur un
   mot courant il n'y a rien, et aucune source ne changera cela. 59 % est le
   plafond structurel de ces deux livres, pas un défaut d'intégration.
2. **Arabe uniquement.** Confirmé par la recherche ET par l'audit : aucun
   lexique mot-à-mot français sous licence de redistribution claire. Les
   traductions modernes (Hamidullah, Montada…) sont protégées séparément.
3. **Obligation de fraîcheur** : la licence rend le distributeur responsable
   s'il diffuse un texte périmé, et fournit `/v1/changes?since=<version>`.
   Faible risque sur du texte classique, mais la version du dump doit être
   conservée avec les données.

## Sources écartées, et pourquoi (confirmé à la source)

- **quran.com / Quran Foundation** : la redistribution exige une licence
  écrite, et le fait que l'app soit gratuite n'y change rien. Mise en cache
  limitée à une semaine — incompatible avec un usage hors ligne embarqué.
- **way2quran.com** : « personal, educational, and non-commercial da'wa use »,
  pas de dump texte ; tafsir en streaming audio. À écarter en l'état.
- **spa5k/tafsir_api**, **turath.io**, **Al-Maktaba Al-Shamela** : aucune
  licence claire sur les données.
- **Internet Archive** : ne garantit rien, « at their own risk ».

## Décision attendue

Partir sur l'arabe, mots difficiles, 0,2 Mo embarqué, sans cascade (demande
utilisateur : « pas de cascade »). Le code de l'app existe déjà
(`quran_sciences_service.dart`, `coach_explanation_sheet.dart`) — il faudrait
surtout remplacer le lookup en cascade par un lookup simple.
