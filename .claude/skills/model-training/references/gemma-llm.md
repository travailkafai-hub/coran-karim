# Gemma 4 E2B — LoRA tuteur textuel islamique

Ce fichier couvre l'entraînement du **tuteur** (pilier B de l'architecture, cf. `ARCHITECTURE.md`) : un LoRA texte-seul sur Gemma 4 E2B, entraîné à expliquer le Coran (tafsir), citer des hadiths, et analyser le vocabulaire coranique — toujours en attribuant chaque réponse à une source réelle, jamais en inventant. Différent du pilier ASR (voir `asr.md`) : ici pas d'audio, l'enjeu est la qualité et la traçabilité du dataset texte, pas la reconnaissance vocale.

## Pattern LoRA (`benchmark/gemma_finetune_tutor.py`)

```python
lora = LoraConfig(
    r=16, lora_alpha=32, lora_dropout=0.05,
    target_modules=r".*language_model.*\.(q_proj|k_proj|v_proj|o_proj|gate_proj|up_proj|down_proj)$",
    task_type="CAUSAL_LM")
```

**Bug majeur corrigé le 2026-07-09 — a invalide TOUS les runs precedents (v2 4-epoch inclus)** : le regex utilisait auparavant le suffixe `\.linear$` (cense cibler un wrapper `Gemma4ClippableLinear` autour de chaque `Linear`, suppose present partout dans Gemma 4). **Faux pour ce checkpoint** : `model.language_model.layers.N.self_attn.q_proj` etc. sont des `torch.nn.Linear` **directs, sans suffixe `.linear`** — seuls `vision_tower` (112 modules) et `audio_tower` (36 modules) ont encore ce wrapper `.linear`. Consequence : `target_modules=r".*\.linear$"` attachait le LoRA **exclusivement aux branches vision/audio**, jamais utilisees en entrainement texte-seul (aucun input image/audio) -> zero gradient reel, `lora_B` restait a **exactement zero** (son init standard) sur toute la duree de l'entrainement, donc `B @ A` = 0 en permanence : l'adaptateur etait un no-op total, indetectable au forward/generation (identique au modele de base) et la loss "plate" observee etait juste la performance figee du modele de base sur des exemples qui changent, pas un plateau d'apprentissage.

**Piege** : `print_trainable_parameters()` affichait bien un pourcentage non-nul (ex: 0.11%, 0.44%) — la verification "0% trainable = bug" suggeree avant est **insuffisante**, puisque le mauvais regex matchait quand meme quelque chose (juste pas le bon endroit). **Verification fiable a faire systematiquement apres tout changement de regex/architecture** :
```python
matches = [(n, type(m).__name__) for n, m in model.named_modules() if pattern.match(n)]
print({n.split('.')[1] for n,_ in matches})  # doit contenir 'language_model', PAS seulement vision_tower/audio_tower
```
Et plus radicalement, apres un training (meme court, 50-100 steps) : charger l'adaptateur et verifier qu'au moins quelques `lora_B` ont un `abs().max() > 0` — si tous sont exactement zero, le LoRA n'a touche aucune couche reellement traversee par le forward pass.

