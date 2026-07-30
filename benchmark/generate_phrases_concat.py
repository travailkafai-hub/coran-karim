"""PASSE 1 — synthetise les MOTS des phrases, un par un. N'assemble rien.

LE COMPROMIS QUE CETTE APPROCHE CONTOURNE (mesures du 2026-07-30).

XTTS ne rend une faute que s'il n'a pas de contexte pour la corriger :

    mot isole  (corpus existant, controle sur 400 paires)   70 %  (lettres 83 %)
    phrase 2-3 mots                                         29 %
    phrase 3-6 mots                                         10 %
    assemblage de mots synthetises seuls, 4-8 mots          42 %

Or ce qui manque au modele ASR est justement le CONTEXTE : ses 81 380
contre-exemples a fautes font tous 1 mot (`piege_contre_exemples_mots_isoles`),
d'ou les deux regimes disjoints qu'il a appris -- court = fidele, long =
canonique. Demander la phrase entiere a XTTS echange un probleme contre l'autre.

D'ou l'assemblage. Et d'ou le DECOUPAGE EN DEUX PASSES : la passe 2
(`assembler_phrases_fautees.py`) controle le clip du mot faute AVANT de le
coller dans la phrase. Le rendement de la phrase devient celui du mot isole au
lieu de s'effondrer avec la longueur ; c'est la seule raison d'etre du
decoupage, aucune autre.

CE N'EST PAS LE MONTAGE AUDIO DECLARE MORT. Celui-la
(`mort_montage_audio_splice`) remplacait UNE FRAME de 80 ms A L'INTERIEUR d'un
mot, position donnee par un alignement CTC peaky ; le modele continuait de lire
la lettre d'origine. Sa note de deces dit explicitement : « a rouvrir seulement
s'il remplace l'etendue reelle du phoneme, pas la frame de pic ». Ici l'unite
est le MOT ENTIER et son audibilite est verifiee clip par clip.

Usage :
    .venv_tts/bin/python generate_phrases_concat.py --n 200
"""
import argparse
import json
import os
import random
import time
import wave
from pathlib import Path

os.environ.setdefault("COQUI_TOS_AGREED", "1")
BASE_DIR = Path(__file__).parent
os.environ.setdefault("TTS_HOME", str(BASE_DIR / "tts-cache"))
os.environ.setdefault("HF_HOME", str(BASE_DIR / "hf-cache"))

import numpy as np  # noqa: E402
import soundfile as sf  # noqa: E402
import torch  # noqa: E402
from TTS.api import TTS  # noqa: E402

try:  # torch >= 2.6 refuse les configs Coqui picklees
    from TTS.config.shared_configs import BaseDatasetConfig
    from TTS.tts.configs.xtts_config import XttsConfig
    from TTS.tts.models.xtts import XttsArgs, XttsAudioConfig
    torch.serialization.add_safe_globals(
        [XttsConfig, XttsAudioConfig, XttsArgs, BaseDatasetConfig])
except Exception:
    pass

try:  # torchaudio >= 2.9 exige libtorchcodec (FFmpeg absent ici)
    import torchaudio as _ta

    def _charger(chemin, *a, **k):
        x, sr = sf.read(str(chemin), dtype="float32", always_2d=True)
        return torch.from_numpy(np.ascontiguousarray(x.T)), sr

    _ta.load = _charger
except Exception:
    pass

from generate_tts_phrases_fautees import SHORT_HARAKAT, VOIX, phrases_sources  # noqa: E402

OUT_DIR = BASE_DIR / "data" / "tts_phrases_concat"
SR_XTTS = 24000
SR = 16000            # ce qu'attend le modele ; on convertit des la passe 1

# LES VRAIES CONFUSIONS DE RECITATION, avec leur rendement MESURE sur mot isole
# (controle d'audibilite du 2026-07-30, 400 clips du corpus existant). Sur mot
# isole XTTS rend tres bien l'emphase : la consigne « points d'articulation
# differents » ne valait que pour la synthese de PHRASE entiere, ou XTTS
# corrigeait. L'assemblage la rend caduque -- on peut donc viser les confusions
# qu'on cherche reellement a detecter.
CONFUSABLES = [
    ("ط", "ت"),   # 100 %
    ("ه", "ح"),   #  95 %
    ("ك", "ق"),   #  95 %
    ("ق", "ك"),   #  89 %
    ("ح", "ه"),   #  88 %
    ("ت", "ط"),   #  86 %
    ("ذ", "ز"),   #  86 %
    ("د", "ض"),   #  78 %
    ("س", "ص"),   #  72 %
    ("ض", "د"),   #  71 %
    ("ع", "ء"),   #  71 %
    ("ص", "س"),   #  67 %
    # Famille jim/ha/kha : ABSENTE du corpus d'origine, signalee par
    # l'utilisateur apres son propre test (« mon cas c'etait remplacer jim par
    # ha »). Rendement inconnu -- c'est le controle de la passe 2 qui tranchera.
    ("ج", "ح"), ("ح", "خ"), ("ج", "خ"),
]
# NE PAS SUPPRIMER : ز->ز mesure 0/4 sur mot isole, seule substitution du
# corpus d'origine que XTTS ne rend jamais. Exclue tant que ce n'est pas
# explique.
EXCLUES = {"ز->ذ"}


