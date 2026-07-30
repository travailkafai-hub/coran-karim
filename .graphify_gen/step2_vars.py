# -*- coding: utf-8 -*-
"""Etape 2 : les VARIABLES reelles, lues dans le code, avec leur valeur et
leur ligne. Plus le commit qui les a introduites/modifiees (git log -S)."""
import json, re, subprocess
from pathlib import Path

ROOT = Path("/media/kafai/NouveauNom/Coran Karim")
KTDIR = "app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer"
st = json.loads(Path("/tmp/gen/state1.json").read_text(encoding="utf-8"))
nodes, edges, hyper = st["nodes"], st["edges"], st["hyperedges"]
seen = {n["id"] for n in nodes}

def N(i,l,t,s,loc=None,**x):
    if i in seen: return i
    seen.add(i); d={"id":i,"label":l,"file_type":t,"source_file":s,"source_location":loc,
    "source_url":None,"captured_at":None,"author":None,"contributor":None}; d.update(x); nodes.append(d); return i
def E(s,t,r,c,sc,sf,loc=None,w=1.0):
    edges.append({"source":s,"target":t,"relation":r,"confidence":c,"confidence_score":sc,
                  "source_file":sf,"source_location":loc,"weight":w})

# Quelle variable appartient a quelle couche, et ce qu'elle PILOTE.
ROLE = {
 "SAMPLE_RATE":("couche_3_buffer","Frequence d'echantillonnage, 16 kHz. Fige tout le reste."),
 "MAX_SECONDS":("couche_3_buffer","Garde-fou memoire : plafond dur du buffer (180 s)."),
 "MIN_NEW_SECONDS":("couche_3_buffer","CADENCE de re-transcription. Fixe le retard minimal de jugement (~1,5 s)."),
 "SILENCE_RMS_THRESHOLD":("couche_3_buffer","LE PORTIER. Seuil fixe non calibre au bruit ambiant. Sa desactivation a mesure WER 70,2% contre 22,8%."),
 "MAX_SILENCE_SAMPLES":("couche_3_buffer","Silence CONSERVE par pause. Au-dela, l'audio est JETE : le flux brut et le flux de travail n'ont pas la meme echelle de temps."),
 "DEFAULT_COMMIT_SILENCE_MS":("couche_3_buffer","Pause franche qui declenche un gel (450 ms)."),
 "MIN_COMMIT_SECONDS":("couche_3_buffer","Plancher avant gel : pas de gel sur un segment trop court (stats de normalisation peu fiables)."),
 "MAX_SEGMENT_SECONDS":("couche_3_buffer","BORNE DURE de gel (12 s). C'est CE mecanisme qui coupe en plein mot - 47,4% des coupes mesurees."),
 "MAX_TARGET_SECONDS":("couche_3_buffer","Alias de la borne dure pour la cible."),
 "MIN_TRACKED_PAUSE_MS":("couche_3_buffer","Sous ce seuil = micro-respiration, ignoree du profil de pauses."),
 "OVERLAP_SECONDS":("couche_3_buffer","Recouvrement entre segments (3 s) pour ne plus commencer en plein mot."),
 "RIGHT_CONTEXT_SECONDS":("couche_3_buffer","Contexte DROIT donne a l'encodeur (2 s). Le jugement ne porte qu'au centre."),
 "RESYNC_ACTIF":("couche_3_buffer","INTERRUPTEUR du rattrapage d'ancre. Mis a false en v23 : mesure 8,16% -> 6,12%."),
 "CHUNKWISE_ACTIF":("couche_3_buffer","INTERRUPTEUR du decoupage chunkwise. Active sur la branche d'experimentation, NON MESURE."),
 "RATTRAPAGE_GELS_IMMOBILES":("couche_3_buffer","Nombre de gels sans progres avant de forcer un rattrapage."),
 "RATTRAPAGE_SAUT_MAX":("couche_3_buffer","Saut maximal autorise au rattrapage borne."),
 "MIN_RESYNC_TOKENS":("couche_3_buffer","Segment trop court -> on ne tente aucun resync."),
 "MIN_RESYNC_HITS":("couche_3_buffer","3 mots attendus retrouves D'AFFILEE pour accepter un resync."),
 "RESYNC_WINDOW_WORDS":("couche_3_buffer","Fenetre d'appariement du resync."),
 "MAX_RESYNC_LOOKAHEAD":("couche_3_buffer","Ne jamais sauter plus loin que 60 mots."),
 "RESCUE_CONTEXT_SECONDS":("couche_3_buffer","Contexte gauche donne au secours."),
 "RESCUE_TAIL_SECONDS":("couche_3_buffer","Queue donnee au secours."),
 "RESCUE_RING_SECONDS":("couche_3_buffer","Taille de l'anneau de secours (120 s). Teste 30->120 : secours IMPOSSIBLE 6 -> 0, mais decrochage inchange -> REFUTE comme cause."),
 "RESCUE_MAX_SEARCH_SECONDS":("couche_3_buffer","Borne de recherche du secours."),
 "SHIFTED_OFFSET_SECONDS":("couche_3_buffer","Decalage du buffer de secours decale (piste VIVANTE, non ecartee)."),
 "SHIFTED_SEGMENT_SECONDS":("couche_3_buffer","Longueur du segment decale."),
 "OVERLAP_SAMPLES":("couche_3_buffer","OVERLAP_SECONDS converti en echantillons."),
 "STAMP_MARGIN_SECONDS":("couche_3_buffer","Marge autour d'un horodatage de mot sur."),
 "FINE_WINDOW_MS":("couche_3_buffer","Resolution d'analyse fine (20 ms)."),
 "MIN_MICRO_SILENCE_MS":("couche_3_buffer","2 fenetres : un vrai inter-mot, pas une occlusive."),
 "TARGET_SECONDS":("couche_3_buffer","Cible de longueur de segment."),
 "MIN_TARGET_SECONDS":("couche_3_buffer","Plancher de la cible."),
 "CUT_SEARCH_RADIUS_SECONDS":("couche_3_buffer","Rayon de recherche de la coupe (0,8 s). Elargi a 2 s en v13 : la VARIANCE REVIENT, annule le jour meme."),
 "MAX_ALIGN_WORDS":("couche_5_alignement","Borne du cout de la DP (80 mots/passe)."),
 "MIN_FRAMES_FOR_JUDGMENT":("couche_5_alignement","Opportunite minimale pour juger (3 frames ~240 ms)."),
 "RETRY_STALL_MIN_FRAMES":("couche_5_alignement","Frames minimales avant de re-tenter un mot cale."),
 "RESCORE_PAD_FRAMES":("couche_5_alignement","Marge de frames au rescoring."),
 "FREE_MATCH_LOOKAHEAD":("couche_5_alignement","Anticipation d'appariement sur le decodage libre."),
 "N_FFT":("couche_4_asr","Taille de FFT (512)."),
 "WIN_LENGTH":("couche_4_asr","Fenetre d'analyse (400 = 25 ms)."),
 "HOP_LENGTH":("couche_4_asr","Pas d'analyse (160 = 10 ms). Fixe la duree d'une frame."),
 "N_MELS":("couche_4_asr","80 bandes mel."),
 "PREEMPH":("couche_4_asr","Preemphasis 0,97 - DEPEND de l'echantillon precedent (piege du mel incremental)."),
 "FMIN":("couche_4_asr","Frequence min du banc mel."),
 "FMAX":("couche_4_asr","Frequence max du banc mel (8 kHz)."),
 "LOG_ZERO_GUARD":("couche_4_asr","Garde numerique du log."),
 "NORM_EPS":("couche_4_asr","Epsilon de la normalisation per_feature."),
 "WIN_PAD_SAMPLES":("couche_4_asr","Padding de fenetre."),
 "CENTER_PAD":("couche_4_asr","Padding centre."),
 "TAJWID_OUTPUT":("couche_4_asr","Nom de la sortie ONNX de la 2e tete."),
 "TRACE_MAX":("couche_3_buffer","Plafond de la trace fine en memoire (200k) - accumulee pour ne pas fausser la mesure."),
 "SCHEMA_VERSION":("couche_4_asr","Version du contrat du modele causal."),
 "EXPECTED_SOURCE_NEMO":("couche_4_asr","VERROU : n'accepte que causal-final.nemo. Le deploiement causal v1."),
 "EXPECTED_ATTENTION_CONTEXT":("couche_4_asr","Contexte d'attention causal attendu [70,13]."),
 "EXPECTED_INPUT_FRAMES":("couche_4_asr","121 frames d'entree par chunk."),
 "EXPECTED_SHIFT_FRAMES":("couche_4_asr","112 frames de decalage par chunk."),
 "EXPECTED_PRE_ENCODE_CACHE_FRAMES":("couche_4_asr","9 frames de cache pre-encodeur."),
 "EXPECTED_VALID_OUTPUT_FRAMES":("couche_4_asr","14 frames de sortie valides par chunk."),
 "EXPECTED_SUBSAMPLING_FACTOR":("couche_4_asr","Facteur de sous-echantillonnage 8."),
 "EXPECTED_WINDOW_STRIDE_MS":("couche_4_asr","Pas de fenetre 10 ms."),
}
# Seuils Dart (couche 6)
DART = [
 ("_kGopCorrectDefault","-0.45","app/lib/providers/recitation_provider.dart",80,"SEUIL VERT par defaut. gop >= -0,45 => correct."),
 ("_kGopUnclearDefault","-1.6","app/lib/providers/recitation_provider.dart",81,"SEUIL ORANGE par defaut. gop >= -1,60 => douteux, sinon rouge."),
 ("_kGopCorrectTolerant","-0.90","app/lib/providers/recitation_provider.dart",92,"Seuil vert, prereglage tolerant."),
 ("_kGopUnclearTolerant","-2.50","app/lib/providers/recitation_provider.dart",93,"Seuil orange, prereglage tolerant."),
 ("_kGopCorrectStrict","-0.20","app/lib/providers/recitation_provider.dart",94,"Seuil vert, prereglage strict."),
 ("_kGopUnclearStrict","-0.90","app/lib/providers/recitation_provider.dart",95,"Seuil orange, prereglage strict."),
 ("_kSimThreshold","0.6","app/lib/providers/recitation_provider.dart",27,"Similarite texte minimale."),
 ("_kUnclearSimThreshold","0.85","app/lib/providers/recitation_provider.dart",31,"Similarite pour lever un doute."),
 ("_kLookahead","3","app/lib/providers/recitation_provider.dart",32,"Anticipation de mots."),
 ("_kAlignLookahead","6","app/lib/providers/recitation_provider.dart",33,"Tolerance mots sautes/bruit dans le realign complet."),
 ("_kFreeConfidentTolerant","-0.15","app/lib/providers/recitation_provider.dart",214,"free au-dessus => le modele est SUR de ce qu'il entend => trou d'alignement, ne pas juger."),
 ("_kFreeConfidentStrict","-0.02","app/lib/providers/recitation_provider.dart",215,"Variante stricte du meme garde-fou."),
 ("_kPreviewsBeforeCorrection","2","app/lib/providers/recitation_provider.dart",1668,"Nombre d'apercus avant de declencher la correction."),
 ("_kBackToleranceWindow","5","app/lib/providers/recitation_provider.dart",2211,"Fenetre de tolerance en arriere."),
]

