"""
Valide que l'ONNX streaming (fastconformer_ctc_streaming.onnx) produit EXACTEMENT
la meme sortie que l'encodeur PyTorch natif, chunk par chunk, avec le cache qui
persiste d'un appel au suivant -- c'est la vraie question de fidelite pour le
streaming (pas juste "un appel isole marche", mais "la chaine de plusieurs
appels avec cache transmis reste coherente").
"""
import os, json, random
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

import torch, numpy as np, onnxruntime as ort
import nemo.collections.asr as nemo_asr
from pathlib import Path

BASE_DIR = Path(__file__).parent
NEMO_PATH = BASE_DIR / "models" / "fastconformer-quran-pcd" / "fastconformer-quran-pcd-snapshot.nemo"
ONNX_PATH = BASE_DIR / "models" / "fastconformer-quran-pcd" / "onnx_streaming" / "fastconformer_ctc_streaming.onnx"
ATT_CONTEXT_SIZE = [70, 1]

model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(NEMO_PATH), map_location="cpu")
model.eval()
enc = model.encoder
enc.att_context_style = "chunked_limited"
enc.set_default_att_context_size(ATT_CONTEXT_SIZE)
enc.export_cache_support = True
enc.setup_streaming_params()
cfg = enc.streaming_cfg
print("streaming_cfg:", cfg)

chunk_size = cfg.chunk_size[1] if isinstance(cfg.chunk_size, list) else cfg.chunk_size
pre_cache = cfg.pre_encode_cache_size[1] if isinstance(cfg.pre_encode_cache_size, list) else cfg.pre_encode_cache_size
window = chunk_size + pre_cache
print(f"chunk_size={chunk_size} pre_cache={pre_cache} window={window}")

# Vrai audio -> mel features (via le preprocesseur NeMo, deja valide ailleurs)
rows = [json.loads(l) for l in open(BASE_DIR/"nemo_manifests"/"val_manifest.jsonl", encoding="utf-8")]
random.seed(5)
r = random.choice(rows)
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
padded_len = feats_len + pre_cache

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

    diff = np.abs(pt_logprobs - onnx_logprobs).max()
    max_diff_overall = max(max_diff_overall, diff)
    print(f"chunk {n_chunks}: pt_logprobs shape={pt_logprobs.shape} max_diff={diff:.6f}")

    # avancer l'etat (PyTorch cote reference, onnx cote test) independamment
    cache_ch, cache_t, cache_len = pt_cache_ch_next.transpose(0,1), pt_cache_t_next.transpose(0,1), pt_cache_len_next
    onnx_cache_ch, onnx_cache_t, onnx_cache_len = onnx_cache_ch_next, onnx_cache_t_next, onnx_cache_len_next

    pos += chunk_size
    n_chunks += 1

print(f"\n=== Max diff sur {n_chunks} chunks consecutifs (cache transmis) : {max_diff_overall:.6f} ===")
print("OK (fidele)" if max_diff_overall < 1e-3 else "ATTENTION : divergence significative")
