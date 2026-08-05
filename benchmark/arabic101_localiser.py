#!/usr/bin/env python3
"""Localise les passages ARABES dans une video anglophone, avec notre modele.

DEMANDE DE L'UTILISATEUR (2026-08-05) : « pour le dataset des erreurs utilise
cette playlist https://www.youtube.com/@arabic101 ».

CE QUE LA CHAINE EST REELLEMENT. 426 videos, 62,3 h, mais ANGLOPHONES : c'est
un cours d'arabe et de tajwid donne en anglais. La parole arabe n'y est que par
extraits. Prise telle quelle, cette source n'apporte pas d'heures de lecture
arabe -- elle apporterait surtout de l'anglais dans un modele arabe.

CE QU'ELLE APPORTE, ET QUI N'EXISTE NULLE PART AILLEURS. 205 de ces videos
portent explicitement sur des FAUTES (« Most Common Qur'an Mistakes in South
Asia », « Do You Pronounce Shaddah on Raa Wrong? », « Have Teachers been
Teaching this Wrong? »). Le format y est toujours le meme : le presentateur
PRONONCE LA FAUTE, puis la correction. C'est de la mauvaise prononciation
HUMAINE, produite volontairement, sur un texte canonique connu.

C'est precisement ce que le corpus TTS ne sait pas fabriquer : nos fautes sont
synthetiques, et l'utilisateur a dit lui-meme que leur qualite etait pauvre.
Une faute reelle, articulee par un locuteur qui sait exactement quelle erreur il
imite, vaut plus qu'une centaine de fautes generees.

POURQUOI LES SOUS-TITRES NE SERVENT A RIEN ICI. YouTube fournit bien une piste
`.ar`, mais c'est une TRADUCTION automatique de l'anglais, pas une transcription
de l'arabe parle -- on y lit « ra مع shed » (les termes arabes en caracteres
latins). Elle ne dit donc rien de l'endroit ou l'arabe est PRONONCE.

D'OU CE SCRIPT. On passe notre propre modele arabe sur l'audio par fenetres et
on retient celles dont le texte decode contient un BIGRAMME CORANIQUE exact.

⚠️ LE PREMIER CRITERE ECRIT ICI ETAIT FAUX, et son echec merite d'etre garde.
Il retenait les fenetres « confiantes ET contenant des caracteres arabes » : il
annoncait alors 82 % d'arabe sur une video anglophone. Un modele arabe pose sur
de l'anglais ne produit pas du vide -- il TRANSCRIT l'anglais phonetiquement en
caracteres arabes, avec une confiance parfaitement normale (`free = -0,05` sur
du charabia). Ni le script ni la confiance ne discriminent quoi que ce soit.
Mesure avec le bon critere sur la meme video : 4 %, soit 3 fenetres sur 145.

⚠️ CE SCRIPT NE PRODUIT PAS UN JEU DE DONNEES. Il repond a UNE question --
combien de coranique y a-t-il, et ou. Savoir LAQUELLE des deux prononciations
est la faute demande le sens du discours anglais autour ; c'est l'etape
suivante, et elle ne doit pas etre devinee.
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path

os.environ["USE_TF"] = "0"
os.environ["USE_JAX"] = "0"

import numpy as np
import torch

BASE = Path(__file__).parent
sys.path.insert(0, str(BASE))
from assainir_corpus_fautes import lire_wav  # noqa: E402

ARABE = re.compile(r"[ء-ي]")
DIACRITIQUES = re.compile(r"[\u064B-\u0652\u0670\u06D6-\u06ED\u0640]")


def normaliser(t):
    """Squelette consonantique : c'est ce qui rend la comparaison robuste aux
    harakat que le modele place mal sur de l'anglais."""
    t = DIACRITIQUES.sub("", t)
    for a, b in (("\u0622", "\u0627"), ("\u0623", "\u0627"), ("\u0625", "\u0627"),
                 ("\u0671", "\u0627"), ("\u0649", "\u064A"), ("\u0629", "\u0647")):
        t = t.replace(a, b)
    return t


