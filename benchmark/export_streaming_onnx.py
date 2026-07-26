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
OUT_DIR = BASE_DIR / "models" / "fastconformer-quran-pcd" / "onnx_streaming"
ATT_CONTEXT_SIZE = [70, 1]


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


def main():
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(NEMO_PATH), map_location="cpu")
    model.eval()

    enc = model.encoder
    enc.att_context_style = "chunked_limited"
    enc.set_default_att_context_size(ATT_CONTEXT_SIZE)
    enc.export_cache_support = True
    enc.setup_streaming_params()
    print("streaming_cfg:", enc.streaming_cfg)

    wrapper = StreamingCTCWrapper(enc, model.ctc_decoder)
    wrapper.eval()

    # Exemple d'entree genere par NeMo lui-meme (bonne taille de fenetre/cache)
    audio_ex, length_ex, cache_ch_ex, cache_t_ex, cache_len_ex = enc.input_example()
    print("Shapes -> audio:", audio_ex.shape, "length:", length_ex.shape,
          "cache_ch:", cache_ch_ex.shape, "cache_t:", cache_t_ex.shape, "cache_len:", cache_len_ex.shape)

    with torch.no_grad():
        ref_out = wrapper(audio_ex, length_ex, cache_ch_ex, cache_t_ex, cache_len_ex)
    print("Sortie logprobs shape (test dummy):", ref_out[0].shape)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    onnx_path = OUT_DIR / "fastconformer_ctc_streaming.onnx"
    torch.onnx.export(
        wrapper,
        (audio_ex, length_ex, cache_ch_ex, cache_t_ex, cache_len_ex),
        str(onnx_path),
        input_names=["audio_signal", "length", "cache_last_channel", "cache_last_time", "cache_last_channel_len"],
        output_names=["logprobs", "cache_last_channel_next", "cache_last_time_next", "cache_last_channel_next_len"],
        dynamic_axes={
            "audio_signal": {0: "batch"},
            "length": {0: "batch"},
            "cache_last_channel": {1: "batch"},
            "cache_last_time": {1: "batch"},
            "cache_last_channel_len": {0: "batch"},
            "logprobs": {0: "batch", 1: "time"},
        },
        opset_version=17,
        do_constant_folding=True,
        dynamo=False,
    )
    print(f"Export termine : {onnx_path} ({onnx_path.stat().st_size/1e6:.1f} Mo)")


if __name__ == "__main__":
    main()
