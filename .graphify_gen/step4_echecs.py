# -*- coding: utf-8 -*-
"""Etape 4 : LE COEUR DU GARDE-FOU.
Toutes les pistes MORTES avec la mesure qui les tue, tous les pieges, et les
effets ballon (corriger X fait revenir Y). Sources : CAPITAL_VERSIONS.md,
ARCHITECTURE_RECITATION.md, CLAUDE.md, messages de commit."""
import json
from pathlib import Path
ROOT = Path("/media/kafai/NouveauNom/Coran Karim")
SC = str(ROOT/"CAPITAL_VERSIONS.md"); SA = str(ROOT/"ARCHITECTURE_RECITATION.md")
SK = str(ROOT/"CLAUDE.md"); SR = str(ROOT/"REVUE_ARCHITECTURE_KARAOKE.md")
st = json.loads(Path("/tmp/gen/state3.json").read_text(encoding="utf-8"))
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

# ============ PISTES MORTES : mesurees perdantes. NE PAS REINTRODUIRE. ============
MORTES = [
 ("mort_rayon_coupe_2s","Rayon de coupe elargi a 2 s","36c03d0",
  "La VARIANCE REVIENT : 4,2/9,9/3,7 contre 7,0/4,2/4,0. Annule le jour meme.", ["var_cut_search_radius_seconds"], SC),
 ("mort_resync_sur_apercu","Resync arbitre par score, sur APERCU","305db63",
  "8,16 % -> 13,40 %. A saute les mots 46 a 54 que v21 jugeait VERTS. Annule par 69de15a.", ["var_resync_actif","fn_findresyncoffset"], SC),
 ("mort_relachement_proportion","Relachement de la regle de proportion","a54cfe2",
  "PALLIATIF : un recitateur ne disant que la moitie d'un mot etait VALIDE. Retire le jour meme (8507b0e).", ["fn_onaligned"], SC),
 ("mort_sonde_4_lettres","Sonde de 4 lettres","v19 non commite",
  "9,18 % -> 17,89 %.", ["fn_rescueword"], SC),
 ("mort_conserve_zero","Garde de frontiere conserve=0","non commite",
  "r = 0,67 sur 45 sessions, separation sans chevauchement - MAIS l'intervention l'a REFUTEE : conserve=0 ramene de 89 % a 11 %, decrochage inchange. CORRELATION N'EST PAS CAUSALITE.", ["couche_3_buffer"], SC),
 ("mort_portier_rms_desactive","Desactiver le portier RMS","2026-07-23",
  "WER 70,2 % contre 22,8 %. Le portier n'est pas a enlever, il est a rendre adaptatif.", ["var_silence_rms_threshold"], SA),
 ("mort_coupe_chaque_pause","Couper a chaque pause","2026-07-23","WER 103,5 %.", ["var_default_commit_silence_ms"], SA),
 ("mort_fenetre_glissante_naive","Fenetre glissante naive","2026-07-23",
  "WER > 100 % par DUPLICATION DE TEXTE.", ["couche_3_buffer"], SA),
 ("mort_stats_normalisation_fixes","Stats de normalisation FIXES","2026-07-23",
  "Ne corrige rien ET +1,28 pt de WER sur le checkpoint actuel. A ne retenter QU'AVEC un checkpoint reentraine avec ces stats.", ["var_norm_eps","couche_4_asr"], SA),
 ("mort_validation_groupee_gop","Validation groupee par GOP","028be10",
  "Mesuree SANS AUCUN GAIN. Retiree.", ["fn_onaligned"], SC),
 ("mort_cache_aware","Streaming cache-aware","33378dd",
  "Abandonne au profit du repli bufferise, en gardant le modele causal.", ["couche_4_asr"], SC),
 ("mort_anneau_120s_cause","Anneau de secours 30 s -> 120 s comme CAUSE du decrochage","non commite",
  "secours IMPOSSIBLE 6 -> 0, mais decrochage INCHANGE (41,83 %/49,34 %) -> REFUTE comme cause. Le reglage est garde, l'hypothese est morte.", ["var_rescue_ring_seconds"], SC),
 ("mort_harakat_rescoring","Rescoring de variantes pour les HARAKAT","variant_rescoring_eval.py",
  "49,6 % sur 954 clips = QUASI PILE OU FACE, marge mediane -0,10. Verifie non-artefact de tokenisation (0 % de collision BPE). NE JAMAIS verrouiller un verdict harakat la-dessus.", ["couche_5_alignement"], SR),
 ("mort_entrainement_on_device","Entrainement 100% on-device (ONNX Runtime Training)","6861b0b",
  "Echec documente, revert.", ["couche_4_asr"], SC),
]
for mid, lab, com, mesure, cibles, src in MORTES:
    N(mid, f"[MORT] {lab}", "rationale", src, rationale=f"MESURE QUI LA TUE : {mesure}  (commit {com})")
    for c in cibles: E(mid, c, "conceptually_related_to", "EXTRACTED", 1.0, src)
    if f"commit_{com}" in seen: E(f"commit_{com}", mid, "implements", "EXTRACTED", 1.0, src)
