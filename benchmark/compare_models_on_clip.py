"""Compare DEUX modèles sur LE MÊME audio, et mesure l'effet des symboles de
règles dans la cible d'alignement forcé.

POURQUOI (2026-07-20) : sur device, l'utilisateur constate « ça bloque
beaucoup » avec le nouveau modèle (stage1b-260h) alors que l'ancien
(mixed-e14) bloquait peu — même récitation, même mode. Chaque test sur
téléphone faisait varier trop de choses à la fois (voix, placement du micro,
timing, corrections en cascade). Ici tout est FIXE sauf ce qu'on fait varier.

TROIS QUESTIONS, dans l'ordre :
  Q1. Les deux modèles entendent-ils la même chose ? (transcription libre)
  Q2. Le nouveau modèle veut-il émettre des symboles de règles ? Combien ?
  Q3. `gop = forced - free` : quel est l'effet d'aligner sur le texte NU
      (sans symboles) alors que le décodage libre, lui, PEUT les émettre ?
      Hypothèse à tester : le modèle « gagne » des points en free grâce aux
      symboles, le chemin forcé ne le peut pas -> pénalité SYSTÉMATIQUE, sans
      aucune faute du récitant. Ce serait une régression introduite par le
      correctif du même jour (alignTarget repassé sur le texte nu).

⚠️ Le GOP de l'app est calculé côté Kotlin (ForcedAligner.kt). Ici il est
réimplémenté en Python (Viterbi CTC forcé). Les valeurs ABSOLUES ne sont donc
pas forcément identiques au dixième près à celles du téléphone ; ce qui est
fiable et exploitable, ce sont les ÉCARTS entre configurations mesurées sur
le même audio avec le même code.
"""
import os, json, sys
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"

import numpy as np
import torch
import soundfile as sf
import nemo.collections.asr as nemo_asr
from pathlib import Path

BASE = Path(__file__).parent
NEW = BASE / "models/fastconformer-quran-hybrid-v1/stage1b-260h/stage1b-final.nemo"
OLD = BASE / "models/fastconformer-quran-tajweed-mixed/mixed-e14-snapshot.nemo"
RULES = BASE / "data/quran_tajweed_rules/annotated.jsonl"
CANON = BASE / "data/quran_tajweed_rules/uthmani.jsonl"


def is_sym(ch):
    return 0xE000 <= ord(ch) <= 0xF8FF


def strip_sym(s):
    return "".join(c for c in s if not is_sym(c))


def show(t):
    return "".join(f"<{ord(c)-0xE000}>" if is_sym(c) else c for c in t)


def load(p):
    m = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(p), map_location="cpu")
    m.eval()
    m.preprocessor.featurizer.dither = 0.0
    return m


def logprobs(model, wav):
    audio, sr = sf.read(wav, dtype="float32")
    a = torch.tensor(audio).unsqueeze(0)
    l = torch.tensor([audio.shape[0]], dtype=torch.int64)
    with torch.no_grad():
        feats, flen = model.preprocessor(input_signal=a, length=l)
        enc, elen = model.encoder(audio_signal=feats, length=flen)
        logits = model.ctc_decoder(encoder_output=enc)
        return torch.log_softmax(logits, dim=-1)[0].numpy()


def greedy(lp, tok):
    ids = lp.argmax(axis=-1)
    blank = lp.shape[-1] - 1
    out, prev = [], None
    for i in ids:
        if i != prev and i != blank:
            out.append(int(i))
        prev = i
    return tok.ids_to_text(out)


def forced_nll(lp, ids, blank):
    """NLL du meilleur chemin CTC contraint à produire exactement `ids`.
    Viterbi standard sur la séquence étendue (blanks intercalés)."""
    T, V = lp.shape
    ext = [blank]
    for i in ids:
        ext += [i, blank]
    S = len(ext)
    NEG = -1e30
    dp = np.full(S, NEG)
    dp[0] = lp[0, ext[0]]
    if S > 1:
        dp[1] = lp[0, ext[1]]
    for t in range(1, T):
        nd = np.full(S, NEG)
        for s in range(S):
            best = dp[s]
            if s > 0 and dp[s - 1] > best:
                best = dp[s - 1]
            if s > 1 and ext[s] != blank and ext[s] != ext[s - 2] and dp[s - 2] > best:
                best = dp[s - 2]
            if best > NEG / 2:
                nd[s] = best + lp[t, ext[s]]
        dp = nd
    return max(dp[S - 1], dp[S - 2] if S > 1 else NEG)


