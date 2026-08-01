#!/usr/bin/env python3
"""GENERE des fragments COURTS a partir des clips de recitation reelle existants.

Traite le trou mesure dans ETAT_CTC_NEMO.md (2026-07-31, demande utilisateur
« plutot sur des durees plus courtes que sur des durees plus longues ») : sur
les 59 232 clips de `train_wav_local/`, seuls 2,6 % durent moins de 3 s -- la
zone des segments coupes en frontiere (mot tronque, phrase amputee en tete),
exactement ce que produit la segmentation reelle de l'app.

── LA DECISION DE CONCEPTION, ET POURQUOI ELLE EST LA PARTIE QUI COMPTE ────
Ce script COUPE REELLEMENT EN PLEIN MOT en fin de fragment -- c'est le point,
puisque c'est ce que la segmentation reelle produit -- mais NE DONNE RIEN
comme cible pour ce mot tronque. La cible ne contient QUE les mots COMPLETS
qui precedent.

Correction utilisateur (2026-07-31) sur une premiere version qui evitait toute
coupe en plein mot par prudence : « je n'ai pas demande que tu lui donnes le
mot complet ... je pense rien donner pour que le modele puisse ignorer un mot
non complet ». C'est le bon choix, et il evite les deux ecueils :
  - donner le mot ENTIER comme cible apprendrait a HALLUCINER un mot complet
    depuis un son partiel -- le correctif palliatif que le projet interdit
    (CLAUDE.md, « ne jamais compenser une perte d'information d'une couche
    basse par une tolerance ajoutee dans une couche haute »). Le precedent
    concret : requalifier un fragment "correct" en aval avait masque la vraie
    cause (coupe en plein mot dans le BUFFER) -- meme defaut, vu depuis
    l'entrainement cette fois.
  - EVITER la coupe en plein mot (version precedente) manquait justement
    l'occasion d'entrainer la robustesse a ce cas-la, qui est le cas REEL que
    l'app produit en continu.
  - NE RIEN DONNER pour le mot tronque laisse le CTC apprendre lui-meme, sans
    cible fabriquee, ce qu'une fin d'audio incomplete doit produire -- au
    pire du silence/blank, jamais un mot invente.

── D'OU VIENNENT LES FRONTIERES DE MOTS, SANS NOUVEL ALIGNEMENT ────────────
De `word_timings_ref.json` (deja construit, cf. collect_word_timings.py) :
mediane INTER-RECITATEURS des durees de mots, exprimee en PROPORTIONS (`rel`,
sans dimension) -- donc reutilisable sur N'IMPORTE QUEL recitateur en la
mettant a l'echelle de sa duree de clip reelle. Verifie manuellement (44:15,
Yasser Ad-Dussary) : le compte de mots correspond exactement.

⚠️ APPROXIMATION ASSUMEE : `rel` vient d'AUTRES recitateurs (median murattal),
pas de celui du clip en cours. La frontiere estimee peut glisser de quelques
dizaines de ms par rapport a la vraie prononciation de CE recitateur precis.
Suffisant pour de l'augmentation d'entrainement (statistique sur des milliers
de clips) ; PAS suffisant pour un usage de jugement temps reel -- ce script ne
touche a aucune chaine de decision.

── CE QUI EST EXCLU, ET POURQUOI ──────────────────────────────────────────
- Bismillah et versets sans timings de reference (`word_timings_ref` absent) :
  passes, comptes et rapportes en fin de run -- pas d'estimation bricolee.
- Le symbole de pause waqf (`ۚ` etc.) dans le texte est un token du split()
  mais PAS un mot recite -- filtre AVANT d'apparier aux `rel` (sinon le compte
  ne correspond plus, cf. verification manuelle 6 `rel` pour 7 tokens dont 1
  waqf sur 44:15).
"""
import json
import random
import re
from pathlib import Path

import numpy as np
import soundfile as sf

BASE = Path(__file__).parent
TIMINGS = BASE / "word_timings_ref.json"
MANIFEST_IN = BASE / "nemo_manifests_dual" / "train_manifest.jsonl"
OUT_DIR = BASE / "data" / "clips_courts"
OUT_MANIFEST = OUT_DIR / "manifest.jsonl"

# Le meme filtre que collect_word_timings.py utilise implicitement : un token
# qui ne contient AUCUNE lettre arabe n'est pas un mot recite (waqf, ponctuation).
_LETTRE_AR = re.compile(r"[ء-يٮ-ۓ]")


def est_un_mot(tok: str) -> bool:
    return bool(_LETTRE_AR.search(tok))


def verse_key_depuis_chemin(p: Path):
    """`.../<reciter>/<surah>_<ayah>.wav` -> "surah:ayah", ou None si le nom
    ne suit pas ce format (fichiers hors convention, ecartes proprement)."""
    m = re.match(r"^(\d+)_(\d+)$", p.stem)
    return f"{m.group(1)}:{m.group(2)}" if m else None


def frontieres_mots(duree_s: float, rels: list[float]) -> list[float]:
    """Bornes cumulees ESTIMEES des mots (secondes), a l'echelle de la duree
    REELLE de ce clip -- pas de la duree de reference (le recitateur de ce clip
    peut etre plus lent ou plus rapide que la mediane murattal)."""
    total_rel = sum(rels)
    if total_rel <= 0:
        return []
    bornes = [0.0]
    acc = 0.0
    for r in rels:
        acc += r
        bornes.append(duree_s * acc / total_rel)
    return bornes


