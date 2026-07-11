"""
Prototype : verification par ALIGNEMENT FORCE contre le texte CONNU a l'avance,
au lieu du decodage libre + comparaison de chaines qu'on vient de debugger
longuement (instable). Reutilise la meme technique deja validee dans ce projet
pour reparer le dataset assajda (realign_assajda.py, wav2vec2-arabe + torchaudio
forced_align) -- ici appliquee a la VERIFICATION en direct, pas la reparation
de dataset : idee proposee par l'utilisateur (exploiter le fait qu'on connaisse
deja le texte, comme lors d'une phase de "lecture" avant recitation).

Deux tests :
  A) Audio du bon verset, aligne contre (1) le bon texte (2) un texte FAUX
     (verset different) -> le score moyen doit etre nettement meilleur pour (1).
  B) Audio du bon verset, aligne contre le texte de reference dans lequel UN MOT
     a ete substitue par un mot errone -> le score PAR MOT doit clairement
     chuter a la position du mot substitue (localise l'erreur, pas juste un
     score global) -- c'est la vraie capacite utile pour l'app : dire QUEL mot
     est faux, pas juste "erreur quelque part".
"""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
import truststore; truststore.inject_into_ssl()
import json, random, re
import numpy as np, torch, torchaudio, soundfile as sf
from pathlib import Path
from transformers import AutoProcessor, AutoModelForCTC

BASE = Path(__file__).parent
ALIGNER = "jonatasgrosman/wav2vec2-large-xlsr-53-arabic"
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
_STRIP = re.compile(r'[ً-ٰٟؐ-ؚۖ-ۭـ۟-۪ۤۧۨ]')

print(f"Chargement aligneur sur {DEVICE}...")
proc = AutoProcessor.from_pretrained(ALIGNER)
model = AutoModelForCTC.from_pretrained(ALIGNER, dtype=torch.float16 if DEVICE == "cuda" else torch.float32).to(DEVICE).eval()
vocab = proc.tokenizer.get_vocab()
WORD_SEP = vocab["|"]
BLANK = vocab["<pad>"] if "<pad>" in vocab else 0


def norm_word(w: str) -> list[int]:
    w = w.replace("ٱ", "ا")
    w = _STRIP.sub("", w)
    return [vocab[c] for c in w if c in vocab]


def align_and_score(audio: np.ndarray, text: str):
    """Retourne (score_moyen_global, [scores_par_mot]) via forced_align."""
    words = text.split()
    token_ids = []
    word_spans = []  # (start_tok_idx, end_tok_idx) par mot
    for w in words:
        ids = norm_word(w)
        if not ids:
            word_spans.append(None)
            continue
        start = len(token_ids)
        token_ids.extend(ids)
        token_ids.append(WORD_SEP)
        word_spans.append((start, start + len(ids)))

    inputs = proc(audio, sampling_rate=16000, return_tensors="pt")
    with torch.no_grad():
        logits = model(inputs.input_values.to(DEVICE).to(model.dtype)).logits.float()
    emissions = torch.log_softmax(logits, dim=-1).cpu()

    targets = torch.tensor([token_ids], dtype=torch.int32)
    input_lengths = torch.tensor([emissions.shape[1]])
    target_lengths = torch.tensor([len(token_ids)])
    aligned_tokens, scores = torchaudio.functional.forced_align(
        emissions, targets, input_lengths, target_lengths, blank=BLANK)
    scores = scores[0].exp()  # log-prob -> prob

    per_word = []
    for span in word_spans:
        if span is None:
            per_word.append(None)
            continue
        s, e = span
        per_word.append(scores[s:e].mean().item())
    global_score = scores.mean().item()
    return global_score, per_word


def main():
    rows = [json.loads(l) for l in open(BASE / "nemo_manifests" / "val_manifest.jsonl", encoding="utf-8")]
    random.seed(11)
    sample = random.sample(rows, 4)

    print("\n=== TEST A : bon texte vs texte FAUX (verset different) ===")
    wrong_pool = [r["text"] for r in random.sample(rows, 10)]
    for i, r in enumerate(sample):
        audio, sr = sf.read(r["audio_filepath"], dtype="float32")
        wrong_text = wrong_pool[i]
        score_correct, _ = align_and_score(audio, r["text"])
        score_wrong, _ = align_and_score(audio, wrong_text)
        print(f"\nAudio: {r['text'][:50]}...")
        print(f"  score vs TEXTE CORRECT : {score_correct:.4f}")
        print(f"  score vs TEXTE FAUX    : {score_wrong:.4f}  ({wrong_text[:40]}...)")
        print(f"  -> {'OK, discrimine bien' if score_correct > score_wrong + 0.1 else 'PROBLEME: pas assez discriminant'}")

    print("\n\n=== TEST B : localisation d'un mot substitue ===")
    for r in sample[:2]:
        audio, sr = sf.read(r["audio_filepath"], dtype="float32")
        words = r["text"].split()
        if len(words) < 3:
            continue
        bad_idx = len(words) // 2
        corrupted = words.copy()
        # remplace un mot par un mot pris ailleurs (longueur similaire si possible)
        corrupted[bad_idx] = random.choice(wrong_pool[0].split())
        corrupted_text = " ".join(corrupted)

        global_score, per_word = align_and_score(audio, corrupted_text)
        print(f"\nRef      : {r['text']}")
        print(f"Corrompu : {corrupted_text}  (mot #{bad_idx} substitue: '{words[bad_idx]}' -> '{corrupted[bad_idx]}')")
        print("Scores par mot:")
        for i, (w, s) in enumerate(zip(corrupted, per_word)):
            marker = " <-- SUBSTITUE" if i == bad_idx else ""
            print(f"  [{i}] {w:20s} {s:.4f}{marker}" if s is not None else f"  [{i}] {w:20s} (vide){marker}")


if __name__ == "__main__":
    main()
