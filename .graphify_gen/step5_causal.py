# -*- coding: utf-8 -*-
"""Etape 5 : chaines causales et COUPLAGES INTER-COUCHES.
C'est ce qui manque a un agent : ou NAIT un defaut vs ou il se VOIT, et quel
mecanisme tire sur quel autre (effet ballon)."""
import json
from pathlib import Path
ROOT = Path("/media/kafai/NouveauNom/Coran Karim")
SC = str(ROOT/"CHAINE_RECITATION.md"); SA = str(ROOT/"ARCHITECTURE_RECITATION.md")
SK = str(ROOT/"CLAUDE.md"); SV = str(ROOT/"CAPITAL_VERSIONS.md")
st = json.loads(Path("/tmp/gen/state4.json").read_text(encoding="utf-8"))
nodes, edges, hyper = st["nodes"], st["edges"], st["hyperedges"]
seen = {n["id"] for n in nodes}
def N(i,l,t,s,loc=None,**x):
    if i in seen: return i
    seen.add(i); d={"id":i,"label":l,"file_type":t,"source_file":s,"source_location":loc,
    "source_url":None,"captured_at":None,"author":None,"contributor":None}; d.update(x); nodes.append(d); return i
def E(s,t,r,c,sc,sf,loc=None,w=1.0):
    if s in seen and t in seen:
        edges.append({"source":s,"target":t,"relation":r,"confidence":c,"confidence_score":sc,"source_file":sf,"source_location":loc,"weight":w})
def H(i,l,ns,r,c,sc,s):
    ns=[n for n in ns if n in seen]
    if len(ns)>=3: hyper.append({"id":i,"label":l,"nodes":ns,"relation":r,"confidence":c,"confidence_score":sc,"source_file":s})

# ===== SYMPTOMES : ou ils se VOIENT vs ou ils NAISSENT =====
SYMPTOMES = [
 ("sympt_mot_tronque","Mot tronque (sad-alif pour sadiqin)","couche_6_jugement","couche_3_buffer",
  "Se VOIT a l'affichage. NAIT dans la coupe de segment, ou dans le verrou sur apercu."),
 ("sympt_entendu_vide","entendu vide, gop effondre, free NORMAL","couche_6_jugement","couche_5_alignement",
  "Se VOIT comme un rouge. NAIT dans la POSITION DE L'ANCRE, pas dans la prononciation."),
 ("sympt_mot_jamais_place","Mot jamais place","couche_5_alignement","couche_3_buffer",
  "Se VOIT comme un non-juge. NAIT du fait que son audio n'est PAS DANS LE SEGMENT."),
 ("sympt_bloc_abandonne","Bloc de mots abandonnes","couche_6_jugement","couche_3_buffer",
  "Se VOIT comme un decrochage. NAIT du rattrapage d'ancre (findResyncOffset)."),
 ("sympt_charabia","Texte charabia sur segment long","couche_4_asr","couche_4_asr",
  "NAIT de la derive de normalisation per_feature. Se voit au meme endroit."),
 ("sympt_audio_jamais_consomme","Audio capte mais jamais consomme","couche_3_buffer","couche_3_buffer",
  "NAIT du portier RMS ou de la purge."),
 ("sympt_faux_positifs","12 faux positifs sur 12, MODELE HORS DE CAUSE","couche_6_jugement","couche_3_buffer",
  "Recul architectural 2ced1b1 : verifier chaque mot signale sur l'audio brut. Un mot que le modele lit correctement est un faux positif de la CHAINE."),
 ("sympt_decrochage","Decrochage 124-180 : six hypotheses refutees","couche_6_jugement","couche_3_buffer",
  "Tombe au MEME endroit sur SIX versions. L'anneau n'y est pour rien. Le decrochage n'est pas dans le TEXTE : il est dans un RATTRAPAGE QUI ECHOUE."),
 ("sympt_lag_validation","Retard de validation de 1,5 a 3 s","couche_6_jugement","couche_3_buffer",
  "Un mot n'est juge qu'au plus tot MIN_NEW_SECONDS apres avoir ete prononce, et definitif qu'au GEL. Le retard DEPEND DE LA LONGUEUR DU SEGMENT."),
 ("sympt_coupe_plein_mot","47,4 % des coupes tombent en plein mot","couche_3_buffer","couche_3_buffer",
  "Mesure d629d63, chiffree A LA COUCHE OU ELLE NAIT."),
]
for sid, lab, vu, ne, note in SYMPTOMES:
    N(sid, f"[SYMPTOME] {lab}", "concept", SC, rationale=note)
    E(sid, vu, "references", "EXTRACTED", 1.0, SC, loc="se VOIT ici")
    E(ne, sid, "rationale_for", "EXTRACTED", 1.0, SC, loc="NAIT ici")
