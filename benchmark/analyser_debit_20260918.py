"""LE DEBIT DEGRADE-T-IL LE MODELE, ET A PARTIR DE QUEL SEUIL ?

Demande utilisateur (2026-09-18) : « est-ce qu'il y a moyen de rendre l'ecran
vert, changer la couleur vers le rouge quand le debit est eleve, pour qu'il
reste sur la zone correcte du modele ? »

Un voyant a besoin d'un SEUIL. Un seuil invente ne vaut rien -- il ferait
clignoter l'ecran sur une frontiere qui ne correspond a aucune degradation
reelle. Ce script cherche donc si cette frontiere EXISTE dans les mesures.

CE QUI EST MESURE ICI, ET CE QUI NE L'EST PAS
---------------------------------------------
`CALIBRAGE_DEBIT_ET_PAUSES.md` (2026-07-31) dit noir sur blanc : « le debit
d'articulation n'est mesure nulle part ». Il ne l'est toujours pas -- mais les
donnees pour le calculer existaient deja : le corpus du banc porte les
SEGMENTS mot par mot (debut/fin en ms), alignes. Aucun son n'est synthetise,
aucun time-stretch : on lit le debit que les recitateurs ont REELLEMENT eu.

Le debit local d'un mot = nombre de mots / duree, sur une fenetre des W mots
qui le precedent DANS SON VERSET. Le decoupage par verset est volontaire : le
banc insere 350 ms de silence entre deux versets, et une pause inter-verset
compressee dans la fenetre ferait passer un debit normal pour un debit lent.

⚠️ LIMITE A GARDER EN TETE. C'est une CORRELATION sur des recitations reelles,
pas une experience. Le debit n'a pas ete fait varier sur un meme audio : un
recitateur rapide differe aussi par la voix, le micro, la prosodie. La lecon du
2026-09-17 s'applique ici plus qu'ailleurs -- l'idgham a 10,8 % et le contexte
d'ecoute a 69 % etaient deux correlations REELLES et deja neutralisees en aval.
Un ecart de taux entre deciles ne suffira donc pas a poser un seuil : il faudra
que la degradation soit MONOTONE et large, sinon c'est du bruit de recitateur.
"""
import json
import statistics
import unicodedata
from collections import defaultdict
from pathlib import Path

import campagne_100x20_dense30 as dense

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "benchmark/replay_chaine_jvm_20260915"
MAN = json.loads((ROOT / "benchmark/campagne_erreurs_reelles_20260916"
                  / "manifest.json").read_text(encoding="utf-8"))
CAS = {c["case_id"]: c for c in MAN["cases"]}
CFG = "vote_t3_bpe"

# Fenetre de calcul du debit : le mot lui-meme et les quatre precedents.
# L'encodeur est CAUSAL (cf. FAUX_SIGNALEMENTS_GRAPHIE_DE_LIAISON_20260917.md
# §3bis) : ce qui compte pour lui est ce qu'il vient d'entendre, pas la suite.
W = 5


def signale(s):
    return s not in ("inconnu", "definitif:VERT", "provisoire:VERT")


def charger_records():
    """(reciter, surah, premier_verset) -> {cle_verset: record}."""
    index = {}
    for reciter, surah, first, records in dense.load_scenarios():
        index[(reciter, surah, first)] = {r["key"]: r for r in records}
    return index


def debits_du_cas(cas, records):
    """idx global du mot -> (debit mots/s, duree du mot en s)."""
    out = {}
    for t in cas["timeline"]:
        rec = records.get(t["verse"])
        if rec is None:
            continue
        segs = rec["segments"]
        for k in range(min(t["word_count"], len(segs))):
            debut_fenetre = max(0, k - (W - 1))
            nb = k - debut_fenetre + 1
            if nb < 2:
                continue  # un seul mot ne donne pas un debit
            t0 = segs[debut_fenetre][2]
            t1 = segs[k][3]
            duree = (t1 - t0) / 1000.0
            if duree <= 0:
                continue
            out[t["word_start"] + k] = (nb / duree,
                                        (segs[k][3] - segs[k][2]) / 1000.0)
    return out


