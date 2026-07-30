# -*- coding: utf-8 -*-
"""Construit la couche semantique du graphe de la chaine de recitation.
Granularite : couche > fichier > fonction > VARIABLE, + commits + versions.
Tout est derive du CODE REEL et du GIT REEL, jamais de memoire."""
import json, re, subprocess
from pathlib import Path

ROOT = Path("/media/kafai/NouveauNom/Coran Karim")
KT = ROOT / "app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer"
SRC_CHAINE = str(ROOT / "CHAINE_RECITATION.md")
SRC_CAPITAL = str(ROOT / "CAPITAL_VERSIONS.md")
SRC_ARCH = str(ROOT / "ARCHITECTURE_RECITATION.md")
SRC_GIT = str(ROOT / "graphify-out/git_history_all_branches.md")

nodes, edges, hyper = [], [], []
seen = set()

def nid(s):
    s = re.sub(r'[^a-z0-9]+', '_', s.lower()).strip('_')
    return re.sub(r'_+', '_', s)

def N(node_id, label, ftype, src, loc=None, **extra):
    if node_id in seen: return node_id
    seen.add(node_id)
    d = {"id": node_id, "label": label, "file_type": ftype, "source_file": src,
         "source_location": loc, "source_url": None, "captured_at": None,
         "author": None, "contributor": None}
    d.update(extra)
    nodes.append(d)
    return node_id

def E(s, t, rel, conf, score, src, loc=None, w=1.0):
    edges.append({"source": s, "target": t, "relation": rel, "confidence": conf,
                  "confidence_score": score, "source_file": src,
                  "source_location": loc, "weight": w})

def H(hid, label, ns, rel, conf, score, src):
    hyper.append({"id": hid, "label": label, "nodes": ns, "relation": rel,
                  "confidence": conf, "confidence_score": score, "source_file": src})

# ---------------------------------------------------------------- 1. COUCHES
COUCHES = [
  ("couche_1_micro", "① Capture micro (Dart)",
   "Ouvre le micro, produit le PCM 16 kHz mono par blocs de 80 ms."),
  ("couche_2_transport", "② Transport Dart→Kotlin",
   "Serialise les envois PCM via MethodChannel, redecoupe en blocs de 80 ms cote Kotlin."),
  ("couche_3_buffer", "③ Buffer et segmentation (Kotlin)",
   "Portier RMS, accumulation, decision de gel/coupe, ancre, secours. La couche ou naissent la plupart des defauts."),
  ("couche_4_asr", "④ Inference ASR (mel + ONNX)",
   "PCM -> mel 80 bandes -> ONNX -> logprobs. Decodage libre (greedy)."),
  ("couche_5_alignement", "⑤ Alignement force et scores",
   "DP CTC : force les tokens attendus, produit forced/free/gop par mot."),
  ("couche_6_jugement", "⑥ Jugement et affichage (Dart)",
   "Applique les seuils, decide la couleur, verrouille ou non."),
]
for cid, lab, why in COUCHES:
    N(cid, lab, "concept", SRC_CHAINE, rationale=why)
for i in range(len(COUCHES)-1):
    E(COUCHES[i][0], COUCHES[i+1][0], "shares_data_with", "EXTRACTED", 1.0, SRC_CHAINE)

H("pipeline_recitation_complet", "Chaine complete micro -> couleur affichee",
  [c[0] for c in COUCHES], "form", "EXTRACTED", 1.0, SRC_CHAINE)

