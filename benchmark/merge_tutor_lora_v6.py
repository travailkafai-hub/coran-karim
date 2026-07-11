import torch
from transformers import AutoModelForImageTextToText, AutoTokenizer, AutoProcessor
from peft import PeftModel

BASE = "/mnt/d/Coran Karim/benchmark/models/gemma-4-E2B-it"
LORA = "/mnt/d/Coran Karim/benchmark/models/gemma-4-E2B-tutor-lora-v6"
OUT = "/mnt/d/Coran Karim/benchmark/models/gemma-4-E2B-tutor-v6-merged"

print("Loading base model (bf16, CPU)...", flush=True)
base = AutoModelForImageTextToText.from_pretrained(
    BASE, torch_dtype=torch.bfloat16, device_map="cpu"
)

print("Loading LoRA adapter v6...", flush=True)
model = PeftModel.from_pretrained(base, LORA)

print("Merging...", flush=True)
merged = model.merge_and_unload()

print(f"Saving merged model to {OUT} ...", flush=True)
merged.save_pretrained(OUT, safe_serialization=True)

print("Saving tokenizer/processor...", flush=True)
try:
    proc = AutoProcessor.from_pretrained(LORA)
    proc.save_pretrained(OUT)
except Exception as e:
    print("processor save failed, falling back to tokenizer:", e, flush=True)
    tok = AutoTokenizer.from_pretrained(LORA)
    tok.save_pretrained(OUT)

print("DONE", flush=True)
