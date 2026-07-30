#!/usr/bin/env python3
"""PASSE 2 — controle le mot faute, PUIS assemble la phrase. Jamais l'inverse.

L'ordre est tout l'interet du decoupage en deux passes. Synthetiser la phrase
entiere donne 10 a 29 % de fautes audibles ; assembler des mots synthetises
seuls sans controle donne 42 % ; controler le clip du mot AVANT de le coller
ramene le rendement de la phrase a celui du mot isole (83 % sur les lettres).

CRITERE, sur le clip du mot seul et rien d'autre :

    garder  <=>  logP(mot faute | audio faute) > logP(mot correct | audio faute)
            ET   logP(mot correct | audio correct) > logP(mot faute | audio correct)

La seconde condition n'est pas decorative : si le clip « correct » porte lui
aussi la faute, la paire n'oppose plus rien et la phrase correcte serait
etiquetee a tort.

L'ARTEFACT DE MONTAGE NE DOIT RIEN PREDIRE. Les deux versions sont assemblees
par le MEME chemin, a partir des MEMES clips de mots, a un seul mot pres :
memes coutures, meme prosodie hachee, meme absence de coarticulation. Un modele
qui apprendrait « ca sonne colle-a-colle donc il y a une faute » n'y gagnerait
rien. Sans cette symetrie on entrainerait un detecteur de montage, pas un
detecteur de faute.

CE QUE CA COUTE, ET QUI EST ASSUME : une phrase assemblee ne sonne pas comme
une recitation continue (pas de coarticulation, intonation de fin de phrase sur
chaque mot). C'est un ECART DE DOMAINE reel. Il est borne par le fait que ces
clips restent minoritaires face aux ~75 000 phrases de recitation naturelle du
corpus, et il doit etre verifie a la fin sur le banc device -- pas sur le WER.

Usage :
    PYTHONPATH=... /usr/bin/python3.14 assembler_phrases_fautees.py \
        --dossier data/tts_phrases_concat [--travailleurs 12]
"""
import argparse
import json
import os
import sys
import time
import wave
from multiprocessing import Pool
from pathlib import Path

os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import numpy as np

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))
from assainir_corpus_fautes import demarrer, lire_wav, score_force  # noqa: E402

SR = 16000
FONDU_MS = 25
SILENCE_MS = 40


