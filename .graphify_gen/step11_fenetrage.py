#!/usr/bin/env python3
"""Consigne les mesures du 2026-08-06 (FENETRAGE : recouvrement, grilles, k).

Meme principe que step10_decrochage.py : on enrichit, on n'ecrase pas, et
le `rationale` porte LE CHIFFRE ou LA LIGNE DE LOG -- jamais l'intention.

Contexte : une soiree entiere de correctifs sur le decrochage / SAUT REFUSE,
dont la moitie visaient le mauvais maillon. Ce fichier existe pour qu'on ne
repaye pas ces heures -- chaque noeud dit ce qui a ETE MESURE, pas ce qui a ete
espere.

Protocole des mesures : sessions reelles sur device (Samsung R3CY20XW7TD),
builds v49 a v57, sourates 90/93/95, mode NORMALE sauf mention, journal
`recitation_diagnostic.log` + flux brut `stream_*.wav` confronte au modele.
"""
import json
import shutil
import subprocess
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE / "graphify-out"
GRAPHE = SORTIE / "graph.json"

NOEUDS = [
    # ── LA CONFIGURATION RETENUE ────────────────────────────────────────────
    ("mesure_recouvrement_apercus_inutile_avec_deux_lignes",
     "[MESURE] Le recouvrement de 50 % des apercus ne sert plus des qu'il y a "
     "DEUX lignes",
     "REJEU DETERMINISTE du MEME WAV (Al-Baqara v6, 433 s, 295 mots, build "
     "v70) -- seul le pas de la grille change : pas=2/largeur=4 (recouvrement "
     "50 %) -> 274 fenetres, 1826 s presentes, 3/295 = 1,02 % non verts ; "
     "pas=4/largeur=4 (recouvrement 0 %) -> 214 fenetres, 1603 s, 3/295 = "
     "1,02 %, ET LES MEMES TROIS MOTS (172, 228, 285). Ancre 294 des deux "
     "cotes, 0 RESYNC, 0 verdict sans preuve, 0 mot jamais vu. Soit -22 % de "
     "fenetres pour un resultat identique au bit pres. Banc JVM concordant "
     "(pas 2 : 14,24 % / 1158 obs ; pas 3 : 14,92 % ; pas 4 : 13,90 % / 917 "
     "obs). ORIGINE DU RECOUVREMENT (utilisateur, 2026-08-06) : il avait ete "
     "choisi en supposant une ligne UNIQUE, ou un mot coupe au bord n'avait "
     "que la fenetre suivante pour etre revu. La ligne B (blocs fermes aux "
     "vrais silences + fusion) fournit deja cette relecture."),

    ("mort_deux_grilles_periodes_premieres",
     "[MORT] Deux grilles d'apercus de periodes PREMIERES entre elles (3 s et "
     "5 s)",
     "IDEE UTILISATEUR (2026-08-06) : deux grilles de periodes 3 et 5 ne "
     "realignent leurs frontieres que toutes les 15 s, donc un mot coupe par "
     "l'une ne l'est pas par l'autre. Raisonnement JUSTE, gain NUL. Banc JVM, "
     "meme audio, ligne B active des deux cotes : A(4/4) seul -> 265 fenetres, "
     "1277 obs, 14,24 % non verts, 43 mots sans bonne observation ; "
     "A(3/3)+A(5/5) -> 295 fenetres, 1266 obs, 14,24 %, 43. IDENTIQUE, pour "
     "30 fenetres de plus. POURQUOI : l'argument suppose que la seconde ligne "
     "est une GRILLE dont les frontieres pourraient coincider. La ligne B ne "
     "coupe pas sur une horloge, elle coupe aux SILENCES REELS -- instants "
     "sans periodicite, donc jamais synchronisables avec une grille. La "
     "decorrelation cherchee est deja acquise, et plus fortement (ses coupes "
     "tombent la ou le recitateur s'arrete). Code conserve et desactive "
     "(apercu2Secondes = 0) : la mesure a coute une demi-heure."),

    ("mort_deux_grilles_a_remplacent_ligne_b",
     "[MORT] Remplacer la ligne B (blocs aux silences) par deux grilles A",
     "Banc JVM, meme audio : A(3/3)+A(5/5) SANS fusion -> 670 observations, "
     "19,66 % non verts, 85 mots sans une seule observation correctement notee "
     "(contre 43 avec la ligne B). Recette REELLE concordante : une seule "
     "ligne d'apercus, fusion coupee, k=2 -> 3,73 % non verts dont 7 `omis`, "
     "contre 1,02 % et 1 `omis` avec les deux lignes. La ligne B n'est pas un "
     "controle redondant : elle apporte l'audio que la grille ne couvre "
     "jamais bien."),

    ("mort_une_seule_preuve_k1",
     "[MORT] Abaisser k a 1 (figer sur une seule observation)",
     "HYPOTHESE (utilisateur) : « vert = condition1 ET condition2, donc "
     "retirer la 2e condition augmente les verts ». Banc JVM, meme audio : "
     "fusion=on k=2 -> 14,24 % ; k=1 -> 15,59 %. fusion=off k=2 -> 19,32 % ; "
     "k=1 -> 20,00 %. Recette reelle : fusion=off k=1 -> 6,46 % avec 8 `omis`, "
     "contre 3,73 % et 7 `omis` a k=2. POURQUOI L'HYPOTHESE TOMBE : un VERT ne "
     "passe deja PAS par k. La regle `nette` du Decideur fige un vert des la "
     "PREMIERE observation attestee, interieure et de texte non vide -- mesure "
     "sur device : 117 mots sur 286 (41 %) verrouilles avec obs=1. k ne "
     "retient que les NON-verts, qu'il laisse provisoires pour qu'une fenetre "
     "ulterieure puisse encore les rendre verts. L'abaisser ne libere aucun "
     "vert : il gele des rouges de POSITION plus tot. Les 12 mots qui changent "
     "d'etat vont tous de provisoire non-vert a definitif non-vert, aucun ne "
     "devient vert."),

    # ── LES PIEGES DE MESURE DE LA JOURNEE ──────────────────────────────────
    ("piege_maxbloc_partage_avec_le_plafond_de_fusion",
     "[PIEGE] Un seul plafond pour le bloc SEUL et le bloc de FUSION",
     "MESURE (2026-08-06, recette reelle) : en portant `maxBloc` de 30 s a 5 s "
     "pour raccourcir les blocs, le bloc de FUSION -- qui vaut PAR "
     "CONSTRUCTION deux blocs -- depassait toujours ce meme plafond et n'etait "
     "PLUS JAMAIS produit. Resultat : 24,41 % de mots non verts dont 46 "
     "`omis`, et ZERO fenetre de plus de 6 s dans tout le journal. On croyait "
     "mesurer « des blocs plus courts », on mesurait « seconde ligne "
     "supprimee », sans aucune ligne de log pour le dire. Corrige par "
     "`maxFusionSecondes` (plafond separe) : meme configuration -> 2,03 %. "
     "SIGNATURE GENERALE : un reglage qui doit satisfaire deux exigences "
     "opposees se DEDOUBLE, il ne se regle pas mieux."),

    ("piege_drapeau_de_mesure_avale_par_un_garde",
     "[PIEGE] Un drapeau de mesure ignore en silence par `if (!_loaded) return`",
     "MESURE (2026-08-06) : `v2SetFusion` commencait par `if (!_loaded) "
     "return;` et son erreur etait avalee par un `catch (_) {}`. La recette "
     "pose ses drapeaux AVANT d'ouvrir la capture, donc avant le chargement du "
     "modele : l'appel repartait sans rien faire ET sans trace. Deux passes "
     "ont ete mesurees en croyant comparer deux configurations alors qu'elles "
     "etaient IDENTIQUES (5 puis 3 mots non verts = la variance entre deux "
     "passes, lue a tort comme un effet). CONTROLE OBLIGATOIRE : verifier dans "
     "le journal la ligne que le reglage DOIT produire avant d'interpreter la "
     "moindre mesure. Corrige : plus de garde, valeur memorisee et rejouee "
     "apres le chargement, echec JOURNALISE."),

    ("piege_variance_micro_depasse_l_effet_cherche",
     "[PIEGE] Deux passes micro a 7,46 % n'etaient PAS une regression",
     "MESURE (2026-08-06) : apres la mise au defaut du recouvrement 0 %, deux "
     "recettes consecutives haut-parleur -> micro donnent 7,46 % de non verts "
     "(22/295) sur des mots DIFFERENTS, contre 1,02 % la passe precedente. "
     "Compteurs de decrochage et de recul identiques (126/3 contre 127/2), "
     "nombre de fenetres comparable : rien dans le decoupage n'avait bouge. Le "
     "REJEU DETERMINISTE du WAV de la bonne passe avec le code incrimine rend "
     "214 fenetres, 3 non verts, 1,02 %, LES MEMES TROIS MOTS -- le code etait "
     "hors de cause, l'audio du canal acoustique s'etait degrade. REGLE : "
     "quand deux passes micro s'ecartent, ne jamais conclure sans rejouer le "
     "WAV de la passe de reference sur le binaire suspect."),

    ("mesure_verts_figes_sur_une_seule_observation",
     "[MESURE] 41 % des mots sont verrouilles VERT sur UNE seule observation",
     "MESURE (2026-08-06, device, Al-Baqara 295 mots) : 117 mots definitifs "
     "avec obs=1, 56 avec obs=2, 61 avec obs=3, 52 avec obs>=4. Consequence "
     "directe : la double preuve n'est PAS ce qui retient un vert, et un "
     "`Provisoire(VERT)` est deja peint en vert a l'ecran -- le banc le compte "
     "comme vert (`BancFluxBrut`). Toute discussion sur k doit partir de la, "
     "sinon on raisonne sur une conjonction qui n'existe pas."),
]

