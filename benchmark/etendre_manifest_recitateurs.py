#!/usr/bin/env python3
"""Ajoute au manifeste d'entrainement les recitateurs presents sur le disque
mais jamais utilises.

DEMANDE DE L'UTILISATEUR (2026-08-05) : « je tiens a augmenter dans
l'entrainement de l'encodeur plus d'heures de Coran et plus d'heures d'audio
arabe de lecture de texte arabe litteraire ».

CE QUE L'INVENTAIRE A MONTRE. 85 recitateurs sont sur le disque, 54 seulement
apparaissent dans `train_manifest.jsonl` : 24 dossiers non vides -- environ
513 heures, 103 898 clips -- n'ont JAMAIS servi. C'est presque TROIS FOIS les
260 heures de Coran actuellement utilisees, et cela ne demande aucun
telechargement.

POURQUOI LE TEXTE N'A PAS BESOIN D'UNE SOURCE EXTERNE. Les fichiers sont
nommes `<sourate>_<verset>.wav` et TOUS les recitateurs lisent le meme texte
coranique. Le texte vocalise de chaque verset est donc deja dans le manifeste,
porte par les recitateurs deja utilises. On le REPREND tel quel au lieu de le
redériver : aucune divergence de normalisation possible entre les anciennes
lignes et les nouvelles -- un piege classique, et le projet en a deja paye un
du meme genre avec deux `word_tokens.json` de meme taille mais de contenus
differents.

DUREE : lue dans l'en-tete WAV, jamais estimee. NeMo filtre sur `duration`
(min_duration/max_duration) ; une valeur approchee ferait entrer des clips que
la configuration voulait exclure.
"""
import argparse
import json
import os
import wave
from collections import defaultdict
from pathlib import Path

BASE = Path(__file__).parent
MANIFEST_DIR = BASE / "nemo_manifests_dual"


def cle_verset(chemin):
    """`.../<recitateur>/43_18.wav` -> ('43', '18'). None si le nom ne suit
    pas la convention (fichiers hors-Coran, augmentations...)."""
    nom = os.path.basename(chemin)
    if not nom.endswith(".wav"):
        return None
    base = nom[:-4]
    if "_" not in base:
        return None
    s, a = base.split("_", 1)
    return (s, a) if s.isdigit() and a.isdigit() else None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--manifest", default=str(MANIFEST_DIR / "train_manifest.jsonl"))
    p.add_argument("--racine", default=str(BASE / "data" / "train_wav_local"))
    p.add_argument("--sortie", required=True)
    p.add_argument("--min-duree", type=float, default=0.5)
    p.add_argument("--max-duree", type=float, default=20.0,
                   help="meme borne que la config d'entrainement : au-dela, "
                        "NeMo ecarterait la ligne de toute facon")
    a = p.parse_args()

    lignes = [json.loads(l) for l in open(a.manifest, encoding="utf-8")]
    print(f"manifeste actuel : {len(lignes)} lignes")

    # Texte de reference par verset + recitateurs deja presents.
    texte = {}
    presents = set()
    for d in lignes:
        c = cle_verset(d["audio_filepath"])
        if "train_wav" not in d["audio_filepath"]:
            continue
        rec = d["audio_filepath"].split("train_wav_local/")[-1] \
                                 .split("train_wav/")[-1].split("/")[0]
        presents.add(rec)
        if c and c not in texte:
            texte[c] = d["text"]
    print(f"  {len(presents)} recitateurs deja utilises, "
          f"{len(texte)} versets dont le texte est connu")

    racine = Path(a.racine)
    tous = sorted(x for x in os.listdir(racine) if (racine / x).is_dir())
    nouveaux = [r for r in tous if r not in presents]
    print(f"  {len(nouveaux)} recitateurs a ajouter\n")

    ajoutees, sans_texte, hors_bornes, illisibles = [], 0, 0, 0
    par_rec = defaultdict(float)
    for rec in nouveaux:
        for f in sorted(os.listdir(racine / rec)):
            chemin = racine / rec / f
            c = cle_verset(str(chemin))
            if c is None:
                continue
            t = texte.get(c)
            if t is None:
                sans_texte += 1
                continue
            try:
                with wave.open(str(chemin)) as w:
                    duree = w.getnframes() / w.getframerate()
            except Exception:
                illisibles += 1
                continue
            if not (a.min_duree <= duree <= a.max_duree):
                hors_bornes += 1
                continue
            ajoutees.append({"audio_filepath": str(chemin),
                             "duration": round(duree, 3), "text": t})
            par_rec[rec] += duree
        if par_rec[rec]:
            print(f"  {rec:38s} {par_rec[rec]/3600:6.1f} h")

    with open(a.sortie, "w", encoding="utf-8") as g:
        for d in lignes:
            g.write(json.dumps(d, ensure_ascii=False) + "\n")
        for d in ajoutees:
            g.write(json.dumps(d, ensure_ascii=False) + "\n")

    h_av = sum(float(d.get("duration", 0)) for d in lignes) / 3600
    h_ap = h_av + sum(par_rec.values()) / 3600
    print(f"\n  ecartes : {sans_texte} sans texte connu, "
          f"{hors_bornes} hors bornes de duree, {illisibles} illisibles")
    print(f"  {len(lignes)} -> {len(lignes)+len(ajoutees)} lignes")
    print(f"  {h_av:.1f} h -> {h_ap:.1f} h  (+{h_ap-h_av:.1f} h, "
          f"+{100*(h_ap-h_av)/h_av:.0f} %)")
    print(f"  -> {a.sortie}")


if __name__ == "__main__":
    main()
