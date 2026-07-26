"""
Valide que l'ONNX streaming (fastconformer_ctc_streaming.onnx) produit EXACTEMENT
la meme sortie que l'encodeur PyTorch natif, chunk par chunk, avec le cache qui
persiste d'un appel au suivant -- c'est la vraie question de fidelite pour le
streaming (pas juste "un appel isole marche", mais "la chaine de plusieurs
appels avec cache transmis reste coherente").

MISE A JOUR 2026-07-26 : la version d'origine validait la tentative PCD non
causale en forcant [70,1]. Elle est conservee dans l'historique Git, mais ce
validateur cible desormais le checkpoint causal entraine et son contexte
[70,13], sans mutation de configuration.
"""
import os, json
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

import torch, numpy as np, onnxruntime as ort
import nemo.collections.asr as nemo_asr
from pathlib import Path

BASE_DIR = Path(__file__).parent
NEMO_PATH = BASE_DIR / "models" / "fastconformer-streaming-causal-v1-lr3e4" / "causal-final.nemo"
ONNX_PATH = NEMO_PATH.parent / "deploy" / "fastconformer-ctc-causal-v1" / "model_streaming.onnx"
VAL_MANIFEST = BASE_DIR / "nemo_manifests_dual" / "val_manifest.jsonl"

model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(NEMO_PATH), map_location="cpu")
model.eval()
enc = model.encoder
if enc.att_context_style != "chunked_limited" or list(enc.att_context_size) != [70, 13]:
    raise RuntimeError(
        f"checkpoint inattendu : {enc.att_context_style=} {enc.att_context_size=}"
    )
enc.export_cache_support = True
enc.setup_streaming_params()
cfg = enc.streaming_cfg
print("streaming_cfg:", cfg)

chunk_size = cfg.chunk_size[1] if isinstance(cfg.chunk_size, list) else cfg.chunk_size
pre_cache = cfg.pre_encode_cache_size[1] if isinstance(cfg.pre_encode_cache_size, list) else cfg.pre_encode_cache_size
window = chunk_size + pre_cache
print(f"chunk_size={chunk_size} pre_cache={pre_cache} window={window}")

# Vrai audio -> mel features (via le preprocesseur NeMo, deja valide ailleurs)
rows = [json.loads(l) for l in open(VAL_MANIFEST, encoding="utf-8")]
r = next(
    row for row in rows
    if float(row.get("duration", 0)) >= 5.0 and Path(row["audio_filepath"]).exists()
)
import soundfile as sf
audio_np, sr = sf.read(r["audio_filepath"], dtype="float32")
audio_t = torch.tensor(audio_np).unsqueeze(0)
len_t = torch.tensor([audio_np.shape[0]])
with torch.no_grad():
    feats, feats_len = model.preprocessor(input_signal=audio_t, length=len_t)
print("feats shape:", feats.shape, "text:", r["text"][:60])

sess = ort.InferenceSession(str(ONNX_PATH), providers=["CPUExecutionProvider"])

# Etat initial (PyTorch ET onnx demarrent avec le meme etat)
cache_ch, cache_t, cache_len = enc.get_initial_cache_state(batch_size=1)
cache_ch = cache_ch.transpose(0, 1)  # (B, layers, ...) convention externe
cache_t = cache_t.transpose(0, 1)

onnx_cache_ch = cache_ch.numpy().astype(np.float32)
onnx_cache_t = cache_t.numpy().astype(np.float32)
onnx_cache_len = cache_len.numpy().astype(np.int64)

T = feats.shape[-1]
n_chunks = 0
max_diff_overall = 0.0
pos = 0
# Premiere fenetre a besoin de pre_cache frames de "silence" avant les vraies donnees
# (comme le fait le vrai streaming buffer NeMo au demarrage) -- on simplifie ici en
# testant seulement quelques chunks consecutifs a partir du debut du signal, en
# zero-paddant le debut pour avoir une fenetre complete des le 1er appel.
padded = torch.nn.functional.pad(feats, (pre_cache, 0))
pt_chunks = []
onnx_chunks = []

while pos + window <= padded.shape[-1] and n_chunks < 5:
    chunk = padded[:, :, pos:pos+window]
    chunk_len = torch.tensor([window])

    with torch.no_grad():
        pt_encoded, pt_encoded_len, pt_cache_ch_next, pt_cache_t_next, pt_cache_len_next = enc(
            audio_signal=chunk, length=chunk_len,
            cache_last_channel=cache_ch.transpose(0,1),
            cache_last_time=cache_t.transpose(0,1),
            cache_last_channel_len=cache_len,
        )
        pt_logits = model.ctc_decoder(encoder_output=pt_encoded)
        pt_logprobs = torch.nn.functional.log_softmax(pt_logits, dim=-1).numpy()

    onnx_out = sess.run(None, {
        "audio_signal": chunk.numpy().astype(np.float32),
        "length": chunk_len.numpy().astype(np.int64),
        "cache_last_channel": onnx_cache_ch,
        "cache_last_time": onnx_cache_t,
        "cache_last_channel_len": onnx_cache_len,
    })
    onnx_logprobs, onnx_cache_ch_next, onnx_cache_t_next, onnx_cache_len_next = onnx_out
    pt_chunks.append(pt_logprobs)
    onnx_chunks.append(onnx_logprobs)

    diff = np.abs(pt_logprobs - onnx_logprobs).max()
    max_diff_overall = max(max_diff_overall, diff)
    print(f"chunk {n_chunks}: pt_logprobs shape={pt_logprobs.shape} max_diff={diff:.6f}")

    # avancer l'etat (PyTorch cote reference, onnx cote test) independamment
    cache_ch, cache_t, cache_len = pt_cache_ch_next.transpose(0,1), pt_cache_t_next.transpose(0,1), pt_cache_len_next
    onnx_cache_ch, onnx_cache_t, onnx_cache_len = onnx_cache_ch_next, onnx_cache_t_next, onnx_cache_len_next

    pos += chunk_size
    n_chunks += 1

print(f"\n=== Max diff sur {n_chunks} chunks consecutifs (cache transmis) : {max_diff_overall:.6f} ===")
if n_chunks < 3:
    raise RuntimeError(f"clip trop court pour valider la chaine : {n_chunks} chunks")
if max_diff_overall >= 1e-3:
    raise RuntimeError(f"divergence significative : {max_diff_overall}")


def greedy_decode(chunks):
    logprobs = np.concatenate(chunks, axis=1)
    ids = logprobs[0].argmax(axis=-1)
    collapsed = []
    prev = -1
    blank = logprobs.shape[-1] - 1
    for token in ids:
        token = int(token)
        if token != prev and token != blank:
            collapsed.append(token)
        prev = token
    return model.tokenizer.ids_to_text(collapsed)


pt_text = greedy_decode(pt_chunks)
onnx_text = greedy_decode(onnx_chunks)
print("PyTorch :", pt_text)
print("ONNX    :", onnx_text)
if pt_text != onnx_text:
    raise RuntimeError("le decodage PyTorch et ONNX diverge")
if not onnx_text.strip():
    raise RuntimeError("le modele causal stateful ne produit aucun texte sur le clip reel")
print("OK : fidele sur audio reel et cache transmis")