H("hyper_symptomes","Symptomes : couche ou ils se voient vs couche ou ils naissent",
  [s[0] for s in SYMPTOMES], "form", "EXTRACTED", 1.0, SC)

# ===== COUPLAGES : tirer sur A deplace B (effet ballon) =====
COUPLAGES = [
 ("var_max_segment_seconds","var_min_new_seconds","Baisser la borne dure augmente le nombre de FRONTIERES, donc le nombre d'occasions de se tromper. Les erreurs de frontiere SE COMPOSENT.",0.95),
 ("var_max_segment_seconds","sympt_coupe_plein_mot","La borne dure est LE mecanisme qui coupe en plein mot.",1.0),
 ("var_max_segment_seconds","sympt_lag_validation","Le retard de validation est borne par la longueur du segment.",0.95),
 ("piege_normalisation_dicte_archi","var_max_segment_seconds","La derive per_feature EST la raison d'etre de la borne 12 s.",0.95),
 ("piege_normalisation_dicte_archi","var_min_new_seconds","La normalisation globale interdit l'incremental -> d'ou le tout-retranscrire.",0.95),
 ("var_silence_rms_threshold","var_max_silence_samples","Le portier decide QUOI est du silence, le plafond decide COMBIEN on en garde. Les deux ensemble determinent l'audio JETE.",1.0),
 ("var_silence_rms_threshold","sympt_mot_tronque","Voix douce/micro eloigne -> debut de mot classe silence et JETE -> mot tronque a l'aligneur.",0.95),
 ("var_silence_rms_threshold","var_default_commit_silence_ms","Piece bruyante -> aucun silence detecte -> le gel sur pause ne tire JAMAIS, seule la borne dure agit.",0.95),
 ("var_resync_actif","sympt_bloc_abandonne","Correlation PARFAITE resync<->decrochage sur 5 sessions. Coupe en v23 : 8,16 % -> 6,12 %.",1.0),
 ("fn_findresyncoffset","piege_resync_avant_seulement","La recherche en avant seulement est structurelle.",1.0),
 ("var_overlap_seconds","var_right_context_seconds","Contexte gauche et contexte droit : deux reglages du MEME probleme de frontiere.",0.85),
 ("fn_onaligned","piege_verrou_sur_apercu","Le verrou sur apercu est decide dans _onAligned.",1.0),
 ("piege_verrou_sur_apercu","sympt_mot_tronque","Verrouiller sur apercu fige un verdict pris sur un audio INCOMPLET.",0.95),
 ("couche_3_buffer","couche_6_jugement","COUPLAGE STRUCTUREL : la moitie de la logique de jugement existe pour compenser la segmentation.",0.95),
 ("fn_tokenizewordgreedy","piege_gop_relatif","Le repli glouton produit des forced tres negatifs sur des mots bien prononces -> pollue le gop.",0.85),
 ("var_rescue_ring_seconds","fn_rescue_extract","L'anneau borne ce que le secours peut atteindre : hors anneau = IMPOSSIBLE.",1.0),
 ("fn_cibleavecvoisins","fn_rescueword","Aligner un mot SEUL produisait 7 faux positifs sur 33 : le secours doit voir les voisins.",1.0),
 ("fn_secoursmeilleur","couche_6_jugement","Garde-fou : un mot deja vert ne peut pas devenir rouge par le secours.",1.0),
 ("var_gopcorrectdefault","var_gopunclairdefault","Les deux seuils decoupent le meme axe : deplacer l'un deplace la classe de l'autre.",0.95),
 ("var_freeconfidenttolerant","piege_gop_vs_free","free confiant = trou d'alignement, ne pas juger. C'est la reconnaissance explicite du piege.",1.0),
]
nc = 0
for a, b, note, sc in COUPLAGES:
    # tolerance sur les noms de seuils Dart
    for cand in (b, b.replace("gopunclair","gopunclear")):
        if a in seen and cand in seen:
            E(a, cand, "shares_data_with", "INFERRED" if sc<1.0 else "EXTRACTED", sc, SA, loc=note); nc+=1
            break

