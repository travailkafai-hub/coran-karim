"""Calibration GOP par mot -- construit une ligne de base (moyenne/ecart-type)
du gop pour chaque mot canonique du Coran, a partir de VRAIES recitations
(pas TTS/ASC), pour remplacer le seuil global fixe (-0.45/-1.60) par un
seuil NORMALISE par mot.

POURQUOI (2026-07-20 nuit) : mesure sur 3 pistes d'entrainement differentes
la meme soiree -- certains mots (Bismillah, mots a chadda) ont un gop
structurellement bas MEME bien recites (ex. "ٱللَّهِ" ~-5 a -6), tandis que
d'autres sont a ~0.00. Un seuil global condamne injustement les premiers.
Idee utilisateur : calculer un z-score par mot (gop - moyenne_mot) / ecart_type_mot
au lieu de comparer le gop brut a un seuil unique.

METHODE :
- Modele : le checkpoint deploye (piste 3, mixed-e14 + tokenizer regles + CTC-only).
- Corpus : UNIQUEMENT les clips Coran reels (train_wav_local, PAS tts_augmentation
  ni asc) -- ce sont des recitations professionnelles verifiees, la meilleure
  approximation de "correct" disponible.
- Alignement forcé sur le texte NU (symboles retires), memes correctifs que
  ForcedAligner.kt (masquage+renormalisation symboles, exclusion chadda nu) --
  coherent avec ce que l'app calcule reellement au jugement (alignTarget=training).
- Regroupe par mot CANONIQUE NU (symboles retires de la cle) pour ne pas
  fragmenter les stats selon qu'une regle soit annotee ou non a cette occurrence
  precise -- mais garde une trace separee "avec regle attendue" vs "sans" pour
  verifier si ca fait une vraie difference (demande utilisateur : "tenir compte
  du tajwid dans ces mots").
"""
import os, json, sys, random
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
import numpy as np, torch, soundfile as sf
import nemo.collections.asr as nemo_asr
from pathlib import Path
import collections

BASE = Path(__file__).parent
MODEL = BASE / "models/fastconformer-quran-mixed-e14-rules-ctc/fastconformer-quran-best.nemo"
MANIFEST = BASE / "nemo_manifests_rules/train_manifest.jsonl"
OUT = BASE / "data/gop_word_baseline.json"

def is_sym(c): return 0xE000 <= ord(c) <= 0xF8FF
def strip_sym(s): return "".join(c for c in s if not is_sym(c))


