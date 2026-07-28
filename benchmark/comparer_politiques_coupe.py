#!/usr/bin/env python3
"""Compare HORS DEVICE deux politiques de coupe de segment, sur du vrai audio.

    ENERGIE : la coupe cherche un micro-silence (RMS < seuil) -- politique
              ACTUELLE de BufferedTranscriber.
    BLANCS  : la coupe cherche une suite de frames ou le CTC emet le BLANC --
              c'est-a-dire la ou le MODELE ne dit rien.

POURQUOI. Mesure du 2026-07-28 : 47,4 % des coupes tombent en plein mot, et
19 des 22 mots non verts ont ZERO frame -- ce sont les victimes de ces coupes.
La coupe est decidee sur l'ENERGIE, or les occlusives arabes (ب ذ ن) ont une
phase peu energique AU MILIEU d'un mot : l'energie ne porte pas la frontiere.
L'information existe pourtant deja dans la chaine, sous la forme des logprobs.

Le projet impose de regler une politique de segmentation sur des chiffres AVANT
de toucher au Kotlin (CLAUDE.md). C'est ce que fait ce script.

CRITERE. Pour chaque coupe : on decode une fenetre centree dessus, puis les deux
moities. Un mot present dans la fenetre entiere mais absent des deux moities a
ete casse par la coupe.
"""
import glob, json, os, re, sys, wave
os.environ["USE_TF"] = "0"
import numpy as np, onnxruntime as ort
sys.path.insert(0, os.path.dirname(__file__))
from mel_numpy_reference import compute_mel_features

SR = 16000; M = os.path.expanduser("~/.cache/coran-karim")
SEUIL_RMS = 0.02          # BufferedTranscriber.SILENCE_RMS_THRESHOLD
BLOC = 1280               # 80 ms
CIBLE = 12.0              # MAX_SEGMENT_SECONDS
DIAC = re.compile(r"[ً-ْٰٖ-ٟۖ-ۭـ]")

def nz(x):
    x = DIAC.sub("", x)
    for a, b in (("أإآٱ","ا"),("ىي","ي"),("ؤو","و"),("ئء","ي"),("ة","ه")):
        for c in a: x = x.replace(c, b)
    return x

s = ort.InferenceSession(f"{M}/dev_model.onnx", providers=["CPUExecutionProvider"])
v = json.load(open(f"{M}/dev_vocab.json", encoding="utf-8"))
VOC = [k for k,_ in sorted(v.items(), key=lambda kv: kv[1])] if isinstance(v, dict) else v
BL = len(VOC)

def logprobs(a):
    mel = compute_mel_features(a).astype(np.float32)[None]
    return s.run(None, {"audio_signal": mel,
                        "length": np.array([mel.shape[2]], dtype=np.int64)})[0][0]

def dec_lp(lp):
    ids = lp.argmax(-1); o=[]; p=-1
    for i in ids:
        if i != p and i != BL: o.append(VOC[i])
        p = i
    return "".join(o).replace("▁"," ").strip()

def dec(a):
    return dec_lp(logprobs(a)) if len(a) >= SR//3 else ""

def coupes_energie(a):
    """Cherche le micro-silence le plus proche de la cible, comme le fait le
    moteur : fenetres de 80 ms sous le seuil RMS."""
    out, base = [], 0
    while base + int(CIBLE*SR) < len(a):
        cible = base + int(CIBLE*SR)
        best, bd = cible, 10**9
        for i in range(max(base, cible-int(3*SR)), min(len(a)-BLOC, cible+int(3*SR)), BLOC):
            if float(np.sqrt((a[i:i+BLOC]**2).mean())) < SEUIL_RMS:
                if abs(i-cible) < bd: bd, best = abs(i-cible), i
        out.append(best); base = best
    return out

def coupes_blancs(a, lp, spf):
    """Cherche la plus longue suite de BLANCS du CTC pres de la cible : la ou le
    MODELE ne dit rien, pas la ou le signal est faible."""
    ids = lp.argmax(-1)
    out, base = [], 0
    while base + int(CIBLE*SR) < len(a):
        cible = base + int(CIBLE*SR)
        f0 = max(base//spf, (cible-int(3*SR))//spf); f1 = min(len(ids)-1, (cible+int(3*SR))//spf)
        best, bl = None, 0
        i = f0
        while i <= f1:
            if ids[i] == BL:
                j = i
                while j <= f1 and ids[j] == BL: j += 1
                if j-i > bl: bl, best = j-i, (i+j)//2
                i = j
            else: i += 1
        pos = best*spf if best else cible
        out.append(max(pos, base+SR)); base = out[-1]
    return out

def casse(a, bornes):
    n = c = 0
    for b in bornes:
        if b < 2*SR or b + 2*SR > len(a): continue
        ent = nz(dec(a[b-2*SR:b+2*SR])).split()
        g = nz(dec(a[b-2*SR:b])).split(); d = nz(dec(a[b:b+2*SR])).split()
        n += 1
        if [w for w in ent if len(w) >= 3 and w not in g and w not in d]: c += 1
    return c, n

tc_e = tn_e = tc_b = tn_b = 0
for f in sys.argv[1:]:
    with wave.open(f, "rb") as w:
        a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32)/32768.
    lp = logprobs(a); spf = max(1, len(a)//len(lp))
    ce, ne = casse(a, coupes_energie(a))
    cb, nb = casse(a, coupes_blancs(a, lp, spf))
    tc_e += ce; tn_e += ne; tc_b += cb; tn_b += nb
    print(f"{os.path.basename(f)[:28]:<30} ENERGIE {ce}/{ne}   BLANCS {cb}/{nb}")
if tn_e and tn_b:
    print(f"\nENERGIE (actuel) : {tc_e}/{tn_e} coupes en plein mot = {tc_e/tn_e*100:.1f} %")
    print(f"BLANCS  (propose): {tc_b}/{tn_b} coupes en plein mot = {tc_b/tn_b*100:.1f} %")
