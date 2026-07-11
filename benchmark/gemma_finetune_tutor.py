"""LoRA fine-tuning of Gemma 4 E2B as Quran text tutor (NO audio).
Reads gemma_tutor_sft.jsonl (text-only Q&A from tafsir).
Saves to models/gemma-4-E2B-tutor-lora (separate from audio LoRA).

Reprise (GEMMA_RESUME=1) : recharge l'adaptateur LoRA déjà entraîné +
l'état complet (optimiseur, scheduler, step, epoch, exemples restants de
l'époque en cours) depuis training_state.pt dans OUT, pour continuer
exactement là où l'entraînement s'était arrêté plutôt que de repartir
d'un optimiseur/scheduler vierges.
"""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
# Reduit la fragmentation de l'allocateur CUDA (longueurs de sequence tres
# variables ici, sans batching) -> moins de risque d'OOM a memoire nominale
# suffisante mais fragmentee. Doit etre defini AVANT le premier import torch.
os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")
import truststore; truststore.inject_into_ssl()
import sys, json, math, time, random, torch
os.environ["HF_HUB_OFFLINE"] = "1"
from transformers import AutoProcessor, AutoModelForMultimodalLM, get_cosine_schedule_with_warmup
from peft import LoraConfig, get_peft_model, PeftModel

ROOT = os.path.dirname(os.path.abspath(__file__))
M   = os.path.join(ROOT, "models", "gemma-4-E2B-it")
OUT = os.environ.get("GEMMA_OUT", os.path.join(ROOT, "models", "gemma-4-E2B-tutor-lora"))
# SFT dataset : surchargeable via env GEMMA_SFT (defaut = tutor tafsir-only)
SFT = os.environ.get("GEMMA_SFT", os.path.join(ROOT, "data", "gemma_tutor_sft.jsonl"))
MAX_SAMPLES = int(sys.argv[1]) if len(sys.argv) > 1 else 30000
EPOCHS = int(os.environ.get("GEMMA_EPOCHS", 2)); ACCUM = 32; LR = 1e-4; LOG = 50; CKPT_EVERY = 200
MAX_TARGET_TOKENS = int(os.environ.get("GEMMA_MAX_TARGET_TOKENS", 512))  # cap long tafsir answers
MAX_TOTAL_TOKENS = int(os.environ.get("GEMMA_MAX_TOTAL_TOKENS", 1024))  # cap prompt+target combine (system peut aussi etre long)

RESUME = os.environ.get("GEMMA_RESUME", "0") == "1"
STATE_FILE = os.path.join(OUT, "training_state.pt")
ADAPTER_FILE = os.path.join(OUT, "adapter_model.safetensors")

proc = AutoProcessor.from_pretrained(M)
model = AutoModelForMultimodalLM.from_pretrained(M, dtype=torch.bfloat16, device_map="cuda")
model.config.use_cache = False
model.gradient_checkpointing_enable()
model.enable_input_require_grads()

LORA_R = int(os.environ.get("GEMMA_LORA_R", 16))
LORA_ALPHA = int(os.environ.get("GEMMA_LORA_ALPHA", 32))
lora = LoraConfig(
    r=LORA_R, lora_alpha=LORA_ALPHA, lora_dropout=0.05,
    # Le regex '\.linear$' ne matche QUE vision_tower/audio_tower (Gemma4 y enveloppe
    # chaque Linear dans un wrapper .linear) -> zero effet, LoRA jamais applique au
    # texte. Dans ce checkpoint, language_model.*.{q,k,v,o,gate,up,down}_proj sont des
    # nn.Linear direct, SANS suffixe .linear (confirme 2026-07-09 : tous les lora_B
    # restaient a zero apres entrainement, preuve qu'aucun gradient reel n'atteignait
    # le texte). Cibler explicitement language_model corrige ca (205 modules, 35 couches).
    target_modules=r".*language_model.*\.(q_proj|k_proj|v_proj|o_proj|gate_proj|up_proj|down_proj)$",
    task_type="CAUSAL_LM")

