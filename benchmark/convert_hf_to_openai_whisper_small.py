"""Convertit whisper-small-ft (HuggingFace) -> format OpenAI (.pt) pour export GGML.
Meme logique que convert_hf_to_openai_whisper.py, dimensions adaptees a small.
Sortie: ./small-aishell.pt
"""
import torch, whisper
from whisper.model import Whisper, ModelDimensions
from safetensors.torch import load_file

HF = "models/whisper-small-ft/model.safetensors"
OUT = "small-aishell.pt"

# Dimensions Whisper small (multilingue, 80 mels)
dims = ModelDimensions(
    n_mels=80, n_audio_ctx=1500, n_audio_state=768, n_audio_head=12, n_audio_layer=12,
    n_vocab=51865, n_text_ctx=448, n_text_state=768, n_text_head=12, n_text_layer=12,
)

MAP = {
    "blocks": "layers", "mlp.0": "fc1", "mlp.2": "fc2", "mlp_ln": "final_layer_norm",
    ".attn.query": ".self_attn.q_proj", ".attn.key": ".self_attn.k_proj",
    ".attn.value": ".self_attn.v_proj", ".attn_ln": ".self_attn_layer_norm",
    ".attn.out": ".self_attn.out_proj",
    ".cross_attn.query": ".encoder_attn.q_proj", ".cross_attn.key": ".encoder_attn.k_proj",
    ".cross_attn.value": ".encoder_attn.v_proj", ".cross_attn_ln": ".encoder_attn_layer_norm",
    ".cross_attn.out": ".encoder_attn.out_proj",
    "decoder.ln.": "decoder.layer_norm.", "encoder.ln.": "encoder.layer_norm.",
    "token_embedding": "embed_tokens",
    "encoder.positional_embedding": "encoder.embed_positions.weight",
    "decoder.positional_embedding": "decoder.embed_positions.weight",
    "ln_post": "layer_norm",
}

def oai_to_hf(key: str) -> str:
    for k, v in MAP.items():
        if k in key:
            key = key.replace(k, v)
    return "model." + key

print("Chargement HF safetensors...", flush=True)
hf = load_file(HF)
print(f"  {len(hf)} tenseurs HF", flush=True)

print("Construction squelette OpenAI...", flush=True)
skel = Whisper(dims)
oai_sd = skel.state_dict()

new_sd, missing = {}, []
for oai_key in oai_sd:
    hf_key = oai_to_hf(oai_key)
    if hf_key in hf:
        t = hf[hf_key]
        if t.shape != oai_sd[oai_key].shape:
            missing.append(f"{oai_key} SHAPE {tuple(t.shape)} != {tuple(oai_sd[oai_key].shape)} (hf={hf_key})")
        else:
            new_sd[oai_key] = t
    else:
        missing.append(f"{oai_key}  ->(introuvable) {hf_key}")

if missing:
    print(f"!!! {len(missing)} cles non resolues :", flush=True)
    for m in missing[:40]:
        print("   ", m, flush=True)
    raise SystemExit("Conversion incomplete — abandon.")

skel.load_state_dict(new_sd, strict=True)
print("load_state_dict strict OK (toutes les cles matchent).", flush=True)

torch.save({"dims": dims.__dict__, "model_state_dict": new_sd}, OUT)
print(f"Sauvegarde -> {OUT}", flush=True)
