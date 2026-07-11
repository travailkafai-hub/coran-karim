import torch
from transformers import AutoModelForImageTextToText, AutoTokenizer

MERGED = "/mnt/d/Coran Karim/benchmark/models/gemma-4-E2B-tutor-v6-merged"

print("Loading merged model (bf16, CPU) for sanity check...", flush=True)
model = AutoModelForImageTextToText.from_pretrained(
    MERGED, torch_dtype=torch.bfloat16, device_map="cpu"
)
tok = AutoTokenizer.from_pretrained(MERGED)

system = (
    "Tu es un tuteur spécialisé en mémorisation et compréhension du Coran. "
    "Tu aides les apprenants francophones à comprendre le sens des versets, "
    "leur contexte et leur portée spirituelle. Tes réponses sont précises, "
    "bienveillantes et pédagogiques."
)
user = (
    "Je mémorise le Coran. Explique-moi en français le verset 1:5 :\n"
    "إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ"
)

messages = [
    {"role": "system", "content": system},
    {"role": "user", "content": user},
]
inputs = tok.apply_chat_template(
    messages, add_generation_prompt=True, return_tensors="pt", return_dict=True
)

print("Generating (CPU, this can take a few minutes)...", flush=True)
with torch.no_grad():
    out = model.generate(**inputs, max_new_tokens=150, do_sample=False)

text = tok.decode(out[0][inputs["input_ids"].shape[1]:], skip_special_tokens=True)
print("=" * 20, "RESPONSE", "=" * 20, flush=True)
print(text, flush=True)
print("DONE", flush=True)
