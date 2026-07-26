"""Contrat de déploiement du FastConformer causal cache-aware.

Ce test ne valide pas seulement qu'un fichier ONNX existe : il protège les
dimensions qui ont déjà divergé entre l'ancien prototype non causal et le
checkpoint causal réellement entraîné.
"""

import json
import unittest
from pathlib import Path

import onnx


BASE = Path(__file__).parent
DEPLOY = (
    BASE
    / "models"
    / "fastconformer-streaming-causal-v1-lr3e4"
    / "deploy"
    / "fastconformer-ctc-causal-v1"
)
ONNX_PATH = DEPLOY / "model_streaming.onnx"
CONFIG_PATH = DEPLOY / "streaming_config.json"


class CausalStreamingOnnxContractTest(unittest.TestCase):
    def test_export_exposes_trained_stateful_contract(self):
        self.assertTrue(ONNX_PATH.exists(), f"export absent : {ONNX_PATH}")
        self.assertTrue(CONFIG_PATH.exists(), f"métadonnées absentes : {CONFIG_PATH}")

        config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
        self.assertEqual(config["att_context_size"], [70, 13])
        self.assertEqual(config["input_frames"], 121)
        self.assertEqual(config["shift_frames"], 112)
        self.assertEqual(config["pre_encode_cache_frames"], 9)
        self.assertEqual(config["valid_output_frames"], 14)
        self.assertEqual(config["cache_last_channel_shape"], [1, 17, 70, 512])
        self.assertEqual(config["cache_last_time_shape"], [1, 17, 512, 8])
        self.assertEqual(config["lookahead_ms"], 1040)
        self.assertFalse(config["has_tajwid_head"])

        model = onnx.load(str(ONNX_PATH), load_external_data=False)
        inputs = {value.name: value for value in model.graph.input}
        outputs = {value.name: value for value in model.graph.output}
        self.assertEqual(
            set(inputs),
            {
                "audio_signal",
                "length",
                "cache_last_channel",
                "cache_last_time",
                "cache_last_channel_len",
            },
        )
        self.assertEqual(
            set(outputs),
            {
                "logprobs",
                "cache_last_channel_next",
                "cache_last_time_next",
                "cache_last_channel_next_len",
            },
        )


if __name__ == "__main__":
    unittest.main()
