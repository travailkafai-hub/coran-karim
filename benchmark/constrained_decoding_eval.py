#!/usr/bin/env python3
"""Prototype OFFLINE du décodage contraint au texte attendu (piste 🟢 n°1,
cf. ETAT_CTC_NEMO.md §6 "Pistes de qualité" et GLOSSAIRE_TECHNIQUES_ASR.md).

DIFFÉRENCE AVEC variant_rescoring_eval.py (validé GO 80,8% lettres) :
    Le rescoring 2-candidats compare NLL(canonique) vs NLL(prononcé) -- mais en
    production on ne SAIT PAS ce qui a été prononcé. Ici on reproduit le vrai
    cas produit : à partir du SEUL texte attendu, on énumère toutes les
    variantes confusables à 1 édition (harakat substituées + confusions de
    lettres observées dans le corpus TTS), on force-décode chaque candidat, et
    le modèle élit celui qui explique le mieux l'audio (NLL CTC minimal).
    C'est un décodage contraint à un ensemble fermé dérivé du verset attendu --
    exactement ce que l'app pourra faire par mot dans le karaoké.

DEUX MESURES (l'éval rescoring n'avait pas la seconde) :
    A. Sensibilité (val_errors_annotated, clips fautifs mot isolé) : quand
       l'audio contient une faute, une variante bat-elle le canonique
       (détection) ? Et est-ce la BONNE variante (identification) ?
    B. Spécificité (val_canonical, versets corrects) : quand l'audio est
       correct, à quelle fréquence une variante bat-elle À TORT le canonique
       (faux positif) ? Balayage d'un seuil de marge τ pour situer le
       compromis détection/faux positifs exploitable dans l'app.

Usage :
    python3 constrained_decoding_eval.py <modele.nemo> [--limit N]
        [--canon-limit N] [--max-cands N] [--cpu]
"""
import argparse
import json
import random
import statistics
import unicodedata
from pathlib import Path

import soundfile as sf
import torch
import torch.nn.functional as F
import nemo.collections.asr as nemo_asr

BASE = Path(__file__).parent
VAL_ERRORS = BASE / "nemo_manifests_mixed" / "val_errors_annotated.jsonl"
VAL_CANON = BASE / "nemo_manifests_mixed" / "val_canonical.jsonl"

# Chemins absolus d'une autre machine dans les manifests du dépôt (règle
# projet : remapper au vol, ne pas modifier les fichiers du dépôt).
REMAP = [
    ("/mnt/ssd5/Coran Karim/", "/media/kafai/NouveauNom/Coran Karim/"),
    ("/mnt/hdd/Coran Karim/", "/run/media/kafai/HDD/Coran Karim/"),
]

# Harakat substituables (mêmes classes que le générateur TTS d'erreurs :
# err_detail "harakat@i:X->Y" ne fait varier que ces signes).
HARAKAT = "ًٌٍَُِْ"  # fatha damma kasra sukun + tanwins
THRESHOLDS = [0.0, 1.0, 2.0, 3.0, 5.0, 8.0, 12.0, 20.0]


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
    """Même chemin que la production (mel -> encoder -> ctc_decoder ->
    log_softmax), avec rééchantillonnage explicite (clips TTS en 24kHz,
    piège déjà payé une fois dans variant_rescoring_eval.py)."""
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
    return F.log_softmax(logits, dim=-1), encoded_len  # (1, T, V+1)


@torch.no_grad()
def ctc_nll_batch(logprobs, enc_len, cand_ids, blank_id, device):
    """NLL CTC de chaque candidat sur le MÊME audio, en un seul appel batché.
    Retourne une liste de float ou None (cible infaisable : T < longueur
    requise -> inf/nan, jamais zero_infinity qui la rendrait faussement
    excellente)."""
    n = len(cand_ids)
    lengths = [len(c) for c in cand_ids]
    smax = max(lengths)
    targets = torch.zeros(n, smax, dtype=torch.int64, device=device)
    for i, c in enumerate(cand_ids):
        targets[i, :len(c)] = torch.tensor(c, dtype=torch.int64)
    t = logprobs.transpose(0, 1).expand(-1, n, -1)  # (T, N, C)
    losses = F.ctc_loss(
        t, targets, enc_len.expand(n), torch.tensor(lengths, device=device),
        blank=blank_id, reduction="none", zero_infinity=False)
    out = []
    for v in losses.tolist():
        out.append(None if (v != v or v == float("inf")) else v)
    return out


