"""STAGE 0 — go/no-go du fine-tune streaming (2026-07-25).

Deux questions auxquelles la documentation ne repond pas, et qui decident si
la piste vaut une nuit de GPU :

  Q1. NeMo accepte-t-il de reconstruire l'encodeur en CAUSAL et d'y charger
      l'etat NON causal ? (les formes devraient etre identiques -- le padding
      change, pas les poids -- mais c'est a verifier, pas a supposer)

  Q2. Le chemin de streaming officiel fonctionne-t-il une fois causal ?
      Il CRASHAIT avant (`cannot reshape tensor of 0 elements` dans rel_shift,
      cf. references/asr.md "Streaming CTC : incompatibilite architecturale").
      Si le crash persiste, c'est un bug NeMo independant et la piste est
      bloquee -- mieux vaut le savoir en 30 min qu'apres un entrainement.

N'ENTRAINE RIEN. Ne modifie aucun checkpoint.
"""
import os
os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import json
from pathlib import Path

import torch
from omegaconf import OmegaConf, open_dict
import nemo.collections.asr as nemo_asr

BASE = Path(__file__).parent
NEMO = BASE / "models/fastconformer-quran-tajweed-mixed/mixed-e14-snapshot.nemo"
VAL = BASE / "nemo_manifests_dual/tajwid_frame_spans_val.jsonl"

print("=" * 78)
print("Q0. Chargement du checkpoint de reference")
print("=" * 78)
m = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(NEMO), map_location="cpu")
m.eval()
enc = m.cfg.encoder
print(f"  self_attention_model : {enc.get('self_attention_model')}")
print(f"  att_context_style    : {enc.get('att_context_style')}")
print(f"  att_context_size     : {enc.get('att_context_size')}")
print(f"  conv_context_size    : {enc.get('conv_context_size')}")
print(f"  causal_downsampling  : {enc.get('causal_downsampling')}")
print(f"  conv_kernel_size     : {enc.get('conv_kernel_size')}")
print(f"  n_layers / d_model   : {enc.get('n_layers')} / {enc.get('d_model')}")

sd_ref = {k: v.shape for k, v in m.state_dict().items()}
print(f"  parametres           : {len(sd_ref)} tenseurs")

print()
print("=" * 78)
print("Q1. Reconstruction CAUSALE + chargement de l'etat non causal")
print("=" * 78)
# Voie OFFICIELLE : recuperer la config du .nemo, la surcharger, puis laisser
# restore_from reconstruire -- c'est lui qui extrait le tokenizer et les autres
# artefacts. Reconstruire a la main depuis cfg echoue (`expected str, bytes or
# os.PathLike object, not NoneType`) : le chemin du tokenizer pointe dans le
# dossier temporaire du .nemo, deja supprime apres le restore.
cfg = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
    str(NEMO), return_config=True)
with open_dict(cfg):
    cfg.encoder.att_context_style = "chunked_limited"
    cfg.encoder.att_context_size = [70, 1]
    cfg.encoder.conv_context_size = "causal"
    cfg.encoder.causal_downsampling = True

try:
    m2 = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        str(NEMO), override_config_path=cfg, map_location="cpu")
    m2.eval()
    print("  construction causale : OK")
    e2 = m2.cfg.encoder
    print(f"    att_context_style   : {e2.get('att_context_style')}")
    print(f"    att_context_size    : {e2.get('att_context_size')}")
    print(f"    conv_context_size   : {e2.get('conv_context_size')}")
    print(f"    causal_downsampling : {e2.get('causal_downsampling')}")
except Exception as e:
    print(f"  construction causale : ECHEC -> {type(e).__name__}: {e}")
    import traceback; traceback.print_exc()
    raise SystemExit(1)

