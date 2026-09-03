#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Controle avant/apres : taux de cles trouvees dans word_tokens_warsh.json
pour le texte Warsh REEL, avec la normalisation Dart a jour (shadda-ordre +
yeh-barree->alif-maksoura). Meme discipline que le controle du 2026-08-22
(100% attendu, sinon regression silencieuse du lookup)."""
import json, re, io, sys
from pathlib import Path
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

RACINE = Path(__file__).resolve().parent.parent
VERSES = RACINE / "app" / "assets" / "data" / "quran_verses_warsh.json"
DICO = RACINE / "modele_2geles_2026-08-22" / "word_tokens_warsh.json"

_HARAKAT = re.compile(r'[ً-ْٰۖ-ۭ]')

def nettoyer_pour_entrainement(t: str) -> str:
    t = t.replace('۞', '')  # rub el hizb
    t = t.replace('﻿', '')  # BOM
    return re.sub(r'\s+', ' ', t)

def normalize_training_warsh(w: str) -> str:
    t = nettoyer_pour_entrainement(w)
    t = t.replace('ے', 'ى')  # ye barree -> alif maksoura
    # shadda+harakat -> harakat+shadda (INVERSE de Hafs)
    t = re.sub('ّ' + '([ً-ٍَُِْ])',
               lambda m: m.group(1) + 'ّ', t)
    return re.sub(r'\s+', ' ', t).strip()

def split_expected_words(text: str):
    # Approximation de ArabicNormalizer.splitExpectedWords : on retire les
    # tokens qui ne contiennent AUCUNE lettre (marques de waqf isolees).
    out = []
    for w in text.split(' '):
        w = w.strip()
        if not w:
            continue
        sans_harakat = _HARAKAT.sub('', w)
        if sans_harakat.strip() == '' or sans_harakat.strip() in {'۞'}:
            continue
        out.append(w)
    return out

verses = json.loads(VERSES.read_text(encoding='utf-8'))
dico = json.loads(DICO.read_text(encoding='utf-8'))

distincts = set()
total_occurrences = 0
for v in verses:
    for w in split_expected_words(v['text_uthmani']):
        key = normalize_training_warsh(w)
        distincts.add(key)
        total_occurrences += 1

trouves = sum(1 for k in distincts if k in dico)
print(f"mots distincts (post-normalisation) : {len(distincts)}")
print(f"trouves dans le dictionnaire : {trouves} ({100*trouves/len(distincts):.2f}%)")
manquants = [k for k in distincts if k not in dico]
print(f"manquants : {len(manquants)}")
for m in manquants[:20]:
    print("  ", repr(m))