def ecrire_wav(chemin, x, sr=SR):
    x = np.clip(np.asarray(x, dtype=np.float32), -1.0, 1.0)
    with wave.open(str(chemin), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def reechantillonner(x, src=SR_XTTS, dst=SR):
    if src == dst:
        return x
    n = int(round(len(x) * dst / src))
    return np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x).astype(np.float32)


def fauter_mot(mot, rng):
    """Rend (mot_faute, kind, detail) ou None. Une lettre, ou une harakat."""
    if rng.random() < 0.65:
        paires = CONFUSABLES[:]
        rng.shuffle(paires)
        for src, dst in paires:
            if f"{src}->{dst}" in EXCLUES:
                continue
            j = mot.find(src)
            if j >= 0:
                return mot[:j] + dst + mot[j + 1:], "letter", f"{src}->{dst}"
    pos = [k for k, c in enumerate(mot) if c in SHORT_HARAKAT]
    if pos:
        k = rng.choice(pos)
        dst = rng.choice([h for h in SHORT_HARAKAT if h != mot[k]])
        return mot[:k] + dst + mot[k + 1:], "harakat", f"harakat@{k}:{mot[k]}->{dst}"
    return None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--n", type=int, default=200)
    p.add_argument("--seed", type=int, default=5)
    p.add_argument("--mots-min", type=int, default=4)
    p.add_argument("--mots-max", type=int, default=10)
    p.add_argument("--saute", type=int, default=0, help="phrases sources a ignorer")
    p.add_argument("--debut", type=int, default=0,
                   help="decalage de numerotation, pour completer un lot existant "
                        "sans ecraser ses clips")
    p.add_argument("--sortie", default=str(OUT_DIR))
    args = p.parse_args()

    sortie = Path(args.sortie)
    (sortie / "mots").mkdir(parents=True, exist_ok=True)
    voix = {k: v for k, v in VOIX.items() if v.exists()}
    if not voix:
        raise SystemExit("aucune voix de clonage atteignable")
    noms = list(voix)
    rng = random.Random(args.seed)
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"{len(voix)} voix, XTTS sur {dev}", flush=True)
    tts = TTS("tts_models/multilingual/multi-dataset/xtts_v2").to(dev)

    # Les latents de clonage ne dependent que de la voix : une fois par voix au
    # lieu d'une fois par mot. C'est la partie chere de XTTS.
    latents = {}
    for nom, chemin in voix.items():
        latents[nom] = tts.synthesizer.tts_model.get_conditioning_latents(
            audio_path=[str(chemin)])
    print(f"latents calcules pour {len(latents)} voix", flush=True)

    def dire(texte, nom):
        gpt, spk = latents[nom]
        w = tts.synthesizer.tts_model.inference(
            texte, "ar", gpt, spk, temperature=0.75, enable_text_splitting=False)
        return reechantillonner(np.asarray(w["wav"], dtype=np.float32))

    plan = open(sortie / "plan.jsonl", "a" if args.debut else "w", encoding="utf-8")
    n, vus, t0 = 0, 0, time.time()
    for phrase in phrases_sources(args.mots_min, args.mots_max):
        if n >= args.n:
            break
        vus += 1
        if vus <= args.saute:
            continue
        mots = phrase.split()
        ordre = list(range(len(mots)))
        rng.shuffle(ordre)
        choix = None
        for i in ordre:
            r = fauter_mot(mots[i], rng)
            if r:
                choix = (i, *r)
                break
        if choix is None:
            continue
        i, faute, kind, detail = choix
        v = noms[n % len(noms)]
        try:
            ident = f"p{args.debut + n:06d}"
            for k, m in enumerate(mots):
                ecrire_wav(sortie / "mots" / f"{ident}_m{k:02d}.wav", dire(m, v))
            ecrire_wav(sortie / "mots" / f"{ident}_faute.wav", dire(faute, v))
            plan.write(json.dumps({
                "id": ident,
                "mots": mots,
                "mot_index": i,
                "mot_correct": mots[i],
                "mot_faute": faute,
                "correct_text": phrase,
                "kind": kind,
                "detail": detail,
                "voice": v,
            }, ensure_ascii=False) + "\n")
            plan.flush()
            n += 1
            if n % 20 == 0:
                dt = time.time() - t0
                print(f"  {n}/{args.n}  ({dt/n:.1f} s/phrase, "
                      f"reste ~{(args.n-n)*dt/n/60:.0f} min)", flush=True)
        except Exception as e:
            print(f"  echec '{phrase[:28]}...' : {str(e)[:90]}", flush=True)
    plan.close()
    print(f"\n{n} phrases planifiees -> {sortie}/plan.jsonl")
    print("PASSE 2 : assembler_phrases_fautees.py -- elle CONTROLE le clip du "
          "mot faute avant de l'assembler. Sans elle, rien n'est utilisable.")


if __name__ == "__main__":
    main()
