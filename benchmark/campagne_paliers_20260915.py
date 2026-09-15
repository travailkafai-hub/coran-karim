"""Campagne a DENSITE D'ERREURS REGLABLE, en paliers, pour ~30 min de device.

POURQUOI DES PALIERS ET PAS UN SEUL TAUX (demande du 15/09 : « 40 % »).
`campagne_100x20_dense30` injecte SIX erreurs par rejeu de 20 versets, soit
4,78 % des mots (600 operations / 12 540 mots, mesure sur son manifeste). A
40 %, deux mots sur cinq sont montes : la LCS entre le texte attendu et le
decodage libre s'effondre, et l'ancre decroche. Le risque n'est pas que le
test echoue -- c'est qu'il mesure LE DECROCHAGE au lieu de la detection, sans
qu'on puisse distinguer les deux dans le resultat.

Les paliers repondent a la demande SANS perdre l'interpretation : le meme
banc porte 40 %, des taux intermediaires et des temoins propres. On lit alors
A PARTIR DE QUEL TAUX l'app cede, ce qu'un point unique ne peut pas dire.
Les temoins ne sont pas du remplissage : sans mot correct, aucun faux
signalement n'est mesurable (point 6 de la liste de Codex,
`TACHE_CLAUDE_VOTE_ET_TETE3_HAFS_20260915.md`).

CE QUE CE BANC NE PEUT PAS DIRE. Le montage reste synthetique, aux frontieres
de l'API : a 40 %, c'est un collage tous les deux mots et demi, et la prosodie
n'existe plus. Un signalement peut donc venir de l'ARTEFACT DE MONTAGE et non
de la faute -- distinction qu'aucun chiffre de sortie ne fera a notre place.
C'est du Hafs uniquement : les sources sont l'audio deja telecharge de
`campagne_100x20`, il n'existe pas d'equivalent Warsh dans ce banc.
"""
from __future__ import annotations

import argparse
import json
import random

import campagne_100x20 as base
import campagne_100x20_dense30 as dense

q = base.q
ROOT = q.ROOT
OUT = ROOT / "benchmark" / "campagne_paliers_20260915"

# Familles qui ne touchent QU'UN mot. `omission_span`, `omission_2words` et
# `permutation` mordent sur le mot i+1 : deux d'entre elles sur des cibles
# voisines se recouvriraient, et l'operation archivee ne decrirait plus
# l'audio reellement produit.
MONO = ["haraka_mutation", "extra_letter", "near_word_substitution",
        "truncate", "insertion", "omission_word"]


def choisir_cibles(n_mots: int, k: int, rng: random.Random) -> list[int]:
    """k mots NON ADJACENTS. Deux fautes collees rendraient le verdict
    inattribuable : on ne saurait plus laquelle des deux un rouge designe.
    Plafond structurel : un mot sur deux."""
    choisis: list[int] = []
    for i in rng.sample(range(n_mots), n_mots):
        if len(choisis) >= k:
            break
        if all(abs(i - j) >= 2 for j in choisis):
            choisis.append(i)
    return sorted(choisis)


def operation_mono(record, i, famille, rng, pool, reciter, base_index):
    """Une erreur sur le seul mot i. Positions rendues dans l'audio ORIGINAL."""
    words, segs, original = record["words"], record["segments"], record["samples"]
    start = int(segs[i][2] * 16)
    end = min(len(original), int(segs[i][3] * 16))
    clip_mot = original[start:end]
    actual = famille
    donor = dense.donor_for({"reciter": reciter, "word": words[i]}, pool, actual, rng)
    if actual in ("haraka_mutation", "extra_letter", "near_word_substitution") and donor is None:
        donor = dense.donor_for({"reciter": reciter, "word": words[i]}, pool,
                                "near_word_substitution", rng)
        # Requalifie AU VRAI CONTENU : un donneur trouve par le repli n'a plus
        # les memes lettres, annoncer encore `haraka_mutation` decrirait une
        # faute que l'audio ne porte pas.
        # Et PAS le repli « phoneme duplique » de dense30 quand il n'y a aucun
        # donneur : a cette densite il devenait la famille MAJORITAIRE (53 des
        # 195 erreurs du premier tirage), et on aurait mesure la reaction a un
        # ARTEFACT DE MONTAGE plutot qu'a une faute de recitation. Une
        # troncature est une vraie erreur audible et ne fabrique aucun son
        # absent du corpus.
        actual = "near_word_substitution" if donor else "truncate"
    op = dict(verse=record["key"], family=actual, word_index=i, expected=words[i],
              affected_word_indices=[base_index + i],
              target_normalized=dense.strip_marks(words[i]))
    if donor:
        op.update(donor_verse=donor["record"]["key"], donor_word=donor["index"],
                  replacement_text=donor["word"],
                  replacement_normalized=dense.strip_marks(donor["word"]))
    if actual in ("haraka_mutation", "extra_letter", "near_word_substitution") and donor:
        replacement = dense.clip(donor["record"], donor["index"])
        op["difference"] = ("same_letters_different_harakat" if actual == "haraka_mutation"
                            else "one_base_letter_or_near_word")
    elif actual == "insertion":
        d = donor or dense.donor_for({"reciter": reciter, "word": words[i]}, pool, "other", rng)
        replacement = dense.clip(d["record"], d["index"]) + q.silence(35) + clip_mot
        op["evaluation"] = "inserted donor word; nearby verdicts are proxy only"
    else:
        replacement = clip_mot[:max(1, int(len(clip_mot) * 0.48))]
        op["difference"] = "truncated_word"
    return start, end, replacement, op