sd_new = {k: v.shape for k, v in m2.state_dict().items()}
manquants = [k for k in sd_new if k not in sd_ref]
en_trop = [k for k in sd_ref if k not in sd_new]
formes = [(k, sd_ref[k], sd_new[k]) for k in sd_new if k in sd_ref and sd_ref[k] != sd_new[k]]
print(f"  cles absentes de la reference : {len(manquants)}")
print(f"  cles de la reference inutilisees : {len(en_trop)}")
print(f"  FORMES DIFFERENTES : {len(formes)}")
for k, a, b in formes[:10]:
    print(f"     {k}: {tuple(a)} -> {tuple(b)}")

print("  (les poids sont charges par restore_from lui-meme)")

print()
print("=" * 78)
print("Q1bis. Passe avant OFFLINE sur un vrai clip (le modele parle-t-il encore ?)")
print("=" * 78)
clip = None
for line in open(VAL, encoding="utf-8"):
    d = json.loads(line)
    p = Path(d["audio_filepath"])
    if p.exists():
        clip = str(p)
        break
if clip is None:
    print("  aucun clip de validation accessible (chemins morts ?) -- passe ignoree")
else:
    print(f"  clip : {clip}")
    m2.eval()
    with torch.no_grad():
        for nom, mod in (("NON causal (reference)", m), ("CAUSAL (non entraine)", m2)):
            try:
                txt = mod.transcribe([clip], batch_size=1, verbose=False)
                t = txt[0] if not isinstance(txt[0], (list, tuple)) else txt[0][0]
                t = getattr(t, "text", t)
                print(f"  {nom:26s} : {str(t)[:70]}")
            except Exception as e:
                print(f"  {nom:26s} : ECHEC {type(e).__name__}: {e}")

print()
print("=" * 78)
print("Q2. Chemin de STREAMING officiel (celui qui crashait avant)")
print("=" * 78)
try:
    from nemo.collections.asr.parts.utils.streaming_utils import CacheAwareStreamingAudioBuffer
    m2.encoder.setup_streaming_params()
    print(f"  setup_streaming_params : OK")
    for a in ("streaming_cfg",):
        if hasattr(m2.encoder, a):
            print(f"  {a} : {getattr(m2.encoder, a)}")
    if clip:
        buf = CacheAwareStreamingAudioBuffer(model=m2, online_normalization=False)
        buf.append_audio_file(clip, stream_id=-1)
        cache_last_channel, cache_last_time, cache_last_channel_len = \
            m2.encoder.get_initial_cache_state(batch_size=1)
        n = 0
        prev = None
        with torch.no_grad():
            for chunk, chunk_len in buf:
                (prev, _, cache_last_channel, cache_last_time,
                 cache_last_channel_len, _) = m2.conformer_stream_step(
                    processed_signal=chunk,
                    processed_signal_length=chunk_len,
                    cache_last_channel=cache_last_channel,
                    cache_last_time=cache_last_time,
                    cache_last_channel_len=cache_last_channel_len,
                    keep_all_outputs=buf.is_buffer_empty(),
                    previous_hypotheses=prev,
                    previous_pred_out=None,
                    drop_extra_pre_encoded=None,
                    return_transcription=True,
                )
                n += 1
                if n >= 5:
                    break
        print(f"  conformer_stream_step : OK sur {n} chunk(s) -- PAS de crash")
        if prev:
            print(f"  hypothese apres {n} chunks : {str(getattr(prev[0], 'text', prev[0]))[:70]}")
except Exception as e:
    print(f"  conformer_stream_step : ECHEC {type(e).__name__}: {e}")
    import traceback
    traceback.print_exc()

print()
print("=" * 78)
print("VERDICT")
print("=" * 78)
print("  Q1 (formes compatibles)  :", "OK" if not formes else f"NON -- {len(formes)} tenseurs incompatibles")
print("  -> si Q1 OK et Q2 OK  : le fine-tune causal est lancable")
print("  -> si Q1 OK et Q2 NON : bug NeMo a contourner AVANT de depenser du GPU")
print("  -> si Q1 NON          : il faut un run depuis une config streaming, pas un fine-tune")