LIENS = [
    ("mesure_recouvrement_apercus_inutile_avec_deux_lignes",
     "mort_deux_grilles_periodes_premieres", "meme_question"),
    ("mort_deux_grilles_periodes_premieres",
     "mort_deux_grilles_a_remplacent_ligne_b", "meme_zone"),
    ("mort_une_seule_preuve_k1",
     "mesure_verts_figes_sur_une_seule_observation", "explique_par"),
    ("piege_maxbloc_partage_avec_le_plafond_de_fusion",
     "mort_deux_grilles_a_remplacent_ligne_b", "a_masque"),
    ("piege_drapeau_de_mesure_avale_par_un_garde",
     "piege_variance_micro_depasse_l_effet_cherche", "meme_session"),
]


def noeud(nid, label, rationale):
    return {"id": nid, "label": label, "rationale": rationale,
            "node_type": "concept", "community": "recitation"}


def sha() -> str:
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=RACINE,
                          capture_output=True, text=True).stdout.strip()


def main():
    g = json.loads(GRAPHE.read_text(encoding="utf-8"))
    connus = {n["id"] for n in g["nodes"]}
    ajoutes = 0
    for nid, label, rationale in NOEUDS:
        if nid not in connus:
            g["nodes"].append(noeud(nid, label, rationale))
            ajoutes += 1
        else:
            # On ENRICHIT sans ecraser : si le noeud existe deja, on ne touche
            # a rien (regle projet -- aucune piste n'est jamais ecrasee).
            print(f"  = deja present, inchange : {nid}")

    connus = {n["id"] for n in g["nodes"]}
    aretes = 0
    for s, t, rel in LIENS:
        if s not in connus or t not in connus:
            print(f"  ! cible absente, arete ignoree : {s} -> {t}")
            continue
        g["links"].append({
            "source": s, "target": t, "relation_type": rel,
            "source_location": None, "rationale": None,
        })
        aretes += 1

    if GRAPHE.exists():
        shutil.copy2(GRAPHE, SORTIE / "graph_avant_fenetrage.json")
    g["built_at_commit"] = sha()
    GRAPHE.write_text(json.dumps(g, ensure_ascii=False), encoding="utf-8")
    print(f"+{ajoutes} noeuds, +{aretes} aretes -> {len(g['nodes'])} noeuds, "
          f"{len(g['links'])} aretes")
    print("sauvegarde de l'etat precedent : graphify-out/graph_avant_fenetrage.json")


if __name__ == "__main__":
    main()
