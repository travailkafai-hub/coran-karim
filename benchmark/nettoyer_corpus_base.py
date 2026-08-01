#!/usr/bin/env python3
"""NETTOIE le corpus de base (tous les clips de `train_wav_local`, tous
recitateurs) par le meme principe que `generer_et_nettoyer_clips_courts.py` :
decoder CHAQUE clip ENTIER et comparer au texte du manifeste. Pas d'exclusion
par recitateur (l'audit de cette nuit n'a teste que 8 clips par recitateur,
54 recitateurs -- un echantillon, pas une couverture) : ici CHAQUE clip est
verifie individuellement.

Objectif (2026-08-01, goal utilisateur "fiabilisation des dataset des 3 tetes
et encodeur") : produire un manifeste de base NETTOYE, utilisable pour tout
futur entrainement CTC/tajwid sans repasser par l'exclusion manuelle de
recitateurs -- le filtre agit clip par clip, pas recitateur par recitateur.

Seuil : WER <= 30 % (norme), meme seuil que le filtre des fragments courts,
pour rester coherent. Un clip ENTIER (verset complet, ~12s en moyenne) est
plus long qu'un fragment de 3-8s -- le seuil reste pertinent : une vraie
faute d'etiquetage donne un WER bien plus eleve que le bruit normal du
modele (cf. mesure de cette nuit : recitateurs propres a 5-25 %, contamines a
30-104 %).
"""
import json
import numpy as np
import torch
from pathlib import Path

BASE = Path(__file__).parent
TRAIN_MANIFEST = BASE / "nemo_manifests_dual" / "train_manifest.jsonl"
OUT_MANIFEST = BASE / "nemo_manifests_dual" / "train_manifest_nettoye.jsonl"
OUT_REJETS = BASE / "nemo_manifests_dual" / "train_manifest_rejets.jsonl"


def wer(ref, hyp):
    r, h = ref.split(), hyp.split()
    d = [[0] * (len(h) + 1) for _ in range(len(r) + 1)]
    for i in range(len(r) + 1):
        d[i][0] = i
    for j in range(len(h) + 1):
        d[0][j] = j
    for i in range(1, len(r) + 1):
        for j in range(1, len(h) + 1):
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1,
                          d[i - 1][j - 1] + (r[i - 1] != h[j - 1]))
    return d[-1][-1], len(r)


def norm(s):
    out = []
    for c in s:
        o = ord(c)
        if 0x064B <= o <= 0x0652 or o in (0x0670, 0x0640, 0x06DF, 0x06E0):
            continue
        if 0xE000 <= o <= 0xF8FF:
            continue
        if c in "أإآٱ":
            c = "ا"
        if c == "ى":
            c = "ي"
        out.append(c)
    return "".join(out)


def lire_wav16(p):
    import soundfile as sf
    x, sr = sf.read(str(p), dtype="float32")
    if x.ndim > 1:
        x = x.mean(axis=1)
    return x


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--nemo", default=str(
        BASE / "models" / "fastconformer-verifie-v1" / "causal-final.nemo"))
    ap.add_argument("--seuil_wer", type=float, default=0.30)
    ap.add_argument("--limite", type=int, default=None)
    a = ap.parse_args()

    import nemo.collections.asr as nemo_asr
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"chargement du modele sur {dev} : {a.nemo}", flush=True)
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(a.nemo, map_location=dev)
    model.eval()
    model.preprocessor.featurizer.dither = 0.0
    vocab = model.tokenizer.tokenizer.vocab if hasattr(model.tokenizer.tokenizer, "vocab") else None

    lignes = [json.loads(l) for l in open(TRAIN_MANIFEST, encoding="utf-8")]
    longs = [l for l in lignes if "train_wav_local" in l.get("audio_filepath", "")]
    autres = [l for l in lignes if "train_wav_local" not in l.get("audio_filepath", "")]
    if a.limite:
        longs = longs[:a.limite]
    print(f"{len(longs)} clips de recitation reelle a verifier "
          f"({len(autres)} autres -- TTS/ASC -- copies telles quelles)", flush=True)

    def decoder(pcm):
        with torch.no_grad():
            sig = torch.tensor(pcm, device=dev).unsqueeze(0)
            ln = torch.tensor([len(pcm)], device=dev)
            feats, flen = model.preprocessor(input_signal=sig, length=ln)
            enc, enc_len = model.encoder(audio_signal=feats, length=flen)
            lg = model.ctc_decoder(encoder_output=enc)
            ids_raw = lg[0].argmax(-1).cpu().numpy()
        # EFFONDREMENT GLOUTON obligatoire avant filtrage du blanc -- sans ca
        # chaque frame repetee produit un token duplique (bug trouve le
        # 2026-08-01 : donnait 127 % de WER median sur un corpus pourtant bon).
        out, prev = [], -1
        for t in ids_raw:
            if t != prev and t < model.tokenizer.vocab_size:
                out.append(int(t))
            prev = t
        return model.tokenizer.ids_to_text(out)

    gardes = rejetes = erreurs = 0
    wers = []
    with open(OUT_MANIFEST, "w", encoding="utf-8") as fout, \
         open(OUT_REJETS, "w", encoding="utf-8") as frej:
        for l in autres:
            fout.write(json.dumps(l, ensure_ascii=False) + "\n")
        for k, l in enumerate(longs):
            try:
                pcm = lire_wav16(l["audio_filepath"])
                if len(pcm) < 1600:
                    raise ValueError("trop court")
                hyp = norm(decoder(pcm))
            except Exception as e:
                erreurs += 1
                continue
            ref = norm(l["text"])
            e, n = wer(ref, hyp)
            w = e / max(1, n)
            wers.append(w)
            if n > 0 and w <= a.seuil_wer:
                fout.write(json.dumps(l, ensure_ascii=False) + "\n")
                gardes += 1
            else:
                l2 = dict(l)
                l2["wer_mesure"] = round(w, 3)
                l2["decode"] = hyp
                frej.write(json.dumps(l2, ensure_ascii=False) + "\n")
                rejetes += 1
            if (k + 1) % 3000 == 0:
                print(f"  {k+1}/{len(longs)}  gardes={gardes} rejetes={rejetes} "
                      f"erreurs={erreurs}  WER median jusqu'ici={100*np.median(wers):.1f}%",
                      flush=True)

    print(f"\n{gardes} clips GARDES / {len(longs)} ({100*gardes/max(1,len(longs)):.1f} %)")
    print(f"rejetes (WER > {a.seuil_wer:.0%}) : {rejetes}")
    print(f"erreurs de lecture/decodage : {erreurs}")
    print(f"WER median sur tout le corpus teste : {100*np.median(wers):.1f} %")
    print(f"\nmanifeste nettoye -> {OUT_MANIFEST}")
    print(f"rejets (pour audit) -> {OUT_REJETS}")


if __name__ == "__main__":
    main()
