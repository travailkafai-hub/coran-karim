"""
Export ONNX streaming (cache-aware) de l'encodeur FastConformer CTC + tete CTC,
en utilisant le support natif NeMo (export_cache_support) plutot que de bricoler
l'export a la main -- decouvert en inspectant conformer_encoder.py.

Entrees ONNX : audio_signal (features mel, une fenetre/chunk), length,
               cache_last_channel, cache_last_time, cache_last_channel_len
Sorties ONNX : logprobs (CTC, pour le chunk courant),
               cache_last_channel_next, cache_last_time_next, cache_last_channel_next_len
               (a repasser en entree pour le CHUNK SUIVANT -> etat qui persiste)

Contexte att_context_size choisi : [70, 1].

⛔ CORRECTION 2026-07-25 : le commentaire d'origine disait "~1120ms de
look-ahead, le plus gros preset" -- C'EST FAUX, et l'erreur fausse tout
arbitrage latence/qualite. Formule officielle NVIDIA :
    look-ahead(s) = att_context_size[1] * subsampling_factor * window_stride
soit ici R * 8 * 0.01 = R * 80 ms. Donc [70,1] = 80 ms, le preset le plus
AGRESSIF (pas le plus gros) ; les ~1040 ms correspondent a [70,13], qui est le
DEFAUT NVIDIA. Cf. references/asr.md du skill model-training. Bascule "zero-shot" sans reentrainement, deja validee
(test_streaming_ctc.py) : qualite comparable au mode offline sur le
checkpoint actuel (~20% val_wer_ctc, training en cours).

MISE A JOUR 2026-07-26 : ce script historique pointait encore vers le
checkpoint PCD NON causal et forcait [70,1]. C'est precisement l'ancienne
tentative qui sortait du blank sur le telephone. L'export de production pointe
desormais vers `causal-final.nemo`, deja entraine en [70,13], et refuse de muter
ce contexte pendant l'export. Les dimensions sont ecrites dans
`streaming_config.json` pour que Kotlin ne reutilise plus les constantes de
l'ancien prototype (25/16/cache-time=4 au lieu de 121/112/cache-time=8).
"""
import os, json, shutil
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

import torch, numpy as np
import nemo.collections.asr as nemo_asr
from pathlib import Path

BASE_DIR = Path(__file__).parent
NEMO_PATH = (
    BASE_DIR
    / "models"
    / "fastconformer-streaming-causal-v1-lr3e4"
    / "causal-final.nemo"
)
OUT_DIR = (
    BASE_DIR
    / "models"
    / "fastconformer-streaming-causal-v1-lr3e4"
    / "deploy"
    / "fastconformer-ctc-causal-v1"
)
ONNX_PATH = OUT_DIR / "model_streaming.onnx"
CONFIG_PATH = OUT_DIR / "streaming_config.json"
VOCAB_PATH = OUT_DIR / "vocab.json"
WORD_TOKENS_PATH = OUT_DIR / "word_tokens.json"
TOKENIZER_DEPLOY_DIR = (
    BASE_DIR / "models" / "fastconformer-quran-tajweed-mixed" / "deploy"
)
EXPECTED_ATT_CONTEXT_SIZE = [70, 13]


class StreamingCTCWrapper(torch.nn.Module):
    """encoder (cache-aware) -> ctc_decoder -> log_softmax, en un seul graphe ONNX."""
    def __init__(self, encoder, ctc_decoder):
        super().__init__()
        self.encoder = encoder
        self.ctc_decoder = ctc_decoder

    def forward(self, audio_signal, length, cache_last_channel, cache_last_time, cache_last_channel_len):
        # input_example()/convention externe (ONNX, batch-first) = (B, num_layers, ...)
        # mais ConformerEncoder.forward() interne attend (num_layers, B, ...) -- cf.
        # input_types (D,B,T,D) vs input_types_for_export (B,D,T,D). Transpose
        # aller-retour pour garder un graphe ONNX batch-first (plus simple cote mobile).
        encoded, encoded_len, cache_last_channel_next, cache_last_time_next, cache_last_channel_next_len = (
            self.encoder(
                audio_signal=audio_signal,
                length=length,
                cache_last_channel=cache_last_channel.transpose(0, 1),
                cache_last_time=cache_last_time.transpose(0, 1),
                cache_last_channel_len=cache_last_channel_len,
            )
        )
        logits = self.ctc_decoder(encoder_output=encoded)
        logprobs = torch.nn.functional.log_softmax(logits, dim=-1)
        return (
            logprobs,
            cache_last_channel_next.transpose(0, 1),
            cache_last_time_next.transpose(0, 1),
            cache_last_channel_next_len,
        )


