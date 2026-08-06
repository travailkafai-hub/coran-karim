#!/usr/bin/env python3
"""Balaye le FLUX BRUT d'une session et decode ce que le MODELE recoit.

    PYTHONPATH="benchmark/.venv_nemo/lib/python3.14/site-packages" \
      /usr/bin/python3.14 benchmark/balayer_flux_brut.py <stream_*.wav> <t0> <t1>

POURQUOI CET OUTIL EXISTE (demande utilisateur 2026-08-06 : « ca m'interesse,
avec les temps 3-6, 6-9... ce que le modele recoit, ca m'aide a analyser »).

Le journal dit ce que la chaine a CONCLU ; ce balayage dit ce que le modele
RECOIT, seconde par seconde, hors de toute politique de fenetrage. C'est le
seul instrument qui separe :
  - un defaut de la CHAINE  (mot net dans le brut, absent des `attestes`)
  - une limite du MODELE    (lectures instables du meme son)
  - un vrai arret du RECITATEUR (rien d'exploitable sur la plage)
  - une REPETITION          (meme passage a deux instants eloignes)

DEUX LARGEURS AU MINIMUM, jamais une seule : mesure du 2026-07-28, `عظيم` est
parfait a 3 s et introuvable a 12 s -- une largeur unique fait conclure
« absent » sur un mot present.

Cas reel qu'il a tranche (2026-08-06) : « il se mele avec cette sourate ». Le
balayage a montre Al-Kafirun recitee entierement et correctement (0-30 s) puis
REPETEE (36-48 s), alors que la cible chargee etait bien Al-Kafirun -- donc
aucun melange de sourate, mais une repetition d'un passage qui figure deux fois.
Sans lui, l'hypothese « mauvaise sourate » aurait ete retenue a tort.
"""
import os,sys,wave,json
os.environ["USE_TF"]="0"
sys.path.insert(0,"/media/kafai/NouveauNom/Coran Karim/benchmark")
import numpy as np, onnxruntime as ort
from mel_numpy_reference import compute_mel_features
SR=16000; M=os.path.expanduser("~/.cache/coran-karim")
s=ort.InferenceSession(f"{M}/dev_model.onnx",providers=["CPUExecutionProvider"])
v=json.load(open(f"{M}/dev_vocab.json",encoding="utf-8"))
vocab=[k for k,_ in sorted(v.items(),key=lambda kv:kv[1])] if isinstance(v,dict) else v
blank=len(vocab)
def dec(a):
    if len(a)<SR//2: return ""
    mel=compute_mel_features(a).astype(np.float32)[None]
    lp=s.run(None,{"audio_signal":mel,"length":np.array([mel.shape[2]],dtype=np.int64)})[0][0]
    out,prev=[],-1
    for i in lp.argmax(-1):
        if i!=prev and i!=blank: out.append(vocab[i])
        prev=i
    return "".join(out).replace("|"," ").strip()
w=wave.open(sys.argv[1]); a=np.frombuffer(w.readframes(w.getnframes()),dtype=np.int16).astype(np.float32)/32768.0
t0,t1=float(sys.argv[2]),float(sys.argv[3])
for L in (4,6):
    print(f"--- largeur {L}s ---")
    t=t0
    while t+L<=t1:
        txt=dec(a[int(t*SR):int((t+L)*SR)])
        if txt: print(f"  [{t:6.1f}-{t+L:6.1f}] {txt}")
        t+=L/2
