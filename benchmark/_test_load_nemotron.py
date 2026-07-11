"""Test NON destructif : peut-on seulement CHARGER nemotron-3.5 avec NeMo 2.7.3 ?
Charge sur CPU, imprime la classe, ne fait aucune inference lourde."""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
os.environ["CUDA_VISIBLE_DEVICES"] = ""  # force CPU, ne touche pas le GPU du training
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass
import traceback
MODEL = "nvidia/nemotron-3.5-asr-streaming-0.6b"
print("Tentative de chargement:", MODEL, flush=True)
try:
    import nemo.collections.asr as nemo_asr
    m = nemo_asr.models.ASRModel.from_pretrained(model_name=MODEL, map_location="cpu")
    print("SUCCES. Classe:", type(m).__name__, flush=True)
    print("has ctc head:", hasattr(m, "ctc_decoder") or hasattr(m, "ctc_head"), flush=True)
    print("cfg keys:", list(m.cfg.keys())[:20], flush=True)
except Exception as e:
    print("ECHEC:", type(e).__name__, flush=True)
    traceback.print_exc()