def _stream_value(value):
    """Valeur mel (dernier preset) d'un champ streaming_cfg scalaire ou liste."""
    if isinstance(value, (list, tuple)):
        return int(value[-1])
    return int(value)


def _shape(tensor):
    return [int(v) for v in tensor.shape]


def _write_config(enc, examples):
    audio_ex, _, cache_ch_ex, cache_t_ex, _ = examples
    att_context = [int(v) for v in enc.att_context_size]
    if att_context != EXPECTED_ATT_CONTEXT_SIZE:
        raise RuntimeError(
            "contexte du checkpoint inattendu : "
            f"{att_context}, attendu {EXPECTED_ATT_CONTEXT_SIZE}; "
            "l'export ne doit pas changer le contexte appris"
        )

    cfg = enc.streaming_cfg
    shift_frames = _stream_value(cfg.shift_size)
    pre_encode_cache_frames = _stream_value(cfg.pre_encode_cache_size)
    metadata = {
        "schema_version": 1,
        "source_nemo": NEMO_PATH.name,
        "att_context_size": att_context,
        "input_frames": int(audio_ex.shape[-1]),
        "shift_frames": shift_frames,
        "pre_encode_cache_frames": pre_encode_cache_frames,
        "valid_output_frames": int(cfg.valid_out_len),
        "cache_last_channel_shape": _shape(cache_ch_ex),
        "cache_last_time_shape": _shape(cache_t_ex),
        "subsampling_factor": int(enc.subsampling_factor),
        "window_stride_ms": 10,
        "lookahead_ms": att_context[1] * int(enc.subsampling_factor) * 10,
        "has_tajwid_head": False,
    }
    if metadata["input_frames"] != shift_frames + pre_encode_cache_frames:
        raise RuntimeError(
            "contrat NeMo incoherent : input_frames != "
            "shift_frames + pre_encode_cache_frames"
        )
    CONFIG_PATH.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Metadonnees : {CONFIG_PATH}")
    print(json.dumps(metadata, ensure_ascii=False, indent=2))


def _deploy_tokenizer_assets():
    """Copie le lookup exact uniquement si le vocabulaire est identique."""
    source_vocab = TOKENIZER_DEPLOY_DIR / "vocab.json"
    source_word_tokens = TOKENIZER_DEPLOY_DIR / "word_tokens.json"
    deployed_vocab = json.loads(VOCAB_PATH.read_text(encoding="utf-8"))
    compatible_vocab = json.loads(source_vocab.read_text(encoding="utf-8"))
    if deployed_vocab != compatible_vocab:
        raise RuntimeError(
            "word_tokens.json refuse : son vocabulaire source differe de "
            "celui du checkpoint causal"
        )
    shutil.copy2(source_word_tokens, WORD_TOKENS_PATH)
    print(
        f"Lookup tokenizer : {WORD_TOKENS_PATH} "
        f"({WORD_TOKENS_PATH.stat().st_size / 1024:.0f} Ko)"
    )


def _write_vocab(model):
    vocab = [
        model.tokenizer.ids_to_tokens([index])[0]
        for index in range(model.tokenizer.vocab_size)
    ]
    VOCAB_PATH.write_text(
        json.dumps(vocab, ensure_ascii=False),
        encoding="utf-8",
    )
    print(f"Vocabulaire : {VOCAB_PATH} ({len(vocab)} tokens)")


