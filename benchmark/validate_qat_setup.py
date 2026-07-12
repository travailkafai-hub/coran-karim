"""Valide l'ETAPE A RISQUE du plan QAT avant de lancer un vrai training :
bitsandbytes (4-bit) + AutoModelForMultimodalLM (Gemma4) + LoRA r=128 sur
target_modules language_model. Si ca charge et que les modules matches
couvrent bien 'language_model' (pas seulement vision/audio_tower), on peut
lancer le vrai script en confiance.
"""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
import truststore; truststore.inject_into_ssl()
import re, torch
from transformers import AutoModelForMultimodalLM, BitsAndBytesConfig
from peft import LoraConfig, get_peft_model, TaskType, prepare_model_for_kbit_training

ROOT = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.join(ROOT, "models", "gemma-4-E2B-it")

print("Chargement 4-bit (bitsandbytes NF4)...", flush=True)
bnb_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_quant_type="nf4",
    bnb_4bit_compute_dtype=torch.float16,
    bnb_4bit_use_double_quant=False,
)
model = AutoModelForMultimodalLM.from_pretrained(
    BASE, quantization_config=bnb_config, device_map="auto",
    dtype=torch.float16,
)
print("OK: modele charge en 4-bit.", flush=True)

model = prepare_model_for_kbit_training(model, use_gradient_checkpointing=True)
print("OK: prepare_model_for_kbit_training.", flush=True)

pattern = re.compile(r".*language_model.*\.(q_proj|k_proj|v_proj|o_proj|gate_proj|up_proj|down_proj)$")
matches = [(n, type(m).__name__) for n, m in model.named_modules() if pattern.match(n)]
branches = {n.split(".")[1] if "." in n else n for n, _ in matches}
print(f"Modules matches par le regex : {len(matches)}", flush=True)
print(f"Branches touchees : {branches}", flush=True)
assert len(matches) > 0, "AUCUN module matche par le regex -> LoRA sera un no-op (bug deja vu sur v6)"
assert any("language_model" in n for n, _ in matches), "Le regex ne touche PAS language_model -> no-op garanti"

lora = LoraConfig(
    r=128, lora_alpha=256, lora_dropout=0.05,
    target_modules=pattern.pattern,
    task_type=TaskType.CAUSAL_LM,
)
model = get_peft_model(model, lora)
model.print_trainable_parameters()
print("VALIDATION OK - pret pour le vrai training QAT", flush=True)
