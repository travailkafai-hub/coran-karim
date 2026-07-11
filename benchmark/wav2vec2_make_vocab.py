"""
Construit le vocabulaire caractere pour le CTC (wav2vec2) a partir du texte Coran.
Le CTC predit un caractere par frame audio -> il faut la liste des caracteres.

Sortie : data/wav2vec2_vocab.json   { "ا":0, "ب":1, ..., "|":N, "[UNK]":N+1, "[PAD]":N+2 }
  "|" = delimiteur de mot (remplace l'espace, convention wav2vec2)

CPU uniquement — n'utilise pas le GPU.
"""
import json, os
from collections import Counter

ROOT  = os.path.dirname(os.path.abspath(__file__))
SRC   = os.path.join(ROOT, "data", "train_combined.jsonl")
if not os.path.exists(SRC):
    SRC = os.path.join(ROOT, "data", "train_full.jsonl")
OUT   = os.path.join(ROOT, "data", "wav2vec2_vocab.json")

counter = Counter()
n = 0
for line in open(SRC, encoding="utf-8"):
    txt = json.loads(line)["text"]
    counter.update(txt.replace(" ", ""))   # on compte les chars hors espace
    n += 1

# Garde tous les caracteres apparaissant (le Coran a un jeu de chars fixe)
chars = sorted(counter.keys())
print(f"{n} lignes, {len(chars)} caracteres distincts", flush=True)
print("Caracteres:", "".join(chars), flush=True)
print("Top 10 freq:", counter.most_common(10), flush=True)

vocab = {c: i for i, c in enumerate(chars)}
vocab["|"]     = len(vocab)   # delimiteur de mot (= espace)
vocab["[UNK]"] = len(vocab)
vocab["[PAD]"] = len(vocab)

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(vocab, f, ensure_ascii=False, indent=2)

print(f"\nVocab size: {len(vocab)} -> {OUT}", flush=True)
print("VOCAB DONE", flush=True)