H("hyper_pistes_mortes","Pistes MORTES - mesurees perdantes, ne pas reintroduire",
  [m[0] for m in MORTES], "form", "EXTRACTED", 1.0, SC)

# ============ EN ATTENTE : non mesure ou non gagnant, RECUPERABLE ============
ATTENTE = [
 ("attente_contexte_droit_dp","Contexte droit AUSSI a la DP","6ae0884",
  "NON MESURE sur device (poste des telephones injoignable). Seule piece jamais evaluee sur device.", ["var_right_context_seconds"]),
 ("attente_borne_droite_coupe","Borne droite de coupe (targetOffset + radius)","f2d61bc",
  "Rend la coupe independante de l'ordonnancement. NE BAISSE PAS le taux (7,0/4,2/4,0 contre 2,8/3,9/5,3). A rouvrir si la REPRODUCTIBILITE devient le probleme.", ["fn_findcutoffset"]),
 ("attente_cible_etendue","Secours etendu aux mots amont (cibleEtendue)","6d07754",
  "Declenche 1 fois sur 15 mots non verts. Maryam 15,46 % contre 14,58 % - aucun gain demontrable. A rouvrir si le secours devient le goulot.", ["fn_cibleetendue"]),
 ("attente_coupe_fin_de_mot","Couper a une FIN DE MOT connue","6d07754",
  "47,4 % des coupes tombaient en plein mot. Blancs CTC 45,5 % -> 27,3 % en simulation. LA PISTE LA PLUS ETAYEE DU LOT.", ["fn_findcutoffset","var_max_segment_seconds"]),
 ("attente_max_silence_09","MAX_SILENCE_SAMPLES 0,3 s -> 0,9 s","6d07754",
  "Endroits ou couper 12 -> 11 ; silence total 8,9 s -> 3,6 s (-60 %).", ["var_max_silence_samples"]),
 ("attente_resync_texte","Resync comparant du TEXTE (et non des ids de tokens)","4606d64",
  "Maryam 15,46 % -> 9,18 %, rouges 10 -> 6. SANS OBJET tant que RESYNC_ACTIF = false.", ["var_resync_actif","fn_findresyncoffset"]),
 ("attente_buffer_decale","Buffer de secours DECALE","4a91ff3",
  "Documente comme piste VIVANTE, pas ecartee.", ["var_shifted_offset_seconds"]),
 ("attente_rescoring_letter","Rescoring de variantes pour les LETTRES","variant_rescoring_eval.py",
  "80,8 % sur 854 clips, marge mediane +3,80. GO NET, restreint aux CONFUSABLE_PAIRS.", ["couche_5_alignement"]),
 ("attente_vad_silero","VAD reel (Silero, ~1 Mo)","P1.4",
  "Le RMS fixe depend du micro/environnement. Jamais implemente.", ["var_silence_rms_threshold"]),
 ("attente_mel_incremental","Mel incremental + FFT iterative","P0.2",
  "Les colonnes log-mel NE DEPENDENT PAS du reste du buffer - seule l'etape 5 (normalisation) est globale. Cachable des aujourd'hui.", ["fn_mel_compute","fn_fft"]),
]
for aid, lab, com, note, cibles in ATTENTE:
    N(aid, f"[EN ATTENTE] {lab}", "rationale", SC, rationale=f"{note}  (commit/ref {com})")
    for c in cibles: E(aid, c, "conceptually_related_to", "EXTRACTED", 1.0, SC)
    if f"commit_{com}" in seen: E(f"commit_{com}", aid, "implements", "EXTRACTED", 1.0, SC)
H("hyper_en_attente","Pistes EN ATTENTE - recuperables par git show",
  [a[0] for a in ATTENTE], "form", "EXTRACTED", 1.0, SC)

