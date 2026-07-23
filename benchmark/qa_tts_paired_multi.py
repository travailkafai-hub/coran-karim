#!/usr/bin/env python3
"""QA des clips TTS APPARIES (generate_tts_paired.py) -- 2026-07-22.

Reprend les criteres acoustiques de qa_tts_quality.py (duree, RMS, ecretage)
et AJOUTE la verification qui manquait et qui est la plus importante ici :

    ── LE CLIP DIT-IL VRAIMENT LE TEXTE DE SON ETIQUETTE ? ──
    Un clip peut etre parfaitement audible (duree OK, RMS OK) et pourtant
    prononcer autre chose que ce qu'on a demande au TTS -- XTTS peut avaler
    une lettre, mal rendre une harakat, ou "normaliser" une forme inhabituelle
    (or nos variantes fautives SONT des formes inhabituelles par construction :
    ٱلْوَعْضَ, مَّرْكُومٌ...). Un tel clip empoisonne l'entrainement en silence :
    on apprendrait au modele qu'un audio disant X s'ecrit Y.

    Verification : on transcrit chaque clip avec le modele ASR et on compare
    au texte demande (CER). Un CER eleve = le TTS n'a pas dit ce qu'on voulait.

⚠️ PIEGE A NE PAS CONFONDRE (raison d'etre du seuil different par type) :
    Sur un clip FAUTIF, un CER eleve peut avoir DEUX causes opposees :
      (a) le TTS a mal genere            -> clip a jeter
      (b) le TTS a bien genere, mais le MODELE ASR "corrige" vers le canonique
          -> c'est le biais canonique, precisement ce qu'on veut corriger :
             le clip est BON et meme particulierement precieux.
    On ne peut donc pas rejeter un clip fautif sur son seul CER. On compare
    donc au canonique : si la transcription colle au CANONIQUE plutot qu'au
    texte demande, c'est (b) -- on garde et on COMPTE (mesure du biais).
    Si elle ne colle a AUCUN des deux, c'est (a) -- on rejette.

Usage :
    PYTHONPATH=... python3.14 qa_tts_paired.py <modele.nemo> [--limit N]
"""
import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
import soundfile as sf
import torch
import torch.nn.functional as F
import nemo.collections.asr as nemo_asr

BASE = Path(__file__).parent
PAIRED = BASE / "data" / "tts_paired"
MANIFEST = PAIRED / "manifest.jsonl"
WAV_DIR = PAIRED / "wav"
OUT_CLEAN = PAIRED / f"manifest_clean_{__import__("os").environ.get("TAG","x")}.jsonl"
OUT_REJECT = PAIRED / f"rejets_{__import__("os").environ.get("TAG","x")}.jsonl"

# Criteres acoustiques (memes valeurs que qa_tts_quality.py)
MIN_DURATION, MAX_DURATION = 0.4, 30.0
MIN_RMS = 0.01
MAX_CLIP_RATIO = 0.01     # >1 % d'echantillons satures = ecretage

# Seuil de CER au-dela duquel on considere que le clip ne dit pas son texte.
# 0.5 = la moitie des caracteres divergent : tres permissif volontairement
# (l'ASR n'est pas parfait, surtout sur mot isole hors contexte) -- on ne veut
# attraper que les echecs FRANCS de generation, pas noter la qualite du TTS.
CER_REJECT = 0.5


class _Zero(torch.nn.Module):
    def forward(self, lp, t, il, tl):
        return lp.sum() * 0.0


def load_model(path):
    m = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        path, map_location="cpu")
    if hasattr(m, "joint") and hasattr(m.joint, "set_fuse_loss_wer"):
        m.joint.set_fuse_loss_wer(False, loss=None, metric=None)
    m.loss = _Zero()
    m.ctc_loss_weight = 1.0
    m.eval()
    if torch.cuda.is_available():
        m = m.cuda()
    return m


@torch.no_grad()
def transcribe(model, audio, device):
    at = torch.tensor(audio, device=device).unsqueeze(0)
    lt = torch.tensor([audio.shape[0]], dtype=torch.int64, device=device)
    f, fl = model.preprocessor(input_signal=at, length=lt)
    enc, _ = model.encoder(audio_signal=f, length=fl)
    lp = F.log_softmax(model.ctc_decoder(encoder_output=enc), dim=-1)
    ids = lp[0].argmax(-1).tolist()
    blank = model.tokenizer.vocab_size
    out, prev = [], -1
    for i in ids:
        if i != prev and i != blank:
            out.append(i)
        prev = i
    return model.tokenizer.ids_to_text(out)


def cer(a, b):
    """Character error rate (Levenshtein normalise) entre deux chaines."""
    a, b = a.strip(), b.strip()
    if not a and not b:
        return 0.0
    if not a or not b:
        return 1.0
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1,
                           prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[len(b)] / max(len(a), len(b))