# ===== REGLES DE METHODE (garde-fou de process) =====
REGLES = [
 ("regle_pas_de_palliatif","Ne JAMAIS compenser une perte d'information d'une couche basse par une tolerance ajoutee dans une couche haute",
  "Ca degrade la fonction premiere (verifier la recitation) et rend le vrai defaut INVISIBLE dans les logs suivants. Cas concret : requalifier 'correct' tout fragment coherent validait un recitateur ne disant que la MOITIE d'un mot."),
 ("regle_mesure_avant_kotlin","Toucher a BufferedTranscriber sans mesure prealable HORS DEVICE = perte de temps garantie",
  "Decision 2026-07-23 apres une journee entiere : QUATRE correctifs evidents testes, TOUS rejetes par la mesure. Le code en place s'est revele le moins mauvais."),
 ("regle_un_seul_changement","Un seul changement par version avant de mesurer",
  "Empiler deux changements rend le resultat ININTERPRETABLE - c'est ce qui a produit treize versions dont AUCUNE n'est concluante."),
 ("regle_jamais_ecraser","Aucune piste n'est eliminee tant que le retour en arriere est possible",
  "Ne jamais ecraser un checkpoint, ne jamais supprimer un commentaire qui documente une tentative passee. Sans ca, impossible de distinguer 'jamais essaye' de 'essaye et retire sans laisser de trace'."),
 ("regle_identifier_la_couche","Identifier la couche ou le defaut NAIT, pas celle ou il se VOIT",
  "Remonter : jugement -> alignement -> buffer/segmentation -> capture/micro."),
 ("regle_correlation_causalite","Une correlation parfaite ne prouve RIEN",
  "conserve=0 : r=0,67, separation sans chevauchement - et l'INTERVENTION l'a refutee. Toujours intervenir sur la variable avant de conclure."),
 ("regle_preuve_acoustique","Aucun verdict sans preuve acoustique",
  "Confronter chaque mot signale au modele sur l'audio BRUT. Un mot que le modele lit correctement est un faux positif de la CHAINE, pas une faute de recitation."),
]
for rid, lab, note in REGLES:
    N(rid, f"[REGLE] {lab}", "rationale", SK, rationale=note)
E("regle_pas_de_palliatif","mort_relachement_proportion","rationale_for","EXTRACTED",1.0,SK)
E("regle_mesure_avant_kotlin","couche_3_buffer","rationale_for","EXTRACTED",1.0,SK)
E("regle_un_seul_changement","piege_9_versions_perdues","rationale_for","EXTRACTED",1.0,SV)
E("regle_correlation_causalite","mort_conserve_zero","rationale_for","EXTRACTED",1.0,SV)
E("regle_identifier_la_couche","hyper_symptomes","rationale_for","INFERRED",0.85,SC) if "hyper_symptomes" in seen else None
for s,_,_,_,_ in SYMPTOMES: E("regle_identifier_la_couche", s, "rationale_for","EXTRACTED",1.0,SC)
H("hyper_regles","REGLES DE METHODE - garde-fou de process",[r[0] for r in REGLES],"form","EXTRACTED",1.0,SK)

print(f"[5/6] Symptomes : {len(SYMPTOMES)} | couplages inter-couches : {nc} | regles : {len(REGLES)}")
print(f"      Total : {len(nodes)} noeuds, {len(edges)} aretes, {len(hyper)} hyperaretes")
Path("/tmp/gen/state5.json").write_text(json.dumps(
    {"nodes":nodes,"edges":edges,"hyperedges":hyper}, ensure_ascii=False), encoding="utf-8")
