#!/usr/bin/env python3
"""Confronte CHAQUE mot non vert d'une recette au FLUX BRUT. Etape obligatoire.

Demande utilisateur 2026-07-31 : « verifie bien les wav » puis « rajoute
surtout ca pour la prochaine recitation ». Le log dit ce que l'app a CRU ; seul
l'audio dit ce qui a ete PRONONCE. Sans cette confrontation, un tableau de mots
non verts n'est qu'un releve — on ne sait pas si l'app a tort ou si le
recitateur a rate le mot.

DEUX PIEGES DE METHODE, tous deux payes sur ce projet :

1. NE JAMAIS ECRIRE « absent » SUR UN TEST DE SOUS-CHAINE. Le modele decode
   souvent une quasi-homophone ou perd une lettre (`قاموا` -> `قالوا`,
   `لذهب` -> `لهب`). Trois « non » sur trois etaient faux le 2026-07-27. On
   IMPRIME donc le texte reellement decode de la zone, et c'est un humain qui
   tranche.

2. LA ZONE PEUT ETRE DECALEE. Mesure du 2026-07-31 : sur un alignement global
   de 295 mots sur 432 s, plusieurs zones decodaient le texte des mots
   VOISINS -- le mot n'etait pas absent, c'est le reperage qui derivait. Une
   zone qui rend le texte d'un autre mot est donc un resultat INDECIDABLE, pas
   une absence. Le script le dit explicitement au lieu de conclure.

Usage :
    PYTHONPATH=... /usr/bin/python3.14 verifier_non_verts_v2.py <dossier_recette>
"""
import json
import os
import re
import sys
from pathlib import Path

os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import numpy as np

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))


def main():
    d = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    modele = sys.argv[2] if len(sys.argv) > 2 else "/tmp/claude-1000/modele"
    import onnxruntime as ort
    import sentencepiece as spm
    from assainir_corpus_fautes import lire_wav
    from banc_deux_passes import decode
    from banc_regles_gop import logprobs_flux, spans_mots

    txt = (d / "session.log").read_text(encoding="utf-8", errors="replace")
    pat = re.compile(r'\[V2\] mot=(\d+) "([^"]*)" -> (\S+) \| (.*)')
    dernier = {}
    for l in txt.splitlines():
        m = pat.search(l)
        if m:
            dernier[int(m.group(1))] = (m.group(2), m.group(3), m.group(4))
    if not dernier:
        raise SystemExit("aucune ligne [V2] mot=... : mauvaise recette ?")
    n = max(dernier) + 1
    cible = [dernier.get(i, ("", "", ""))[0] for i in range(n)]
    suspects = [i for i, v in sorted(dernier.items()) if "vert" not in v[1]]
    print(f"{n} mots, {len(suspects)} non verts a confronter au WAV\n")

    wavs = sorted((d / "wav").glob("stream_*.wav"))
    if not wavs:
        raise SystemExit("aucun stream_*.wav : le flux brut n'a pas ete ecrit")
    pcm = lire_wav(wavs[0])
    pieces = json.load(open(Path(modele) / "vocab.json", encoding="utf-8"))
    sp = spm.SentencePieceProcessor(
        model_file=str(BASE / "tokenizers" / "tajweed_bpe_v1" / "tokenizer.model"))
    sess = ort.InferenceSession(str(Path(modele) / "model.onnx"),
                                providers=["CPUExecutionProvider"])
    lp = logprobs_flux(sess, pcm)

    # ALIGNEMENT GLOBAL — et une TENTATIVE PAR TRANCHES, MESUREE PIRE.
    #
    # L'alignement force unique sur 433 s et 295 mots DERIVE : le 2026-07-31,
    # 4 mots suspects sur 7 voyaient leur zone decoder le texte d'un VOISIN.
    # J'ai donc essaye d'avancer par tranches de 45 s en reportant un pointeur
    # de mot, comme le fait la bande de l'app. RESULTAT MESURE : pire encore --
    # les 7 zones tombaient a cote, la ou le global en tranchait 3. Le report
    # de pointeur derivait davantage que ce qu'il devait corriger.
    # Revenu au global, qui reste le moins mauvais. La piste par tranches n'est
    # pas morte : elle demande de vrais points de recalage (les silences que
    # l'app utilise deja pour couper), pas une arithmetique d'avance.
    spans = spans_mots(sp, lp, cible)
    print(f"flux {len(pcm)/16000:.0f} s, {lp.shape[0]} frames, "
          f"{sum(1 for s in spans if s)}/{n} mots alignes\n")

    E = 1280
    print(f"{'mot':>4} | {'attendu':<14} | {'etat':<17} | "
          f"{'decode de la zone (+/- 1,5 s)':<44} | verdict")
    print("-" * 104)
    for i in suspects:
        att, etat, _ = dernier[i]
        s = spans[i] if i < len(spans) else None
        if s is None:
            print(f"{i:>4} | {att[:14]:<14} | {etat:<17} | (non aligne)"
                  f"{'':<32} | INDECIDABLE")
            continue
        a = max(0, s[0] * E - 24000)
        b = min(len(pcm), s[1] * E + 24000)
        zone = decode(logprobs_flux(sess, pcm[a:b]), pieces)
        # Le mot est-il la ? Et sinon, la zone parle-t-elle d'un VOISIN ?
        present = att and att in zone
        voisins = [cible[j] for j in (i - 2, i - 1, i + 1, i + 2)
                   if 0 <= j < n and cible[j]]
        derive = any(v in zone for v in voisins)
        verdict = ("PRESENT" if present else
                   "ZONE DECALEE (texte d'un voisin) -> INDECIDABLE" if derive
                   else "a LIRE a l'oeil")
        print(f"{i:>4} | {att[:14]:<14} | {etat:<17} | {zone[:44]:<44} | {verdict}")
    print("\nAucun « absent » n'est ecrit par ce script : il n'imprime que ce "
          "que le modele a reellement decode. Conclure est un acte humain.")


if __name__ == "__main__":
    main()
