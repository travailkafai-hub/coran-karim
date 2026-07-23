"""Le JUGE DE PAIX de la détection des règles tajwid.

PRINCIPE : on donne au modèle un récitateur PROFESSIONNEL (ici Mishary,
capté au micro par l'utilisateur le 2026-07-20). Un professionnel applique le
tajwid. Donc, pour tout mot que le modèle transcrit correctement :
  - s'il émet le symbole attendu  -> règle détectée (vrai positif)
  - s'il ne l'émet PAS            -> FAUSSE ACCUSATION : l'app dirait
                                     « règle non réalisée » à tort.

C'est exactement ce que fait `RecitationNotifier.unrealizedRulesFor` dans
l'app. Le mesurer ici, hors téléphone, permet de savoir AVANT de l'imposer à
l'utilisateur si le mode tajwid accuse juste ou au hasard.

Ce test ne mesure PAS la détection d'une règle VOLONTAIREMENT ratée (il
faudrait un récitant qui les omette exprès -- le vrai set humain, toujours
pas constitué). Il mesure le taux de FAUX NÉGATIFS sur récitation correcte,
qui est la première chose à connaître : une app qui accuse un professionnel
est inutilisable, quelle que soit sa sensibilité aux vraies fautes.

Découpe l'audio en fenêtres (le modèle est entraîné sur <= 20 s ; un décodage
long-forme en une passe dérive).
"""
import os, json, sys, unicodedata
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"

import numpy as np, torch, soundfile as sf
import nemo.collections.asr as nemo_asr
from pathlib import Path
from difflib import SequenceMatcher
import collections

BASE = Path(__file__).parent
NEW = Path("/tmp/claude-1000/-media-kafai-NouveauNom-Coran-Karim/df7744f5-205b-458b-b71f-f9ef1062f18c/scratchpad/piste3-epoch2.nemo")
RULES = BASE / "data/quran_tajweed_rules/annotated.jsonl"
CANON = BASE / "data/quran_tajweed_rules/uthmani.jsonl"
RULES_MAP = BASE / "data/quran_tajweed_rules/rules_map.json"
WIN_S = 15.0


def is_sym(c): return 0xE000 <= ord(c) <= 0xF8FF
def strip_sym(s): return "".join(c for c in s if not is_sym(c))
def syms_of(w): return [ord(c) - 0xE000 for c in w if is_sym(c)]


def norm(s):
    """Squelette de comparaison : sans harakat, variantes repliées."""
    s = unicodedata.normalize("NFC", strip_sym(s))
    for a, b in [("ٱ","ا"),("أ","ا"),("إ","ا"),("آ","ا"),("ى","ي"),("ة","ه")]:
        s = s.replace(a, b)
    return "".join(c for c in s if not (0x064B <= ord(c) <= 0x0652)).strip()


def main():
    wav = sys.argv[1]
    surah = int(sys.argv[2]) if len(sys.argv) > 2 else 2

    names = json.load(open(RULES_MAP, encoding="utf-8"))
    names = list(names.keys()) if isinstance(names, dict) else names

    ann = {}
    for l in open(RULES, encoding="utf-8"):
        r = json.loads(l)
        if r["verse_key"].startswith(f"{surah}:"):
            ann[int(r["verse_key"].split(":")[1])] = r["text"]

    expected = []  # (mot_annote, no_verset)
    for a in sorted(ann):
        for w in ann[a].replace("۞", " ").split():
            if w.strip():
                expected.append((w, a))

    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(NEW), map_location="cpu")
    model.eval(); model.preprocessor.featurizer.dither = 0.0
    if torch.cuda.is_available():
        model = model.cuda()

    audio, sr = sf.read(wav, dtype="float32")
    win = int(WIN_S * sr)
    hyp_words = []
    for st in range(0, len(audio), win):
        chunk = audio[st:st + win]
        if len(chunk) < sr * 0.5:
            break
        a = torch.tensor(chunk).unsqueeze(0)
        l = torch.tensor([len(chunk)], dtype=torch.int64)
        if torch.cuda.is_available():
            a, l = a.cuda(), l.cuda()
        with torch.no_grad():
            f, fl = model.preprocessor(input_signal=a, length=l)
            e, el = model.encoder(audio_signal=f, length=fl)
            lp = torch.log_softmax(model.ctc_decoder(encoder_output=e), dim=-1)[0].cpu().numpy()
        ids = lp.argmax(axis=-1); blank = lp.shape[-1] - 1
        out, prev = [], None
        for i in ids:
            if i != prev and i != blank: out.append(int(i))
            prev = i
        hyp_words += [w for w in model.tokenizer.ids_to_text(out).split() if w.strip()]

    print(f"audio {len(audio)/sr:.0f}s -> {len(hyp_words)} mots transcrits, "
          f"{len(expected)} mots attendus (sourate {surah})")

    # Aligne transcrit <-> attendu sur le SQUELETTE (indépendant des symboles)
    sm = SequenceMatcher(None, [norm(w) for w, _ in expected],
                         [norm(w) for w in hyp_words], autojunk=False)
    detected = collections.Counter(); missed = collections.Counter()
    matched = 0
    examples = collections.defaultdict(list)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag != "equal":
            continue
        for k in range(i2 - i1):
            exp_w, verse = expected[i1 + k]
            hyp_w = hyp_words[j1 + k]
            exp_s, hyp_s = set(syms_of(exp_w)), set(syms_of(hyp_w))
            if not exp_s:
                continue
            matched += 1
            for s in exp_s:
                nm = names[s] if s < len(names) else f"?{s}"
                if s in hyp_s:
                    detected[nm] += 1
                else:
                    missed[nm] += 1
                    if len(examples[nm]) < 2:
                        examples[nm].append(f"{surah}:{verse} {strip_sym(exp_w)}")

    print(f"mots alignés portant au moins une règle : {matched}\n")
    print(f"{'règle':<22}{'détectée':>9}{'ratée':>7}{'rappel':>9}   (rappel = détectée / attendue)")
    tot_d = tot_m = 0
    for nm in sorted(set(detected) | set(missed), key=lambda x: -(detected[x] + missed[x])):
        d, m_ = detected[nm], missed[nm]
        tot_d += d; tot_m += m_
        r = 100 * d / (d + m_) if d + m_ else 0
        flag = "  <-- FAUSSES ACCUSATIONS" if r < 80 else ""
        print(f"{nm:<22}{d:>9}{m_:>7}{r:>8.0f}%{flag}")
        if m_ and examples[nm]:
            print(f"{'':<22}ex. non détectée : {', '.join(examples[nm])}")
    if tot_d + tot_m:
        print(f"\nTOTAL : {tot_d} détectées / {tot_m} ratées "
              f"-> rappel global {100*tot_d/(tot_d+tot_m):.0f}%")
        print(f"=> sur un récitateur PROFESSIONNEL, {tot_m} signalements "
              f"« règle non réalisée » seraient FAUX.")


if __name__ == "__main__":
    main()