def decouper_un_clip(pcm, sr, mots, bornes, dmin, dmax, rng,
                     p_troncature=0.6, max_essais=6):
    """Choisit une fenetre [i, j) de mots COMPLETS, PUIS -- la plupart du
    temps -- prolonge l'AUDIO d'une fraction aleatoire du mot j+1 SANS
    l'ajouter a la cible texte. C'est la coupe en plein mot reelle, avec
    « rien donne » pour la partie tronquee (cf. docstring du module).

    @param p_troncature probabilite de produire un fragment tronque plutot
        qu'un fragment proprement borne -- les deux cotoexistent dans le
        corpus, comme les deux cas coexistent reellement sur device (une
        coupe tombe parfois pile sur une frontiere).
    """
    n = len(mots)
    if n < 1:
        return None
    for _ in range(max_essais):
        cible = rng.uniform(dmin, dmax)
        i = rng.randrange(n)
        j = i
        while j < n and bornes[j + 1] - bornes[i] <= cible:
            j += 1
        d = bornes[j] - bornes[i]
        if not (dmin <= d <= dmax and j > i):
            continue

        a = int(bornes[i] * sr)
        b_propre = min(int(bornes[j] * sr), len(pcm))
        tronque = False
        b = b_propre
        if j < n and rng.random() < p_troncature:
            # Prolonge dans le mot SUIVANT, sans jamais l'atteindre en entier
            # (sinon ce serait juste un mot complet de plus, pas une coupe).
            duree_mot_suivant = bornes[j + 1] - bornes[j]
            fraction = rng.uniform(0.15, 0.85)
            b_essai = b_propre + int(duree_mot_suivant * fraction * sr)
            b_essai = min(b_essai, len(pcm))
            if b_essai > b_propre and (b_essai - a) / sr <= dmax + 2.0:
                b = b_essai
                tronque = True

        if b - a < int(0.5 * sr):
            continue
        # La cible ne contient QUE les mots i:j -- le mot tronque (j) n'y
        # figure JAMAIS, meme partiellement.
        return pcm[a:b], " ".join(mots[i:j]), tronque
    return None


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--dmin", type=float, default=3.0,
                     help="borne basse -- 3 s, la bande demandee par l'utilisateur")
    ap.add_argument("--dmax", type=float, default=8.0)
    ap.add_argument("--par_clip", type=int, default=2,
                     help="fragments courts vises par clip source -- 2 pour "
                          "couvrir plus large que la seule premiere fenetre "
                          "tiree par clip")
    ap.add_argument("--p_troncature", type=float, default=0.6,
                     help="proportion de fragments COUPES EN PLEIN MOT "
                          "(le mot tronque n'est JAMAIS dans la cible texte) "
                          "-- le reste est proprement borne sur des mots "
                          "entiers, cf. decouper_un_clip()")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--limite", type=int, default=None,
                     help="pour un essai rapide avant le run complet")
    a = ap.parse_args()

    timings = json.loads(TIMINGS.read_text(encoding="utf-8"))
    lignes = [json.loads(l) for l in open(MANIFEST_IN, encoding="utf-8")]
    reelles = [l for l in lignes if "train_wav_local" in l.get("audio_filepath", "")]
    if a.limite:
        reelles = reelles[:a.limite]
    print(f"{len(reelles)} clips de recitation reelle candidats")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    rng = random.Random(a.seed)

    sans_timing, trop_courts, ecrits, tronques = 0, 0, 0, 0
    with open(OUT_MANIFEST, "w", encoding="utf-8") as fout:
        for k, l in enumerate(reelles):
            p = Path(l["audio_filepath"])
            vk = verse_key_depuis_chemin(p)
            t = timings.get(vk) if vk else None
            if t is None:
                sans_timing += 1
                continue

            mots = [w for w in l["text"].split() if est_un_mot(w)]
            rels = t["rel"]
            if len(mots) != len(rels):
                # Desaccord de comptage (texte manifest != quran.com pour ce
                # verset) : on n'invente pas de correspondance, on passe.
                sans_timing += 1
                continue

            try:
                pcm, sr = sf.read(str(p), dtype="float32")
            except Exception:
                continue
            if pcm.ndim > 1:
                pcm = pcm.mean(axis=1)
            bornes = frontieres_mots(len(pcm) / sr, rels)

            for _ in range(a.par_clip):
                r = decouper_un_clip(pcm, sr, mots, bornes, a.dmin, a.dmax, rng,
                                     p_troncature=a.p_troncature)
                if r is None:
                    trop_courts += 1
                    continue
                audio, texte, tronque = r
                if not texte:
                    # Fenetre reduite au seul mot tronque (aucun mot COMPLET
                    # avant lui) : aucune cible utilisable, on n'ecrit rien
                    # plutot que d'ecrire un texte vide qui n'apprendrait rien
                    # de fiable.
                    trop_courts += 1
                    continue
                nom = f"court_{ecrits:06d}.wav"
                sf.write(str(OUT_DIR / nom), audio, sr)
                fout.write(json.dumps({
                    "audio_filepath": str(OUT_DIR / nom),
                    "duration": round(len(audio) / sr, 3),
                    "text": texte,
                    "tronque": tronque,
                    "source": str(p), "verse_key": vk,
                }, ensure_ascii=False) + "\n")
                ecrits += 1
                if tronque:
                    tronques += 1

            if (k + 1) % 5000 == 0:
                print(f"  {k+1}/{len(reelles)}  ecrits={ecrits}")

    print(f"\n{ecrits} fragments ecrits -> {OUT_MANIFEST}")
    print(f"  dont TRONQUES (coupe en plein mot, mot exclu de la cible) : "
          f"{tronques} ({100*tronques/max(1,ecrits):.0f} %)")
    print(f"sans timing de reference : {sans_timing}")
    print(f"aucune fenetre [{a.dmin};{a.dmax}] trouvee ou cible vide : {trop_courts}")


if __name__ == "__main__":
    main()
