# Plan — Réentraîner le Coach IA en QAT (Quantization-Aware Training)

> Objectif : corriger la dégénérescence en répétition observée sur `tutor-v6`
> (cohérent sur la 1ère phrase, puis boucle) en fine-tunant directement en
> connaissance de la quantification INT4 cible, au lieu de fine-tuner en pleine
> précision puis quantifier après coup (ce qu'on a fait pour v6).
>
> À exécuter par l'utilisateur dans un environnement Unix (WSL/Linux) — ce
> document ne fait que préparer le plan, l'entraînement n'a pas été lancé.

---

## 1. Pourquoi (diagnostic)

- `tutor-v6` fine-tuné en bf16 pleine précision, puis quantifié post-training
  (PTQ) via `litert-torch export_hf --quantization_recipe=dynamic_wi4_afp32`.
- Test CPU pré-quantification (bf16, `transformers.generate()`) : réponses
  cohérentes de bout en bout, pas de répétition.
- Sur l'appareil (`.litertlm` INT4) : dégénérescence quasi systématique après
  1-3 phrases, quels que soient le prompt (proche ou non de la distribution
  d'entraînement) ou les paramètres d'échantillonnage (glouton, ou
  `topK=40/topP=0.9/temp=0.7`).
- Palliatif déjà en place côté app (`TutorLlmService._truncateToFirstParagraph`,
  cf. `app/lib/services/tutor_llm_service.dart`) : coupe la réponse au premier
  paragraphe, avant que la boucle ne s'installe. **Ça règle l'UX immédiatement,
  mais ce n'est pas une correction de la cause.**
- Cause probable : le delta LoRA (rang 16) appris en pleine précision ne
  "survit" pas bien à l'arrondi INT4 — écart documenté en ML. Le QAT (charger
  le modèle en 4-bit *pendant* l'entraînement, pas seulement à l'export) laisse
  l'adaptateur apprendre à compenser le bruit de quantification.

## 2. Référence : ça a déjà marché ailleurs sur ce compte

Projet `E:\RECUP_EMTEC\Projet Harcelement\detox\finetune\` — Gemma **3 1B**
détox, résultats jugés bons en réel ("0 hallucination" sur données TikTok
réelles). Scripts clés (à lire avant de commencer, ils contiennent tous les
détails d'implémentation) :
- `finetune_qat.py` — le fine-tuning QAT lui-même (QLoRA NF4 via bitsandbytes).
- `merge_qat.py` — fusion du LoRA appris-en-4-bit dans une copie fp16 fraîche
  (on NE fusionne PAS depuis le modèle chargé en 4-bit).
- `eval_int4_sim.py` — mesure la perte réelle due à la quantif en simulant
  `dynamic_int4_block32` en PyTorch (fake-quant) sur tous les `Linear`/
  `Embedding`, à comparer au modèle float (référence notée : 96,2 %).
- `convert_native_int4_v2.py` / `_v3.py` — itérations de la conversion finale.

Même symptôme déjà rencontré et noté par le passé sur leur Gemma 3 1B
**zero-shot** (avant tout fine-tuning) : *"hallucinations après la première
phrase (junk tokens)... couper à la première phrase terminée suffit"* — cf.
mémoire `project_detox_module` (`C:\Users\Adam\.claude\projects\d--Projet-Harcelement\memory\`).

## 3. Différences à gérer pour l'adapter à notre cas (Gemma 4 E2B, pas Gemma 3 1B)

⚠️ Ce ne sont **pas** des détails cosmétiques — ce sont des pièges déjà
rencontrés une fois sur ce projet (v6 lui-même a été cassé par le premier au
départ) :

1. **Classe de modèle** : Gemma 4 E2B est multimodal → charger avec
   `AutoModelForMultimodalLM` (pas `AutoModelForCausalLM` comme dans
   `finetune_qat.py`, qui vise Gemma 3 1B, un modèle texte pur). Vérifier que
   `BitsAndBytesConfig` + `prepare_model_for_kbit_training` fonctionnent bien
   avec cette classe — **pas garanti, à valider en premier** (risque
   d'incompatibilité entre bitsandbytes et le wrapper multimodal).
2. **`target_modules` du LoRA** — piège déjà vécu sur v6 : le regex simple
   `["q_proj","k_proj","v_proj","o_proj","gate_proj","up_proj","down_proj"]`
   utilisé par Harcèlement (Gemma 3, `nn.Linear` direct) **ne fonctionne PAS**
   sur Gemma 4 E2B tel quel. Il faut le regex ciblant explicitement le texte :
   ```python
   target_modules=r".*language_model.*\.(q_proj|k_proj|v_proj|o_proj|gate_proj|up_proj|down_proj)$"
   ```
   (cf. commentaire dans `benchmark/gemma_finetune_tutor.py` : sans ce préfixe,
   tous les `lora_B` restent à zéro après l'entraînement — aucun gradient
   n'atteint le texte, constaté le 2026-07-09).
3. **Dataset** : réutiliser `benchmark/data/gemma_tutor_sft.jsonl` tel quel
   (même prompts « Je mémorise le Coran... » / « Quel est le sens du
   verset... » / « Traduis... » / « ما معنى الآية... » / « فسِّر الآية... »).
4. **Base model** : `benchmark/models/gemma-4-E2B-it` (déjà en local, pas
   besoin de retélécharger).

## 4. Environnement (Unix/WSL)

Un venv de conversion existe déjà (`~/venv_convert`, utilisé pour l'export
`tutor-v6`) mais **pas pour l'entraînement** — il n'a ni `bitsandbytes`, ni
`trl`, ni GPU-facing training deps. Créer un venv dédié à l'entraînement (ou
réutiliser celui qui a servi pour `gemma_finetune_tutor.py` s'il existe déjà) :

```bash
python3 -m venv ~/venv_qat
source ~/venv_qat/bin/activate
pip install torch transformers peft trl bitsandbytes accelerate datasets truststore
```

Vérifier `bitsandbytes` (nécessite CUDA) :
```bash
python3 -c "import bitsandbytes; print(bitsandbytes.__version__)"
```

## 5. Script adapté — squelette

Base : `finetune_qat.py` (Harcèlement) + `benchmark/gemma_finetune_tutor.py`
(notre chargement Gemma4 + dataset + gabarits de prompt). À écrire comme
`benchmark/gemma_finetune_tutor_qat.py` :

```python
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
import torch, json, random
from transformers import AutoProcessor, AutoModelForMultimodalLM, BitsAndBytesConfig
from peft import LoraConfig, get_peft_model, TaskType, prepare_model_for_kbit_training
from trl import SFTTrainer, SFTConfig

ROOT = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.join(ROOT, "models", "gemma-4-E2B-it")
SFT  = os.path.join(ROOT, "data", "gemma_tutor_sft.jsonl")
OUT  = os.path.join(ROOT, "models", "gemma-4-E2B-tutor-qat-lora")

proc = AutoProcessor.from_pretrained(BASE)

# --- ETAPE A VALIDER EN PREMIER : bitsandbytes + AutoModelForMultimodalLM ---
bnb_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_quant_type="nf4",
    bnb_4bit_compute_dtype=torch.float16,
    bnb_4bit_use_double_quant=False,  # rester proche de dynamic_wi4_afp32 (pas de double quant)
)
model = AutoModelForMultimodalLM.from_pretrained(
    BASE, quantization_config=bnb_config, device_map="auto",
    dtype=torch.float16, trust_remote_code=True,
)
model = prepare_model_for_kbit_training(model, use_gradient_checkpointing=True)

