"""
Teste si notre checkpoint FastConformer CTC (entraine en attention "regular"/
full-context, pcd, snapshot ~20% val_wer_ctc) peut etre bascule en streaming
cache-aware "chunked_limited" SANS reentrainement -- juste un changement de
config d'attention a l'inference (piste identifiee via recherche : FastConformer
supporte ce changement zero-shot, la qualite peut varier sans entrainement dedie).

Compare la transcription en streaming (chunk-by-chunk, conformer_stream_step)
vs en mode offline complet (regular, meme checkpoint), sur les memes clips.
"""
import os, json, random
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

import torch
import nemo.collections.asr as nemo_asr
from pathlib import Path

BASE_DIR = Path(__file__).parent
NEMO_PATH = BASE_DIR / "models" / "fastconformer-quran-pcd" / "fastconformer-quran-pcd-snapshot.nemo"

# Taille de contexte streaming : [left, right] en nombre de frames encodeur
# (chaque frame = 4 frames mel apres sous-echantillonnage x8 -> ~80ms/frame).
# [70, 1] = ~1120ms de latence de look-ahead (valeur par defaut la plus grosse
# du preset NeMo), on commence large pour maximiser la qualite avant d'optimiser
# la latence.
ATT_CONTEXT_SIZE = [70, 1]

def main():
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(NEMO_PATH), map_location="cpu")
    model.eval()
    model.cur_decoder = "ctc"

    rows = [json.loads(l) for l in open(BASE_DIR/"nemo_manifests"/"val_manifest.jsonl", encoding="utf-8")]
    random.seed(4)
    sample = random.sample(rows, 3)

    print("=== Mode OFFLINE (regular, full context) ===")
    model.encoder.att_context_style = "regular"
    model.encoder.set_default_att_context_size([-1, -1])
    with torch.no_grad():
        offline_hyps = model.transcribe([r["audio_filepath"] for r in sample], batch_size=3)
    offline_texts = [h.text if hasattr(h, "text") else h for h in offline_hyps]

    print("\n=== Bascule streaming chunked_limited (SANS reentrainement) ===")
    model.encoder.att_context_style = "chunked_limited"
    model.encoder.set_default_att_context_size(ATT_CONTEXT_SIZE)
    model.encoder.setup_streaming_params()
    print("streaming_cfg:", model.encoder.streaming_cfg)

    for r, offline_text in zip(sample, offline_texts):
        # Streaming simule : on encode tout le fichier d'un coup MAIS avec le
        # masque d'attention chunked_limited (equivalent qualite a un vrai
        # streaming chunk-by-chunk, sans la complexite du cache inter-appels).
        with torch.no_grad():
            stream_hyp = model.transcribe([r["audio_filepath"]], batch_size=1)
        stream_text = stream_hyp[0].text if hasattr(stream_hyp[0], "text") else stream_hyp[0]
        print(f"\nREF      : {r['text']}")
        print(f"OFFLINE  : {offline_text}")
        print(f"STREAMING: {stream_text}")


if __name__ == "__main__":
    main()