def muter_verset(record, cibles, rng, pool, reciter, base_index, debut_audio):
    """Applique les erreurs de GAUCHE A DROITE avec un delta cumule : sans lui,
    `output_edit_start_ms` designerait la position dans l'audio d'origine et
    non dans le montage, et toute reecoute ciblee tomberait a cote."""
    changed = list(record["samples"])
    ops, delta = [], 0
    for i in cibles:
        start, end, replacement, op = operation_mono(
            record, i, rng.choice(MONO), rng, pool, reciter, base_index)
        op.update(source_start_sample=start, source_end_sample=end,
                  replacement_samples=len(replacement),
                  output_edit_start_ms=(debut_audio + start + delta) / 16)
        changed[start + delta:end + delta] = replacement
        delta += len(replacement) - (end - start)
        ops.append(op)
    return changed, ops


def prepare(paliers, cas_par_palier, versets):
    scenarios = dense.load_scenarios()
    pool = dense.make_pool(scenarios)
    OUT.mkdir(parents=True, exist_ok=True)
    cases, numero = [], 0
    for taux in paliers:
        for rang in range(cas_par_palier):
            scenario = scenarios[(numero + rang) % len(scenarios)]
            reciter, surah, first, records = scenario
            records = records[:versets]
            numero += 1
            rng = random.Random(20260915_40 + numero)
            expected, audio, operations, timeline = [], [], [], []
            total_mots = sum(len(r["words"]) for r in records)
            restant = round(taux * total_mots)
            for record in records:
                base_index = len(expected)
                expected.extend(record["words"])
                n = len(record["words"])
                # Reparti au prorata du verset, plafonne par les mots non
                # adjacents disponibles ; le reliquat glisse sur les suivants.
                vise = min(restant, max(0, round(taux * n)), (n + 1) // 2)
                cibles = choisir_cibles(n, vise, rng) if vise else []
                changed, ops = muter_verset(record, cibles, rng, pool, reciter,
                                            base_index, len(audio))
                restant -= len(ops)
                operations.extend(ops)
                timeline.append(dict(verse=record["key"], start_ms=len(audio) / 16,
                                     word_start=base_index, word_count=n))
                audio.extend(changed)
                audio.extend(q.silence(350))
            # `campagne_100x20.run` fait `int(case_id[1:])` pour ordonner : un
            # identifiant parlant comme « P040_1 » y leve une ValueError. Le
            # palier vit donc dans `family`/`palier_pct`, pas dans le nom.
            case_id = f"T{800 + numero:03d}"
            wav = OUT / "wav" / f"{case_id}.wav"
            q.write_wav(wav, audio)
            cases.append(dict(case_id=case_id, family=f"palier_{int(round(taux * 100))}pct",
                              palier_pct=int(round(taux * 100)),
                              taux_vise=taux, taux_reel=len(operations) / len(expected),
                              reciter=reciter, surah=surah, depart=first,
                              verse_count=len(records), riwaya="hafs",
                              expected_words=expected, duration_seconds=len(audio) / 16000,
                              wav=str(wav), sha256=q.sha256(wav), operations=operations,
                              timeline=timeline,
                              sources=[dict(key=r["key"], words=r["words"]) for r in records]))
            print(f"{case_id} palier={taux:.0%} reel={len(operations)/len(expected):.1%} "
                  f"{len(operations)} erreurs / {len(expected)} mots "
                  f"{len(audio)/16000:.1f}s", flush=True)
    base.save(OUT / "manifest.json", dict(
        seed=20260915_40, cases=cases,
        limitations=[
            "Paliers de densite : le taux est un TAUX DE MOTS, pas de versets.",
            "Familles mono-mot seulement ; deux fautes ne sont jamais adjacentes.",
            "Plafond structurel d'un mot sur deux (non-adjacence).",
            "Montage synthetique aux frontieres de l'API : a densite elevee un "
            "signalement peut venir de l'artefact de montage, pas de la faute.",
            "Hafs uniquement -- aucune source Warsh dans ce banc.",
        ]))
    duree = sum(c["duration_seconds"] for c in cases)
    reel = sum(len(c["operations"]) for c in cases) / sum(len(c["expected_words"]) for c in cases)
    print(f"PREPARED {len(cases)} cas, {duree/60:.1f} min d'audio, taux reel global {reel:.1%}",
          flush=True)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("action", choices=["prepare", "run"])
    p.add_argument("--serial", default="R3CY20XW7TD")
    p.add_argument("--paliers", default="0.40,0.20,0.10,0.0")
    p.add_argument("--cas-par-palier", type=int, default=2)
    p.add_argument("--versets", type=int, default=20)
    a = p.parse_args()
    if a.action == "prepare":
        prepare([float(x) for x in a.paliers.split(",")], a.cas_par_palier, a.versets)
    else:
        base.OUT = OUT
        base.run(a.serial)
