#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
"""Corrige la substitution du yeh barree dans word_tokens_warsh.json.

Constat (2026-08-23, log device apres plusieurs recitations Warsh reelles) :
"الذي"/"في" (ecrits avec ے dans le texte source Warsh) restaient rouges,
alors meme que le correctif du 2026-08-22 (step39) avait deja elimine leurs
<unk>. Cause : step39 substituait ے -> ي (yeh normal, U+064A) avant de
retokeniser. Le modele, en decodage LIBRE sur ces memes mots, emet
systematiquement ي (U+0649, alif maksoura) -- confirme sur le log device par
le code point exact (0x649) de `entendu`. Or ي et ى sont deux PIECES
DIFFERENTES du vocabulaire SentencePiece (verifie : "في" -> [213] contre
"فى" -> [91], deux ids distincts, pas un synonyme). La cible d'alignement
pointait donc vers la mauvaise piece, quelle que soit la prononciation.

Corrige en alignant la substitution sur celle DEJA utilisee cote Dart pour
la comparaison de jugement (`ArabicNormalizer._collapseVariantsWarsh`,
2026-08-12) : ے -> ى (alif maksoura), pas ي. Cle ET tokens sont mis a jour
ensemble (meme regle que le correctif d'ordre de la shadda du 2026-08-22 :
« changer l'un sans l'autre casse le lookup »).
"""
import json
import sentencepiece as spm
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
DICO = RACINE / "modele_2geles_2026-08-22" / "word_tokens_warsh.json"
MODELE_SP = RACINE / "modele_2geles_2026-08-22" / "tokenizers" / "warsh.model"

sp = spm.SentencePieceProcessor(model_file=str(MODELE_SP))

d = json.loads(DICO.read_text(encoding="utf-8"))
print(f"dictionnaire charge : {len(d)} mots")

cles_ye = [k for k in d if "ے" in k]  # U+06D2 = yeh barree
print(f"cles avec yeh barree (U+06D2) : {len(cles_ye)}")

renommees = 0
collisions_identiques = 0
collisions_differentes = []
unk_apres = []

for ancienne in cles_ye:
    nouvelle = ancienne.replace("ے", "ى")  # -> alif maksoura
    ids = sp.encode(nouvelle, out_type=int)
    if 0 in ids:
        unk_apres.append((nouvelle, ids))
        continue
    if nouvelle in d and nouvelle not in cles_ye:
        if d[nouvelle] == ids:
            collisions_identiques += 1
        else:
            collisions_differentes.append((nouvelle, d[nouvelle], ids))
    d[nouvelle] = ids
    del d[ancienne]
    renommees += 1

print(f"renommees (cle + tokens) : {renommees}")
print(f"collisions avec une cle preexistante identique en tokens : {collisions_identiques}")
print(f"collisions DIFFERENTES (a examiner) : {len(collisions_differentes)}")
for c in collisions_differentes[:10]:
    print("  ", c)
print(f"<unk> apres retokenisation (ne devrait jamais arriver ici) : {len(unk_apres)}")
for u in unk_apres[:10]:
    print("  ", u)

DICO.write_text(json.dumps(d, ensure_ascii=False), encoding="utf-8")
print(f"ecrit : {DICO} ({len(d)} mots)")