def build_letter_confusions(rows):
    """Paires de confusion observées dans le corpus d'erreurs TTS
    (err_detail 'X->Y' des clips kind=letter), rendues symétriques -- le même
    inventaire que devra embarquer l'app."""
    conf = {}
    for r in rows:
        if r.get("err_kind") != "letter":
            continue
        d = r.get("err_detail", "")
        if "->" in d and "@" not in d:
            a, b = d.split("->", 1)
            a, b = a.strip(), b.strip()
            if len(a) == 1 and len(b) == 1:
                conf.setdefault(a, set()).add(b)
                conf.setdefault(b, set()).add(a)
    return conf


def word_variants(word, conf):
    """Toutes les variantes à 1 édition : chaque harakat substituée par une
    autre, chaque lettre confusable substituée. Pas d'insertion/suppression
    pour ce prototype (les erreurs du corpus sont des substitutions)."""
    out = set()
    for i, ch in enumerate(word):
        if ch in HARAKAT:
            for h in HARAKAT:
                if h != ch:
                    out.add(word[:i] + h + word[i + 1:])
        elif ch in conf:
            for c in conf[ch]:
                out.add(word[:i] + c + word[i + 1:])
    out.discard(word)
    return out


def norm(s):
    return " ".join(unicodedata.normalize("NFC", s).split())