# ------------------------------------------------- 2. FONCTIONS (fichier:ligne)
# Releve dans CHAINE_RECITATION.md, ecrit en LISANT le code.
FONCTIONS = [
 # (couche, id, label, fichier, ligne, role)
 ("couche_1_micro","fn_start","start(expectedWords)","app/lib/services/recitation_verifier.dart",613,"Point d'entree d'une session, serialise pour ne jamais demarrer deux captures"),
 ("couche_1_micro","fn_startlocked","_startLocked()","app/lib/services/recitation_verifier.dart",619,"Demarrage reel sous verrou"),
 ("couche_1_micro","fn_startstreamingcapture","_startStreamingCapture()","app/lib/services/recitation_verifier.dart",681,"Ouvre le micro et abonne le flux PCM"),
 ("couche_1_micro","fn_closestalecapture","_closeStaleContinuousCapture()","app/lib/services/recitation_verifier.dart",826,"Ferme une capture precedente restee ouverte (sinon deux flux se superposent)"),
 ("couche_1_micro","fn_stop","stop()","app/lib/services/recitation_verifier.dart",1082,"Arrete et vide la trace fine (_flushTraces)"),
 ("couche_1_micro","fn_stopifcurrentsession","stopIfCurrentSession(gen)","app/lib/services/recitation_verifier.dart",1118,"N'arrete que si la session est celle attendue - garde anti-course"),
 ("couche_1_micro","fn_cutandrestart","_cutAndRestart()","app/lib/services/recitation_verifier.dart",991,"Coupe et relance la capture (changement de verset, correction)"),

 ("couche_2_transport","fn_pumpfeed","_pumpFeed()","app/lib/services/recitation_verifier.dart",908,"Serialise les envois : garde _feedInFlight, envoie tout le PCM en attente en UN appel"),
 ("couche_2_transport","fn_processcontinuouschunk","_processContinuousChunk(bytes,n)","app/lib/services/recitation_verifier.dart",923,"L'appel effectif, chronometre (feedEntree/feedSortie)"),
 ("couche_2_transport","fn_feedbufferedaudio_dart","feedBufferedAudio(pcm16)","app/lib/services/fastconformer_verifier.dart",539,"Passe le PCM au natif par MethodChannel"),
 ("couche_2_transport","fn_feedbufferedaudio_kt","\"feedBufferedAudio\" (handler)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/FastConformerCtcPlugin.kt",273,"Redecoupe en blocs de 80 ms avant feed() : le portier et la detection de pause decident PAR BLOC"),

 ("couche_3_buffer","fn_feed","feed(newSamples, scope)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt",1646,"LE point d'entree de tout : RMS, portier, accumulation, decision de gel, lancement de l'inference"),
 ("couche_3_buffer","fn_rmsat","rmsAt(buf, from, len)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt",1433,"Energie d'une tranche - sert au portier et a la recherche de coupe"),
 ("couche_3_buffer","fn_reset","reset()","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt",1617,"Remet le buffer a zero"),
 ("couche_3_buffer","fn_findcutoffset","findCutOffset(buf, target, minKeep)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt",1484,"OU couper : cherche un micro-silence pres de la cible"),
 ("couche_3_buffer","fn_targetseconds","targetSeconds()","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt",1614,"La cible courante (aujourd'hui = la borne dure)"),
 ("couche_3_buffer","fn_setcommitsilencems","setCommitSilenceMs(ms)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt",1423,"Seuil de pause franche qui declenche un gel"),
 ("couche_3_buffer","fn_setalignmenttarget","setAlignmentTarget(tokens, anchor)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt",422,"Recoit le texte attendu et REMET A ZERO tous les etats (ancre, differe, horodatages, chunkwise)"),
 ("couche_3_buffer","fn_extendalignmenttarget","extendAlignmentTarget()","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt",467,"Allonge la cible sans tout reinitialiser (verset suivant)"),
 ("couche_3_buffer","fn_setalignmentanchor","setAlignmentAnchor(anchor)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt",454,"Deplacement explicite de l'ancre demande par Dart (correction)"),
 ("couche_3_buffer","fn_setneverblockanchor","setNeverBlockAnchor(v)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt",449,"Mode reference : l'ancre ne cale jamais, avance de +1 sur echec"),
 ("couche_3_buffer","fn_horodater","horodater(words, origin, spf)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt",533,"Note la position absolue des mots SURS - ce registre borne les fenetres de secours"),
 ("couche_3_buffer","fn_fenetrederecherche","fenetreDeRecherche(wordIndex)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt",556,"Ou chercher un mot : borne par ses VOISINS surs, pas par son propre placement qui vient d'echouer"),
 ("couche_3_buffer","fn_cibleavecvoisins","cibleAvecVoisins(zone, idx, toks)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt",617,"La cible du secours = tous les mots que la fenetre couvre. Aligner un mot SEUL produisait 7 faux positifs sur 33"),
 ("couche_3_buffer","fn_cibleetendue","cibleEtendue(idx, toks, n)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt",599,"Variante repartant de N mots valides en amont (EN SOMMEIL)"),
 ("couche_3_buffer","fn_rescueword","rescueWord(idx, tokens, from, to)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt",658,"LE secours : extrait l'audio, rejoue le vrai aligneur, rend un verdict"),
 ("couche_3_buffer","fn_secoursmeilleur","secoursMeilleur(orig, rj)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt",629,"Accepte le verdict de secours SEULEMENT s'il ameliore. Un mot vert ne peut pas devenir rouge"),
 ("couche_3_buffer","fn_findresyncoffset","findResyncOffset(logprobs, tokens, anchor)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt",763,"OU en est vraiment le recitateur. Ne cherche QU'EN AVANT (bestOff > anchor) - un recitateur qui REPETE ne peut pas etre suivi"),
 ("couche_3_buffer","fn_indexofsub","indexOfSub(list, sub, from)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt",858,"Recherche de sous-sequence"),
 ("couche_3_buffer","fn_runalignment","runAlignment(logprobs, isFinal)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt",900,"Orchestre : appelle align, declenche le secours, gere l'ancre, construit le message pour Dart"),
 ("couche_3_buffer","fn_energieparframe","energieParFrame(audio, nFrames)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt",885,"Energie RMS par frame pour la penalite de silence de l'aligneur"),
 ("couche_3_buffer","fn_alignmentpayload","alignmentPayload()","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/BufferedTranscriber.kt",868,"Le dernier resultat, lu par Dart"),
 ("couche_3_buffer","fn_rescue_append","RescueBuffer.append(samples)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/RescueBuffer.kt",51,"Anneau EN LECTURE SEULE. Recoit une copie de tout l'audio, jamais purge par le jugement"),
 ("couche_3_buffer","fn_rescue_extract","RescueBuffer.extract(from, to)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/RescueBuffer.kt",81,"Extrait une fenetre absolue ou null. REFUSE une fenetre tronquee : un secours sur audio partiel reproduirait le defaut qu'il corrige"),

 ("couche_4_asr","fn_mel_compute","MelSpectrogram.compute(pcm)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/MelSpectrogram.kt",187,"PCM -> mel 80 bandes. C'est l'APP qui calcule le mel : l'export ONNX doit exposer audio_signal, jamais raw_audio"),
 ("couche_4_asr","fn_framelogmel","frameLogMel(padded, start)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/MelSpectrogram.kt",154,"Une frame de mel"),
 ("couche_4_asr","fn_fft","fft(input)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/MelSpectrogram.kt",107,"FFT maison (recursive allocante - identifiee comme cout GC inutile)"),
 ("couche_4_asr","fn_buildmelfilterbank","buildMelFilterbank()","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/MelSpectrogram.kt",77,"Banc de filtres mel (slaney)"),
 ("couche_4_asr","fn_computeall","computeAll(pcm)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/FastConformerCtc.kt",125,"L'inference ONNX : mel -> logprobs (+ tete tajwid si presente)"),
 ("couche_4_asr","fn_computelogprobs","computeLogProbs(pcm)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/FastConformerCtc.kt",115,"Idem, lettres seulement"),
 ("couche_4_asr","fn_greedydecode","greedyDecode(logprobs)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/FastConformerCtc.kt",172,"Decodage LIBRE : ce que le modele entend, sans contrainte de cible"),
 ("couche_4_asr","fn_decodetajwid","decodeTajwid(tajwid)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/FastConformerCtc.kt",91,"Regles tajwid detectees (2e tete)"),
 ("couche_4_asr","fn_loadvocab","loadVocab(path)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/FastConformerCtc.kt",72,"Vocabulaire 1024 tokens"),

 ("couche_5_alignement","fn_align","align(logprobs, wordTokens, anchor)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/ForcedAligner.kt",491,"LE coeur : treillis CTC, Viterbi, attribution des frames, bornes et scores par mot"),
 ("couche_5_alignement","fn_striprulesymbolmass","stripRuleSymbolMass(logprobs)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/ForcedAligner.kt",113,"Retire la masse des symboles de regles avant scoring"),
 ("couche_5_alignement","fn_ctcminframes","ctcMinFrames(toks)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/ForcedAligner.kt",466,"Minimum PHYSIQUE de frames (n tokens => >= n frames). Sert a CONDAMNER"),
 ("couche_5_alignement","fn_plausibleminframes","plausibleMinFrames(wi, toks, ref)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/ForcedAligner.kt",478,"Minimum TYPIQUE (reference quran.com). Sert a EXCUSER - ne jamais les interchanger"),
 ("couche_5_alignement","fn_greedydecoderange","greedyDecodeRange(logprobs, from, to)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/ForcedAligner.kt",1338,"Texte reellement entendu SUR LES FRAMES DU MOT -> le champ 'entendu'"),
 ("couche_5_alignement","fn_tokenizeword","tokenizeWord(word)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/ForcedAligner.kt",1383,"Mot -> tokens via le dictionnaire precalcule"),
 ("couche_5_alignement","fn_tokenizewordgreedy","tokenizeWordGreedy(word)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/ForcedAligner.kt",1411,"Repli glouton hors dictionnaire - 33% des mots, d'ou des 'forced' tres negatifs sur des mots bien prononces"),
 ("couche_5_alignement","fn_tokenstotext","tokensToText(t)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/ForcedAligner.kt",1319,"Tokens -> texte (detection des troncatures)"),
 ("couche_5_alignement","fn_coveredwordsfromfree","coveredWordsFromFree(free, tokens)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/ForcedAligner.kt",1263,"Combien de mots attendus le decodage libre confirme, dans l'ordre"),
 ("couche_5_alignement","fn_wordspansfromfree","wordSpansFromFree(free, tokens)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/ForcedAligner.kt",1292,"Leurs plages de frames"),
 ("couche_5_alignement","fn_decodefreespan","decodeFreeSpan(free, span)","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/ForcedAligner.kt",1327,"Texte d'une plage du decodage libre"),
 ("couche_5_alignement","fn_ctcforwardnll","ctcForwardNll()","app/android/app/src/main/kotlin/com/corankarim/coran_karim/fastconformer/ForcedAligner.kt",1187,"Rescoring NLL d'une variante (SECOND treillis - ne pas confondre avec celui d'align)"),

 ("couche_6_jugement","fn_onaligned","_onAligned(payload)","app/lib/providers/recitation_provider.dart",2758,"RECOIT l'alignement et DECIDE la couleur. Applique les seuils, ecrit [GOP], verrouille ou non"),
 ("couche_6_jugement","fn_judge","_judge(words, i, status)","app/lib/providers/recitation_provider.dart",2213,"Pose le verdict d'un mot"),
 ("couche_6_jugement","fn_applyjudgementoptions","applyJudgementOptions(opts)","app/lib/providers/recitation_provider.dart",238,"Seuils du prereglage actif"),
 ("couche_6_jugement","fn_applygopwordbaseline","applyGopWordBaseline(baseline)","app/lib/providers/recitation_provider.dart",304,"Reference GOP par mot, propre a la voix de l'utilisateur"),
 ("couche_6_jugement","fn_applyrulereliability","applyRuleReliability()","app/lib/providers/recitation_provider.dart",292,"Fiabilite par regle tajwid"),
 ("couche_6_jugement","fn_classifyerror","classifyError(wordIndex)","app/lib/providers/recitation_provider.dart",469,"Nature de l'erreur pour la revision"),
 ("couche_6_jugement","fn_applydiagnosticcapture","_applyDiagnosticCapture()","app/lib/providers/recitation_provider.dart",2006,"Capture des WAV de diagnostic"),
]
for couche, fid, lab, fich, ligne, role in FONCTIONS:
    N(fid, lab, "code", SRC_CHAINE, f"{fich}:{ligne}", rationale=role)
    E(fid, couche, "implements", "EXTRACTED", 1.0, SRC_CHAINE, f"{fich}:{ligne}")

print(f"[1/6] Couches + fonctions : {len(nodes)} noeuds, {len(edges)} aretes")
Path("/tmp/gen/state1.json").write_text(json.dumps(
    {"nodes":nodes,"edges":edges,"hyperedges":hyper}, ensure_ascii=False), encoding="utf-8")