# --- lecture REELLE des constantes Kotlin
pat = re.compile(r'^\s*(?:private\s+)?(?:const\s+)?val\s+([A-Z][A-Z0-9_]{2,})\s*[:=]\s*(.+?)(?://.*)?$')
nvar = 0
for kt in sorted((ROOT/KTDIR).glob("*.kt")):
    rel = f"{KTDIR}/{kt.name}"
    for ln, line in enumerate(kt.read_text(encoding="utf-8", errors="ignore").splitlines(), 1):
        m = pat.match(line)
        if not m: continue
        name, val = m.group(1), m.group(2).strip().rstrip(',')
        if name == "TAG": continue
        couche, role = ROLE.get(name, ("couche_3_buffer", "Constante du moteur."))
        vid = f"var_{name.lower()}"
        N(vid, f"{name} = {val}", "code", rel, f"{rel}:{ln}", rationale=role)
        E(vid, couche, "implements", "EXTRACTED", 1.0, rel, f"{rel}:{ln}")
        nvar += 1

for name, val, fich, ln, role in DART:
    vid = f"var_{name.lower().lstrip('_')}"
    N(vid, f"{name} = {val}", "code", fich, f"{fich}:{ln}", rationale=role)
    E(vid, "couche_6_jugement", "implements", "EXTRACTED", 1.0, fich, f"{fich}:{ln}")
    nvar += 1

print(f"[2/6] Variables reelles extraites du code : {nvar}")
print(f"      Total : {len(nodes)} noeuds, {len(edges)} aretes")
Path("/tmp/gen/state2.json").write_text(json.dumps(
    {"nodes":nodes,"edges":edges,"hyperedges":hyper}, ensure_ascii=False), encoding="utf-8")
