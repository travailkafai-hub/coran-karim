"""
Adapte de export_pcd_full_pipeline.py pour le NOUVEAU modele tajweed
(models/fastconformer-quran-tajweed/fastconformer-quran-best.nemo, val_wer_ctc
5.82% - cf. session 2026-07-13). Meme pipeline E2E (audio brut -> logprobs CTC),
plus generation de vocab.json (absent du script d'origine, reconstruit ici
depuis le tokenizer NeMo).

word_tokens.json NON regenere ici : la normalisation utilisee par
build_word_token_lookup.py (normalize_training) SUPPRIME les marques tajweed
(dagger alif, wasla, waqf...) que ce nouveau modele apprend justement a
reconnaitre -- le reutiliser telle quelle produirait un lookup incoherent
avec le vocabulaire d'entrainement. L'app tolere l'absence de word_tokens.json
(repli sur la tokenisation greedy, cf. FastConformerVerifier.dart) ; a refaire
proprement plus tard avec une normalisation alignee sur normalizeStrict.
"""
import os, json, random
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

import types
import torch, numpy as np
import nemo.collections.asr as nemo_asr
from pathlib import Path

# torch.onnx (opset17, torch 2.11) ne sait pas tracer torch.stft(return_complex=True)
# -> "STFT does not currently support complex types". Fix standard : demander la
# sortie reelle equivalente (return_complex=False, dernier axe = [re, im]) et rendre
# torch.view_as_real() transparent sur un tenseur deja reel (le code NeMo en aval
# appelle inconditionnellement view_as_real() sur le retour de stft()). Applique
# AVANT la construction du wrapper pour que PyTorch et ONNX suivent le meme chemin.
_orig_view_as_real = torch.view_as_real
def _safe_view_as_real(x):
    return _orig_view_as_real(x) if torch.is_complex(x) else x
torch.view_as_real = _safe_view_as_real

def _stft_real_output(self, x):
    return torch.stft(
        x, n_fft=self.n_fft, hop_length=self.hop_length, win_length=self.win_length,
        center=False if self.exact_pad else True,
        window=self.window.to(dtype=torch.float, device=x.device),
        return_complex=False, pad_mode="constant",
    )

BASE_DIR = Path(__file__).parent
NEMO_PATH = BASE_DIR / "models" / "fastconformer-quran-tajweed" / "fastconformer-quran-best.nemo"
DEPLOY_DIR = BASE_DIR / "models" / "fastconformer-quran-tajweed" / "deploy" / "fastconformer-ctc-tajweed"
OUT_ONNX = DEPLOY_DIR / "model.onnx"
OUT_VOCAB = DEPLOY_DIR / "vocab.json"


class E2ECTCWrapper(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.preprocessor = model.preprocessor
        self.encoder = model.encoder
        self.ctc_decoder = model.ctc_decoder

    def forward(self, raw_audio: torch.Tensor, length: torch.Tensor):
        feats, feats_len = self.preprocessor(input_signal=raw_audio, length=length)
        encoded, encoded_len = self.encoder(audio_signal=feats, length=feats_len)
        logits = self.ctc_decoder(encoder_output=encoded)
        logprobs = torch.nn.functional.log_softmax(logits, dim=-1)
        return logprobs


def main():
    DEPLOY_DIR.mkdir(parents=True, exist_ok=True)
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(NEMO_PATH), map_location="cpu")
    model.eval()
    model.preprocessor.featurizer.dither = 0.0
    model.preprocessor.featurizer.stft = types.MethodType(_stft_real_output, model.preprocessor.featurizer)

    # vocab.json : liste des tokens dans l'ordre des IDs (index = id) + blank final
    vocab_size = model.tokenizer.vocab_size
    vocab = [model.tokenizer.ids_to_tokens([i])[0] for i in range(vocab_size)]
    with open(OUT_VOCAB, "w", encoding="utf-8") as f:
        json.dump(vocab, f, ensure_ascii=False)
    print(f"vocab.json ecrit : {OUT_VOCAB} ({len(vocab)} tokens)")

    wrapper = E2ECTCWrapper(model)
    wrapper.eval()

    dummy_audio = torch.randn(1, 32000)
    dummy_len = torch.tensor([32000], dtype=torch.int64)

    with torch.no_grad():
        ref_out = wrapper(dummy_audio, dummy_len)
    print("Shape logprobs (test dummy):", ref_out.shape)

    torch.onnx.export(
        wrapper,
        (dummy_audio, dummy_len),
        str(OUT_ONNX),
        input_names=["raw_audio", "length"],
        output_names=["logprobs"],
        dynamic_axes={
            "raw_audio": {0: "batch", 1: "num_samples"},
            "length": {0: "batch"},
            "logprobs": {0: "batch", 1: "time"},
        },
        opset_version=17,
        do_constant_folding=True,
        dynamo=False,
    )
    print(f"Export E2E termine : {OUT_ONNX} ({OUT_ONNX.stat().st_size/1e6:.1f} Mo)")

    import onnxruntime as ort
    import soundfile as sf

    rows = [json.loads(l) for l in open(BASE_DIR / "nemo_manifests_tajweed" / "val_manifest.jsonl", encoding="utf-8")]
    random.seed(2)
    r = random.choice(rows)
    audio_np, sr = sf.read(r["audio_filepath"], dtype="float32")
    audio_t = torch.tensor(audio_np).unsqueeze(0)
    len_t = torch.tensor([audio_np.shape[0]], dtype=torch.int64)

    with torch.no_grad():
        torch_logprobs = wrapper(audio_t, len_t).numpy()

    sess = ort.InferenceSession(str(OUT_ONNX), providers=["CPUExecutionProvider"])
    onnx_logprobs = sess.run(["logprobs"], {
        "raw_audio": audio_t.numpy().astype(np.float32),
        "length": len_t.numpy().astype(np.int64),
    })[0]

    def greedy_decode(logprobs, tokenizer, blank_id):
        ids = logprobs[0].argmax(axis=-1)
        out, prev = [], None
        for i in ids:
            if i != prev and i != blank_id:
                out.append(int(i))
            prev = i
        return tokenizer.ids_to_text(out)

    blank_id = torch_logprobs.shape[-1] - 1
    txt_torch = greedy_decode(torch_logprobs, model.tokenizer, blank_id)
    txt_onnx = greedy_decode(onnx_logprobs, model.tokenizer, blank_id)

    print("\n=== Validation pipeline E2E (raw audio -> ONNX) ===")
    print("REF       :", r["text"])
    print("PYTORCH   :", txt_torch)
    print("ONNX E2E  :", txt_onnx)
    print("MATCH     :", txt_torch.strip() == txt_onnx.strip())


if __name__ == "__main__":
    main()
