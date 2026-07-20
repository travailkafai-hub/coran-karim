"""
!!! NE PAS UTILISER POUR DEPLOYER DANS L'APP (2026-07-19) !!!
Ce script exporte la variante E2E (raw_audio -> preprocessor+encoder+ctc).
Elle est VALIDE en soi (PyTorch==ONNX verifie) mais INUTILISABLE par le
plugin Kotlin, qui calcule le mel lui-meme et envoie audio_signal :
le modele se charge ("Modele charge : true") mais chaque transcription
echoue en silence -> aucun suivi, aucune coloration sur device.
Constate en vrai le 2026-07-19, apres avoir reproduit le piege deja
documente le 2026-07-13 dans export_tajweed_checkpoint.py.
=> Utiliser export_rules_260h_checkpoint.py (audio_signal/mel).
Conserve ici comme trace de la tentative (cf. regle CLAUDE.md sur les
commentaires qui documentent un piege).

Export deploiement du modele hybride "vrai tajweed" stage1b-260h
(models/fastconformer-quran-hybrid-v1/stage1b-260h/stage1b-final.nemo --
meilleure version mesuree, cf. PLAN_ENTRAINEMENT_HYBRIDE.md 5ter :
CER canonique 6.85% vs 9.18% deploye, corrections silencieuses 10.7% vs 14.7%,
+ 17 regles tajwid en symboles PUA U+E000..U+E010).

Adapte de export_tajweed_full_pipeline.py (meme pipeline E2E audio brut ->
logprobs CTC, meme patch STFT, meme validation PyTorch<->ONNX). Seule la tete
CTC est exportee -- la tete RNNT (localisation) reste une piste separee
(export decoder+joint + boucle greedy Kotlin, cf. REFONTE_IHM.md 6, mesure
offline prealable pas encore faite).

word_tokens.json NON genere (meme decision que l'export tajweed : l'app
retombe sur la tokenisation greedy de CtcTokenizer.kt, qui gere les symboles
PUA comme n'importe quelle piece du vocabulaire).

IMPORTANT deploiement app : le vocabulaire contient les 17 symboles de
regles ; l'app doit (1) les retirer de tout texte compare/affiche
(ArabicNormalizer) et (2) aligner le GOP sur le texte ANNOTE
(assets quran_rules_annotated.json, cf. build_app_rules_assets.py) -- pas le
texte canonique nu, sinon le chemin force est penalise sur chaque frame ou
le modele veut emettre un symbole appris.
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

# Meme patch STFT que export_tajweed_full_pipeline.py (torch.onnx opset17 ne
# trace pas return_complex=True).
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
NEMO_PATH = BASE_DIR / "models" / "fastconformer-quran-hybrid-v1" / "stage1b-260h" / "stage1b-final.nemo"
DEPLOY_DIR = BASE_DIR / "models" / "fastconformer-quran-hybrid-v1" / "deploy" / "fastconformer-ctc-rules-260h"
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

    vocab_size = model.tokenizer.vocab_size
    vocab = [model.tokenizer.ids_to_tokens([i])[0] for i in range(vocab_size)]
    with open(OUT_VOCAB, "w", encoding="utf-8") as f:
        json.dump(vocab, f, ensure_ascii=False)
    n_pua = sum(1 for p in vocab for c in p if 0xE000 <= ord(c) <= 0xF8FF)
    print(f"vocab.json ecrit : {OUT_VOCAB} ({len(vocab)} tokens, {n_pua} pieces contenant un symbole de regle)")

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

    # Validation sur un clip du val RULES (texte annote) : verifie aussi que
    # les symboles sortent bien du decodage greedy ONNX.
    rows = [json.loads(l) for l in open(BASE_DIR / "nemo_manifests_rules" / "val_manifest.jsonl", encoding="utf-8")]
    random.seed(2)
    r = random.choice([x for x in rows if any(0xE000 <= ord(c) <= 0xF8FF for c in x["text"])])
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

    def show(t):
        # Rend les symboles PUA visibles dans le print (sinon invisibles)
        return "".join(f"<U+{ord(c):04X}>" if 0xE000 <= ord(c) <= 0xF8FF else c for c in t)

    print("\n=== Validation pipeline E2E (raw audio -> ONNX) ===")
    print("REF       :", show(r["text"]))
    print("PYTORCH   :", show(txt_torch))
    print("ONNX E2E  :", show(txt_onnx))
    print("MATCH     :", txt_torch.strip() == txt_onnx.strip())
    has_sym = any(0xE000 <= ord(c) <= 0xF8FF for c in txt_onnx)
    print("SYMBOLES DE REGLES EMIS PAR ONNX :", has_sym)


if __name__ == "__main__":
    main()