# ============ PIEGES : tombes plusieurs fois ============
PIEGES = [
 ("piege_audio_signal","ONNX doit exposer audio_signal (mel), JAMAIS raw_audio",
  "TOMBE DEUX FOIS (2026-07-13 puis 2026-07-19). Un export E2E valide PyTorch==ONNX mais est INUTILISABLE : le modele se charge (rassurant et trompeur) et CHAQUE transcription echoue en silence. 'Le modele est charge' NE PROUVE RIEN.", ["couche_4_asr","fn_computeall"]),
 ("piege_val_wer_ctc","Lire val_wer_ctc uniquement, jamais val_wer",
  "La tete RNNT est historiquement gelee : val_wer = BRUIT.", ["couche_4_asr"]),
 ("piege_deux_echelles_temps","Le flux brut et le flux de travail n'ont PAS la meme echelle de temps",
  "Le portier RMS JETTE l'audio au-dela de MAX_SILENCE_SAMPLES. Confondre les deux a deja fausse un banc entier.", ["var_max_silence_samples","var_silence_rms_threshold","fn_feed"]),
 ("piege_gop_vs_free","Un gop effondre avec un free proche de 0 = MAUVAISE POSITION, pas mauvaise prononciation",
  "Confondre les deux fait chercher au mauvais endroit. Erreur commise plusieurs fois.", ["couche_5_alignement","fn_align"]),
 ("piege_ctcmin_vs_plausible","ctcMinFrames CONDAMNE, plausibleMinFrames EXCUSE",
  "Ne jamais les interchanger.", ["fn_ctcminframes","fn_plausibleminframes"]),
 ("piege_35pct_audio_absent","35 % de l'audio n'existait dans AUCUN fichier",
  "Les clips ne prouvent rien tant que le flux BRUT n'est pas ecrit (03f9a42, f7db06a).", ["couche_1_micro"]),
 ("piege_verrou_sur_apercu","La majorite des mots sont verrouilles sur des APERCUS, donc sur un audio INCOMPLET",
  "lock = p.isFinal || (judged == correct && !deferredTajwid). Un mot juge correct sur un simple apercu est fige immediatement.", ["fn_onaligned","couche_6_jugement"]),
 ("piege_resync_avant_seulement","findResyncOffset ne cherche QU'EN AVANT",
  "Un recitateur qui REPETE ne peut STRUCTURELLEMENT pas etre suivi. Le banc rejoue un audio lineaire et ne peut pas produire ce cas.", ["fn_findresyncoffset"]),
 ("piege_normalisation_dicte_archi","La normalisation per_feature a DICTE toute l'architecture aval",
  "Elle interdit la transcription incrementale -> d'ou le 'tout re-transcrire toutes les 1,5 s'. Elle derive sur les longs buffers -> d'ou le gel et la borne 12 s. Le gel est un CONTOURNEMENT, pas une fonctionnalite voulue.", ["couche_4_asr","var_max_segment_seconds","var_min_new_seconds"]),
 ("piege_moitie_logique_compense","La MOITIE de la logique de jugement existe pour compenser la segmentation",
  "MIN_FRAMES_FOR_JUDGMENT, deferredOnceIndex, tolerance aux fragments, tolerance au bleed prefixe, filet decodage-libre. Chaque rustine est justifiee ; leur ACCUMULATION est le signal que la cause est en amont.", ["couche_3_buffer","couche_6_jugement"]),
 ("piege_gop_relatif","gop = forced - free est RELATIF, il manque un signal ABSOLU",
  "Mesure : attendu sirat, entendu sirat-avec-sin, gop = -0,35 => VERT, parce que le modele hesitait sur tout (free = -1,42). 'Pas beaucoup pire que le meilleur chemin' n'est pas 'correct'.", ["couche_5_alignement"]),
 ("piege_9_versions_perdues","NEUF versions mesurees n'ont JAMAIS ete commitees",
  "v5, v5b, v6, v12, v15, v17, v19, v20. v5b-derive est LE MEILLEUR RESULTAT DU PROJET (mediane 0,57 %, une passe a 0,00 %) et son code est IRRECUPERABLE. Preuve qu'un taux sous 1 % est atteignable et qu'aucune version commitee n'y est parvenue.", ["couche_3_buffer"]),
 ("piege_arbitrer_resync_faux","arbitrer_resync.py mesure un gain SANS SON COUT",
  "Il ignore les mots abandonnes par un deplacement d'ancre. Ses predictions ne valent rien tant qu'il n'est pas corrige.", ["fn_findresyncoffset"]),
 ("piege_tokenize_greedy","33 % des mots passent par le repli glouton de CtcTokenizer",
  "D'ou des forced tres negatifs sur des mots BIEN prononces. Chantier distinct : GOP invariant au decoupage BPE.", ["fn_tokenizewordgreedy"]),
 ("piege_waqf","Le modele emet des symboles waqf que splitExpectedWords filtre",
  "26 occurrences sur une seule session. Decalage non deterministe, latent. A corriger cote app, JAMAIS par reentrainement (le vocabulaire les contient deja).", ["couche_5_alignement"]),
]
for pid, lab, note, cibles in PIEGES:
    N(pid, f"[PIEGE] {lab}", "rationale", SK, rationale=note)
    for c in cibles: E(pid, c, "conceptually_related_to", "EXTRACTED", 1.0, SK)
H("hyper_pieges","PIEGES - erreurs deja commises, souvent plusieurs fois",
  [p[0] for p in PIEGES], "form", "EXTRACTED", 1.0, SK)

print(f"[4/6] Pistes mortes : {len(MORTES)} | en attente : {len(ATTENTE)} | pieges : {len(PIEGES)}")
print(f"      Total : {len(nodes)} noeuds, {len(edges)} aretes, {len(hyper)} hyperaretes")
Path("/tmp/gen/state4.json").write_text(json.dumps(
    {"nodes":nodes,"edges":edges,"hyperedges":hyper}, ensure_ascii=False), encoding="utf-8")
