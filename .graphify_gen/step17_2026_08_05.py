#!/usr/bin/env python3
"""Consigne dans le graphe ce qui a ete MESURE le 2026-08-05.

Chaque `rationale` porte LE CHIFFRE, pas l'intention -- c'est la seule chose
qui permette a un futur agent de repondre « est-ce que ca a deja ete essaye ? »
sans relancer la mesure. L'etat precedent est sauvegarde, aucune piste n'est
jamais ecrasee.
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    ("mesure_parite_tete3_2026_08_05",
     "[MESURE] Parite tete 3 Python/Kotlin etablie — 44 tests JVM",
     "Le telephone calculait une APPROXIMATION : etat moyenne seule (512) au "
     "lieu de moyenne+ecart-type (1024), forced_f recopiant le Viterbi au lieu "
     "du forward CTC, alt/alt2 tires de 2 confusions au lieu du jeu complet. "
     "Aucune ne levait d'erreur : le logit sortait, il etait faux. Vecteur de "
     "reference produit sur vrai audio + vrai modele, arrondi AVANT calcul des "
     "attendus pour que le contrat soit clos sur lui-meme."),
    ("mort_filtre_sentinelle_divise",
     "[MORT] Filtrer la sentinelle NEG apres division par n — ne filtre rien "
     "des 3 frames",
     "`score/n > NEG/2` : pour n>=3, -1e30/n > -5e29, donc la sentinelle PASSE. "
     "Le filtre ne protegeait que les mots de 1-2 frames, c'est-a-dire presque "
     "aucun. Constate sur le vecteur de reference : alt2 a -2,5e29, logit a "
     "3,7e29. Corrige en filtrant le score BRUT. Gain de detection : AUCUN "
     "(46 % -> 43 %) -- le correctif etait juste, pas payant."),
    ("mort_tiers_temporels_tete3",
     "[MORT] Resume de l'etat d'encodeur par TIERS temporels — -9,4 points",
     "Bootstrap a configuration fixe, meme jeu de test (2019 mots, 149 fautes, "
     "2000 tirages) : moyenne_std 44,3 %, tiers 34,9 %, victoires de tiers 3 %. "
     "PIEGE ASSOCIE : l'evaluation interne du script (UNE configuration) "
     "annoncait +11 points ; le balayage complet l'a ramene a +2, le bootstrap "
     "l'a inverse a -9. Comparer deux points arbitraires de la surface "
     "d'hyperparametres ne mesure rien."),
    ("piege_gpu_jamais_utilise_bancs",
     "[PIEGE] Les bancs de la tete 3 tournaient sur PROCESSEUR, GPU a 0 %",
     "`entrainer()` ne placait rien sur CUDA. Chaque balayage tournait "
     "entierement sur CPU pendant des heures, sans que rien ne le signale -- le "
     "calcul est juste, seulement lent. Signale par l'utilisateur, pas trouve "
     "par le banc. Une comparaison passee de plusieurs minutes a 45 secondes. "
     "Le modele reste cree sur CPU APRES la graine puis deplace : creer "
     "directement sur CUDA changerait l'initialisation et tout l'historique "
     "mesure cesserait d'etre comparable."),
    ("mesure_shazam_trous_2026_08_05",
     "[MESURE] Shazam sourd aux mots avales — 50 % -> 96 %",
     "L'ecart entre deux mots faisait partie de la CLE d'index : une paire ne "
     "correspondait que si la distance etait identique dans la requete et dans "
     "le texte, or un mot avale la raccourcit forcement. Sur 200 versets, part "
     "des passages retrouves quand l'ASR avale 1 mot sur 5 : 50 % -> 68 % "
     "(ecart hors cle) -> 96 % (+ fenetre de vote de 4). Les SUBSTITUTIONS ne "
     "genaient deja pas (96 %) : une paire dont un mot est faux ne vote pas."),
    ("symptome_recul_ancre_sans_retour",
     "[SYMPTOME] Recul d'ancre injustifie — 40 mots juges sur 295, en affichant "
     "0 % d'erreur",
     "Session v21 : `RECUL vers le mot 34 (dernier definitif = 38) — le "
     "recitateur repete` a la 47e seconde. L'audio a continue d'avancer, la "
     "bande est restee coincee, 16 decrochages, `bande=inconnue`. 254 mots ont "
     "quitte le denominateur au lieu de compter comme echec. "
     "CONTRE-EXEMPLE MESURE : 147 reculs dans la session v22 qui, elle, atteint "
     "l'ancre 294 avec 3,1 % de non verts. Le recul n'est donc PAS dangereux en "
     "soi -- c'est de ne jamais en revenir qui l'est, `findResyncOffset` ne "
     "cherchant qu'en AVANT."),
    ("correctif_recul_exclusif",
     "[EN ATTENTE] Recul d'ancre EXCLUSIF au lieu de MEILLEUR — 44 tests JVM, "
     "recette non faite",
     "Critere donne par l'utilisateur : « quand le recitateur repete, il redit "
     "un mot deja valide QUI N'EXISTE PAS DEVANT ». La LCS balayait toute la "
     "region et retenait la meilleure correspondance ou qu'elle soit ; le texte "
     "coranique se repetant sans cesse (`كما ءامن` deux fois au verset 2:13), "
     "une correspondance en arriere n'a jamais prouve une repetition. On "
     "re-apparie desormais sur la seule region EN AVANT et on ne recule que si "
     "l'avant n'offre aucune lecture acceptable. A MESURER : nombre de RECUL "
     "(147 en v22, doit chuter) et ancre finale (294, ne doit pas baisser)."),
    ("mesure_cloisonnement_ancre_identification",
     "[MESURE] Identifier n'est pas replacer une ancre — deux profils separes",
     "Une erreur d'IDENTIFICATION se voit (mauvais verset affiche) et se "
     "rattrape (on relance l'ecoute) ; une erreur d'ANCRE ne se voit pas et ne "
     "se rattrape pas. Rendre la recherche plus permissive aide la premiere et "
     "met la seconde en danger : elle trouve plus souvent, donc se trompe plus "
     "souvent. `ProfilRecherche.ancreRecitation` est fige sur le comportement "
     "d'avant le 2026-08-05. Recette v22 : ancre 294, 0 verdict sans preuve, "
     "3,1 % de non verts."),
    ("symptome_sentinelle_aligneur_force",
     "[SYMPTOME] Sentinelle 5e29 dans margeLettres/margeHarakat — 10 % et 6 % "
     "des mots",
     "Meme defaut que celui corrige dans la tete 3, mais BRANCHE SUR LE "
     "VERDICT : une marge infinie signifie « le canonique ecrase sa "
     "confusion », donc la regle C ne peut JAMAIS signaler ces mots. Ce n'est "
     "pas un mot mal juge, c'est un mot structurellement invisible. "
     "Non corrige."),
    ("symptome_violet_sans_preuve",
     "[SYMPTOME] Violet tajwid declenche quand la tete ne detecte RIEN",
     "`[V2tajwid] mot=135 NON DETECTEE(S) : madda_normal | detectees=` (vide). "
     "« Attendue et non detectee » devient vrai mecaniquement des que la tete "
     "se tait sur un mot. Faux positif PROUVE : sur l'audio brut, dans de "
     "bonnes conditions, le modele lit `حولهۥ` parfaitement, madd compris. Non "
     "reproduit a la passe suivante sur le meme audio -- critere instable."),
    ("piege_journal_ecrit_avant_arbitrage",
     "[PIEGE] La ligne [V2] est ecrite AVANT l'arbitrage tajwid",
     "Un mot affiche VIOLET a l'ecran figure « definitif:vert » dans le "
     "journal. Tout tableau de non-verts tire du log en est donc faux, y "
     "compris ceux produits le jour meme. Le defaut est de DIAGNOSTIC et non "
     "d'affichage, mais il corrompt toute analyse de session."),
    ("piege_taux_flatteur_ancre_courte",
     "[PIEGE] Un taux de non-verts calcule sur une session qui a decroche",
     "Session v21 : « 0 % de non verts » sur 41 mots juges, alors que l'ancre "
     "s'etait arretee a 40 sur 295. Les 254 mots restants avaient quitte le "
     "denominateur au lieu de compter comme echec. Verifier l'ANCRE FINALE "
     "avant de lire un taux : plus la session casse, meilleur le taux parait."),
]

LIENS = [
    ("mort_filtre_sentinelle_divise", "mesure_parite_tete3_2026_08_05",
     "trouve_par", "sans le vecteur de reference, le defaut restait invisible"),
    ("symptome_sentinelle_aligneur_force", "mort_filtre_sentinelle_divise",
     "meme_cause_que", "meme sentinelle, mais branchee sur le verdict"),
    ("correctif_recul_exclusif", "symptome_recul_ancre_sans_retour",
     "repond_a", "rend le recul exclusif au lieu de simplement meilleur"),
    ("mesure_cloisonnement_ancre_identification", "mesure_shazam_trous_2026_08_05",
     "protege_de", "le gain d'identification ne doit pas deplacer l'ancre"),
    ("piege_journal_ecrit_avant_arbitrage", "symptome_violet_sans_preuve",
     "masque", "le violet n'apparait pas dans le journal, seulement a l'ecran"),
    ("piege_taux_flatteur_ancre_courte", "symptome_recul_ancre_sans_retour",
     "masque", "le decrochage produit un taux flatteur au lieu d'une alerte"),
]

COUCHE = {
    "symptome_recul_ancre_sans_retour": "couche_v2_d_localisation",
    "correctif_recul_exclusif": "couche_v2_d_localisation",
    "symptome_sentinelle_aligneur_force": "couche_v2_e_alignement",
}


def sha():
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=RACINE,
                          capture_output=True, text=True).stdout.strip()


def main():
    g = json.loads(GRAPHE.read_text(encoding="utf-8"))
    connus = {n["id"] for n in g["nodes"]}
    ajoutes = aretes = 0

    for nid, label, why in NOEUDS:
        if nid in connus:
            print(f"  = deja present : {nid}")
            continue
        g["nodes"].append({"id": nid, "label": label, "rationale": why,
                           "type": "insight", "community": 0})
        connus.add(nid)
        ajoutes += 1

    def lien(s, t, rel, why):
        nonlocal aretes
        if s not in connus or t not in connus:
            print(f"  ! cible absente, arete ignoree : {s} -> {t}")
            return
        g["links"].append({"source": s, "target": t, "relation_type": rel,
                           "source_location": why, "rationale": why})
        aretes += 1

    for s, t, rel, why in LIENS:
        lien(s, t, rel, why)
    for nid, couche in COUCHE.items():
        lien(nid, couche, "nait_dans", "la couche ou le defaut NAIT")

    shutil.copy2(GRAPHE, SORTIE / "graph_avant_2026_08_05.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")
    print("sauvegarde : graphify-out/graph_avant_2026_08_05.json")


if __name__ == "__main__":
    main()
