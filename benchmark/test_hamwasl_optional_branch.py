#!/usr/bin/env python3
"""Test OFFLINE de la piste B : rendre l'alif-wasla OPTIONNEL dans la cible
d'alignement forcé (2026-07-22).

── LE PROBLÈME MESURÉ (session 2026-07-21 soir, device + corpus) ──
Le symbole de règle ham_wasl CASSE la fusion BPE entre ٱ et ل. Conséquence
mesurée sur le corpus d'entraînement du modèle rules-260h :
    lignes ANNOTÉES (58 612, la vraie récitation coranique) :
        ٱل soudé = 1 607 (1,6 %)   |   ٱ seul = 98 305 (98,4 %)
    lignes NON annotées (98 280, arabe général ASC/TTS, autre domaine) :
        ٱل soudé = 7 397 (72,4 %)  |   ٱ seul = 2 820
Le modèle a donc appris "ٱ seul" sur l'audio coranique, et le token soudé
`▁ٱلْعَ` presque uniquement sur de l'audio NON coranique.

Or l'alignement forcé côté app tokenise le texte NU en glouton plus-long-
match (ForcedAligner.tokenizeWordGreedy -- `word_tokens=non` pour ce modèle,
confirmé dans le log device), ce qui produit précisément `▁ٱلْعَ`.
=> On réclame au modèle, sur de l'audio coranique, une tokenisation qu'il
n'associe qu'à un autre domaine acoustique. D'où `forced` effondré alors que
`free` est quasi parfait (device : gop=-3,95 forced=-4,03 free=-0,08 sur
"ٱلْعَـٰلَمِينَ", récitation pourtant correcte).

── CE QUE CE SCRIPT MESURE ──
Sur de VRAIS clips coraniques (val_canonical, récitateurs professionnels =
récitation correcte par construction), pour chaque mot commençant par ٱ :
    NLL_soude  = -log P(mot | audio) avec la tokenisation actuelle (greedy)
    NLL_split  = -log P(mot | audio) avec ٱ séparé du reste
    NLL_elide  = -log P(mot | audio) avec ٱ retiré (chemin "élidé")
et compare. La piste B revient à prendre min(split, élidé) au lieu d'imposer
la forme soudée : on mesure ici le gain que ça représenterait.

⚠️ CONTRÔLE DE NON-RÉGRESSION indispensable (sinon on "améliore" en rendant
le score aveugle) : on vérifie que sur une VARIANTE FAUTIVE du même mot
(harakat substituée), le score reste nettement pire que le canonique. Si
l'écart canonique/fautif s'effondre aussi, la piste est à rejeter.

Usage :
    python3 test_hamwasl_optional_branch.py <modele.nemo> [--limit N] [--cpu]
"""
import argparse
import json
import statistics
import unicodedata
from pathlib import Path

import soundfile as sf
import torch
import torch.nn.functional as F
import nemo.collections.asr as nemo_asr

BASE = Path(__file__).parent
VAL_CANON = BASE / "nemo_manifests_mixed" / "val_canonical.jsonl"

REMAP = [
    ("/mnt/ssd5/Coran Karim/", "/media/kafai/NouveauNom/Coran Karim/"),
    ("/mnt/hdd/Coran Karim/", "/run/media/kafai/HDD/Coran Karim/"),
]
HARAKAT = "ًٌٍَُِْ"
ALIF_WASLA = "ٱ"


def remap(p):
    for old, new in REMAP:
        if p.startswith(old):
            return new + p[len(old):]
    return p


class _ZeroRNNTLoss(torch.nn.Module):
    def forward(self, log_probs, targets, input_lengths, target_lengths):
        return log_probs.sum() * 0.0


def load_model(nemo_path, use_cpu):
    m = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        str(nemo_path), map_location="cpu")
    if hasattr(m, "joint") and hasattr(m.joint, "set_fuse_loss_wer"):
        m.joint.set_fuse_loss_wer(False, loss=None, metric=None)
    m.loss = _ZeroRNNTLoss()
    m.ctc_loss_weight = 1.0
    m.eval()
    if torch.cuda.is_available() and not use_cpu:
        m = m.cuda()
    return m


@torch.no_grad()
def logprobs_for_clip(model, path, device):
    audio, sr = sf.read(path, dtype="float32")
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    if sr != 16000:
        import librosa
        audio = librosa.resample(audio, orig_sr=sr, target_sr=16000)
    audio_t = torch.tensor(audio, device=device).unsqueeze(0)
    len_t = torch.tensor([audio.shape[0]], dtype=torch.int64, device=device)
    feats, feats_len = model.preprocessor(input_signal=audio_t, length=len_t)
    encoded, encoded_len = model.encoder(audio_signal=feats, length=feats_len)
    logits = model.ctc_decoder(encoder_output=encoded)
    return F.log_softmax(logits, dim=-1), encoded_len


