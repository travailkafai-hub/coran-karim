#!/usr/bin/env python3
"""Test OFFLINE de l'idee "valider un fragment globalement quand il colle au
texte attendu, ne fragmenter (alignement forcé mot-par-mot) que si un
mismatch est détecté" (proposition utilisateur, 2026-07-16 soir).

POURQUOI CE TEST : le decoupage mot-par-mot (ForcedAligner, toujours execute
aujourd'hui) est fragile aux FRONTIERES -- un mot peut recevoir une tranche de
frames trop courte si la DP rend la main au mot suivant trop tot (confiance
faible), tronquant le texte extrait pour CE mot meme quand le decodage libre
sur tout le segment (sans decoupage) l'avait parfaitement capte. Observe sur
device : meme passe, memes logprobs -- segment entier "بَلَوْنَـٰهُمْ" correct,
mot isole "بَلَـٰهُمْ" tronque.

L'IDEE : inverser l'ordre. D'abord un test TEXTUEL GLOBAL (decodage libre du
segment entier vs texte attendu, mot a mot, SANS aucune frontiere de frames) --
si ca colle, valider tout le fragment d'un coup (jamais besoin des frontieres
fragiles). Ne declencher le decoupage fin (GOP/ForcedAligner actuel) QUE si un
mismatch est detecte, pour localiser precisement l'erreur.

LE PIEGE CONNU (deja mesure aujourd'hui, cf. variant_rescoring_eval.py) : le
modele a un biais canonique -- sur une erreur de harakat, son decodage libre
peut "corriger" silencieusement vers la forme attendue, donc le texte global
matcherait MEME si l'utilisateur s'est trompe. Rescoring tete-a-tete avait deja
mesure ce plafond : lettres 80.8% detectables, harakat 49.6% (quasi hasard).
CE test-ci mesure la meme question mais pour un mecanisme DIFFERENT (diff
textuel global mot-a-mot, pas de rescoring CTC) -- but attendu : bon sur les
lettres, mauvais sur les harakat, pour la MEME raison de fond (le texte
decode, meme correct dans l'ensemble, peut deja porter le biais canonique sur
UN mot precis).

PROTOCOLE :
  1. Cas "vrai negatif" (segment reellement correct, corpus reel) : le
     decodage libre du segment ENTIER matche-t-il, mot a mot, le texte
     attendu REEL ? Mesure le taux de "fragmentation inutile" qu'on
     eliminerait (combien de segments corrects seraient valides d'un coup,
     sans jamais toucher a l'alignement fin fragile).
  2. Cas "vrai positif simule" (meme audio reel, mais on pretend qu'UN mot
     attendu est different -- substitution confusable lettre/harakat) : le
     diff textuel global detecte-t-il le mismatch a la BONNE position ? Split
     par type (letter/harakat) pour comparer au plafond deja mesure.

Usage : python3 global_match_eval.py <modele.nemo> [--limit N] [--cpu]
"""
import argparse
import json
import random
import statistics
from pathlib import Path

import soundfile as sf
import torch
import torch.nn.functional as F
import nemo.collections.asr as nemo_asr

BASE = Path(__file__).parent
VAL_CANON = BASE / "nemo_manifests_mixed" / "val_canonical.jsonl"

CONFUSABLE_PAIRS = [
    ("ص", "س"), ("س", "ص"), ("ط", "ت"), ("ت", "ط"), ("ض", "د"), ("د", "ض"),
    ("ذ", "ز"), ("ز", "ذ"), ("ح", "ه"), ("ه", "ح"), ("ق", "ك"), ("ك", "ق"),
    ("ع", "ء"), ("ء", "ع"),
]
FATHA, DAMMA, KASRA, SUKUN = "َ", "ُ", "ِ", "ْ"
SHORT_HARAKAT = [FATHA, DAMMA, KASRA, SUKUN]

SEED = 2026
random.seed(SEED)


class _ZeroRNNTLoss(torch.nn.Module):
    def forward(self, log_probs, targets, input_lengths, target_lengths):
        return log_probs.sum() * 0.0


def load_model(path, use_cpu):
    m = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(str(path), map_location="cpu")
    if hasattr(m, "joint") and hasattr(m.joint, "set_fuse_loss_wer"):
        m.joint.set_fuse_loss_wer(False, loss=None, metric=None)
    m.loss = _ZeroRNNTLoss()
    m.ctc_loss_weight = 1.0
    # OBLIGATOIRE (cf. memoire projet) : la tete RNNT n'est jamais entrainee.
    m.change_decoding_strategy(decoder_type="ctc")
    m.eval()
    if torch.cuda.is_available() and not use_cpu:
        m = m.cuda()
    return m


@torch.no_grad()
def free_decode(model, path, device):
    audio, sr = sf.read(path, dtype="float32")
    if sr != 16000:
        import librosa
        audio = librosa.resample(audio, orig_sr=sr, target_sr=16000)
    audio_t = torch.tensor(audio, device=device).unsqueeze(0)
    len_t = torch.tensor([audio.shape[0]], dtype=torch.int64, device=device)
    feats, feats_len = model.preprocessor(input_signal=audio_t, length=len_t)
    encoded, encoded_len = model.encoder(audio_signal=feats, length=feats_len)
    logits = model.ctc_decoder(encoder_output=encoded)
    logprobs = F.log_softmax(logits, dim=-1)[0]
    ids = logprobs.argmax(dim=-1).tolist()
    blank = model.tokenizer.vocab_size
    collapsed = []
    prev = -1
    for i in ids:
        if i != prev and i != blank:
            collapsed.append(i)
        prev = i
    return model.tokenizer.ids_to_text(collapsed).strip()