def ecrire_wav(chemin, x, sr=SR):
    x = np.clip(np.asarray(x, dtype=np.float32), -1.0, 1.0)
    with wave.open(str(chemin), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def enlever_silence(x, seuil=0.015, marge=int(0.02 * SR)):
    """Sans ca, le blanc propre a chaque synthese s'additionne et la phrase
    devient hachee bien au-dela de ce qu'impose l'assemblage."""
    fort = np.where(np.abs(x) > seuil)[0]
    if len(fort) == 0:
        return x
    return x[max(0, fort[0] - marge):min(len(x), fort[-1] + marge)]


def assembler(clips):
    n_f = int(FONDU_MS * SR / 1000)
    silence = np.zeros(int(SILENCE_MS * SR / 1000), dtype=np.float32)
    out = np.zeros(0, dtype=np.float32)
    for k, c in enumerate(clips):
        c = enlever_silence(c).astype(np.float32)
        if k > 0:
            out = np.concatenate([out, silence])
        if len(out) >= n_f and len(c) >= n_f:
            f = np.linspace(0, 1, n_f, dtype=np.float32)
            out[-n_f:] = out[-n_f:] * (1 - f) + c[:n_f] * f
            c = c[n_f:]
        out = np.concatenate([out, c])
    return out


def _scores(chemin, a, b):
    pcm = lire_wav(chemin)
    if len(pcm) < 3200:
        return None
    f = _mel(pcm).astype(np.float32)
    out = _sess.run(None, {"audio_signal": f[None],
                           "length": np.array([f.shape[1]], dtype=np.int64)})
    lp = np.asarray(out[0][0], dtype=np.float32)
    return score_force(lp, _sp.encode(a)), score_force(lp, _sp.encode(b))


def controler(r):
    """Le mot faute porte-t-il la faute, et le mot correct le canonique ?"""
    global _sess, _sp, _mel
    from assainir_corpus_fautes import _etat
    _sess, _sp, _mel = _etat["sess"], _etat["sp"], _etat["mel"]
    d = Path(r["_dossier"]) / "mots"
    try:
        sf_ = _scores(d / f"{r['id']}_faute.wav", r["mot_faute"], r["mot_correct"])
        sc_ = _scores(d / f"{r['id']}_m{r['mot_index']:02d}.wav",
                      r["mot_correct"], r["mot_faute"])
        if sf_ is None or sc_ is None:
            return "COURT", None
        ok = sf_[0] > sf_[1] and sc_[0] > sc_[1]
        return ("OK" if ok else "INAUDIBLE"), round((sf_[0] - sf_[1]) + (sc_[0] - sc_[1]), 3)
    except Exception as e:
        return f"ERREUR:{str(e)[:40]}", None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--dossier", default=str(BASE / "data" / "tts_phrases_concat"))
    p.add_argument("--modele", default="/tmp/claude-1000/modele/model.onnx")
    p.add_argument("--tokenizer",
                   default=str(BASE / "tokenizers" / "tajweed_bpe_v1" / "tokenizer.model"))
    p.add_argument("--travailleurs", type=int, default=12)
    args = p.parse_args()

    d = Path(args.dossier)
    (d / "wav").mkdir(parents=True, exist_ok=True)
    plan = [json.loads(l) for l in open(d / "plan.jsonl", encoding="utf-8")]
    for r in plan:
        r["_dossier"] = str(d)
    print(f"{len(plan)} phrases planifiees, controle du mot faute...", flush=True)

    t0 = time.time()
    verdicts = []
    with Pool(args.travailleurs, initializer=demarrer,
              initargs=(args.modele, args.tokenizer)) as pool:
        for k, v in enumerate(pool.imap(controler, plan, chunksize=8)):
            verdicts.append(v)
            if (k + 1) % 200 == 0:
                print(f"  {k+1}/{len(plan)}...", flush=True)

    manifeste = open(d / "manifest.jsonl", "w", encoding="utf-8")
    rejets = open(d / "manifest_rejete.jsonl", "w", encoding="utf-8")
    gardees = 0
    for r, (verdict, marge) in zip(plan, verdicts):
        r.pop("_dossier", None)
        r["_verdict"], r["_marge"] = verdict, marge
        if verdict != "OK":
            rejets.write(json.dumps(r, ensure_ascii=False) + "\n")
            continue
        clips = [lire_wav(d / "mots" / f"{r['id']}_m{k:02d}.wav")
                 for k in range(len(r["mots"]))]
        faute = lire_wav(d / "mots" / f"{r['id']}_faute.wav")
        i = r["mot_index"]
        ecrire_wav(d / "wav" / f"{r['id']}_correct.wav", assembler(clips))
        ecrire_wav(d / "wav" / f"{r['id']}_faute.wav",
                   assembler(clips[:i] + [faute] + clips[i + 1:]))
        mots_f = r["mots"][:i] + [r["mot_faute"]] + r["mots"][i + 1:]
        manifeste.write(json.dumps({
            "clip_faute": f"{r['id']}_faute.wav",
            "clip_correct": f"{r['id']}_correct.wav",
            "text": " ".join(mots_f),          # etiquette = ce qui est PRONONCE
            "correct_text": r["correct_text"],
            "mot_index": i, "kind": r["kind"], "detail": r["detail"],
            "voice": r["voice"], "marge_mot": r["_marge"],
        }, ensure_ascii=False) + "\n")
        gardees += 1
    manifeste.close()
    rejets.close()

    import collections
    stats = collections.Counter(v for v, _ in verdicts)
    print(f"\n{gardees}/{len(plan)} = {100*gardees/max(1,len(plan)):.0f} % assemblees "
          f"({time.time()-t0:.0f} s)")
    print(f"  verdicts : {dict(stats)}")
    par = collections.defaultdict(lambda: [0, 0])
    for r, (v, _) in zip(plan, verdicts):
        cle = r["detail"].split(":")[0] if r["kind"] == "harakat" else r["detail"]
        par[cle][1] += 1
        par[cle][0] += v == "OK"
    print("\n  rendement par substitution (>= 5 cas) :")
    for c, (bon, tot) in sorted(par.items(), key=lambda kv: -kv[1][0] / max(1, kv[1][1])):
        if tot >= 5:
            print(f"    {c:14} {bon:>4}/{tot:<4} {100*bon/tot:>5.0f} %")
    print(f"\nCONTROLE FINAL sur la PHRASE assemblee (et non plus le mot) :")
    print(f"  controle_paires_fautees.py --dossier {d}")


if __name__ == "__main__":
    main()
