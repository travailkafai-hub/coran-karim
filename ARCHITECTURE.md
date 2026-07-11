# Coran Karim — Architecture technique

> App mobile d'aide à la **mémorisation du Coran** assistée par IA.
> Cible : **Android d'abord** (iOS plus tard via Flutter).
> Tout en **on-device** quand c'est possible (offline + privé + gratuit à l'usage).

---

## 1. Vision & principe directeur

L'app combine **3 piliers**, chacun avec une techno différente. **Erreur classique à éviter** : croire qu'un seul LLM (Gemma) fait tout. Non.

| Pilier | Question utilisateur | Techno | IA ? |
|---|---|---|---|
| **A. Récitation** | « Est-ce que je récite juste ? » | **ASR** (Whisper-Quran) + alignement | Oui (speech-to-text) |
| **B. Tuteur** | « Qu'est-ce que ça veut dire ? Interroge-moi » | **Gemma 3 1B** fine-tuné on-device | Oui (LLM) |
| **C. Révision** | « Qu'est-ce que je dois réviser aujourd'hui ? » | **FSRS** (répétition espacée) | Non (algo) |

Le **socle commun** = une belle IHM mushaf (texte + tajwid + audio).

---

## 2. Stack technique

### Application
- **Flutter** (Dart) — un seul code Android + iOS plus tard, excellent RTL/arabe.
- **State management** : Riverpod.
- **Base locale** : SQLite (`drift` ou `sqflite`) — texte du Coran, progression, données FSRS.
- **Audio** : `just_audio` (lecture récitateurs) + `record` (capture micro de l'utilisateur).

### IA on-device
- **Tuteur** : **MediaPipe LLM Inference** (`flutter_gemma`) → modèle `.litertlm` INT4 (~550 MB).
- **ASR** : **whisper.cpp** via FFI (modèle `whisper-base-ar-quran` quantifié GGML).

### Données du Coran (sources gratuites)
- **API Quran Foundation / Quran.com** : texte Uthmani, traductions, tajwid, audio, timestamps mot-à-mot.
- **Polices** : `KFGQPC HAFS Uthmanic Script` (rendu mushaf officiel).
- **Audio par mot** : everyayah.com / Quran.com (pour surligner pendant la lecture).

---

## 3. Architecture logicielle (couches)

```
┌─────────────────────────────────────────────┐
│  UI (Flutter / Riverpod)                      │
│  MushafView · ReciteScreen · TutorChat · Revise│
├─────────────────────────────────────────────┤
│  Domain (use-cases)                            │
│  VerifyRecitation · ScheduleReview · AskTutor  │
├─────────────────────────────────────────────┤
│  Services                                      │
│  AsrService(whisper) · LlmService(gemma)       │
│  RagService(embeddings+retrieval) · FsrsSched. │
│  AudioService                                  │
├─────────────────────────────────────────────┤
│  Data                                          │
│  QuranRepository(SQLite) · ProgressRepository  │
│  RagRepository(SQLite embeddings, cf. §5)      │
│  QuranApi(cache) · ModelStore(.litertlm/.ggml) │
└─────────────────────────────────────────────┘
```

---

## 4. Pilier A — Vérification de récitation (PRIORITÉ 1)

C'est le cœur et le plus dur. Flux :

```
Micro → enregistrement → Whisper-Quran (ASR) → texte arabe reconnu
      → alignement avec le texte de référence (verset attendu)
      → diff mot-à-mot → feedback visuel (vert/rouge) + score
```

### Choix techniques
- **Modèle ASR** : `tarteel-ai/whisper-base-ar-quran` (HuggingFace) → exporté en **GGML quantifié** (q5/q8) pour whisper.cpp.

#### ⚖️ Décision ouverte : Whisper-Quran (spécialisé) vs **Gemma 4 E2B audio** (unifié) ⭐
**Gemma 4** (sorti avril 2026, Apache 2.0) — variantes **E2B/E4B** mobile avec **audio natif encoder-free** : découpe le son 16 kHz en frames 40 ms projetées directement dans le LLM. Fait **ASR + Q&A audio + texte** dans UN modèle. E2B tourne sur **Android via LiteRT-LM**. Modèle prêt : `litert-community/gemma-4-E2B-it-litert-lm`. **Fine-tuning LoRA unifié** : audio + texte partagent les mêmes poids → 1 seul LoRA met à jour toute la chaîne en une passe (= ASR récitation ET tuteur fine-tunés ensemble). LiteRT-LM charge les adaptateurs LoRA au runtime.

| Critère | Whisper-Quran | Gemma 4 E2B audio |
|---|---|---|
| Précision récitation coranique | ✅ fine-tuné Coran, **5,75 % WER**, prouvé | ⚠️ à fine-tuner/valider |
| Poids on-device | ✅ ~60 MB + Gemma 550 MB ≈ 610 MB | ❌ E2B INT4 ≈ 1,5–2 GB |
| Fine-tuning | texte seulement | ✅ **1 seul LoRA = ASR + tuteur** |
| Runtime / maintenance | whisper.cpp + LiteRT (2) | ✅ **LiteRT-LM seul** |

**Règle d'or quel que soit le modèle** : l'IA **transcrit**, l'**algo juge** (diff mot-à-mot). Ne jamais demander « est-ce correct ? » directement au LLM (trop indulgent pour de la mémorisation exacte).

**Décision (à trancher empiriquement)** : le Gemma 4 E2B fine-tuné transcrit-il la récitation aussi bien que Whisper-Quran ?
- **Oui** → tout en **Gemma 4 E2B** : un seul modèle multimodal, un seul LoRA, LiteRT-LM seul. Architecture cible préférée.
- **Non** → Whisper-Quran pour l'ASR + Gemma 4 pour le tuteur.

#### 📊 Résultat benchmark (2026-06-27) — voir `benchmark/BENCHMARK_RESULTS.md`
Test sur 16 ayahs (récitateur Alafasy), RTX 5080. **Modèles BASE (non fine-tunés)** :

| Métrique | Whisper-Quran | Gemma 4 E2B base |
|---|---|---|
| WER transcription | **5,2 %** | 16,6 % |
| Détection précision | **90,6 %** | 81,2 % (pistes A=B) |
| Faux positifs | **12,5 %** | 31-37 % |
| Latence/ayah | 0,2 s | 0,8-1,0 s |
| Mémoire | 0,34 GB | 10,3 GB bf16 / ~2,5 GB INT4 mobile |

**Verdict** : out-of-the-box, **Whisper-Quran gagne nettement**. Piste A ≈ Piste B sur modèle base (le modèle entend mal → la piste B hérite des erreurs). E4B écarté (16 GB bf16 > VRAM, 3-4 GB INT4 limite mobile).
**v1 = Whisper-Quran (ASR) + Gemma (tuteur).** Reste à tester : **E2B fine-tuné** (objectif WER ≤ 6 %, FP ≤ 12 % pour basculer en architecture unifiée). Note : taille mobile réelle E2B = ~2,5 GB INT4 (format .litertlm), pas 10 GB (le bf16 ne sert qu'au fine-tuning desktop).
- **Alignement** : pas d'IA. Normalisation du texte arabe (retirer diacritiques) puis **distance d'édition mot-à-mot** (Levenshtein sur tokens) → repère mot manquant / substitué / inséré.
- **Mode « test mémorisation »** : on cache le texte, l'utilisateur récite de mémoire, l'app valide.

### Pièges
- Le tajwid fin (madd, ghunna) n'est **pas** détectable par Whisper standard — rester sur la justesse des **mots** au début, pas la prononciation parfaite.
- Latence : faire l'ASR **par verset** (pas la sourate entière) pour un feedback rapide.

---

## 5. Pilier B — Tuteur (Gemma fine-tuné)

### Modèle
- **Cible : Gemma 4 E2B** (multimodal audio+texte) — le même modèle que le Pilier A si la voie unifiée est retenue.
- Repli : Gemma 3 1B texte (pas le 270M : trop faible pour le tafsir), fine-tuning **LoRA** → `.litertlm` INT4 ~550 MB (skill `litertlm-int4-conversion`).
- Fine-tuning **LoRA unifié** sur Gemma 4 E2B : un seul adaptateur couvre ASR récitation + tuteur.

### Dataset à construire (le vrai travail)
Format instruction (français + arabe). Catégories :
1. **Sens des versets** : Q/R sur la signification (basé sur tafsir reconnu : Ibn Kathir, Saadi…).
2. **Vocabulaire / racines** : expliquer un mot, sa racine, ses occurrences.
3. **Coaching mémorisation** : moyens mnémotechniques, découpage de versets longs.
4. **Quiz génératifs** : « complète le verset », « quel verset suit ? », « dans quelle sourate ? ».

> ⚠️ **Garde-fou religieux** : le LLM ne doit **jamais inventer** de texte coranique. Le texte du Coran vient **toujours** de la base SQLite vérifiée, jamais généré par Gemma. Gemma n'explique et n'interroge que ; le texte sacré est servi par la data layer.

### Fonctionnement
- Chat contextualisé : on injecte le verset courant (depuis SQLite) dans le prompt → Gemma explique/interroge dessus.

### Architecture RAG (anti-hallucination) — recherche 2026-07-05, PLAN non implémenté

Le dataset SFT (82k exemples, `benchmark/data/gemma_islamic_sft.jsonl`) apprend au modèle un **style** de réponse sourcée (« ... (Source : Ibn Kathir) »), mais reste un modèle génératif : rien n'empêche Gemma d'inventer un numéro de hadith ou une attribution de tafsir hors de sa distribution d'entraînement. Le garde-fou ci-dessus (texte coranique toujours depuis SQLite) doit s'étendre aux **explications et hadiths** — d'où le RAG, déjà anticipé par `benchmark/rag_build_corpus.py` (son propre docstring : *« base de connaissance RAG anti-hallucination »*) mais jamais formalisé dans ce document.

**Déjà construit (2026-06-29/30, inchangé depuis, vérifié 2026-07-05)** :
- `benchmark/data/rag_corpus/passages.jsonl` — **209 214 passages** déjà découpés et sourcés (177k tafsir + 32k hadith authentique uniquement), schéma `{id, type, source, ref, lang, text, meta}`.
- 82k exemples SFT qui habituent déjà le modèle au style « réponse + source ».

**Rien construit côté recherche** : aucun modèle d'embeddings, aucun index vectoriel, aucune logique de requête (vérifié : pas de FAISS/Chroma/sentence-transformers/LangChain dans le repo ni les venvs). Plan :

**1. Modèle d'embeddings (pour la requête, on-device)** — corpus multilingue AR/FR/EN :
| Modèle | Dim | Taille (INT8) | Remarque |
|---|---|---|---|
| `intfloat/multilingual-e5-small` ⭐ | 384 | ~110 Mo | Entraîné spécifiquement pour la recherche (préfixes query:/passage:) — meilleur choix |
| `paraphrase-multilingual-MiniLM-L12-v2` | 384 | ~120 Mo | Alternative éprouvée, plus généraliste |

Export ONNX (même pattern que FastConformer cette session) → inference Android via **ONNX Runtime**, déjà intégré (`FastConformerCtcPlugin.kt`) : pas de nouvelle dépendance mobile, juste un second modèle chargé par le même mécanisme. **Seule la requête utilisateur s'embed sur le téléphone** — le corpus (209k passages) s'embed **une fois, sur PC**, et se ship comme asset au premier lancement (même pattern que le téléchargement du `.litertlm` après install) : jamais recalculé on-device.

**2. Stockage / recherche vectorielle on-device** — pas de FAISS sur Android. Taille réelle : 209 214 × 384 dims × 1 octet (INT8) ≈ **77 Mo**, gérable.
- Embeddings stockés en BLOB dans une table SQLite (même moteur que `QuranRepository` — pas de nouvelle techno de stockage).
- Recherche **brute-force** (cosine sur ~209k vecteurs 384-dim ≈ 80M FLOPs/requête, <50ms attendu sur CPU mobile actuel). Ne pas construire d'index ANN (HNSW/IVF) tant que le brute-force n'est pas mesuré trop lent en pratique — sur-ingénierie prématurée sinon.

**3. Raccourci : filtrage par verset avant recherche sémantique.** Le verset courant est **déjà connu** (injecté dans le prompt, cf. ci-dessus). Pour « explique ce verset », filtrer `passages` sur `meta.verse_key` suffit (10-20 passages, instantané, pas besoin d'embeddings). La recherche sémantique ne sert que pour les questions **thématiques/transversales** (« que dit le Coran sur la patience ? ») ou les questions hadith non liées à un verset précis. → retrieval hybride : filtre exact d'abord, embeddings en repli.

**4. Question ouverte : faut-il ré-entraîner le SFT pour le format RAG ?** Le format actuel bake le texte tafsir directement dans `target` (rien injecté dans `user`). Deux options :
- **(a) Sans ré-entraînement** : injecter les passages récupérés dans le prompt à l'inférence, modèle actuel tel quel. Coût nul, mais le modèle n'a jamais appris à s'appuyer sur un contexte injecté — risque de paraphraser sa mémoire d'entraînement plutôt que les passages fournis.
- **(b) Avec ré-entraînement** : nouveau format SFT `user: [passages récupérés] + question` → `target: réponse citant UNIQUEMENT ces passages`. Nécessite un nouveau script (joindre questions ↔ passages source réels) + un nouveau LoRA SFT. Grounding plus fiable, standard pour du RAG sérieux.
- **Recommandation** : tester (a) d'abord (coût nul, valide si la récupération elle-même est pertinente) avant d'investir dans (b).

**5. Lié mais indépendant : le ré-entraînement `models/gemma-4-E2B-islamic-lora` n'a jamais abouti.** `benchmark/logs/gemma_islamic.log` (dernière modif 2026-06-30) montre un blocage pendant le chargement des poids (1128/1951 tenseurs), jamais terminé — pas la peine de le relancer tel quel si l'option (b) est retenue, le nouveau format SFT remplacerait ce run de toute façon.

**6. Évaluation** — avant mise en prod : constituer un petit set de test (quelques dizaines de questions avec passage-source attendu connu à la main) pour mesurer la précision de récupération avant de faire confiance au pipeline complet.

**Ce qui bloque le démarrage effectif** : le GPU est occupé par le training ASR (Pilier A, cf. section 4/skill `model-training`) — l'export du modèle d'embeddings et un éventuel ré-entraînement LoRA (option b) attendent la fin/pause de ce training. La construction de l'index (embedding du corpus, une fois, tâche légère) peut se faire dès que le GPU est libre quelques minutes, sans dépendre du reste du Tuteur.

---

## 6. Pilier C — Révision intelligente (FSRS)

- Algorithme **FSRS** (successeur de SM-2 / Anki) — pur calcul, pas d'IA.
- Chaque **verset/page** est une « carte » avec un état (stabilité, difficulté).
- Après chaque session de récitation (Pilier A), le **score ASR alimente la note FSRS** → l'app planifie automatiquement la prochaine révision.
- Écran « Aujourd'hui » : liste des versets à réviser, triés par urgence.

**Synergie clé** : Pilier A (score récitation) → Pilier C (planning) → l'utilisateur révise au bon moment ce qu'il oublie. C'est ça la vraie valeur « IA » perçue.

---

## 7. IHM — atteindre la qualité de référence

3 leviers qui font 80% du rendu pro :
1. **Police** `KFGQPC HAFS Uthmanic Script`.
2. **Coloration tajwid** depuis l'API (données verset-par-verset).
3. **Layout page-mushaf** + surlignage mot-à-mot synchronisé avec l'audio.

Écrans principaux :
- `Mushaf` (lecture, tajwid, audio, favoris) — le socle.
- `Réciter` (Pilier A — micro, feedback temps réel).
- `Tuteur` (Pilier B — chat Gemma).
- `Réviser` (Pilier C — file FSRS du jour).
- `Progression` (stats, sourates mémorisées).

---

## 8. Feuille de route par phases

### Phase 0 — Socle (pas d'IA)
- Projet Flutter, intégration API Quran + cache SQLite.
- MushafView : texte Uthmani + tajwid + audio + surlignage mot-à-mot.
- ✅ Livrable : une app de lecture du Coran de qualité.

### Phase 1 — ASR (Pilier A) ⭐ priorité
- Intégrer whisper.cpp + modèle Quran GGML.
- Capture micro → reconnaissance → alignement → feedback vert/rouge + score.
- Mode « test de mémorisation ».
- ✅ Livrable : l'utilisateur récite, l'app corrige.

### Phase 2 — Révision (Pilier C)
- Implémenter FSRS, brancher le score ASR.
- Écran « Aujourd'hui ».
- ✅ Livrable : boucle mémorisation complète.

### Phase 3 — Tuteur (Pilier B)
- Construire le dataset, fine-tuner Gemma 3 1B (LoRA → .litertlm).
- Intégrer `flutter_gemma`, chat contextualisé.
- RAG anti-hallucination (cf. §5) : embeddings de requête on-device + retrieval sur le corpus tafsir/hadith déjà construit (209k passages) avant de faire confiance aux réponses en production.
- ✅ Livrable : explications + quiz génératifs, sourcés et vérifiables.

### Phase 4 — Polish
- Stats avancées, gamification (séries, objectifs), thèmes, iOS.

---

## 9. Risques & décisions ouvertes

| Risque | Mitigation |
|---|---|
| ASR peu précis sur récitation rapide/accent | Commencer par justesse des mots, pas le tajwid fin ; tester tôt (Phase 1). |
| Taille app (Gemma 550 MB + Whisper) | Télécharger les modèles **après** install (pas dans l'APK). |
| LLM qui invente du texte coranique | Texte sacré **toujours** depuis SQLite, jamais généré. |
| Qualité dataset tuteur | Sources tafsir reconnues + jugement LLM (cf. skill `detox-dataset-improvement`). |
| LLM qui invente une explication/hadith (au-delà du texte coranique) | RAG sur corpus tafsir/hadith déjà construit (209k passages sourcés) — cf. §5, plan pas encore implémenté. |
| Licences (texte, audio, polices) | KFGQPC + Quran.com = usage gratuit ; vérifier attributions. |

---

## 10. Prochaines actions concrètes

1. **Valider les sources** : créer un compte API Quran Foundation, récupérer la police KFGQPC.
2. **Tester l'ASR tôt** (dé-risquer le Pilier A) : essayer `whisper-base-ar-quran` sur un échantillon de récitation **avant** de coder l'app.
3. **Démarrer Phase 0** : init projet Flutter + affichage mushaf.