def index_coranique(manifeste, n=2):
    """Tous les n-grammes de mots du Coran, normalises.

    POURQUOI DES BIGRAMMES ET NON DES MOTS. Un mot arabe isole se retrouve par
    hasard dans du charabia ; une SUITE de deux mots coraniques, non. C'est ce
    qui separe un extrait recite d'un decodage d'anglais."""
    idx = set()
    vus = set()
    with open(manifeste, encoding="utf-8") as f:
        for ligne in f:
            t = json.loads(ligne).get("text", "")
            if t in vus:
                continue
            vus.add(t)
            mots = [normaliser(m) for m in t.split()]
            for i in range(len(mots) - n + 1):
                idx.add(" ".join(mots[i:i + n]))
    return idx


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--nemo", required=True)
    p.add_argument("--wav", required=True, nargs="+")
    p.add_argument("--fenetre", type=float, default=4.0)
    p.add_argument("--saut", type=float, default=2.0)
    p.add_argument("--seuil-free", type=float, default=-0.35,
                   help="au-dessus : le modele est sur de ce qu'il entend")
    p.add_argument("--manifeste",
                   default=str(BASE / "nemo_manifests_dual" / "train_manifest.jsonl"),
                   help="source du texte coranique servant d'index")
    p.add_argument("--sortie", default=None)
    a = p.parse_args()

    import nemo.collections.asr as nemo_asr
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    model = nemo_asr.models.EncDecHybridRNNTCTCBPEModel.restore_from(
        a.nemo, map_location=dev)
    model.eval()
    model.preprocessor.featurizer.dither = 0.0
    sp = model.tokenizer.tokenizer
    blank = model.decoder.vocab_size if hasattr(model, "decoder") else None

    # ── POURQUOI UN INDEX CORANIQUE PLUTOT QU'UN TEST « CONTIENT DE L'ARABE »
    #
    # Le premier detecteur ecrit ici testait la presence de caracteres arabes
    # dans le texte decode. Il annoncait 82 % d'arabe sur une video anglophone
    # -- et c'etait FAUX. Un modele arabe pose sur de l'anglais ne produit pas
    # du vide : il TRANSCRIT l'anglais phonetiquement en caracteres arabes
    # (« لِسِكْرَوَايْت فَْرْسْتْ » pour « let's write first »), avec une confiance tout
    # a fait normale. Le script ne discrimine donc rien, et la confiance non
    # plus.
    # Ce qu'on cherche n'est pas « de l'arabe » mais « du CORANIQUE », et ce
    # texte-la, on l'a. Un bigramme coranique exact ne sort pas du hasard.
    idx = index_coranique(a.manifeste)
    print(f"index : {len(idx)} bigrammes coraniques\n")

    tout = []
    for chemin in a.wav:
        pcm = lire_wav(chemin)
        sr = 16000
        n = int(a.fenetre * sr)
        pas = int(a.saut * sr)
        segments = []
        for d in range(0, max(1, len(pcm) - n + 1), pas):
            bloc = pcm[d:d + n]
            with torch.no_grad():
                sig = torch.tensor(bloc, device=dev).unsqueeze(0)
                ln = torch.tensor([len(bloc)], device=dev)
                f, fl = model.preprocessor(input_signal=sig, length=ln)
                enc, _ = model.encoder(audio_signal=f, length=fl)
                lp = torch.log_softmax(model.ctc_decoder(encoder_output=enc),
                                       dim=-1)[0].cpu().numpy()
            free = float(lp.max(axis=1).mean())
            ids = lp.argmax(axis=1)
            bl = lp.shape[1] - 1
            suite, prec = [], -1
            for i in ids:
                if i != prec and i != bl:
                    suite.append(int(i))
                prec = int(i)
            texte = sp.decode(suite) if suite else ""
            mots = [normaliser(m) for m in texte.split()]
            touches = sum(1 for i in range(len(mots) - 1)
                          if " ".join(mots[i:i + 2]) in idx)
            segments.append({"debut": d / sr, "fin": (d + n) / sr,
                             "free": round(free, 4), "texte": texte,
                             "bigrammes": touches,
                             "arabe": touches >= 1})
        # Un segment compte comme CORANIQUE s'il porte au moins un bigramme du
        # Coran. La confiance n'est PAS un critere ici -- mesure : le modele est
        # tout aussi confiant sur de l'anglais transcrit phonetiquement.
        retenus = [s for s in segments if s["arabe"]]
        duree = len(pcm) / sr
        # Union des fenetres retenues -> duree reelle, sans double compte.
        couvert = 0.0
        fin_prec = -1.0
        for s in sorted(retenus, key=lambda x: x["debut"]):
            d0 = max(s["debut"], fin_prec)
            if s["fin"] > d0:
                couvert += s["fin"] - d0
                fin_prec = s["fin"]
        print(f"{Path(chemin).name}  {duree/60:.1f} min  "
              f"coranique {couvert/60:.1f} min ({100*couvert/duree:.0f} %)  "
              f"{len(retenus)}/{len(segments)} fenetres")
        for s in retenus[:12]:
            print(f"    {s['debut']:6.1f}s free={s['free']:+.2f} "
                  f"big={s['bigrammes']}  {s['texte'][:60]}")
        tout.append({"wav": str(chemin), "duree": duree, "arabe_s": couvert,
                     "segments": segments})

    if a.sortie:
        Path(a.sortie).write_text(json.dumps(tout, ensure_ascii=False),
                                  encoding="utf-8")
        print(f"\n-> {a.sortie}")
    total = sum(t["duree"] for t in tout)
    ar = sum(t["arabe_s"] for t in tout)
    print(f"\nTOTAL {total/60:.1f} min dont {ar/60:.1f} min de coranique "
          f"({100*ar/max(1,total):.0f} %)")


if __name__ == "__main__":
    main()