has_adapter = RESUME and os.path.exists(ADAPTER_FILE)
has_state = has_adapter and os.path.exists(STATE_FILE)
if has_adapter:
    model = PeftModel.from_pretrained(model, OUT, is_trainable=True)
    if has_state:
        print(f"[Resume] Adaptateur + etat complet (optimiseur/scheduler/step) recharges depuis {OUT}", flush=True)
    else:
        print(f"[Resume] Adaptateur recharge depuis {OUT} (pas d'etat sauvegarde -> "
              f"poids repris, optimiseur/scheduler/step repartent a zero)", flush=True)
else:
    if RESUME:
        print(f"[Resume] Demande mais aucun adaptateur dans {OUT} -> depart a zero", flush=True)
    model = get_peft_model(model, lora)
model.print_trainable_parameters()

rows = [json.loads(l) for l in open(SFT, encoding="utf-8")]
random.seed(42); random.shuffle(rows); rows = rows[:MAX_SAMPLES]
print(f"Training on {len(rows)} examples, {EPOCHS} epoch(s)", flush=True)

def build(ex):
    system = ex.get("system", "")
    user_content = [{"type": "text", "text": ex["user"]}]
    # Truncate target to avoid GPU OOM on very long tafsirs. Chaque target se
    # termine par "\n\n(Source : ...)" / "\n\n(المصدر: ...)" (voir
    # gemma_make_islamic_sft.py) : tronquer aveuglement les N premiers tokens
    # coupait cette citation sur les reponses longues, apprenant au modele a
    # repondre sans source (bug constate 2026-07-08). On isole donc la
    # citation finale et on ne tronque que le contenu qui la precede.
    target = ex["target"]
    cite_idx = target.rfind("\n\n(")
    content, citation = (target[:cite_idx], target[cite_idx:]) if cite_idx != -1 else (target, "")
    content_ids = proc.tokenizer(content, add_special_tokens=False).input_ids
    citation_ids = proc.tokenizer(citation, add_special_tokens=False).input_ids if citation else []
    budget = max(MAX_TARGET_TOKENS - len(citation_ids), 0)
    if len(content_ids) > budget:
        content = proc.tokenizer.decode(content_ids[:budget], skip_special_tokens=True)
    target = content + citation

    msgs = []
    if system:
        msgs.append({"role": "system", "content": [{"type": "text", "text": system}]})
    msgs.append({"role": "user", "content": user_content})
    msgs.append({"role": "assistant", "content": [{"type": "text", "text": target}]})

    full = proc.apply_chat_template(
        msgs, tokenize=True, return_dict=True, return_tensors="pt",
        add_generation_prompt=False)
    prompt_msgs = [m for m in msgs if m["role"] != "assistant"]
    prompt = proc.apply_chat_template(
        prompt_msgs, tokenize=True, return_dict=True, return_tensors="pt",
        add_generation_prompt=True)
    pl = prompt["input_ids"].shape[-1]

    # MAX_TARGET_TOKENS ne borne que la reponse ; le prompt (system+user, ex.
    # long extrait de tafsir en contexte) n'est lui jamais tronque -> une
    # sequence totale demesuree peut quand meme faire OOM (crash reproductible
    # 2026-07-06). On saute simplement l'exemple si la sequence totale depasse
    # un plafond raisonnable, plutot que de la tronquer (recalcul de pl risque).
    if full["input_ids"].shape[-1] > MAX_TOTAL_TOKENS:
        return None

    enc = {k: (v.to("cuda") if hasattr(v, "to") else v) for k, v in full.items()}
    lab = enc["input_ids"].clone()
    lab[:, :pl] = -100  # mask prompt tokens, only train on assistant output
    enc["labels"] = lab
    return enc

opt = torch.optim.AdamW(
    [p for p in model.parameters() if p.requires_grad], lr=LR, weight_decay=0.01)