@torch.no_grad()
def ctc_nll_batch(logprobs, enc_len, cand_ids, blank_id, device):
    """NLL CTC de chaque candidat sur le MÊME audio (batché). None si
    infaisable (T trop court) -- jamais 0, qui serait faussement excellent."""
    cand_ids = [c for c in cand_ids]
    n = len(cand_ids)
    lengths = [len(c) for c in cand_ids]
    smax = max(lengths)
    targets = torch.zeros(n, smax, dtype=torch.int64, device=device)
    for i, c in enumerate(cand_ids):
        targets[i, :len(c)] = torch.tensor(c, dtype=torch.int64)
    t = logprobs.transpose(0, 1).expand(-1, n, -1)
    losses = F.ctc_loss(
        t, targets, enc_len.expand(n), torch.tensor(lengths, device=device),
        blank=blank_id, reduction="none", zero_infinity=False)
    return [None if (v != v or v == float("inf")) else v
            for v in losses.tolist()]


def tok_greedy_merged(tokenizer, word):
    """Ce que fait l'app aujourd'hui : tokenisation normale du mot NU
    (SentencePiece fusionne ٱ avec ce qui suit)."""
    return tokenizer.text_to_ids(word)


def tok_split_alif(tokenizer, word):
    """Chemin A du treillis : ٱ tokenisé SÉPARÉMENT du reste (la forme que le
    modèle a vue 98,4 % du temps sur l'audio coranique, où le symbole de règle
    s'intercalait juste après le ٱ)."""
    if not word.startswith(ALIF_WASLA):
        return None
    return tokenizer.text_to_ids(ALIF_WASLA) + tokenizer.text_to_ids(word[1:])


def tok_elided(tokenizer, word):
    """Chemin B du treillis : ٱ absent (le récitant a enchaîné, l'alif de
    liaison ne produit aucun son)."""
    if not word.startswith(ALIF_WASLA):
        return None
    return tokenizer.text_to_ids(word[1:])


# Les 14 lettres SOLAIRES (لام شمسية) : le lam de l'article ne se prononce
# PAS devant elles, il est absorbé par la lettre suivante qui porte alors un
# chadda -- on écrit ٱلشَّمْس, on dit "ash-shams" (pas "al-shams").
# Devant les autres (lunaires), le lam s'entend normalement : "al-'ālamīn".
# 55,8 % des mots en ٱل du Coran sont solaires (mesuré) -- majoritaires, donc
# à ne SURTOUT pas confondre avec les lunaires dans une mesure acoustique.
# NB : la hamzat wasl elle-même obéit à la même règle dans les deux cas
# (prononcée si on démarre là, élidée si on enchaîne) -- ce qui change entre
# solaire et lunaire, c'est le sort du LAM, pas celui de la hamza.
SOLAIRES = set("تثدذرزسشصضطظلن")


def _lettre_apres_lam(word):
    """Première vraie lettre après le lam de l'article (en sautant les
    diacritiques : sukun sur le lam, chadda sur la lettre solaire...)."""
    for ch in word[2:]:
        if ch not in "ًٌٍَُِّْـٰ":
            return ch
    return None


def categorie(word):
    """Les 4 situations distinguées par l'utilisateur (2026-07-22).
    Rappel : la voyelle prononcée est DÉJÀ écrite dans le texte canonique
    (les savants l'ont fixée) -- on la LIT, on ne la recalcule pas.
      - article défini "ٱل" -> toujours fatha quand prononcé
      - sans lam            -> damma si la 3e radicale porte une damma au
                               présent, kasra sinon (règle utilisateur)
    Ici on ne peut lire que ce qui est ÉCRIT, donc on classe sur la voyelle
    effectivement portée par le ٱ dans le texte uthmani."""
    if len(word) < 2:
        return "autre"
    if word[1] == "ل":
        # Distinction ajoutée le 2026-07-22 (remarque utilisateur) : solaire
        # vs lunaire changent ce qu'on ENTEND (lam muet+chadda vs lam
        # prononcé) -- les mélanger dans une mesure acoustique n'a pas de sens.
        L = _lettre_apres_lam(word)
        if L is None:
            return "1c-lam_indetermine"
        return "1a-lam_solaire" if L in SOLAIRES else "1b-lam_lunaire"
    # sans lam : on regarde la voyelle portée par le ٱ lui-même
    for ch in word[1:4]:
        if ch == "ُ":
            return "2-sans_lam_damma"
        if ch == "ِ":
            return "3-sans_lam_kasra"
    return "4-sans_lam_autre"


