"""
Teste si la comparaison audio-a-audio par DTW sur les embeddings de l'encodeur
discrimine mieux que l'alignement force (test precedent, decevant) :
  - MEME verset, reciteurs DIFFERENTS -> doit etre TRES similaire (le but :
    reconnaitre "c'est le meme contenu recite", peu importe la voix)
  - VERSETS DIFFERENTS -> doit etre NETTEMENT moins similaire

Utilise le modele deja exporte (fastconformer_embed_pcd.onnx) + DTW simple
(programmation dynamique sur distance cosinus entre frames).
"""
import os, json, random
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

import numpy as np, onnxruntime as ort, soundfile as sf, torch
from pathlib import Path
from collections import defaultdict

BASE_DIR = Path(__file__).parent
ONNX_PATH = BASE_DIR / "models" / "fastconformer-quran-pcd" / "onnx_export" / "fastconformer_embed_pcd.onnx"

import nemo.collections.asr as nemo_asr
model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
    str(BASE_DIR / "models" / "fastconformer-quran-pcd" / "fastconformer-quran-pcd-snapshot.nemo"),
    map_location="cpu")
preprocessor = model.preprocessor
del model

sess = ort.InferenceSession(str(ONNX_PATH), providers=["CPUExecutionProvider"])


def get_embeddings(wav_path: str) -> np.ndarray:
    audio, sr = sf.read(wav_path, dtype="float32")
    audio_t = torch.tensor(audio).unsqueeze(0)
    len_t = torch.tensor([audio.shape[0]])
    with torch.no_grad():
        feats, feats_len = preprocessor(input_signal=audio_t, length=len_t)
    out = sess.run(["embeddings"], {
        "audio_signal": feats.numpy().astype(np.float32),
        "length": feats_len.numpy().astype(np.int64),
    })
    return out[0][0]  # (T, 512)


def dtw_similarity(a: np.ndarray, b: np.ndarray) -> float:
    """DTW sur distance cosinus, normalise par la longueur du chemin -> similarite [0,1]."""
    an = a / (np.linalg.norm(a, axis=1, keepdims=True) + 1e-8)
    bn = b / (np.linalg.norm(b, axis=1, keepdims=True) + 1e-8)
    cost = 1.0 - an @ bn.T  # (Ta, Tb), 0=identique, 2=oppose

    Ta, Tb = cost.shape
    D = np.full((Ta + 1, Tb + 1), np.inf)
    D[0, 0] = 0.0
    for i in range(1, Ta + 1):
        for j in range(1, Tb + 1):
            D[i, j] = cost[i-1, j-1] + min(D[i-1, j], D[i, j-1], D[i-1, j-1])
    path_len = Ta + Tb  # approx (majoration du vrai chemin)
    avg_cost = D[Ta, Tb] / max(Ta, Tb)
    return 1.0 - avg_cost / 2.0  # cost in [0,2] -> similarite [0,1] (approx)


def main():
    # Regrouper les clips de val_manifest par cle de verset (meme verset, reciteurs differents)
    rows = [json.loads(l) for l in open(BASE_DIR/"nemo_manifests"/"val_manifest.jsonl", encoding="utf-8")]
    by_key = defaultdict(list)
    for r in rows:
        key = r.get("text", "")[:30]  # approx grouping par texte (pas de cle verset explicite ici)
        by_key[key].append(r)

    # Chercher des groupes avec >= 2 clips (meme texte, probablement meme verset diff reciteur)
    groups = [g for g in by_key.values() if len(g) >= 2]
    print(f"{len(groups)} groupes avec >=2 clips (meme texte approx)")
    random.seed(42)
    random.shuffle(groups)

    if len(groups) < 2:
        print("Pas assez de groupes pour le test, abandon")
        return

    same_content_scores = []
    diff_content_scores = []

    n_test = min(5, len(groups))
    for i in range(n_test):
        g = groups[i]
        r1, r2 = g[0], g[1]
        emb1 = get_embeddings(r1["audio_filepath"])
        emb2 = get_embeddings(r2["audio_filepath"])
        sim_same = dtw_similarity(emb1, emb2)
        same_content_scores.append(sim_same)

        other_group = groups[(i + 1) % len(groups)]
        r3 = other_group[0]
        emb3 = get_embeddings(r3["audio_filepath"])
        sim_diff = dtw_similarity(emb1, emb3)
        diff_content_scores.append(sim_diff)

        print(f"\n[{i}] Texte: {r1['text'][:50]}...")
        print(f"    MEME contenu (reciteur different)  : sim={sim_same:.4f}")
        print(f"    Texte different (autre groupe)      : sim={sim_diff:.4f}  ({r3['text'][:40]}...)")
        print(f"    -> {'OK, bien discrimine' if sim_same > sim_diff + 0.05 else 'PROBLEME'}")

    print(f"\n=== Moyennes ===")
    print(f"Meme contenu   : {np.mean(same_content_scores):.4f}")
    print(f"Contenu diff   : {np.mean(diff_content_scores):.4f}")
    print(f"Ecart          : {np.mean(same_content_scores) - np.mean(diff_content_scores):.4f}")


if __name__ == "__main__":
    main()