total = math.ceil(len(rows) / ACCUM) * EPOCHS
sched = get_cosine_schedule_with_warmup(opt, int(0.05 * total), total)

model.train(); step = 0; run = 0.0; t0 = time.time()
start_ep = 0
resume_rows = None
if has_state:
    state = torch.load(STATE_FILE, map_location="cuda")
    opt.load_state_dict(state["optimizer"])
    sched.load_state_dict(state["scheduler"])
    step = state["step"]
    start_ep = state["epoch"]
    resume_rows = state["remaining_rows"]
    t0 = time.time() - state["elapsed"]
    print(f"[Resume] step={step}/{total} epoch={start_ep+1} "
          f"exemples restants dans l'epoque={len(resume_rows)}", flush=True)

oom_count = 0
ok_count = 0
for ep in range(start_ep, EPOCHS):
    if resume_rows is not None:
        epoch_rows = resume_rows
        resume_rows = None
    else:
        random.shuffle(rows)
        epoch_rows = list(rows)
    for i, ex in enumerate(epoch_rows):
        try:
            enc = build(ex)
            if enc is None:
                continue
            loss = model(**enc).loss / ACCUM
            loss.backward()
            run += loss.item() * ACCUM
            ok_count += 1
        except Exception as e:
            # Attrape large sur le MESSAGE plutot que la classe d'exception :
            # deja vu torch.cuda.OutOfMemoryError ET torch.AcceleratorError
            # pour le meme OOM CUDA selon le point du code touche (2026-07-06,
            # crash reproductible 2x au meme endroit apres reprise) -> filtrer
            # sur classe exacte est fragile, on filtre sur le texte du message.
            if "out of memory" not in str(e).lower():
                raise
            opt.zero_grad(set_to_none=True)
            torch.cuda.empty_cache()
            oom_count += 1
            # Visibilite immediate : sans ca, un OOM sur QUASIMENT CHAQUE exemple
            # (ex: mauvais dimensionnement memoire apres un changement de rang/cible
            # LoRA) passe inapercu jusqu'a la fin du run -> aucun step logge, aucun
            # checkpoint, adaptateur final reste a son init aleatoire (constate
            # 2026-07-09). Le ratio oom/(oom+ok) alerte des les 100 premiers exemples.
            if oom_count % 50 == 0:
                print(f"  [ALERTE] {oom_count} OOM / {oom_count+ok_count} exemples "
                      f"tentes (ok={ok_count}) -- si ok reste ~0, reduire "
                      f"GEMMA_LORA_R / GEMMA_MAX_TOTAL_TOKENS", flush=True)
            continue
        if (i + 1) % ACCUM == 0:
            torch.nn.utils.clip_grad_norm_(
                [p for p in model.parameters() if p.requires_grad], 1.0)
            opt.step(); sched.step(); opt.zero_grad(); step += 1
            if step % LOG == 0:
                el = time.time() - t0
                print(f"ep{ep+1} step {step}/{total} loss={run/(LOG*ACCUM):.3f} "
                      f"lr={sched.get_last_lr()[0]:.2e} {el/60:.1f}min "
                      f"vram={torch.cuda.max_memory_allocated()/1e9:.1f}GB", flush=True)
                run = 0.0
            if step % CKPT_EVERY == 0:
                model.save_pretrained(OUT)
                proc.save_pretrained(OUT)
                torch.save({
                    "optimizer": opt.state_dict(),
                    "scheduler": sched.state_dict(),
                    "step": step,
                    "epoch": ep,
                    "remaining_rows": epoch_rows[i + 1:],
                    "elapsed": time.time() - t0,
                }, STATE_FILE)
                print(f"  [checkpoint sauvegarde -> {OUT} @ step {step}]", flush=True)

model.save_pretrained(OUT)
proc.save_pretrained(OUT)
print("GEMMA TUTOR LORA DONE ->", OUT, flush=True)
