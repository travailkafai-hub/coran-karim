"""
Export ONNX qui expose EN PLUS la representation interne de l'encodeur (avant la
tete CTC) -- necessaire pour la comparaison audio-a-audio (niveau 1 de l'idee
"personnalisation voix", cf. memoire voice-personalization-idea.md) : au lieu
de comparer du TEXTE decode (instable, cf. BENCHMARK_RESULTS.md/SKILL.md), on
compare directement les EMBEDDINGS phonetiques de deux enregistrements du meme
passage par la meme personne (DTW), sans jamais repasser par un decodage texte.

Sorties ONNX :
  - embeddings : (1, T, 512) -- sortie brute de l'encodeur, une "empreinte"
    par frame (~80ms), utilisee pour le DTW de comparaison.
  - logprobs   : (1, T, 1025) -- identique a l'export existant (compat, garde
    au cas ou on veut aussi le texte pour debug/affichage).
"""
import os, json, random
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

import torch, numpy as np
import nemo.collections.asr as nemo_asr
from pathlib import Path

BASE_DIR = Path(__file__).parent
NEMO_PATH = BASE_DIR / "models" / "fastconformer-quran-pcd" / "fastconformer-quran-pcd-snapshot.nemo"
OUT_ONNX = BASE_DIR / "models" / "fastconformer-quran-pcd" / "onnx_export" / "fastconformer_embed_pcd.onnx"


class EmbeddingCTCWrapper(torch.nn.Module):
    """encoder -> (embeddings bruts + logprobs CTC), un seul graphe ONNX."""
    def __init__(self, encoder, ctc_decoder):
        super().__init__()
        self.encoder = encoder
        self.ctc_decoder = ctc_decoder

    def forward(self, audio_signal, length):
        encoded, encoded_len = self.encoder(audio_signal=audio_signal, length=length)
        logits = self.ctc_decoder(encoder_output=encoded)
        logprobs = torch.nn.functional.log_softmax(logits, dim=-1)
        # encoded : (B, D, T) -> on transpose en (B, T, D) : plus naturel pour le DTW
        # (une ligne = une frame temporelle = un pas de comparaison)
        embeddings = encoded.transpose(1, 2)
        return embeddings, logprobs


def main():
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(NEMO_PATH), map_location="cpu")
    model.eval()

    wrapper = EmbeddingCTCWrapper(model.encoder, model.ctc_decoder)
    wrapper.eval()

    rows = [json.loads(l) for l in open(BASE_DIR/"nemo_manifests"/"val_manifest.jsonl", encoding="utf-8")]
    random.seed(3)
    r = random.choice(rows)
    import soundfile as sf
    audio_np, sr = sf.read(r["audio_filepath"], dtype="float32")
    audio_t = torch.tensor(audio_np).unsqueeze(0)
    len_t = torch.tensor([audio_np.shape[0]])
    with torch.no_grad():
        feats, feats_len = model.preprocessor(input_signal=audio_t, length=len_t)

    with torch.no_grad():
        emb_ref, logprobs_ref = wrapper(feats, feats_len)
    print("embeddings shape:", emb_ref.shape, "logprobs shape:", logprobs_ref.shape)

    torch.onnx.export(
        wrapper,
        (feats, feats_len),
        str(OUT_ONNX),
        input_names=["audio_signal", "length"],
        output_names=["embeddings", "logprobs"],
        dynamic_axes={
            "audio_signal": {0: "batch", 2: "time"},
            "length": {0: "batch"},
            "embeddings": {0: "batch", 1: "time"},
            "logprobs": {0: "batch", 1: "time"},
        },
        opset_version=17,
        do_constant_folding=True,
        dynamo=False,
    )
    print(f"Export termine : {OUT_ONNX} ({OUT_ONNX.stat().st_size/1e6:.1f} Mo)")

    # Validation ONNX vs PyTorch
    import onnxruntime as ort
    sess = ort.InferenceSession(str(OUT_ONNX), providers=["CPUExecutionProvider"])
    onnx_out = sess.run(None, {
        "audio_signal": feats.numpy().astype(np.float32),
        "length": feats_len.numpy().astype(np.int64),
    })
    emb_onnx, logprobs_onnx = onnx_out
    diff_emb = np.abs(emb_ref.numpy() - emb_onnx).max()
    diff_lp = np.abs(logprobs_ref.numpy() - logprobs_onnx).max()
    print(f"Max diff embeddings: {diff_emb:.6f} | logprobs: {diff_lp:.6f}")


if __name__ == "__main__":
    main()
