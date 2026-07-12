"""QAT (Quantization-Aware Training) LoRA fine-tuning of Gemma 4 E2B as Quran
tafsir tutor — cf. QAT_TRAINING_PLAN.md pour le diagnostic complet.

Difference cle avec gemma_finetune_tutor.py (fix PTQ, deja entraine/deploye
en v6) : le modele de base est charge en 4-bit (bitsandbytes NF4) PENDANT
l'entrainement, pas seulement a l'export. L'adaptateur LoRA apprend ainsi
directement a compenser le bruit de quantification INT4, au lieu d'etre
appris en pleine precision puis quantifie a part (ce qui degenerait en
repetition sur le modele deploye .litertlm, cf. plan).

Reste identique au script v6 (deja valide en prod, ne pas re-decouvrir ces
lecons) : chat template Gemma4, masquage prompt (-100), troncature qui
preserve la citation finale, gestion OOM avec alerte, checkpoint + etat
optimiseur/scheduler complet pour reprise (GEMMA_RESUME=1).

Venv requis : .venv_nemotron (transformers 5.13.0.dev0 -> AutoModelForMultimodalLM
existe ; .venv principal a un transformers trop vieux pour Gemma4, et
bitsandbytes/trl y sont installes mais inutiles ici). bitsandbytes+trl
installes dans .venv_nemotron le 2026-07-11 specifiquement pour ce script.
Valide au prealable via validate_qat_setup.py (205 modules matches, tous
dans 'language_model', 193M params entrainables sur 5.3B -> OK, pas de
repli sur vision/audio_tower comme le bug initial de v6).
"""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")
import truststore; truststore.inject_into_ssl()
import sys, json, math, time, random, torch
os.environ["HF_HUB_OFFLINE"] = "1"
from transformers import AutoProcessor, AutoModelForMultimodalLM, BitsAndBytesConfig, get_cosine_schedule_with_warmup
from peft import LoraConfig, get_peft_model, PeftModel, prepare_model_for_kbit_training

ROOT = os.path.dirname(os.path.abspath(__file__))
M   = os.path.join(ROOT, "models", "gemma-4-E2B-it")
OUT = os.environ.get("GEMMA_OUT", os.path.join(ROOT, "models", "gemma-4-E2B-tutor-qat-lora"))
# Dataset : par defaut le dataset tafsir enrichi (focus explication du Coran,
# AR+FR+EN, hadith exclu) plutot que gemma_tutor_sft.jsonl du plan d'origine
# (ecrit avant ce recentrage) -- surchargeable via GEMMA_SFT si besoin.
SFT = os.environ.get("GEMMA_SFT", os.path.join(ROOT, "data", "gemma_islamic_sft_v2.jsonl"))
MAX_SAMPLES = int(sys.argv[1]) if len(sys.argv) > 1 else 30000
EPOCHS = int(os.environ.get("GEMMA_EPOCHS", 2)); ACCUM = 32; LR = 1e-4; LOG = 50; CKPT_EVERY = 200
MAX_TARGET_TOKENS = int(os.environ.get("GEMMA_MAX_TARGET_TOKENS", 512))
MAX_TOTAL_TOKENS = int(os.environ.get("GEMMA_MAX_TOTAL_TOKENS", 1024))

RESUME = os.environ.get("GEMMA_RESUME", "0") == "1"
STATE_FILE = os.path.join(OUT, "training_state.pt")
ADAPTER_FILE = os.path.join(OUT, "adapter_model.safetensors")

proc = AutoProcessor.from_pretrained(M)

bnb_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_quant_type="nf4",
    bnb_4bit_compute_dtype=torch.float16,
    bnb_4bit_use_double_quant=False,  # rester proche de dynamic_wi4_afp32 (pas de double quant)
)
model = AutoModelForMultimodalLM.from_pretrained(
    M, quantization_config=bnb_config, device_map="auto", dtype=torch.float16,
)
model.config.use_cache = False
model = prepare_model_for_kbit_training(model, use_gradient_checkpointing=True)

LORA_R = int(os.environ.get("GEMMA_LORA_R", 128))
LORA_ALPHA = int(os.environ.get("GEMMA_LORA_ALPHA", 256))
lora = LoraConfig(
    r=LORA_R, lora_alpha=LORA_ALPHA, lora_dropout=0.05,
    # meme regex que le fix v6 (confirme 2026-07-09) : language_model.*.{q,k,v,o,gate,up,down}_proj
    # sont des nn.Linear direct, sans suffixe .linear (seuls vision/audio_tower l'ont).
    target_modules=r".*language_model.*\.(q_proj|k_proj|v_proj|o_proj|gate_proj|up_proj|down_proj)$",
    task_type="CAUSAL_LM")

has_adapter = RESUME and os.path.exists(ADAPTER_FILE)
has_state = has_adapter and os.path.exists(STATE_FILE)
if has_adapter:
    model = PeftModel.from_pretrained(model, OUT, is_trainable=True)
    if has_state:
        print(f"[Resume] Adaptateur + etat complet recharges depuis {OUT}", flush=True)
    else:
        print(f"[Resume] Adaptateur recharge depuis {OUT} (pas d'etat sauvegarde)", flush=True)
else:
    if RESUME:
        print(f"[Resume] Demande mais aucun adaptateur dans {OUT} -> depart a zero", flush=True)
    model = get_peft_model(model, lora)
model.print_trainable_parameters()

rows = [json.loads(l) for l in open(SFT, encoding="utf-8")]
random.seed(42); random.shuffle(rows); rows = rows[:MAX_SAMPLES]
print(f"Training on {len(rows)} examples, {EPOCHS} epoch(s), r={LORA_R} alpha={LORA_ALPHA}", flush=True)

def build(ex):
    system = ex.get("system", "")
    user_content = [{"type": "text", "text": ex["user"]}]
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

    if full["input_ids"].shape[-1] > MAX_TOTAL_TOKENS:
        return None

    enc = {k: (v.to("cuda") if hasattr(v, "to") else v) for k, v in full.items()}
    lab = enc["input_ids"].clone()
    lab[:, :pl] = -100
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
            if "out of memory" not in str(e).lower():
                raise
            opt.zero_grad(set_to_none=True)
            torch.cuda.empty_cache()
            oom_count += 1
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
print("GEMMA TUTOR QAT LORA DONE ->", OUT, flush=True)
