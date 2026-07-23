"""Construit les manifests pour l'entrainement A DEUX TETES CTC (2026-07-22).

── POURQUOI DEUX TETES ──
Mesure de cette session : melanger lettres/harakat et symboles de regles dans
UN SEUL vocabulaire BPE cause deux degats distincts, tous deux mesures :
  1. Dilution -- ~20% de masse de probabilite part sur les tokens-symboles
     MEME sur un mot sans aucune regle attendue (mesure sur "يَوْمِ").
  2. Fusion BPE cassee -- le symbole ham_wasl separe ٱ de ل, si bien que le
     modele n'a JAMAIS appris le token soude `▁ٱلْعَ` sur de l'audio coranique
     (1,6% des lignes annotees contre 72% des lignes non annotees), alors que
     c'est precisement celui que l'alignement force lui reclame.

Separer les deux tetes supprime les DEUX par construction : elles ne
partagent plus le meme softmax, donc plus de competition, et la tete lettres
retrouve un vocabulaire strictement identique a celui de mixed-e14 (jamais
contamine par un symbole).

── CE QUE FAIT CE SCRIPT ──
A partir des manifests annotes existants (nemo_manifests_rules/, dont le texte
contient les symboles PUA U+E000..U+E010 inseres dans les lettres), produit un
manifest ou chaque ligne porte DEUX cibles :
    text        -> lettres + harakat SEULES (symboles retires)  [tete 1]
    text_tajwid -> symboles SEULS, dans l'ordre                 [tete 2]

Exemple :
    entree : "إِنّَا كَاشِفُوا۟ ٱلْعَذَابِ"
    text        = "إِنَّا كَاشِفُوا۟ ٱلْعَذَابِ"
    text_tajwid = ""

⚠️ CLIPS NON ANNOTES (ASC arabe general, TTS) : 98 280 des 156 892 lignes
n'ont aucun symbole -- ce n'est PAS "aucune regle realisee", c'est "on ne
sait pas" (jamais annote). Leur mettre une cible tajwid VIDE apprendrait a la
tete 2 a se taire sur ces voix, ce qui est une information fausse. Ils
recoivent donc `text_tajwid: null` et le script d'entrainement MASQUE la loss
tajwid pour ces echantillons (poids 0) -- ils continuent d'entrainer la tete
lettres normalement.

Sortie (nouveau dossier, aucun ecrasement -- regle projet) :
    nemo_manifests_dual/{train,val}_manifest.jsonl
"""
import json
from pathlib import Path

BASE = Path(__file__).parent
IN_DIR = BASE / "nemo_manifests_rules"
OUT_DIR = BASE / "nemo_manifests_dual"

# Zone privee Unicode utilisee par build_rules_annotated_corpus.py pour les
# 17 classes (U+E000 = madda_necessary ... U+E010 = qalaqah).
PUA_LO, PUA_HI = 0xE000, 0xE010


def split_text(annotated):
    """(lettres_seules, symboles_seuls) a partir du texte annote."""
    lettres, symboles = [], []
    for ch in annotated:
        if PUA_LO <= ord(ch) <= PUA_HI:
            symboles.append(ch)
        else:
            lettres.append(ch)
    return "".join(lettres), "".join(symboles)


def convert(in_path, out_path):
    n_tot = n_annot = n_vides = 0
    with open(in_path, encoding="utf-8") as f, \
            open(out_path, "w", encoding="utf-8") as out:
        for line in f:
            r = json.loads(line)
            lettres, symboles = split_text(r["text"])
            r["text"] = lettres
            if symboles:
                r["text_tajwid"] = symboles
                n_annot += 1
            else:
                # Distinction essentielle (cf. docstring) : null = "non
                # annote, ne rien apprendre", et NON "aucune regle".
                r["text_tajwid"] = None
                n_vides += 1
            out.write(json.dumps(r, ensure_ascii=False) + "\n")
            n_tot += 1
    print(f"{out_path.name} : {n_tot} lignes "
          f"({n_annot} annotees tajwid, {n_vides} non annotees -> loss masquee)")
    return n_tot, n_annot


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name in ("train_manifest.jsonl", "val_manifest.jsonl"):
        src = IN_DIR / name
        if not src.exists():
            raise SystemExit(f"introuvable : {src}")
        convert(src, OUT_DIR / name)

    # Controle : aucun symbole ne doit subsister dans `text`, et tout symbole
    # de `text_tajwid` doit etre dans la plage attendue.
    bad_text = bad_sym = 0
    for line in open(OUT_DIR / "train_manifest.jsonl", encoding="utf-8"):
        r = json.loads(line)
        if any(PUA_LO <= ord(c) <= PUA_HI for c in r["text"]):
            bad_text += 1
        if r["text_tajwid"] and any(
                not (PUA_LO <= ord(c) <= PUA_HI) for c in r["text_tajwid"]):
            bad_sym += 1
    print(f"controle : {bad_text} lignes avec symbole residuel dans `text` "
          f"(doit etre 0), {bad_sym} avec caractere non-PUA dans `text_tajwid` "
          f"(doit etre 0)")
    assert bad_text == 0 and bad_sym == 0, "separation incorrecte"
    print(f"OK -> {OUT_DIR}")


if __name__ == "__main__":
    main()