Autres points du pattern, à reproduire pour tout nouveau script similaire :
- `model.gradient_checkpointing_enable()` + `model.enable_input_require_grads()` avant `get_peft_model` — sans ça, gradient checkpointing + LoRA plante silencieusement (pas de gradients qui remontent).
- Masquage du prompt dans les labels : construire le prompt seul (`add_generation_prompt=True`, sans le tour assistant) pour connaître sa longueur `pl` en tokens, puis `labels[:, :pl] = -100` sur la séquence complète — le modèle n'apprend que sur la réponse générée, jamais sur le prompt.
- `MAX_TARGET_TOKENS` (512 actuellement) : tronque les réponses de tafsir trop longues (Tabari, Razi peuvent dépasser largement) pour éviter l'OOM — combiné à `MAX_TARGET` en caractères côté génération du dataset (voir plus bas), donc la troncature agit à deux niveaux (construction du dataset ET tokenisation à l'entraînement).
- `GEMMA_SFT` / `GEMMA_OUT` (variables d'env) permettent de pointer vers un dataset et un dossier de sortie différents sans toucher au script — utiliser ça pour lancer plusieurs variantes (ex: `GEMMA_SFT=data/gemma_islamic_sft_v2.jsonl GEMMA_OUT=models/gemma-4-E2B-tutor-lora-v2`) sans écraser un run précédent.
- `try/except torch.cuda.OutOfMemoryError: torch.cuda.empty_cache(); continue` autour du forward/backward par exemple — un seul exemple trop long ne doit pas tuer tout le run.

**Le compteur de steps loggé est CUMULÉ sur toutes les epochs, pas remis à zéro par epoch** : `total = math.ceil(len(rows) / ACCUM) * EPOCHS` puis `step` n'est jamais réinitialisé dans la boucle `for ep in range(EPOCHS)`. Le log affiche `ep{N} step {step}/{total}` — le `{total}` est déjà le total sur TOUTES les epochs, donc `step/total` est directement le vrai pourcentage global. Piège rencontré : lire `total` comme "steps de cette epoch" et multiplier par le nombre d'epochs restantes → surestime largement le temps restant (repéré une fois : ça donnait ~19h restantes au lieu des ~8,6h réelles).

## QAT (Quantization-Aware Training) — a faire sous Unix/WSL, PAS Windows

Contexte complet : `QAT_TRAINING_PLAN.md` (racine du projet). Motivation : le
tutor v6 (fix ci-dessus, entraine en pleine precision puis quantifie en INT4
pour l'export `.litertlm`) degenere en repetition sur l'appareil apres 1-3
phrases — le LoRA appris en pleine precision ne compense pas le bruit de
quantification. Le QAT charge le modele en 4-bit (bitsandbytes NF4,
`prepare_model_for_kbit_training`) PENDANT l'entrainement, pas seulement a
l'export, pour que l'adaptateur apprenne a compenser ce bruit.

**Tente sous Windows le 2026-07-11 — abandonne, fragmentation VRAM confirmee** :
`bitsandbytes` s'installe et charge bien sous Windows (wheel natif
`win_amd64`, la validation `AutoModelForMultimodalLM` + 4-bit + LoRA r=128
passe sans erreur : 205 modules matches dans `language_model`, 193M params
entrainables/5.3B). Mais des les premieres minutes du training reel :
`nvidia-smi` affiche 100% GPU-Util alors que `utilization.memory` (bande
passante) reste a 2% et `power.draw` a ~88W sur un cap de 360W — **exactement
la signature de fragmentation VRAM deja documentee** dans la section
FastConformer de `asr.md` (le GPU "travaille" a gerer la memoire, pas a
calculer). Le mitigant habituel echoue ici : `PYTORCH_CUDA_ALLOC_CONF=
expandable_segments:True` est defini mais le warning `expandable_segments
not supported on this platform` apparait quand meme au chargement — cette
option n'est simplement pas disponible sur ce couple Windows/torch/carte.
**Confirme par l'utilisateur : ce probleme n'existe pas sous Ubuntu** avec le
meme genre de charge de travail (bitsandbytes 4-bit + LoRA gros rang). Training
arrete avant le premier step logge (aucun checkpoint perdu). **Regle a
suivre** : ne pas retenter le QAT bitsandbytes 4-bit sur ce PC Windows tel
quel — soit WSL/Linux (recommandation d'origine du plan, maintenant
confirmee empiriquement necessaire et pas juste une precaution), soit
chercher un contournement Windows-specifique si WSL n'est pas disponible
(non explore : `bnb_4bit_use_double_quant`, taille de batch/sequence plus
homogene pour reduire la variabilite d'allocation, ou une version different
de bitsandbytes/torch).

Script prepare et deja fonctionnel jusqu'au chargement/LoRA :
`benchmark/gemma_finetune_tutor_qat.py` (copie de `gemma_finetune_tutor.py`
avec `BitsAndBytesConfig(load_in_4bit=True, nf4, compute_dtype=float16,
double_quant=False)` + `prepare_model_for_kbit_training` avant le LoRA,
r=128/alpha=256 par defaut). Venv dedie `.venv_nemotron` (le seul avec
`AutoModelForMultimodalLM` — `bitsandbytes`+`trl` y ont ete ajoutes le
2026-07-11 specifiquement pour ce script ; `trl` installe mais finalement
pas utilise, la boucle manuelle de `gemma_finetune_tutor.py` a ete reprise
telle quelle plutot que `SFTTrainer`, cf. comparaison ci-dessous). Script de
validation prealable : `benchmark/validate_qat_setup.py` (a relancer sur
toute nouvelle machine/venv avant de lancer le vrai training — verifie que
le regex touche bien `language_model` et pas seulement vision/audio_tower,
meme piege que le bug v6 mais decouvrable en quelques secondes plutot
qu'apres des heures de training).

**Comparaison avec la reference qui a marche** (`E:\RECUP_EMTEC\Projet
Harcelement\detox\finetune\finetune_qat.py`, Gemma 3 1B texte-seul, resultats
juges bons en reel) : memes bnb_config et logique de fusion post-training
(`merge_qat.py` — recharger la base fraiche en fp16 HORS de la copie 4-bit,
appliquer le LoRA, `merge_and_unload()`, ne jamais fusionner depuis le modele
4-bit d'entrainement). Differences assumees : leur script utilise `trl.
SFTTrainer` avec un vrai set d'eval (5%) + `EarlyStoppingCallback` + `eval_
loss` par epoch ; le notre n'a pas d'eval integre (comme v6 deja en prod),
validation prevue a posteriori par test manuel plutot que pendant
l'entrainement. lr=2e-4/10 epochs chez eux vs 1e-4/2 epochs ici — volontaire,
pour comparer au fix v6 a effort egal (cf. `QAT_TRAINING_PLAN.md` §3.4).

## Discipline de checkpoint (leçon coûteuse, 2026-07-05)

Le script d'origine ne sauvegardait **qu'une seule fois**, après la boucle complète des `EPOCHS` :
```python
model.save_pretrained(OUT)
proc.save_pretrained(OUT)
```
Pour un run de ~12h sur ce setup (Windows, un seul GPU, aucune supervision externe), ça veut dire : un crash, une coupure, un plantage à 90% → **zéro artefact récupérable**, tout est reperdu. Fix appliqué (voir le script actuel) : sauvegarde périodique dans la boucle d'entraînement, en plus de la sauvegarde finale :
```python
CKPT_EVERY = 200  # steps optimiseur (pas micro-batches)
...
if step % CKPT_EVERY == 0:
    model.save_pretrained(OUT)
    proc.save_pretrained(OUT)
    print(f"  [checkpoint sauvegarde -> {OUT} @ step {step}]", flush=True)
```
Un adaptateur LoRA est petit (quelques Mo, ~5.7M params entraînables ici) donc ce coût est négligeable — **aucune raison de ne pas le faire**. Règle générale à appliquer à tout nouveau script de training dans ce projet, quel que soit le modèle : vérifier explicitement qu'un checkpoint intermédiaire existe avant de lancer un run de plusieurs heures, ne pas se fier à la sauvegarde finale seule.

## Principe du dataset SFT : attribution, jamais d'invention

`benchmark/gemma_make_islamic_sft.py` construit `data/gemma_islamic_sft.jsonl` (format `{"system","user","target"}`). Le `SYSTEM` prompt et la construction des exemples imposent une règle simple mais centrale : **chaque réponse cite sa source exacte** — nom du tafsir + auteur (ex: `(المصدر: تفسير ابن كثير)`), ou pour un hadith le recueil + numéro + grade d'authenticité (`(Source : Sahih al-Bukhari, n°123 — Sahih (authentique par consensus))`). Les hadiths des 4 Sunan (hors Bukhari/Muslim, sahih par consensus) sont filtrés sur grade Sahih/Hasan — le daif est exclu de l'entraînement, pas juste dé-priorisé. Le modèle apprend à **attribuer**, jamais à halluciner une source ou un contenu religieux non sourcé.

## Ajouter une nouvelle source classique au dataset

Deux API ont été utilisées ce projet, selon que la source est organisée par verset ou par ouvrage entier :

### A. Tafsir/traduction par verset — API `spa5k/tafsir_api`

- Catalogue complet des éditions dispo (arabe/français/anglais) : `https://cdn.jsdelivr.net/gh/spa5k/tafsir_api@main/tafsir/editions.json`.
- Un verset donné : `https://cdn.jsdelivr.net/gh/spa5k/tafsir_api@main/tafsir/{slug}/{surah}/{ayah}.json` → `{"text": "..."}`.
- Script de référence : `benchmark/dl_tafsir_linguistic.py` (télécharge par threads, sauve dans `data/tafsir/{slug}.jsonl` au format `{"verse_key": "s:a", "text": "..."}`).
- Une fois téléchargé, ajouter le slug dans `TAFSIR_META` (nom affiché + langue) de `gemma_make_islamic_sft.py`, ET dans la liste `ar_slugs`/`gharib_slugs` de `build_tafsir_examples()` — avoir l'entrée dans `TAFSIR_META` seul ne suffit pas, si le slug n'est pas aussi dans une des listes de rotation il ne sera jamais réellement utilisé (piège rencontré : 5 sources ajoutées à `TAFSIR_META` mais oubliées dans la rotation, silencieusement absentes du dataset généré).

### B. Ouvrage entier (dictionnaire, encyclopédie) — API `turath.io`

Pas organisé par verset — utile pour les lexiques (Mufradat) et traités dédiés (wujuh wal-naza'ir). Base API : `https://api.turath.io/` (`/book?id=X&include=indexes&ver=3` pour les métadonnées + index de chapitres, `/page?book_id=X&pg=N&ver=3` pour le texte page par page). **`https://files.turath.io/books/{id}.json` (dump du livre entier) renvoie 404 pour les gros ouvrages multi-volumes** — pas un bug, juste pas généré pour ces tailles-là ; utiliser systématiquement `/page` en boucle dans ce cas, pas le dump entier.

Pour trouver l'ID d'un livre précis, une recherche web `site:turath.io "titre exact en arabe"` ou `turath.io "titre" book` fonctionne bien mieux que l'endpoint `/search` de l'API (constaté peu fiable : retourne `count:0` même sur des requêtes qui devraient matcher des dizaines de milliers de résultats, y compris avec la requête exacte de test de leur propre SDK — cause non identifiée, probablement protection anti-bot Cloudflare qui dégrade silencieusement plutôt que bloquer).

**Avant de tout télécharger, isoler le bon périmètre** — deux cas :
- **Dictionnaire/traité entièrement sur le sujet visé** (ex: Mufradat = tout le livre est pertinent) : télécharger le livre en entier.
- **Encyclopédie généraliste avec UN chapitre pertinent parmi des dizaines** (ex: Al-Itqan de As-Suyuti a 80 chapitres sur des sujets très différents — asbab an-nuzul, i'rab, naskh... — dont un seul, "النوع التاسع والثلاثون: في معرفة الوجوه والنظائر", est pertinent pour un dataset sur les nuances lexicales) : **repérer les bornes exactes du chapitre via les `headings` retournés par `/page`** (chercher le titre du chapitre visé ET le titre du chapitre suivant pour borner la plage de pages), puis ne télécharger/inclure QUE cette plage. Inclure le livre entier diluerait le dataset avec du contenu hors-sujet, sans que ça saute aux yeux en relisant quelques exemples au hasard.

### Découper un ouvrage en entrées (mot par mot / racine par racine) — pas de matching naïf sur le texte

Pour un dictionnaire organisé en entrées (Mufradat : une entrée par racine arabe ; Nuzhat al-A'yun : une entrée par mot, "باب X") il faut retrouver où commence/finit chaque entrée. **Piège rencontré et confirmé sur données réelles** : chercher le texte du titre ("أبى" par ex.) comme sous-chaîne dans le texte concaténé de la page semble marcher au premier coup d'œil, mais un mot-racine court apparaît quasi-toujours ailleurs dans le corpus (dans une note de bas de page citant un AUTRE dictionnaire, dans un mot plus long qui le contient, etc.) — résultat : l'entrée "suivante" récupère le mauvais passage, et le modèle apprendrait qu'un mot signifie ce que dit en fait le texte d'un mot différent. Silencieux, pas un crash — une contamination de sens.

**Fix validé** : ancrer les coupures sur la balise structurelle réelle de la source plutôt que sur le contenu. L'API turath.io renvoie le texte brut avec des balises `<span data-type="title" id=toc-N>TITRE</span>` — matcher CES balises (regex sur le HTML brut, pas sur le texte déjà nettoyé) donne des frontières d'entrée fiables à 100%, indépendamment de ce que contient le titre. Voir `benchmark/dl_wujuh_entries.py` (`TITLE_RE = re.compile(r'<span data-type="title"[^>]*>(.*?)</span>', re.S)`, découpage séquentiel via `re.split`).

**Défaut supplémentaire découvert sur une des deux sources (Ibn al-Jawzi, ~11% des entrées)** : certaines balises `<span data-type="title">` de la source englobent, en plus du vrai titre, tout le paragraphe suivant (défaut de la numérisation d'origine, pas de notre extraction) — un "mot" de plus de 150 caractères de long, contenant une phrase entière, est le signe quasi-certain de ce défaut, jamais un vrai mot-titre. Voir `repair_heading()` dans `benchmark/gemma_make_islamic_sft.py` : au-delà de `MAX_WORD_LEN` (40 caractères), tenter de scinder sur le premier saut de ligne si le préfixe ressemble à "باب <mot>", sinon traiter tout le fragment comme la CONTINUATION de l'entrée précédente (jamais comme une nouvelle entrée fantôme avec un "mot" qui est en fait une phrase).

**Après toute extraction automatisée de ce genre, vérifier manuellement un échantillon avant de considérer le dataset prêt** — comparer quelques entrées à un sens connu indépendamment (ex: le mot arabe "قسط" = justice/équité, avec la distinction classique qasata/aqsata ; "خوف" = peur). C'est ce contrôle manuel, pas une relecture de code, qui a révélé le bug ci-dessus.

## Historique des enrichissements (2026-07-05)

Point de départ : 7 sources tafsir/traduction (Ibn Kathir, Saadi, Muyassar AR/EN, Maarif, 3 traductions FR) + 6 tafsirs classiques ajoutés ensuite (Tabari, Qurtubi, Jalalayn, Baghawi, + Mokhtasar FR) = 13 sources par verset, combinées à 6 recueils de hadith authentifiés dans `gemma_islamic_sft.jsonl` (82 073 exemples).

Enrichissement pour mieux couvrir la question "pourquoi CE mot précis, vu la polysémie de l'arabe" (science `al-wujuh wal-naza'ir` / `'ilm al-furuq`) :
- **5 nouvelles sources par verset** (API spa5k) : Tahlil Kalimat al-Qur'an (analyse mot-à-mot, racine+nature grammaticale), Al-Kashshaf (az-Zamakhshari — référence classique de balâgha coranique), At-Tahrir wa At-Tanwir (Ibn Ashur — tafsir linguistique moderne), As-Siraj fi Bayan Gharib al-Qur'an et Al-Muyassar fi al-Gharib (deux dictionnaires de mots rares).
- **Al-Mufradat fi Gharib al-Qur'an** (Ar-Raghib al-Isfahani, livre entier, book_id turath.io 23636) — lexique de référence par racine, ~1590 entrées après nettoyage.
- **Nuzhat al-A'yun an-Nawazir fi 'Ilm al-Wujuh wal-Naza'ir** (Ibn al-Jawzi, livre entier, book_id 6334) — traité dédié exactement à ce sujet (mots à sens multiples selon le contexte), ~321 entrées après nettoyage/réparation des titres corrompus.
- **Chapitre isolé** (pas le livre entier) de deux encyclopédies généralistes : Al-Itqan (As-Suyuti, book_id 11728, pages 526-547) et Al-Burhan (Az-Zarkashi, book_id 11436, pages 119-128) — seul le chapitre "wujuh wal-naza'ir" de chacune, repéré via les `headings`.
- Résultat : **90 240 exemples** dans `data/gemma_islamic_sft_v2.jsonl` — pas encore basculé comme fichier de production le temps qu'un premier run (sur l'ancien dataset) serve de baseline de comparaison.

Sources classiques connues mais non trouvées en version numérique exploitable à cette date : Kitab al-Furuq wa Man' at-Taraduf (al-Hakim at-Tirmidhi — seulement des scans PDF sans OCR sur archive.org) ; le traité autonome Al-Wujuh wal-Naza'ir de Muqatil ibn Sulayman semble fondu dans son Tafsir complet (turath.io book_id 23614) plutôt que disponible seul — à vérifier si nécessaire un jour.
