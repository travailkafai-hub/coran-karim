#!/usr/bin/env python3
"""Variante de eval_error_detection.py pour les modeles tokenizer "regles"
(17 symboles PUA U+E000-U+E010, cf. tokenizers/tajweed_rules_bpe_v1).

POURQUOI CE FICHIER (2026-07-19) : eval_error_detection.py compare la
transcription a des references SANS symboles de regles (val_errors_annotated
/ val_canonical, vocabulaire "light"). Un modele regles qui emet
CORRECTEMENT un symbole de regle serait donc penalise comme si c'etait une
insertion parasite -- injuste, et incoherent avec la decision Phase 2.1 (la
normalisation/suppression des symboles est la couche de comparaison
"mode tolerant", cout zero). On reutilise donc eval_error_detection.py
tel quel (meme metrique, meme protocole, meme jeu de val) et on ne
monkey-patche QUE `transcribe()` pour retirer les symboles avant le calcul
du CER -- comparaison strictement equitable au modele deploye (mixed-e14,
vocabulaire light, jamais entraine avec ces symboles).

Usage : identique a eval_error_detection.py.
    python3 eval_error_detection_rules_stripped.py <checkpoint.nemo> [--limit N] [--cpu]
"""
import eval_error_detection as base

_RULE_SYMBOLS_LO, _RULE_SYMBOLS_HI = 0xE000, 0xE010


def _strip_rule_symbols(text):
    return "".join(c for c in text if not (_RULE_SYMBOLS_LO <= ord(c) <= _RULE_SYMBOLS_HI))


_orig_transcribe = base.transcribe


def transcribe_stripped(model, paths, bs=4):
    hyps = _orig_transcribe(model, paths, bs=bs)
    return [_strip_rule_symbols(h) for h in hyps]


base.transcribe = transcribe_stripped

if __name__ == "__main__":
    base.main()