def main():
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 60000

    rows = []
    for l in open(MANIFEST, encoding="utf-8"):
        r = json.loads(l)
        p = r["audio_filepath"]
        if "train_wav" in p:  # reel (train_wav_local ou train_wav), exclut tts_augmentation/asc
            rows.append(r)
    random.seed(7)
    random.shuffle(rows)
    rows = rows[:limit]
    print(f"{len(rows)} clips Coran reels a traiter (sur corpus filtre)")

    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(MODEL), map_location="cpu")
    model.eval(); model.preprocessor.featurizer.dither = 0.0
    if torch.cuda.is_available():
        model = model.cuda()
    tok = model.tokenizer

    vocab_size = model.ctc_decoder.num_classes_with_blank
    sym_mask = np.zeros(vocab_size, dtype=bool)
    shadda_mask = np.zeros(vocab_size, dtype=bool)
    for i in range(vocab_size - 1):
        piece = tok.ids_to_text([i])
        if any(is_sym(c) for c in piece): sym_mask[i] = True
        if piece.replace("▁", "") == "ّ": shadda_mask[i] = True
    print(f"tokens symboles={sym_mask.sum()} tokens chadda-nu={shadda_mask.sum()}")

    # word -> {"gops": [...], "gops_with_rule": [...], "gops_without_rule": [...]}
    stats = collections.defaultdict(lambda: {"all": [], "with_rule": [], "without_rule": []})

    processed = 0
    skipped = 0
    for ri, r in enumerate(rows):
        if ri % 2000 == 0:
            print(f"  {ri}/{len(rows)} clips ({processed} ok, {skipped} ignores)...", flush=True)
        try:
            audio, sr = sf.read(r["audio_filepath"], dtype="float32")
        except Exception:
            skipped += 1; continue
        if audio.ndim > 1: audio = audio.mean(axis=1)
        dur = len(audio) / sr
        if dur < 0.3 or dur > 20.0:
            skipped += 1; continue

        annotated_text = r["text"]
        words_ann = annotated_text.split()
        words_nu = [strip_sym(w) for w in words_ann]
        if not words_nu:
            skipped += 1; continue

        a = torch.tensor(audio).unsqueeze(0)
        l = torch.tensor([audio.shape[0]], dtype=torch.int64)
        dev = next(model.parameters()).device
        a, l = a.to(dev), l.to(dev)
        try:
            with torch.no_grad():
                feats, flen = model.preprocessor(input_signal=a, length=l)
                enc, elen = model.encoder(audio_signal=feats, length=flen)
                logits = model.ctc_decoder(encoder_output=enc)[0].cpu().numpy()
        except Exception:
            skipped += 1; continue
        lp_raw = torch.log_softmax(torch.tensor(logits), dim=-1).numpy()
        T, V = lp_raw.shape
        blank = V - 1
        if T < 2:
            skipped += 1; continue

        # scoringLp : masque+renormalise les symboles (identique ForcedAligner.kt)
        scoringLp = np.empty_like(lp_raw)
        for ti in range(T):
            row = lp_raw[ti]
            kept = ~sym_mask
            mx = row[kept].max()
            s = np.exp((row[kept] - mx).astype(np.float64)).sum()
            logNorm = mx + np.log(s)
            newrow = row - logNorm
            newrow[sym_mask] = -1e9
            scoringLp[ti] = newrow

        ext = [blank]; word_of_state = [-1]
        ok = True
        for wi, w in enumerate(words_nu):
            ids = tok.text_to_ids(w)
            if not ids:
                ok = False; break
            for i in ids:
                ext += [i, blank]; word_of_state += [wi, wi]
        if not ok:
            skipped += 1; continue
        S = len(ext)
        if S > 2 * T:  # texte trop long pour l'audio -> alignement infaisable
            skipped += 1; continue
        NEG = -1e30
        dp = np.full(S, NEG); bp = np.zeros((T, S), dtype=np.int32)
        dp[0] = scoringLp[0, ext[0]]
        if S > 1: dp[1] = scoringLp[0, ext[1]]
        for t in range(1, T):
            nd = np.full(S, NEG)
            for s in range(S):
                best = dp[s]; from_ = 0
                if s > 0 and dp[s-1] > best: best = dp[s-1]; from_ = 1
                if s > 1 and ext[s] != blank and ext[s] != ext[s-2] and dp[s-2] > best: best = dp[s-2]; from_ = 2
                if best > NEG/2: nd[s] = best + scoringLp[t, ext[s]]
                bp[t, s] = from_
            dp = nd
        s_end = int(np.argmax(dp))
        if dp[s_end] <= NEG/2:
            skipped += 1; continue
        frame_state = [0]*T; frame_state[T-1] = s_end
        for t in range(T-1, 0, -1):
            s = frame_state[t]; frame_state[t-1] = s - int(bp[t, s])
        word_frames = collections.defaultdict(list)
        for t in range(T):
            w = word_of_state[frame_state[t]]
            if w >= 0: word_frames[w].append(t)

        for wi, w in enumerate(words_nu):
            frames = word_frames.get(wi)
            if not frames:
                continue
            fsum, frsum, n = 0.0, 0.0, 0
            for t in frames:
                s = frame_state[t]
                tokid = ext[s]
                if tokid < len(shadda_mask) and shadda_mask[tokid]:
                    continue  # chadda nu exclu du gop, comme ForcedAligner.kt
                lp = scoringLp[t]
                fsum += lp[tokid]; frsum += lp.max(); n += 1
            if n == 0:
                continue
            gop = (fsum - frsum) / n
            has_rule = any(is_sym(c) for c in words_ann[wi])
            entry = stats[w]
            entry["all"].append(gop)
            (entry["with_rule"] if has_rule else entry["without_rule"]).append(gop)
        processed += 1

    print(f"\n{processed} clips traites, {skipped} ignores")
    print(f"{len(stats)} mots distincts observes")

    result = {}
    for w, d in stats.items():
        vals = d["all"]
        if len(vals) < 3:
            continue
        arr = np.array(vals)
        entry = {
            "n": len(vals),
            "mean": float(arr.mean()),
            "std": float(arr.std()) if len(vals) > 1 else 0.0,
        }
        if len(d["with_rule"]) >= 3:
            wa = np.array(d["with_rule"])
            entry["mean_with_rule"] = float(wa.mean())
            entry["n_with_rule"] = len(d["with_rule"])
        if len(d["without_rule"]) >= 3:
            wo = np.array(d["without_rule"])
            entry["mean_without_rule"] = float(wo.mean())
            entry["n_without_rule"] = len(d["without_rule"])
        result[w] = entry

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=1)
    print(f"\nEcrit : {OUT} ({len(result)} mots avec n>=3)")

    # Aperçu : mots avec la moyenne la plus basse (structurellement durs)
    by_mean = sorted(result.items(), key=lambda kv: kv[1]["mean"])
    print("\n20 mots au gop moyen le plus bas (structurellement durs) :")
    for w, e in by_mean[:20]:
        print(f"  {w:<20} moyenne={e['mean']:>7.2f}  ecart-type={e['std']:>6.2f}  n={e['n']}")


if __name__ == "__main__":
    main()