lora = LoraConfig(
    r=128, lora_alpha=256, lora_dropout=0.05,  # r=128 (vs 16 pour le fix PTQ v6) : plus de
    # capacite pour l'adaptateur, decide pour ce run QAT afin de mieux compenser le bruit
    # de quantification INT4. alpha garde le ratio alpha/r=2 du run v6 (memes proportions
    # d'echelle effective de l'adaptation) — a ajuster si l'entrainement ne converge pas
    # comme attendu avec ce ratio.
    target_modules=r".*language_model.*\.(q_proj|k_proj|v_proj|o_proj|gate_proj|up_proj|down_proj)$",
    task_type=TaskType.CAUSAL_LM,
)
model = get_peft_model(model, lora)
model.print_trainable_parameters()  # vérifier trainable% > 0 avant de lancer pour de bon

# --- Dataset : mêmes gabarits que tutor-v6 (voir gemma_finetune_tutor.py::build) ---
rows = [json.loads(l) for l in open(SFT, encoding="utf-8")]
random.seed(42); random.shuffle(rows)
# construire les exemples au format chat Gemma4 (system/user/assistant) comme
# dans gemma_finetune_tutor.py, PUIS les convertir en champ "text" pour SFTTrainer
# (proc.apply_chat_template(...) par exemple)