def free_nll(lp):
    """Score du meilleur chemin LIBRE (aucune contrainte) = somme des max."""
    return float(lp.max(axis=-1).sum())


def main():
    wav = sys.argv[1]
    verses = [f"1:{i}" for i in range(1, 8)]

    ann = {}
    for l in open(RULES, encoding="utf-8"):
        r = json.loads(l); ann[r["verse_key"]] = r["text"]
    canon = {}
    for l in open(CANON, encoding="utf-8"):
        r = json.loads(l); canon[r["verse_key"]] = r["text"]

    text_annot = " ".join(ann[v] for v in verses)
    text_nu = " ".join(canon[v] for v in verses)

    for name, path in [("ANCIEN (mixed-e14)", OLD), ("NOUVEAU (rules-260h)", NEW)]:
        if not path.exists():
            print(f"\n### {name} : ABSENT ({path}) — ignoré")
            continue
        print(f"\n{'='*70}\n### {name}\n{'='*70}")
        m = load(path)
        lp = logprobs(m, wav)
        blank = lp.shape[-1] - 1
        tok = m.tokenizer

        hyp = greedy(lp, tok)
        nsym = sum(1 for c in hyp if is_sym(c))
        print(f"frames={lp.shape[0]}  symboles de règles émis={nsym}")
        print("ENTENDU :", show(hyp)[:300])

        f_free = free_nll(lp)
        # Cible NUE (comportement actuel de l'app depuis le correctif)
        ids_nu = tok.text_to_ids(text_nu)
        f_nu = forced_nll(lp, ids_nu, blank)
        # Cible ANNOTÉE (comportement d'avant le correctif)
        ids_an = tok.text_to_ids(text_annot)
        f_an = forced_nll(lp, ids_an, blank)

        print(f"\n  free (chemin libre)          = {f_free:10.2f}")
        print(f"  forced cible NUE             = {f_nu:10.2f}   gop = {f_nu - f_free:8.2f}")
        print(f"  forced cible ANNOTÉE         = {f_an:10.2f}   gop = {f_an - f_free:8.2f}")
        print(f"  -> écart entre les 2 cibles  = {f_an - f_nu:8.2f}"
              f"  ({'ANNOTÉE meilleure' if f_an > f_nu else 'NUE meilleure'})")

        # ── TEST DÉCISIF, sans biais de texte ────────────────────────────────
        # Les deux mesures ci-dessus forcent le texte CANONIQUE complet : si
        # l'audio n'en contient qu'une partie (ou si le décodage long-forme
        # dérive), l'écart est noyé dans la pénalité de non-correspondance.
        # Ici on force la PROPRE transcription du modèle -- donc zéro
        # désaccord de contenu possible -- une fois AVEC ses symboles, une fois
        # SANS. L'écart mesure EXACTEMENT ce qu'on veut savoir : combien coûte
        # le fait d'interdire au chemin forcé d'émettre les symboles que le
        # modèle veut produire.
        own = hyp
        own_nu = strip_sym(own)
        if own.strip():
            f_own_sym = forced_nll(lp, tok.text_to_ids(own), blank)
            f_own_nu = forced_nll(lp, tok.text_to_ids(own_nu), blank)
            print(f"\n  [test décisif — sur sa PROPRE transcription]")
            print(f"  forced AVEC symboles         = {f_own_sym:10.2f}")
            print(f"  forced SANS symboles         = {f_own_nu:10.2f}")
            print(f"  -> coût d'interdire les symboles = {f_own_nu - f_own_sym:8.2f}"
                  f"  ({'PÉNALITÉ' if f_own_nu < f_own_sym else 'aucun coût'})")


if __name__ == "__main__":
    main()