def check_acoustic(audio, sr):
    """(ok, raison) sur les seuls criteres acoustiques."""
    dur = len(audio) / sr
    if dur < MIN_DURATION:
        return False, f"TROP_COURT({dur:.2f}s)"
    if dur > MAX_DURATION:
        return False, f"TROP_LONG({dur:.1f}s)"
    rms = float(np.sqrt(np.mean(audio ** 2)))
    if rms < MIN_RMS:
        return False, f"SILENCIEUX(rms={rms:.4f})"
    if float(np.mean(np.abs(audio) > 0.99)) > MAX_CLIP_RATIO:
        return False, "ECRETAGE"
    return True, ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model")
    ap.add_argument("--limit", type=int, default=0, help="0 = tout")
    args = ap.parse_args()

    rows = [json.loads(l) for l in open(MANIFEST, encoding="utf-8")]
    if args.limit:
        rows = rows[:args.limit]
    print(f"clips a verifier : {len(rows)}", flush=True)

    model = load_model(args.model)
    device = next(model.parameters()).device

    stats = Counter()
    rejets, clean = [], []
    cer_par_type = defaultdict(list)
    biais_canonique = 0

    for i, r in enumerate(rows):
        p = WAV_DIR / r["clip"]
        if not p.exists():
            stats["ABSENT"] += 1
            rejets.append({**r, "rejet": "ABSENT"})
            continue
        audio, sr = sf.read(p, dtype="float32")
        if audio.ndim > 1:
            audio = audio.mean(axis=1)
        if sr != 16000:
            import librosa
            audio = librosa.resample(audio, orig_sr=sr, target_sr=16000)

        ok, raison = check_acoustic(audio, 16000)
        if not ok:
            stats[raison.split("(")[0]] += 1
            rejets.append({**r, "rejet": raison})
            continue

        heard = transcribe(model, audio, device)
        c_demande = cer(heard, r["text"])
        cer_par_type["fautif" if r["is_error"] else "correct"].append(c_demande)

        if c_demande <= CER_REJECT:
            stats["OK"] += 1
            clean.append({**r, "heard": heard, "cer": round(c_demande, 3)})
            continue

        # CER eleve : distinguer "mal genere" de "biais canonique de l'ASR"
        if r["is_error"]:
            c_canon = cer(heard, r["correct_text"])
            if c_canon < c_demande:
                # l'ASR a entendu le CANONIQUE alors que le TTS disait la
                # faute -> clip valide, et cas precieux (mesure du biais)
                biais_canonique += 1
                stats["OK_BIAIS_CANONIQUE"] += 1
                clean.append({**r, "heard": heard, "cer": round(c_demande, 3),
                              "biais_canonique": True})
                continue
        stats["TEXTE_DIVERGENT"] += 1
        rejets.append({**r, "rejet": f"TEXTE_DIVERGENT(cer={c_demande:.2f})",
                       "heard": heard})

        if (i + 1) % 500 == 0:
            print(f"  {i+1}/{len(rows)}...", flush=True)

    with open(OUT_CLEAN, "w", encoding="utf-8") as f:
        for r in clean:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    with open(OUT_REJECT, "w", encoding="utf-8") as f:
        for r in rejets:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    n = len(rows)
    print("\n" + "=" * 66)
    print(f"RESULTAT QA : {len(clean)}/{n} clips retenus "
          f"({100*len(clean)/n:.1f} %)")
    print("=" * 66)
    for k, v in stats.most_common():
        print(f"   {k:<24s} {v:6d}  ({100*v/n:.1f} %)")

    print(f"\nCER moyen (transcription vs texte demande) :")
    for k, v in sorted(cer_par_type.items()):
        if v:
            print(f"   {k:<10s} moyenne {np.mean(v):.3f}   mediane "
                  f"{np.median(v):.3f}   n={len(v)}")

    if biais_canonique:
        print(f"\n⚠️  BIAIS CANONIQUE mesure : {biais_canonique} clips fautifs "
              f"que l'ASR a transcrits vers le CANONIQUE")
        print(f"    (clips CONSERVES -- ce sont justement les plus utiles a "
              f"l'entrainement)")

    # Integrite des paires : une paire n'a d'interet que COMPLETE (le meme
    # timbre doit porter le correct ET le fautif, sinon la correlation
    # voix<->erreur qu'on veut casser se reconstitue).
    par_paire = defaultdict(set)
    for r in clean:
        par_paire[r["pair_id"]].add(r["is_error"])
    completes = sum(1 for v in par_paire.values() if len(v) == 2)
    print(f"\nPaires COMPLETES (correct + fautif tous deux retenus) : "
          f"{completes}/{len(par_paire)}")
    print(f"   -> n'utiliser QUE ces paires a l'entrainement, sinon le "
          f"desequilibre recree la correlation voix<->erreur")
    print(f"\nmanifest propre  : {OUT_CLEAN}")
    print(f"rejets detailles : {OUT_REJECT}")


if __name__ == "__main__":
    main()