def _validate_three_chunks(wrapper, examples):
    """Compare PyTorch et ONNX avec deux etats de cache independants."""
    import onnxruntime as ort

    audio_ex, length_ex, _, _, _ = examples
    sess = ort.InferenceSession(str(ONNX_PATH), providers=["CPUExecutionProvider"])
    expected_inputs = {
        "audio_signal",
        "length",
        "cache_last_channel",
        "cache_last_time",
        "cache_last_channel_len",
    }
    actual_inputs = {item.name for item in sess.get_inputs()}
    if actual_inputs != expected_inputs:
        raise RuntimeError(f"entrees ONNX invalides : {sorted(actual_inputs)}")

    # `input_example()` genere volontairement un cache ALEATOIRE avec une
    # longueur deja avancee pour le tracing. Ce n'est pas un etat de session
    # valide : le reutiliser dans une chaine de test amplifie de petites
    # divergences numeriques sur un etat impossible. La production demarre par
    # get_initial_cache_state(), donc la validation doit faire de meme.
    cache_ch, cache_t, cache_len = wrapper.encoder.get_initial_cache_state(
        batch_size=1
    )
    pt_cache_ch = cache_ch.transpose(0, 1)
    pt_cache_t = cache_t.transpose(0, 1)
    pt_cache_len = cache_len
    ort_cache_ch = pt_cache_ch.numpy().astype(np.float32)
    ort_cache_t = pt_cache_t.numpy().astype(np.float32)
    ort_cache_len = pt_cache_len.numpy().astype(np.int64)
    generator = torch.Generator().manual_seed(26)
    max_diff = 0.0

    for chunk_index in range(3):
        chunk = torch.randn(audio_ex.shape, generator=generator)
        with torch.no_grad():
            pt_out = wrapper(
                chunk,
                length_ex,
                pt_cache_ch,
                pt_cache_t,
                pt_cache_len,
            )
        ort_out = sess.run(
            None,
            {
                "audio_signal": chunk.numpy().astype(np.float32),
                "length": length_ex.numpy().astype(np.int64),
                "cache_last_channel": ort_cache_ch,
                "cache_last_time": ort_cache_t,
                "cache_last_channel_len": ort_cache_len,
            },
        )
        diff = float(np.max(np.abs(pt_out[0].numpy() - ort_out[0])))
        max_diff = max(max_diff, diff)
        print(
            f"chunk {chunk_index + 1}: logprobs={tuple(ort_out[0].shape)} "
            f"cache_len={int(ort_out[3][0])} diff={diff:.6g}"
        )
        pt_cache_ch, pt_cache_t, pt_cache_len = pt_out[1], pt_out[2], pt_out[3]
        ort_cache_ch, ort_cache_t, ort_cache_len = ort_out[1], ort_out[2], ort_out[3]

    if max_diff >= 1e-3:
        raise RuntimeError(f"divergence PyTorch/ONNX multi-chunks : {max_diff}")
    if int(ort_cache_len[0]) <= 0:
        raise RuntimeError("le cache stateful n'a pas progresse")
    print(f"Validation multi-chunks OK, ecart max={max_diff:.6g}")


def main():
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(NEMO_PATH), map_location="cpu")
    model.eval()

    enc = model.encoder
    if enc.att_context_style != "chunked_limited":
        raise RuntimeError(
            f"checkpoint non streaming : att_context_style={enc.att_context_style}"
        )
    # L'objet runtime transforme "causal" en [kernel-1, 0] et ne conserve pas
    # `causal_downsampling` comme attribut public. La config restauree est la
    # source fiable pour refuser un ancien checkpoint non causal.
    if (
        str(model.cfg.encoder.conv_context_size) != "causal"
        or not bool(model.cfg.encoder.causal_downsampling)
    ):
        raise RuntimeError(
            "checkpoint non causal : conv_context_size/causal_downsampling invalides"
        )
    enc.export_cache_support = True
    enc.setup_streaming_params()
    print("streaming_cfg:", enc.streaming_cfg)

    wrapper = StreamingCTCWrapper(enc, model.ctc_decoder)
    wrapper.eval()

    # Exemple d'entree genere par NeMo lui-meme (bonne taille de fenetre/cache)
    examples = enc.input_example()
    audio_ex, length_ex, cache_ch_ex, cache_t_ex, cache_len_ex = examples
    print("Shapes -> audio:", audio_ex.shape, "length:", length_ex.shape,
          "cache_ch:", cache_ch_ex.shape, "cache_t:", cache_t_ex.shape, "cache_len:", cache_len_ex.shape)

    with torch.no_grad():
        ref_out = wrapper(audio_ex, length_ex, cache_ch_ex, cache_t_ex, cache_len_ex)
    print("Sortie logprobs shape (test dummy):", ref_out[0].shape)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    torch.onnx.export(
        wrapper,
        (audio_ex, length_ex, cache_ch_ex, cache_t_ex, cache_len_ex),
        str(ONNX_PATH),
        input_names=["audio_signal", "length", "cache_last_channel", "cache_last_time", "cache_last_channel_len"],
        output_names=["logprobs", "cache_last_channel_next", "cache_last_time_next", "cache_last_channel_next_len"],
        dynamic_axes={
            "audio_signal": {0: "batch"},
            "length": {0: "batch"},
            "cache_last_channel": {0: "batch"},
            "cache_last_time": {0: "batch"},
            "cache_last_channel_len": {0: "batch"},
            "logprobs": {0: "batch", 1: "time"},
            "cache_last_channel_next": {0: "batch"},
            "cache_last_time_next": {0: "batch"},
            "cache_last_channel_next_len": {0: "batch"},
        },
        opset_version=17,
        do_constant_folding=True,
        dynamo=False,
    )
    print(f"Export termine : {ONNX_PATH} ({ONNX_PATH.stat().st_size/1e6:.1f} Mo)")
    _write_vocab(model)
    _write_config(enc, examples)
    _deploy_tokenizer_assets()
    _validate_three_chunks(wrapper, examples)


if __name__ == "__main__":
    main()