sft_config = SFTConfig(
    output_dir=OUT,
    num_train_epochs=2,          # v6 = 2 epochs, garder pour comparer à qualité égale
    per_device_train_batch_size=8,
    gradient_accumulation_steps=4,
    learning_rate=1e-4,           # v6 = 1e-4, garder identique (Harcelement utilisait 2e-4 mais sur un modele/dataset different)
    bf16=False, fp16=True,        # compute_dtype=float16 ci-dessus -> cohérent
    logging_steps=50,
    save_strategy="epoch",
    warmup_ratio=0.05,
    max_length=1024,              # cf. MAX_TOTAL_TOKENS de gemma_finetune_tutor.py
    dataset_text_field="text",
    packing=False,
)
trainer = SFTTrainer(model=model, args=sft_config, train_dataset=..., processing_class=proc.tokenizer)
trainer.train()
trainer.save_model(OUT)
```

**Points ouverts à trancher pendant l'implémentation** (pas de réponse ferme
ici, à décider en observant les premiers logs) :
- `num_train_epochs=2` et `lr=1e-4` copiés de v6 pour comparer à effort de
  training égal — mais QAT converge parfois différemment ; surveiller
  `eval_loss` et ajuster si besoin.
- Si `AutoModelForMultimodalLM` + `BitsAndBytesConfig` échoue (incompatibilité
  probable, jamais testée) : replier sur un chargement manuel du seul
  sous-module `language_model` en 4-bit, ou abandonner QAT pour Gemma 4 E2B et
  se rabattre sur une meilleure PTQ (INT8 au lieu de INT4, cf. §7).

## 6. Après l'entraînement

1. **Fusionner** (comme `merge_qat.py`) : recharger la base en fp16 **fraîche**
   (pas la copie 4-bit d'entraînement), appliquer le LoRA QAT, merger, sauver
   en safetensors — même procédure que `merge_tutor_lora_v6.py` déjà utilisé
   cette session (`D:\Coran Karim\benchmark\merge_tutor_lora_v6.py`), juste
   pointer vers le nouveau dossier LoRA.
2. **Exporter en `.litertlm`** : réutiliser exactement la même commande qui a
   fonctionné pour v6 (rien à changer ici) :
   ```bash
   litert-torch export_hf <merged_qat_dir> <output_dir> \
     --task=text_generation \
     --quantization_recipe=dynamic_wi4_afp32 \
     --bundle_litert_lm=True \
     --externalize_embedder=True \
     --jinja_chat_template_override=litert-community/gemma-4-E2B-it-litert-lm
   ```
   (le `--jinja_chat_template_override` est **obligatoire** — sans lui,
   l'export utilise le template maison du LoRA, qui contient des `map.get()`
   non supportés par LiteRT-LM → `Failed to start streaming (code: 13)`,
   bug rencontré et corrigé cette session, cf. google-ai-edge/LiteRT-LM#2078).
3. **Valider avant de déployer** : comparer la sortie sur quelques prompts
   (même méthode que `sanity_check_tutor_v6.py` de cette session) — la
   dégénérescence en répétition devrait être nettement réduite ou absente.
   Optionnel mais recommandé : adapter `eval_int4_sim.py` (fake-quant PyTorch)
   pour mesurer objectivement la perte, comme fait Harcèlement.

## 7. Repli si QAT échoue ou n'est pas concluant

- **INT8 au lieu de INT4** : `--quantization_recipe=dynamic_wi8_afp32` (le
  défaut de `litert-torch`, ~2x plus gros, ~5 Go au lieu de 2,5 Go) sur le
  **même LoRA v6 déjà entraîné** (pas besoin de réentraîner) — test rapide
  pour confirmer si la précision de quantification est bien la variable
  déterminante, avant d'investir dans un réentraînement complet.
- Garder la troncature côté app (`_truncateToFirstParagraph`) dans tous les
  cas — filet de sécurité peu coûteux, indépendant de la qualité du modèle.

## 8. Fichiers pertinents (récap rapide)

| Fichier | Rôle |
|---|---|
| `benchmark/gemma_finetune_tutor.py` | Entraînement v6 actuel (PTQ), référence pour le chargement Gemma4/dataset |
| `benchmark/merge_tutor_lora_v6.py` | Script de fusion LoRA→base utilisé cette session |
| `benchmark/data/gemma_tutor_sft.jsonl` | Dataset SFT (à réutiliser tel quel) |
| `app/lib/services/tutor_llm_service.dart` | Service Flutter, contient le palliatif de troncature + les gabarits de prompt exacts à respecter |
| `E:\RECUP_EMTEC\Projet Harcelement\detox\finetune\finetune_qat.py` | Référence QAT qui a fonctionné (Gemma 3 1B) |
| `E:\RECUP_EMTEC\Projet Harcelement\detox\finetune\merge_qat.py` | Référence fusion post-QAT |
| `E:\RECUP_EMTEC\Projet Harcelement\detox\finetune\eval_int4_sim.py` | Référence mesure objective de la perte INT4 |
