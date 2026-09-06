"""Genere l'asset des coupes de palier : app/assets/data/coupes_paliers.json

  {"6:1": [5, 8], "13:2": [5, 10, 13, 17], ...}
    -> index du mot APRES lequel un palier peut s'arreter.

── POURQUOI HORS APP (2026-09-06) ───────────────────────────────────────────

Decision de l'utilisateur : « sinon on analyse le texte nous-memes au lieu de
laisser cette decision dans l'app ; travaille sur le texte entier ; tu peux
deduire les vrais endroits pour s'arreter, avoir une coherence structurelle,
meme si on augmente les paliers ».

Le calcul a l'execution ne voyait qu'un verset a la fois. Ici on lit les 6 236
d'un coup, ce qui ouvre la seule chose qui donne de la COHERENCE : le Coran se
repete enormement, et un meme groupe de mots doit etre coupe partout de la
meme facon.

── LES CINQ SOURCES, DANS L'ORDRE OU ELLES DECIDENT ────────────────────────

 1. WAQF, Hafs UNION Warsh. Le Hafs porte 4 359 marques typees sur 2 637
    versets ; le Warsh 9 946, toutes du meme type, sur 5 173 versets. L'union
    couvre 5 202 versets -- presque le double du Hafs seul.

 2. MAMNU (لا) : le seul signe qui dit « ne t'arrete pas ». Il ne cree aucune
    coupe, il en SUPPRIME -- et il s'applique aussi aux positions proposees par
    le Warsh, dont la typologie est ecrasee. 14 positions sont dans ce cas.

 3. LIAISONS. `و`/`ف` ouvre une proposition SAUF devant l'article defini `ال`,
    ou il coordonne un nom et prolonge la phrase. Regle purement
    orthographique, aucune morphologie : sur 6:1 elle rend exactement les
    arrets que l'utilisateur fait a voix haute (mots 5 et 8).

 4. N-GRAMMES FIGES -- c'est ce que l'analyse globale apporte, et rien d'autre
    ne pouvait le donner. Tout groupe de 2 a 5 mots qui revient au moins 3 fois
    dans le Coran est traite comme une unite : on n'y coupe pas. `ٱلسموت
    وٱلأرض` (133 fois), `يأيها ٱلذين ءامنوا` (89), `على كل شىء قدير` (33) ne
    sont donc jamais separes -- et ils le sont de la meme facon PARTOUT, ce qui
    est la definition meme de la coherence demandee.

 5. LONGUEUR. Distance minimale de 3 mots entre deux coupes (fixee par les
    arrets de 6:1, qui sont a 3 mots d'ecart), et plafond de 10 mots par
    palier. « Un palier a 4 mots reste un bon palier » : on ne cherche pas a
    les allonger, seulement a ne pas depasser.

⚠️ CE QUE CE FICHIER N'EST PAS. Pas une autorite religieuse sur les arrets
licites. C'est une lecture STRUCTURELLE du texte, qui s'appuie sur les marques
que les deux mushaf portent et sur ce que le Coran repete. La voix du
recitateur reste la source la plus fidele quand elle est disponible -- l'app
unit les deux.
"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent / "app" / "assets" / "data"
SORTIE = BASE / "coupes_paliers.json"

HARAKAT = re.compile("[ً-ٰؐ-ؚۖ-ۭـ]")
WAQF = set(range(0x06D6, 0x06DC))
MAMNU = {0x06D9}
ALEFS = "اأإآٱ"

# Ouvrent une proposition quoi qu'il suive.
PARTICULES = {
    "ثم", "فإن", "فإذا", "فأما", "فلما", "إن", "إنا", "إنما", "إنه",
    "أما", "بل", "لكن", "حتى", "إذا", "لعل", "كأن", "ألا", "أفلا", "أولئك",
}
# Ne creent jamais de coupe seules : plan de secours pour refendre un palier
# trop long (prepositions, particules faibles).
SECOURS = {
    "من", "في", "إلى", "على", "عن", "إلا",
    "لما", "كما", "حين", "بين", "عند", "لدى", "قد", "لقد",
}

DISTANCE_MIN = 3
PALIER_MAX = 10
NGRAMME_MIN_OCC = 3      # un groupe vu au moins 3 fois est tenu pour fige
NGRAMME_MAX_LEN = 5


def norm(mot: str) -> str:
    return HARAKAT.sub("", mot).strip()


def mots(texte: str) -> list[str]:
    return [w for w in re.split(r"\s+", texte) if w and norm(w)]


def positions(texte: str, codes: set[int]) -> list[int]:
    """Index du mot APRES lequel tombe chaque marque de `codes`.

    Une marque peut etre collee a un mot ou former un token isole ; dans les
    deux cas elle appartient au mot qui la PRECEDE.
    """
    out, i = [], -1
    for w in re.split(r"\s+", texte):
        if not w:
            continue
        if norm(w):
            i += 1
        for c in w:
            if ord(c) in codes and i >= 0:
                out.append(i)
    return out


def ouvre_proposition(n: str) -> bool:
    if n in PARTICULES:
        return True
    if not n or n[0] not in "وف":
        return False
    reste = n[1:]
    if len(reste) < 2:
        return False
    # و/ف + ARTICLE DEFINI : coordination d'un nom, la phrase continue.
    if reste[0] in ALEFS and reste[1] == "ل":
        return False
    return True


def charger():
    h = {v["verse_key"]: v["text_uthmani"]
         for v in json.load(open(BASE / "quran_verses.json", encoding="utf-8"))}
    try:
        w = {v["verse_key"]: v["text_uthmani"]
             for v in json.load(open(BASE / "quran_verses_warsh.json", encoding="utf-8"))}
    except Exception as e:
        print("  (Warsh indisponible : %s)" % e)
        w = {}
    return h, w


def ngrammes_figes(versets):
    """Positions INTERNES aux groupes figes, par verset.

    Un groupe de 2 a NGRAMME_MAX_LEN mots vu au moins NGRAMME_MIN_OCC fois est
    une unite : couper dedans separerait un syntagme que le Coran traite
    partout comme un bloc.
    """
    compte = Counter()
    for _, m in versets:
        for n in range(2, NGRAMME_MAX_LEN + 1):
            for i in range(len(m) - n + 1):
                compte[tuple(m[i:i + n])] += 1
    interdits = {}
    for cle, m in versets:
        inter = set()
        for n in range(2, NGRAMME_MAX_LEN + 1):
            for i in range(len(m) - n + 1):
                if compte[tuple(m[i:i + n])] >= NGRAMME_MIN_OCC:
                    # positions internes : entre i et i+n-1
                    inter.update(range(i, i + n - 1))
        interdits[cle] = inter
    return interdits, compte


def coupes_du_verset(cle, texte_h, texte_w, interdits):
    m = mots(texte_h)
    n = len(m)
    if n < 2:
        return []
    brut = set(positions(texte_h, WAQF))
    if texte_w and len(mots(texte_w)) == n:
        brut |= set(positions(texte_w, WAQF))
    for i in range(1, n):
        if ouvre_proposition(norm(m[i])):
            brut.add(i - 1)
    brut -= set(positions(texte_h, MAMNU))
    # Les groupes figes ne se coupent pas.
    brut -= interdits

    # Distance minimale.
    out, d = [], -DISTANCE_MIN
    for i in sorted(x for x in brut if 0 <= x < n - 1):
        if i - d < DISTANCE_MIN:
            continue
        out.append(i)
        d = i

    # Plafond : refendre ce qui depasse, sur une preposition si possible.
    #
    # ⚠️ RECURSIF, ET C'EST NECESSAIRE. Premiere version : on coupait puis on
    # avancait (`d = best + 1`), donc le segment de GAUCHE qu'on venait de
    # creer n'etait jamais reexamine. Sur 33:6, le palier 5..23 (19 mots) etait
    # coupe en 17, ce qui laissait un 5..17 de 13 mots -- toujours hors limite,
    # et personne ne le revoyait. On refend donc les DEUX moities.
    final = list(out)

    def refendre(d, fin):
        if fin - d + 1 <= PALIER_MAX:
            return
        milieu = (d + fin) // 2
        cands = [i for i in range(d + DISTANCE_MIN - 1, fin - DISTANCE_MIN + 1)
                 if i + 1 < n
                 and norm(m[i + 1]) in SECOURS
                 and i not in interdits]
        if cands:
            best = min(cands, key=lambda i: abs(i - milieu))
        else:
            # Dernier recours : le milieu, recule hors d'un groupe fige.
            best = milieu
            while best in interdits and best > d + DISTANCE_MIN - 1:
                best -= 1
            if best in interdits:
                return          # tout le segment est fige : on le laisse
        if best <= d - 1 or best >= fin:
            return
        final.append(best)
        refendre(d, best)
        refendre(best + 1, fin)

    debut = 0
    for fin in out + [n - 1]:
        refendre(debut, fin)
        debut = fin + 1
    return sorted(set(final))


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    H, W = charger()
    versets = [(k, [norm(x) for x in mots(t)]) for k, t in H.items()]
    print("versets : %d" % len(versets))
    interdits, compte = ngrammes_figes(versets)
    figes = sum(1 for g, k in compte.items() if k >= NGRAMME_MIN_OCC)
    print("groupes figes (>= %d occurrences, 2 a %d mots) : %d"
          % (NGRAMME_MIN_OCC, NGRAMME_MAX_LEN, figes))

    out, tailles, sans_coupe = {}, [], 0
    for cle, texte in H.items():
        c = coupes_du_verset(cle, texte, W.get(cle), interdits.get(cle, set()))
        n = len(mots(texte))
        if c:
            out[cle] = c
        else:
            sans_coupe += 1
        debut = 0
        for x in c + [n - 1]:
            tailles.append(x - debut + 1)
            debut = x + 1

    tailles.sort()
    med = tailles[len(tailles) // 2]
    trop = sum(1 for t in tailles if t > PALIER_MAX)
    print("\npaliers        : %d" % len(tailles))
    print("  mediane      : %d mots" % med)
    print("  maximum      : %d mots" % tailles[-1])
    print("  au-dela de %d : %d (%.2f %%)" % (PALIER_MAX, trop, 100 * trop / len(tailles)))
    print("versets sans aucune coupe : %d" % sans_coupe)

    SORTIE.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")),
                      encoding="utf-8")
    print("\n%s : %d versets, %.0f ko"
          % (SORTIE, len(out), SORTIE.stat().st_size / 1024))

    for k in ("6:1", "13:2", "33:6"):
        m = mots(H[k])
        c = out.get(k, [])
        print("\n%s -> %s" % (k, c))
        debut = 0
        for x in c + [len(m) - 1]:
            print("   %2d..%2d (%2d) : %s" % (debut, x, x - debut + 1,
                                              " ".join(m[debut:x + 1])))
            debut = x + 1


if __name__ == "__main__":
    main()
