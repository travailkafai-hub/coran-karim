"""
Teste le chemin de streaming OFFICIEL NeMo (conformer_stream_step +
CacheAwareStreamingAudioBuffer) sur notre checkpoint pcd avec att_context [70,1],
pour repondre a LA question : le streaming cache-aware zero-shot produit-il du
vrai texte sur ce checkpoint ? (Ma simulation manuelle du pipeline Kotlin sort
du vide meme avec normalisation oracle -> soit ma grille de fenetrage est
fausse, soit le zero-shot cache ne marche pas du tout sur ce modele.)
"""
import os, json, random
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

import torch
import nemo.collections.asr as nemo_asr
from nemo.collections.asr.parts.utils.streaming_utils import CacheAwareStreamingAudioBuffer
from pathlib import Path

BASE_DIR = Path(__file__).parent
NEMO_PATH = BASE_DIR / "models" / "fastconformer-quran-pcd" / "fastconformer-quran-pcd-snapshot.nemo"

model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(NEMO_PATH), map_location="cpu")
model.eval()
model.cur_decoder = "ctc"
model.encoder.att_context_style = "chunked_limited"
model.encoder.set_default_att_context_size([70, 1])
model.encoder.setup_streaming_params()
print("streaming_cfg:", model.encoder.streaming_cfg)

rows = [json.loads(l) for l in open(BASE_DIR/"nemo_manifests"/"val_manifest.jsonl", encoding="utf-8")]
random.seed(7)
r = random.choice(rows)
print("REF:", r["text"])

streaming_buffer = CacheAwareStreamingAudioBuffer(model=model, online_normalization=False)
_ = streaming_buffer.append_audio_file(r["audio_filepath"], stream_id=-1)

batch_size = 1
cache_last_channel, cache_last_time, cache_last_channel_len = model.encoder.get_initial_cache_state(
    batch_size=batch_size)
previous_hypotheses = None
pred_out_stream = None

with torch.no_grad():
    for step_num, (chunk_audio, chunk_lengths) in enumerate(streaming_buffer):
        (pred_out_stream, transcribed_texts, cache_last_channel, cache_last_time,
         cache_last_channel_len, previous_hypotheses) = model.conformer_stream_step(
            processed_signal=chunk_audio,
            processed_signal_length=chunk_lengths,
            cache_last_channel=cache_last_channel,
            cache_last_time=cache_last_time,
            cache_last_channel_len=cache_last_channel_len,
            keep_all_outputs=streaming_buffer.is_buffer_empty(),
            previous_hypotheses=previous_hypotheses,
            previous_pred_out=pred_out_stream,
            drop_extra_pre_encoded=None,
            return_transcription=True,
        )
        txt = transcribed_texts[0].text if hasattr(transcribed_texts[0], "text") else transcribed_texts[0]
        if step_num % 5 == 0 or streaming_buffer.is_buffer_empty():
            print(f"step {step_num:3d} | chunk {tuple(chunk_audio.shape)} | texte: {txt}")

print("\nTEXTE FINAL:", txt)