def tok_lam_muet(tokenizer, word):
    """Chemin spécifique LAM SOLAIRE (ajouté 2026-07-22) : le lam de l'article
    ne se prononce pas devant une lettre solaire (ٱلشَّمْس -> "ash-shams").
    On retire donc ٱ ET le lam, en gardant la lettre solaire (avec son chadda,
    qui porte justement la gémination issue de l'assimilation du lam).
    Retourne None si le mot n'est pas un cas ٱل+solaire."""
    if not word.startswith("ٱل") or len(word) < 3:
        return None
    L = _lettre_apres_lam(word)
    if L is None or L not in SOLAIRES:
        return None
    # on saute ٱ, le lam, et l'éventuel sukun porté par le lam
    rest = word[2:]
    while rest and rest[0] in "ْ":
        rest = rest[1:]
    return tokenizer.text_to_ids(rest) if rest else None


def make_faulty(word):
    """Variante FAUTIVE : première harakat substituée (fatha<->kasra...).
    Sert au contrôle de non-régression."""
    for i, ch in enumerate(word):
        if ch in HARAKAT:
            repl = "ِ" if ch != "ِ" else "َ"
            return word[:i] + repl + word[i + 1:]
    return None


def norm(s):
    return " ".join(unicodedata.normalize("NFC", s).split())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model")
    ap.add_argument("--limit", type=int, default=60)
    ap.add_argument("--cpu", action="store_true")
    args = ap.parse_args()

    print(f"Chargement : {args.model}", flush=True)
    model = load_model(args.model, args.cpu)
    device = next(model.parameters()).device
    blank_id = model.tokenizer.vocab_size
    tk = model.tokenizer
    print(f"device={device} blank_id={blank_id}", flush=True)

    rows = [json.loads(l) for l in open(VAL_CANON, encoding="utf-8")]
    # Les mots ٱ SANS lam (verbes : ٱدْخُلُوا, ٱعْبُدُوا...) sont rares dans un
    # échantillon pris au fil de l'eau (5/55 au premier essai, insuffisant pour
    # conclure). On échantillonne donc les DEUX familles séparément, pour que
    # les 4 situations de l'utilisateur soient toutes représentées.
    def a_sans_lam(r):
        return any(w.startswith(ALIF_WASLA) and len(w) > 1 and w[1] != "ل"
                   for w in r["text"].split())
    sans_lam = [r for r in rows if a_sans_lam(r)]
    avec_lam = [r for r in rows if not a_sans_lam(r)]
    moitie = max(1, args.limit // 2)
    rows = sans_lam[:moitie] + avec_lam[:args.limit - moitie]
    print(f"échantillon : {len(sans_lam[:moitie])} clips contenant un ٱ-sans-lam"
          f" + {len(avec_lam[:args.limit - moitie])} autres", flush=True)

    # gains par mot : NLL_soude - min(NLL_split, NLL_elide)  (>0 = gain)
    gains, n_split_gagne, n_elide_gagne, n_soude_gagne = [], 0, 0, 0
    # non-regression : marge (fautif - canonique), avant et apres la piste B
    marges_avant, marges_apres = [], []
    details = []
    # ventilation par les 4 situations (demande utilisateur 2026-07-22)
    import collections
    par_cat = collections.defaultdict(lambda: {"gains": [], "elide": 0,
                                               "split": 0, "soude": 0})

    for ri, r in enumerate(rows):
        path = remap(r["audio_filepath"])
        if not Path(path).exists():
            continue
        try:
            lp, elen = logprobs_for_clip(model, path, device)
        except Exception as e:
            print(f"  clip ignoré ({e})", flush=True)
            continue

        for word in norm(r["text"]).split():
            if not word.startswith(ALIF_WASLA):
                continue
            ids_merged = tok_greedy_merged(tk, word)
            ids_split = tok_split_alif(tk, word)
            ids_elide = tok_elided(tk, word)
            ids_lam_muet = tok_lam_muet(tk, word)   # None hors cas solaire
            if not ids_merged or not ids_split or not ids_elide:
                continue
            faulty = make_faulty(word)
            cands = [ids_merged, ids_split, ids_elide]
            names = ["merged", "split", "elide"]
            if ids_lam_muet:
                cands.append(ids_lam_muet)
                names.append("lam_muet")
            if faulty:
                cands += [tok_greedy_merged(tk, faulty)]
                f_split = tok_split_alif(tk, faulty)
                f_elide = tok_elided(tk, faulty)
                cands += [f_split, f_elide]
                names += ["f_merged", "f_split", "f_elide"]
            cands = [c for c in cands if c]
            if len(cands) < 3:
                continue
            nlls = ctc_nll_batch(lp, elen, cands, blank_id, device)
            d = dict(zip(names, nlls))
            if d.get("merged") is None or d.get("split") is None or d.get("elide") is None:
                continue

            alts = {"split": d["split"], "elide": d["elide"]}
            if d.get("lam_muet") is not None:
                alts["lam_muet"] = d["lam_muet"]
            best_name = min(alts, key=alts.get)
            best_new = alts[best_name]
            gain = d["merged"] - best_new     # >0 : la piste B améliore
            gains.append(gain)
            cat = categorie(word)
            par_cat[cat]["gains"].append(gain)
            if best_new >= d["merged"]:
                n_soude_gagne += 1
                par_cat[cat]["soude"] += 1
            elif best_name == "elide":
                n_elide_gagne += 1
                par_cat[cat]["elide"] += 1
            elif best_name == "lam_muet":
                par_cat[cat]["lam_muet"] = par_cat[cat].get("lam_muet", 0) + 1
            else:
                n_split_gagne += 1
                par_cat[cat]["split"] += 1

            # non-régression : le fautif doit rester PIRE que le canonique
            f_vals = [d.get(k) for k in ("f_merged", "f_split", "f_elide")
                      if d.get(k) is not None]
            if f_vals:
                marges_avant.append(d["f_merged"] - d["merged"]
                                    if d.get("f_merged") is not None else None)
                f_best_new = min(v for k, v in d.items()
                                 if k in ("f_split", "f_elide") and v is not None) \
                    if any(d.get(k) is not None for k in ("f_split", "f_elide")) else None
                if f_best_new is not None:
                    marges_apres.append(f_best_new - best_new)

            if len(details) < 15:
                details.append((word, cat, d["merged"], d["split"], d["elide"], gain))

    marges_avant = [m for m in marges_avant if m is not None]

    print("\n" + "=" * 72)
    print(f"MOTS EN ٱ ANALYSÉS : {len(gains)}")
    print("=" * 72)
    if not gains:
        print("aucun mot analysable")
        return

    print(f"\nGAIN de NLL (positif = la piste B améliore le score du mot correct) :")
    print(f"   moyenne  : {statistics.mean(gains):+8.2f}")
    print(f"   médiane  : {statistics.median(gains):+8.2f}")
    print(f"   min/max  : {min(gains):+8.2f} / {max(gains):+8.2f}")
    n_ameliore = sum(1 for g in gains if g > 0.5)
    print(f"   mots nettement améliorés (gain>0.5) : {n_ameliore}/{len(gains)}"
          f"  ({100*n_ameliore/len(gains):.1f} %)")

    print(f"\nCHEMIN retenu par l'audio :")
    print(f"   élidé (ٱ muet)   : {n_elide_gagne:5d}  ({100*n_elide_gagne/len(gains):.1f} %)")
    print(f"   ٱ séparé prononcé: {n_split_gagne:5d}  ({100*n_split_gagne/len(gains):.1f} %)")
    print(f"   soudé (actuel)   : {n_soude_gagne:5d}  ({100*n_soude_gagne/len(gains):.1f} %)")

    print(f"\nCONTRÔLE NON-RÉGRESSION (marge fautif-canonique, doit rester >0"
          f" et du même ordre) :")
    if marges_avant:
        print(f"   AVANT (soudé)  : moyenne {statistics.mean(marges_avant):+7.2f}"
              f"   médiane {statistics.median(marges_avant):+7.2f}"
              f"   négatives {sum(1 for m in marges_avant if m<0)}/{len(marges_avant)}")
    if marges_apres:
        print(f"   APRÈS (piste B): moyenne {statistics.mean(marges_apres):+7.2f}"
              f"   médiane {statistics.median(marges_apres):+7.2f}"
              f"   négatives {sum(1 for m in marges_apres if m<0)}/{len(marges_apres)}")

    print(f"\nVENTILATION PAR SITUATION (les 4 cas) :")
    print(f"   {'situation':<20s} {'n':>5s} {'gain moy':>9s} {'élidé':>7s}"
          f" {'split':>7s} {'lam_muet':>9s} {'soudé':>7s}")
    for cat in sorted(par_cat):
        v = par_cat[cat]
        g = v["gains"]
        print(f"   {cat:<20s} {len(g):5d} {statistics.mean(g):+9.2f}"
              f" {v['elide']:7d} {v['split']:7d} {v.get('lam_muet',0):9d}"
              f" {v['soude']:7d}")

    print(f"\nDÉTAIL (15 premiers mots) :")
    print(f"   {'mot':<18s} {'situation':<18s} {'soudé':>9s} {'split':>9s}"
          f" {'élidé':>9s} {'gain':>8s}")
    for w, c, m, s, e, g in details:
        print(f"   {w:<18s} {c:<18s} {m:9.2f} {s:9.2f} {e:9.2f} {g:+8.2f}")


if __name__ == "__main__":
    main()
