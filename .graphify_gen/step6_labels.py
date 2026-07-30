import json, subprocess
from pathlib import Path
ROOT = Path("/media/kafai/NouveauNom/Coran Karim")
a = json.loads((ROOT/"graphify-out/.graphify_analysis.json").read_text(encoding="utf-8"))
comms = a["communities"]

FIXES = {
 "0":"Provider de recitation (jugement Dart)", "1":"ForcedAligner (DP CTC)",
 "2":"Provider de lecture audio", "3":"COUCHE 3 - Buffer et segmentation",
 "4":"Etat de recitation (modele Dart)", "5":"Pistes de coupe EN ATTENTE + commits",
 "6":"COUCHE 5 - Alignement + bascule causale", "7":"Portier RMS, VAD et bancs de mesure",
 "8":"Amorcage de l'application", "9":"COUCHE 4 - Mel + inference ONNX",
 "10":"Export ONNX des checkpoints", "11":"Bancs 2-tetes (dual-head)",
 "12":"Options de jugement (prereglages)", "13":"Etat du lecteur",
 "14":"Revision des erreurs", "15":"Provider des seuils de jugement",
 "16":"COUCHE 6 - Jugement et affichage", "17":"Durees de reference et mots frontiere",
 "18":"Branches de test GOP (revert cibles)", "19":"Resync et branches d'experimentation",
 "20":"BufferedTranscriber (symboles AST)", "21":"Modele de verset",
 "22":"Contexte droit + traces de diagnostic", "23":"Selection du reciteur",
 "24":"MelSpectrogram (symboles AST)", "25":"Piste RNNT hybride 3 tetes",
 "26":"Baseline GOP par mot", "27":"Banc du double decoupage",
 "28":"Banc de la fenetre glissante", "29":"Resync sur apercu (REFUTE)",
 "30":"COUCHES 1-2 - Micro et transport", "31":"FastConformerCtc (symboles AST)",
 "32":"RescueBuffer (symboles AST)", "33":"Banc d'appariement global",
 "34":"StreamingModelConfig (contrat causal)", "35":"Bancs ancre et arbitrage resync",
 "36":"Banc de normalisation fixe", "37":"Deploiement 260h + refonte IHM",
 "38":"CausalAlignmentSession (symboles AST)", "39":"Modele de reciteur",
 "40":"VERROU SUR APERCU et palliatifs retires", "41":"Banc des politiques de coupe",
 "42":"Banc de rescoring par variantes", "43":"Bascule vers le modele causal",
 "44":"SYMPTOMES - ou ils naissent vs ou ils se voient", "45":"Banc de normalisation causale",
 "46":"Utilitaires de banc communs", "47":"Confrontation des erreurs au modele",
 "48":"WavReader / WavWriter", "49":"Plugin d'enregistrement audio",
 "50":"Resume de log de recitation", "51":"Tableau de session",
}
labels = {}
for k, members in comms.items():
    if k in FIXES: labels[int(k)] = FIXES[k]; continue
    ms = [str(m) for m in members]
    def has(*p): return any(any(x in m for x in p) for m in ms)
    if has("mort_"):      labels[int(k)] = "Pistes MORTES (mesurees perdantes)"
    elif has("piege_"):   labels[int(k)] = "PIEGES deja rencontres"
    elif has("regle_"):   labels[int(k)] = "REGLES de methode"
    elif has("attente_"): labels[int(k)] = "Pistes EN ATTENTE"
    elif has("sympt_"):   labels[int(k)] = "Symptomes observes"
    elif has("var_"):     labels[int(k)] = "Variables du moteur"
    elif has("commit_"):  labels[int(k)] = "Grappe de commits lies"
    elif has("benchmark_"): labels[int(k)] = "Banc de mesure"
    elif has("fastconformer"): labels[int(k)] = "Moteur Kotlin (AST)"
    elif has("app_lib_"): labels[int(k)] = "Code Dart (AST)"
    else: labels[int(k)] = f"Groupe {k}"
Path("/tmp/gen/labels.json").write_text(json.dumps(labels, ensure_ascii=False), encoding="utf-8")
print(f"{len(labels)} communautes nommees")