def main():
    rows = {(r["cas"], r["configuration"]): r
            for r in json.loads((OUT / "resultats.json").read_text(encoding="utf-8"))}
    index = charger_records()

    corrects, fautes = [], []
    for cid, cas in CAS.items():
        row = rows.get((cid, CFG))
        if not row:
            continue
        records = index.get((cas["reciter"], cas["surah"], cas["depart"]))
        if not records:
            print(f"  (pas de source pour {cid})")
            continue
        deb = debits_du_cas(cas, records)
        fautees = set()
        for o in cas["operations"]:
            fautees.update(o["affected_word_indices"])
        for i, mot in enumerate(cas["expected_words"]):
            s = row["statuts"].get(str(i), "inconnu")
            if s == "inconnu" or i not in deb:
                continue
            d, duree_mot = deb[i]
            ligne = dict(cas=cid, mot=i, texte=mot, debit=d,
                         duree=duree_mot, signale=signale(s))
            (fautes if i in fautees else corrects).append(ligne)

    print(f"{len(corrects)} mots corrects et {len(fautes)} fautes, "
          f"debit mesure sur une fenetre de {W} mots\n")

    tous = [x["debit"] for x in corrects + fautes]
    q = statistics.quantiles(tous, n=10)
    print("Distribution du debit (mots/s) sur tout le banc :")
    print("  min %.2f  p10 %.2f  mediane %.2f  p90 %.2f  max %.2f\n"
          % (min(tous), q[0], statistics.median(tous), q[8], max(tous)))

    # ── Le tableau qui repond a la question ────────────────────────────────
    # Par tranche de debit : combien de mots CORRECTS sont faussement
    # signales, et combien de FAUTES sont detectees. Un seuil n'existe que si
    # l'un des deux se degrade nettement et REGULIEREMENT quand le debit monte.
    bornes = [q[1], q[3], q[5], q[7]]  # p20, p40, p60, p80

    def tranche(d):
        for n, b in enumerate(bornes):
            if d < b:
                return n
        return len(bornes)

    noms = [f"< {bornes[0]:.2f}"] + \
           [f"{bornes[i]:.2f} – {bornes[i+1]:.2f}" for i in range(len(bornes) - 1)] + \
           [f"> {bornes[-1]:.2f}"]

    print("| debit (mots/s) | mots | faux signalements | fautes | detectees |")
    print("|---|---:|---:|---:|---:|")
    for n, nom in enumerate(noms):
        c = [x for x in corrects if tranche(x["debit"]) == n]
        f = [x for x in fautes if tranche(x["debit"]) == n]
        nf = sum(1 for x in c if x["signale"])
        nd = sum(1 for x in f if x["signale"])
        print("| %s | %d | %d — %.1f %% | %d | %d — %.0f %% |"
              % (nom, len(c), nf, 100 * nf / max(1, len(c)),
                 len(f), nd, 100 * nd / max(1, len(f))))

    # Comparaison directe des moyennes : le debit des mots faussement
    # signales differe-t-il seulement de celui des autres ?
    fx = [x["debit"] for x in corrects if x["signale"]]
    ok = [x["debit"] for x in corrects if not x["signale"]]
    print("\nDebit median des mots faussement signales : %.2f mots/s (n=%d)"
          % (statistics.median(fx) if fx else 0, len(fx)))
    print("Debit median des mots correctement laisses : %.2f mots/s (n=%d)"
          % (statistics.median(ok) if ok else 0, len(ok)))
    rd = [x["duree"] for x in corrects if x["signale"]]
    ro = [x["duree"] for x in corrects if not x["signale"]]
    print("Duree mediane du mot : faux %.3f s / corrects %.3f s"
          % (statistics.median(rd) if rd else 0,
             statistics.median(ro) if ro else 0))

    dest = ROOT / "benchmark/debit_20260918.json"
    dest.write_text(json.dumps(dict(fenetre_mots=W, corrects=corrects,
                                    fautes=fautes), ensure_ascii=False),
                    encoding="utf-8")
    print(f"\nDetail par mot : {dest.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