# ── Normalisation minimale : NFC + espaces -- garde les harakat (c'est ce
# qu'on mesure), collapse juste les variantes orthographiques comme le fait
# ArabicNormalizer.normalizeStrict côté app (alef wasla/hamza/ta marbuta). ──
def collapse(t):
    for a, b in [("ٱ", "ا"), ("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ى", "ي"),
                 ("ؤ", "و"), ("ئ", "ي"), ("ة", "ه"), ("ـ", ""), ("ٰ", "ا")]:
        t = t.replace(a, b)
    return t


def word_match(expected_word, decoded_word):
    """Tolerance de bord (cf. matchesTolerant app) : prefixe/suffixe partagé
    d'au moins la moitié des caractères = considéré comme le même mot."""
    e, d = collapse(expected_word), collapse(decoded_word)
    if e == d:
        return True
    if not e or not d:
        return False
    if d.endswith(e) or e.endswith(d) or d.startswith(e) or e.startswith(d):
        shorter = min(len(e), len(d))
        longer = max(len(e), len(d))
        return shorter * 2 >= longer
    return False


def segment_matches(expected_words, decoded_text):
    """Diff textuel GLOBAL, mot-a-mot, sans aucune frontière de frames --
    c'est le "test rapide" propose : renvoie (match_global, positions_ko)."""
    decoded_words = decoded_text.split()
    if len(decoded_words) != len(expected_words):
        # Nombre de mots différent : pas de correspondance position-à-position
        # fiable -> traité comme mismatch global (déclenche la fragmentation).
        return False, list(range(len(expected_words)))
    bad = [i for i, (e, d) in enumerate(zip(expected_words, decoded_words))
           if not word_match(e, d)]
    return len(bad) == 0, bad


def corrupt_word(word, kind):
    if kind == "letter":
        candidates = [(a, b) for a, b in CONFUSABLE_PAIRS if a in word]
        if not candidates:
            return None, None
        a, b = random.choice(candidates)
        return word.replace(a, b, 1), f"{a}->{b}"
    else:  # harakat
        positions = [i for i, c in enumerate(word) if c in SHORT_HARAKAT]
        if not positions:
            return None, None
        pos = random.choice(positions)
        original = word[pos]
        alt = random.choice([h for h in SHORT_HARAKAT if h != original])
        return word[:pos] + alt + word[pos + 1:], f"harakat@{pos}:{original}->{alt}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model")
    ap.add_argument("--limit", type=int, default=150)
    ap.add_argument("--cpu", action="store_true")
    args = ap.parse_args()

    print(f"Chargement : {args.model}")
    model = load_model(args.model, args.cpu)
    device = next(model.parameters()).device

    rows = [json.loads(l) for l in open(VAL_CANON, encoding="utf-8")]
    random.shuffle(rows)
    rows = [r for r in rows if 2 <= len(r["text"].split()) <= 12][:args.limit]
    print(f"Clips reels (segments multi-mots) : {len(rows)} (device={device})\n")

    # ── Cas 1 : vrai negatif (segment reellement correct) ──────────────────
    tn_ok = 0
    for i, r in enumerate(rows):
        decoded = free_decode(model, r["audio_filepath"], device)
        matched, _ = segment_matches(r["text"].split(), decoded)
        if matched:
            tn_ok += 1
        if (i + 1) % 50 == 0:
            print(f"  [vrai negatif] {i + 1}/{len(rows)}...")

    print(f"\n{'=' * 62}\nCAS 1 -- segments REELLEMENT corrects (vrai negatif)\n{'=' * 62}")
    print(f"  validés d'un coup (pas besoin de fragmenter) : {tn_ok}/{len(rows)} "
          f"({100 * tn_ok / len(rows):.1f}%)")
    print(f"  -> {100 * (1 - tn_ok / len(rows)):.1f}% auraient quand même besoin du "
          f"découpage fin (faux déclenchements)")

    # ── Cas 2 : vrai positif simulé (mismatch texte, meme audio) ───────────
    by_kind = {"letter": {"n": 0, "detect": 0}, "harakat": {"n": 0, "detect": 0}}
    skipped = 0
    for i, r in enumerate(rows):
        decoded = free_decode(model, r["audio_filepath"], device)
        words = r["text"].split()
        if len(words) < 2:
            continue
        kind = random.choice(["letter", "harakat"])
        idx = random.randrange(len(words))
        corrupted, detail = corrupt_word(words[idx], kind)
        if corrupted is None:
            skipped += 1
            continue
        fake_expected = words[:idx] + [corrupted] + words[idx + 1:]
        matched, bad_positions = segment_matches(fake_expected, decoded)
        s = by_kind[kind]
        s["n"] += 1
        # Détection = mismatch global levé (peu importe si la position exacte
        # tombe pile sur idx -- le but ici est juste "faut-il fragmenter ?").
        if not matched:
            s["detect"] += 1
        if (i + 1) % 50 == 0:
            print(f"  [vrai positif simulé] {i + 1}/{len(rows)}...")

    print(f"\n{'=' * 62}\nCAS 2 -- mismatch simulé (même audio, texte attendu corrompu)\n{'=' * 62}")
    print(f"clips ignorés (aucune position substituable) : {skipped}")
    for kind, s in by_kind.items():
        pct = 100 * s["detect"] / s["n"] if s["n"] else 0.0
        print(f"  {kind:<10} n={s['n']:<5} détecté={s['detect']:<5} ({pct:.1f}%)")


if __name__ == "__main__":
    main()