def pct(a, b):
    return 100.0 * a / b if b else float("nan")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model")
    ap.add_argument("--limit", type=int, default=2000)
    ap.add_argument("--canon-limit", type=int, default=150)
    ap.add_argument("--max-cands", type=int, default=120,
                    help="plafond de candidats par verset (test B)")
    ap.add_argument("--cpu", action="store_true")
    args = ap.parse_args()

    print(f"Chargement : {args.model}", flush=True)
    model = load_model(args.model, args.cpu)
    device = next(model.parameters()).device
    blank_id = model.tokenizer.vocab_size

    all_rows = [json.loads(l) for l in open(VAL_ERRORS, encoding="utf-8")]
    conf = build_letter_confusions(all_rows)
    print(f"Confusions lettres apprises du corpus : "
          f"{sorted((k, ''.join(sorted(v))) for k, v in conf.items())}", flush=True)

    # ── Test A : sensibilité sur clips fautifs (mots isolés) ────────────────
    rows = [r for r in all_rows
            if r.get("correct_text") and r["text"] != r["correct_text"]]
    rows = rows[:args.limit]
    print(f"\nTest A -- clips fautifs : {len(rows)} (device={device})", flush=True)

    stats = {}   # kind -> dict
    coverage_miss = 0
    infeasible = 0
    for i, r in enumerate(rows):
        canon = norm(r["correct_text"])
        said = norm(r["text"])
        cands = sorted(word_variants(canon, conf))
        if not cands:
            continue
        in_set = said in cands
        coverage_miss += (not in_set)
        try:
            logprobs, enc_len = logprobs_for_clip(
                model, remap(r["audio_filepath"]), device)
        except Exception as e:
            print(f"  [skip] {r['audio_filepath']} : {e}", flush=True)
            continue
        texts = [canon] + cands
        ids = [model.tokenizer.text_to_ids(t) for t in texts]
        nlls = ctc_nll_batch(logprobs, enc_len, ids, blank_id, device)
        if nlls[0] is None:
            infeasible += 1
            continue
        scored = [(nll, t) for nll, t in zip(nlls[1:], cands) if nll is not None]
        if not scored:
            infeasible += 1
            continue
        best_nll, best_text = min(scored)
        margin = nlls[0] - best_nll  # >0 : une variante bat le canonique
        k = r.get("err_kind", "?")
        s = stats.setdefault(k, {"n": 0, "margins": [], "ident": 0, "in_set": 0})
        s["n"] += 1
        s["margins"].append(margin)
        s["in_set"] += in_set
        # identification : le candidat élu (canonique inclus) est le texte dit
        overall_best = min([(nlls[0], canon)] + scored)
        s["ident"] += (overall_best[1] == said)
        if (i + 1) % 200 == 0:
            print(f"  {i + 1}/{len(rows)}...", flush=True)

    print(f"\n{'=' * 66}\nTEST A -- DÉTECTION sur clips fautifs "
          f"(candidats générés SANS connaître la faute)\n{'=' * 66}")
    print(f"variante dite absente de l'ensemble généré : {coverage_miss} clips "
          f"(mesure la couverture du générateur)")
    print(f"cibles infaisables : {infeasible}")
    header = f"{'kind':<9}{'n':>6}{'ident.':>9}" + "".join(
        f"{'det τ=' + str(int(t)):>10}" for t in THRESHOLDS)
    print(header)
    for k, s in sorted(stats.items()):
        line = f"{k:<9}{s['n']:>6}{pct(s['ident'], s['n']):>8.1f}%"
        for t in THRESHOLDS:
            det = sum(1 for m in s["margins"] if m > t)
            line += f"{pct(det, s['n']):>9.1f}%"
        print(line)
    tot_n = sum(s["n"] for s in stats.values())
    tot_id = sum(s["ident"] for s in stats.values())
    line = f"{'TOTAL':<9}{tot_n:>6}{pct(tot_id, tot_n):>8.1f}%"
    for t in THRESHOLDS:
        det = sum(1 for s in stats.values() for m in s["margins"] if m > t)
        line += f"{pct(det, tot_n):>9.1f}%"
    print(line)

    # ── Test B : spécificité sur versets canoniques corrects ────────────────
    canon_rows = [json.loads(l) for l in open(VAL_CANON, encoding="utf-8")]
    canon_rows = canon_rows[:args.canon_limit]
    print(f"\nTest B -- versets canoniques corrects : {len(canon_rows)}", flush=True)

    rng = random.Random(0)
    verse_margins = []       # marge max par verset (pire variante)
    cand_total = cand_win = 0
    for i, r in enumerate(canon_rows):
        text = norm(r["text"])
        words = text.split()
        cands = []
        for wi, w in enumerate(words):
            for v in word_variants(w, conf):
                cands.append(" ".join(words[:wi] + [v] + words[wi + 1:]))
        if not cands:
            continue
        if len(cands) > args.max_cands:
            cands = rng.sample(cands, args.max_cands)
        try:
            logprobs, enc_len = logprobs_for_clip(
                model, remap(r["audio_filepath"]), device)
        except Exception as e:
            print(f"  [skip] {r['audio_filepath']} : {e}", flush=True)
            continue
        ids = [model.tokenizer.text_to_ids(t) for t in [text] + cands]
        nlls = ctc_nll_batch(logprobs, enc_len, ids, blank_id, device)
        if nlls[0] is None:
            continue
        vm = [nlls[0] - v for v in nlls[1:] if v is not None]
        if not vm:
            continue
        verse_margins.append(max(vm))
        cand_total += len(vm)
        cand_win += sum(1 for m in vm if m > 0)
        if (i + 1) % 25 == 0:
            print(f"  {i + 1}/{len(canon_rows)}...", flush=True)

    print(f"\n{'=' * 66}\nTEST B -- FAUX POSITIFS sur audio correct "
          f"(un candidat bat le canonique à tort)\n{'=' * 66}")
    print(f"candidats évalués : {cand_total} sur {len(verse_margins)} versets ; "
          f"candidats gagnants (τ=0) : {cand_win} ({pct(cand_win, cand_total):.2f}%)")
    print(f"{'seuil τ':>8}{'versets flagués à tort':>26}")
    for t in THRESHOLDS:
        fp = sum(1 for m in verse_margins if m > t)
        print(f"{t:>8.0f}{fp:>15} ({pct(fp, len(verse_margins)):.1f}%)")
    if verse_margins:
        print(f"marge max médiane sur versets corrects : "
              f"{statistics.median(verse_margins):.2f}")

    print("\nLecture : choisir τ tel que 'det' (test A) reste haut ET "
          "'versets flagués à tort' (test B) tombe bas.")


if __name__ == "__main__":
    main()
