"""
Export du checkpoint de la piste 3 (mixed-e14 intact + tokenizer tajweed +
VRAI CTC-only) pour test cote app, EN PARALLELE de stage1b-260h -- pas encore
la version finale, juste un point d'etape choisi par l'utilisateur pour
comparer sa perception au fil de l'entrainement.

Meme piege a eviter que d'habitude (cf. CLAUDE.md, export_rules_260h_checkpoint.py) :
TOUJOURS audio_signal/length, JAMAIS raw_audio.

Le .ckpt Lightning seul n'a pas le tokenizer resolu (register_artifact echoue,
cf. skill model-training/references/asr.md) -> on restaure mixed-e14, on
reapplique change_vocabulary vers le MEME tokenizer que le training
(tajweed_rules_bpe_v1) pour matcher les formes, PUIS on ecrase les poids
avec le state_dict du .ckpt (missing=0/unexpected=0 attendu).
"""
import os, json, sys, random
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
import torch, numpy as np
import nemo.collections.asr as nemo_asr
from pathlib import Path

BASE_DIR = Path(__file__).parent
BASE_NEMO = BASE_DIR / "models" / "fastconformer-quran-tajweed-mixed" / "mixed-e14-snapshot.nemo"
TOKENIZER_DIR = BASE_DIR / "tokenizers" / "tajweed_rules_bpe_v1"
CKPT_DIR = BASE_DIR / "models" / "fastconformer-quran-mixed-e14-rules-ctc"
DEPLOY_DIR = BASE_DIR / "models" / "fastconformer-quran-mixed-e14-rules-ctc" / "deploy" / "fastconformer-ctc-rules-260h"
OUT_ONNX = DEPLOY_DIR / "model.onnx"
OUT_VOCAB = DEPLOY_DIR / "vocab.json"


class EncCTCWrapper(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.encoder = model.encoder
        self.ctc_decoder = model.ctc_decoder

    def forward(self, audio_signal: torch.Tensor, length: torch.Tensor):
        encoded, encoded_len = self.encoder(audio_signal=audio_signal, length=length)
        logits = self.ctc_decoder(encoder_output=encoded)
        return torch.nn.functional.log_softmax(logits, dim=-1)


def main():
    ckpt_path = sys.argv[1] if len(sys.argv) > 1 else None
    if not ckpt_path:
        cands = sorted(CKPT_DIR.glob("fastconformer-quran-epoch=*.ckpt"),
                        key=lambda p: p.stat().st_mtime)
        if not cands:
            print("Aucun checkpoint trouve dans", CKPT_DIR); return
        ckpt_path = str(cands[-1])
    print(f"Checkpoint : {ckpt_path}")

    DEPLOY_DIR.mkdir(parents=True, exist_ok=True)
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(BASE_NEMO), map_location="cpu")
    model.change_vocabulary(new_tokenizer_dir=str(TOKENIZER_DIR), new_tokenizer_type="bpe")

    ckpt = torch.load(ckpt_path, map_location="cpu", weights_only=False)
    missing, unexpected = model.load_state_dict(ckpt["state_dict"], strict=False)
    print(f"load_state_dict : missing={len(missing)} unexpected={len(unexpected)}")
    if missing or unexpected:
        print("  missing[:5]:", missing[:5])
        print("  unexpected[:5]:", unexpected[:5])

    model.eval()
    model.preprocessor.featurizer.dither = 0.0

    vocab_size = model.tokenizer.vocab_size
    vocab = [model.tokenizer.ids_to_tokens([i])[0] for i in range(vocab_size)]
    with open(OUT_VOCAB, "w", encoding="utf-8") as f:
        json.dump(vocab, f, ensure_ascii=False)
    n_pua = sum(1 for p in vocab for c in p if 0xE000 <= ord(c) <= 0xF8FF)
    print(f"vocab.json ecrit : {OUT_VOCAB} ({len(vocab)} tokens, {n_pua} pieces symboles)")

    wrapper = EncCTCWrapper(model)
    wrapper.eval()

    n_mels = model.cfg.preprocessor.features
    dummy_mel = torch.randn(1, n_mels, 200)
    dummy_len = torch.tensor([200], dtype=torch.int64)
    with torch.no_grad():
        ref_out = wrapper(dummy_mel, dummy_len)
    print(f"n_mels={n_mels} — shape logprobs (dummy):", ref_out.shape)

    torch.onnx.export(
        wrapper, (dummy_mel, dummy_len), str(OUT_ONNX),
        input_names=["audio_signal", "length"], output_names=["logprobs"],
        dynamic_axes={
            "audio_signal": {0: "batch", 2: "time"},
            "length": {0: "batch"},
            "logprobs": {0: "batch", 1: "time"},
        },
        opset_version=17, do_constant_folding=True, dynamo=False,
    )
    print(f"Export termine : {OUT_ONNX} ({OUT_ONNX.stat().st_size/1e6:.1f} Mo)")

    import onnxruntime as ort
    sess = ort.InferenceSession(str(OUT_ONNX), providers=["CPUExecutionProvider"])
    entrees = [i.name for i in sess.get_inputs()]
    print("ENTREES ONNX :", entrees)
    assert entrees == ["audio_signal", "length"], "PIEGE : mauvais export, pas audio_signal/length !"

    import soundfile as sf
    rows = [json.loads(l) for l in open(BASE_DIR / "nemo_manifests_rules" / "val_manifest.jsonl", encoding="utf-8")]
    random.seed(2)
    r = random.choice([x for x in rows if any(0xE000 <= ord(c) <= 0xF8FF for c in x["text"])])
    audio_np, sr = sf.read(r["audio_filepath"], dtype="float32")
    audio_t = torch.tensor(audio_np).unsqueeze(0)
    len_t = torch.tensor([audio_np.shape[0]], dtype=torch.int64)
    feats, feats_len = model.preprocessor(input_signal=audio_t, length=len_t)
    with torch.no_grad():
        torch_logprobs = wrapper(feats, feats_len).numpy()
    onnx_logprobs = sess.run(["logprobs"], {
        "audio_signal": feats.numpy().astype(np.float32),
        "length": feats_len.numpy().astype(np.int64),
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

    def show(t):
        return "".join(f"<U+{ord(c):04X}>" if 0xE000 <= ord(c) <= 0xF8FF else c for c in t)

    print("\n=== Validation ===")
    print("REF   :", show(r["text"]))
    print("PYTORCH:", show(txt_torch))
    print("ONNX  :", show(txt_onnx))
    print("MATCH :", txt_torch.strip() == txt_onnx.strip())


if __name__ == "__main__":
    main()
