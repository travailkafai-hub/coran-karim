"""Contre-exemples a fautes EN CONTEXTE DE PHRASE (et non plus mots isoles).

POURQUOI CE SCRIPT EXISTE — la mesure du 2026-07-30.

Le modele deploye ENTEND la faute quand il regarde le mot seul, et la CORRIGE
des qu'il a le contexte de la phrase :

    fenetre etroite (2 s)   -> il ecrit le ز reellement prononce
    fenetre large  (7,5 s)  -> il ecrit la forme CANONIQUE

Verifie sur 12 modeles sur 12 : en fenetre large, TOUS ecrivent le canonique.
Cause racine trouvee dans le manifeste `nemo_manifests_dual` :

    contre-exemples a fautes   81 380   duree med 1,71 s   1 MOT (maximum 1)
    Coran recite sans faute    75 512   duree med 10,40 s  9 mots (max 98)

TOUS les contre-exemples sont des mots ISOLES. Le modele n'a donc jamais vu une
PHRASE contenant une faute : il a appris deux regimes disjoints, court = fidele,
long = corrige. Ce qui manque n'est pas la faute, c'est son CONTEXTE.

POURQUOI PAS LE MONTAGE AUDIO. `build_confusable_splice_augmentation.py` fait
exactement ca en vraie voix -- mais mesure le 2026-07-30, il remplace UNE SEULE
FRAME (80 ms), parce que l'alignement CTC est peaky : il marque la frame de pic,
pas l'etendue acoustique du phoneme. Sur le fichier monte (س -> ص), le modele lit
la lettre D'ORIGINE. L'outil etiquetterait donc ص un son qui reste س -- entrainer
la-dessus apprendrait l'INVERSE de ce qu'on veut. [MORT] mort_montage_audio_splice.

Reste XTTS-v2 avec CLONAGE VOCAL sur de vrais recitateurs -- l'outil qui a
produit les 18 195 fautes existantes (`generate_tts_augmentation.py`), applique
a des versets entiers au lieu de mots.

ETIQUETTE = le texte REELLEMENT demande au TTS (avec la substitution), jamais le
canonique. Meme principe que tout le corpus d'erreurs du projet.

CONTROLE OBLIGATOIRE AVANT DE PASSER A L'ECHELLE : chaque phrase fautee est
generee AVEC son pendant correct (meme voix, meme texte a la substitution pres).
On donne les deux au modele : si la faute ne s'entend pas, la paire est rejetee.
C'est ce controle qui a tue le montage audio en cinq minutes.

Usage :
    .venv_tts/bin/python generate_tts_phrases_fautees.py --n 40      # premier lot
    .venv_tts/bin/python generate_tts_phrases_fautees.py --n 4000    # a l'echelle
"""
import argparse
import json
import os
import random
import re
import time
from pathlib import Path

os.environ.setdefault("COQUI_TOS_AGREED", "1")
BASE_DIR = Path(__file__).parent
os.environ.setdefault("TTS_HOME", str(BASE_DIR / "tts-cache"))
os.environ.setdefault("HF_HOME", str(BASE_DIR / "hf-cache"))

import torch  # noqa: E402
from TTS.api import TTS  # noqa: E402

# PIEGE torch >= 2.6 : `weights_only` est passe a True par defaut, ce qui refuse
# les checkpoints Coqui (ils contiennent des objets de config picklees). Le
# corpus de 18 195 fautes avait ete genere sur une autre machine avec un torch
# anterieur -- d'ou un script qui "marchait" et qui ne demarre plus ici.
# On autorise explicitement les classes de XTTS, et rien d'autre.
try:
    from TTS.config.shared_configs import BaseDatasetConfig
    from TTS.tts.configs.xtts_config import XttsConfig
    from TTS.tts.models.xtts import XttsArgs, XttsAudioConfig
    torch.serialization.add_safe_globals(
        [XttsConfig, XttsAudioConfig, XttsArgs, BaseDatasetConfig])
except Exception as _e:  # versions plus anciennes : rien a autoriser
    pass

# PIEGE torchaudio >= 2.9 : le decodage passe par libtorchcodec, qui exige des
# bibliotheques FFmpeg absentes ici -- « Could not load libtorchcodec ». XTTS ne
# se sert de torchaudio QUE pour lire le WAV de reference du clonage vocal, donc
# on lui substitue soundfile, deja installe et sans dependance systeme.
try:
    import numpy as _np
    import soundfile as _sf
    import torchaudio as _ta

    def _charger(chemin, *a, **k):
        x, sr = _sf.read(str(chemin), dtype="float32", always_2d=True)
        return torch.from_numpy(_np.ascontiguousarray(x.T)), sr

    _ta.load = _charger
except Exception:
    pass

# Racine HDD de CETTE machine. Le script d'origine pointe vers /mnt/hdd/... ,
# chemin d'une autre machine (piege documente dans CLAUDE.md : les manifests et
# scripts portent des chemins morts, on remappe sans modifier l'original).
HDD = Path("/run/media/kafai/HDD/Coran Karim/benchmark")

# Coran HAFS uniquement. Le manifeste `nemo_manifests_dual` a d'abord ete
# utilise : il contient 16 280 entrees `arabic_speech_corpus` (MSA, pas du
# Coran) dont certaines sont du charabia -- « ضَوسْبَرَ وَتَضَوسَّرَ » est reellement
# sorti comme phrase source. Un TTS a qui on demande du charabia ne prononce
# rien de fiable, et la paire ne mesure plus rien.
SOURCE_MANIFEST = BASE_DIR / "data" / "manifest_hafs_only.jsonl"
OUT_DIR = BASE_DIR / "data" / "tts_phrases_fautees"
OUT_WAV = OUT_DIR / "wav"

# Memes paires que voice_calibration_words.dart et le corpus de fautes existant.
# Elles CHANGENT le son : ce sont de vraies fautes, pas des variantes d'ecriture.
# Lettres de POINTS D'ARTICULATION DIFFERENTS -- consigne utilisateur
# 2026-07-30 : « varie les lettres, pas avec des lettres qui ont meme sortie
# vocale ». MESURE qui la confirme : sur le premier lot, ت->ط et ك->ق ne
# passent pas le controle d'audibilite (marge +0,86 et -8,96). Ces couples ne
# different que par l'EMPHASE ; XTTS, entraine sur de l'arabe courant non
# coranique, ne la rend pas. Le couple ر/ز est le cas REEL rapporte par
# l'utilisateur (« razaqnahoum » prononce « zazaqnahoum »).
CONFUSABLES = [
    ("ر", "ز"), ("ب", "م"), ("س", "ش"), ("ف", "ث"), ("د", "ج"),
    ("ك", "ت"), ("ل", "ن"), ("ه", "س"), ("ع", "ن"), ("ج", "ب"),
]

# NE PAS SUPPRIMER -- table d'origine, conservee parce qu'elle porte la mesure.
# Ce sont les vraies confusions de recitation (meme makhraj, emphase seule),
# donc la cible finale ; mais XTTS ne sait pas les produire, et un corpus ou la
# faute ne s'entend pas apprend l'INVERSE de ce qu'on veut. A rouvrir avec un
# autre vehicule de generation (vraie voix, ou TTS entraine sur du Coran).
CONFUSABLES_MEME_MAKHRAJ = [
    ("ص", "س"), ("ط", "ت"), ("ض", "د"), ("ذ", "ز"),
    ("ح", "ه"), ("ق", "ك"), ("ع", "ء"),
    ("ج", "ح"), ("ح", "خ"), ("ج", "خ"),
]
FATHA, DAMMA, KASRA, SUKUN = "َ", "ُ", "ِ", "ْ"
SHORT_HARAKAT = [FATHA, DAMMA, KASRA, SUKUN]

VOIX = {
    "YT_sajdah": HDD / "data/youtube_wav/s032_as_sajdah/8x7ZomOnDgM_0014.wav",
    "YT_sad": HDD / "data/youtube_wav/s038_sad/SHk2wS_TBkA_0021.wav",
    "YT_waqiah": HDD / "data/youtube_wav/s056_al_waqiah/N78PGdl2-Wo_0013.wav",
    "YT_haqqah": HDD / "data/youtube_wav/s069_al_haqqah/uOWWZNrNwms_0016.wav",
    "YT_tin": HDD / "data/youtube_wav/s095_at_tin/0eyMtHBDDUE_0002.wav",
    "YT_falaq": HDD / "data/youtube_wav/s113_al_falaq/MaOepE0iVP0_0001.wav",
    "Alafasy": BASE_DIR / "data/train_wav/Alafasy_128kbps/53_14.wav",
    "Sudais": BASE_DIR / "data/train_wav/Abdurrahmaan_As-Sudais_192kbps/82_5.wav",
}


def phrases_sources(mini=3, maxi=6, fragments=True):
    """Versets COURTS ET SIMPLES -- consigne utilisateur 2026-07-30 : « choisis
    des phrases simples, la tu choisis toute la phrase compliquee a prononcer ».

    Deux raisons, et la seconde est la vraie. (1) Plus la phrase est longue,
    plus XTTS derive. (2) Le QA du corpus de mots isoles montre que XTTS rend
    bien la faute sur UN mot (94 % passaient) ; le rendement s'effondre en
    phrase longue. La faute doit rester une part notable de ce qui est
    synthetise -- 3 a 6 mots, pas 12.

    Toujours au moins 3 mots : c'est le CONTEXTE qui manque au corpus existant,
    un mot de plus ne suffirait pas.

    FENETRES GLISSANTES (2026-07-31, apres EPUISEMENT du vivier). Le Coran ne
    contient que 6 062 versets DISTINCTS, dont 2 341 seulement font 4 a 10 mots
    -- tous consommes en une soiree. Ca ne s'est pas vu par une erreur mais par
    un « 0 phrases planifiees », qui a fait demarrer l'etape suivante sur un
    corpus incomplet. On decoupe donc aussi les versets LONGS en fenetres de
    `maxi` mots : le fragment reste une suite de mots coraniques reels, et comme
    chaque mot est de toute facon synthetise SEUL puis assemble, la coupure au
    bord du fragment n'a aucun effet acoustique. Vivier porte de 2 341 a
    ~17 000 phrases."""
    vus = set()
    for ligne in open(SOURCE_MANIFEST, encoding="utf-8"):
        try:
            d = json.loads(ligne)
        except Exception:
            continue
        t = d.get("text", "").strip()
        mots = t.split()
        if mini <= len(mots) <= maxi:
            if t not in vus:
                vus.add(t)
                yield t
        elif fragments and len(mots) > maxi:
            for k in range(0, len(mots) - mini + 1, max(1, maxi // 2)):
                f = " ".join(mots[k:k + maxi])
                if len(f.split()) >= mini and f not in vus:
                    vus.add(f)
                    yield f


def fauter(phrase, rng):
    """Substitue UNE lettre confusable ou UNE harakat, dans UN mot de la phrase.

    @return (phrase_fautee, index_du_mot, kind, detail) ou None si rien a fauter.
    """
    mots = phrase.split()
    ordre = list(range(len(mots)))
    rng.shuffle(ordre)
    for i in ordre:
        m = mots[i]
        if rng.random() < 0.5:
            paires = CONFUSABLES[:]
            rng.shuffle(paires)
            for a, b in paires:
                for src, dst in ((a, b), (b, a)):
                    j = m.find(src)
                    if j >= 0:
                        mots[i] = m[:j] + dst + m[j + 1:]
                        return " ".join(mots), i, "letter", f"{src}->{dst}"
        pos = [k for k, c in enumerate(m) if c in SHORT_HARAKAT]
        if pos:
            k = rng.choice(pos)
            autres = [h for h in SHORT_HARAKAT if h != m[k]]
            dst = rng.choice(autres)
            mots[i] = m[:k] + dst + m[k + 1:]
            return " ".join(mots), i, "harakat", f"harakat@{k}:{m[k]}->{dst}"
    return None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--n", type=int, default=40, help="nombre de PAIRES a generer")
    p.add_argument("--seed", type=int, default=7)
    p.add_argument("--mots-min", type=int, default=3)
    p.add_argument("--mots-max", type=int, default=6)
    p.add_argument("--sortie", default=None)
    args = p.parse_args()

    voix = {k: v for k, v in VOIX.items() if v.exists()}
    if not voix:
        raise SystemExit("aucune voix de clonage atteignable -- verifier les chemins HDD")
    print(f"{len(voix)} voix de clonage : {', '.join(voix)}")

    global OUT_DIR, OUT_WAV
    if args.sortie:
        OUT_DIR = Path(args.sortie); OUT_WAV = OUT_DIR / "wav"
    OUT_WAV.mkdir(parents=True, exist_ok=True)
    rng = random.Random(args.seed)
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"chargement XTTS-v2 sur {dev}...")
    tts = TTS("tts_models/multilingual/multi-dataset/xtts_v2").to(dev)

    noms = list(voix)
    manifeste = open(OUT_DIR / "manifest.jsonl", "w", encoding="utf-8")
    n = 0
    t0 = time.time()
    for phrase in phrases_sources(args.mots_min, args.mots_max):
        if n >= args.n:
            break
        r = fauter(phrase, rng)
        if r is None:
            continue
        fautee, idx, kind, detail = r
        v = noms[n % len(noms)]
        try:
            # La PAIRE : meme voix, meme texte a la substitution pres. Sans le
            # pendant correct on ne peut pas verifier que la faute s'entend.
            for suffixe, texte in (("faute", fautee), ("correct", phrase)):
                out = OUT_WAV / f"phr_{n:05d}_{suffixe}.wav"
                tts.tts_to_file(text=texte, file_path=str(out),
                                speaker_wav=str(voix[v]), language="ar")
            manifeste.write(json.dumps({
                "clip_faute": f"phr_{n:05d}_faute.wav",
                "clip_correct": f"phr_{n:05d}_correct.wav",
                "text": fautee,          # etiquette = ce qui est PRONONCE
                "correct_text": phrase,
                "mot_index": idx,
                "kind": kind,
                "detail": detail,
                "voice": v,
            }, ensure_ascii=False) + "\n")
            manifeste.flush()
            n += 1
            if n % 5 == 0:
                dt = time.time() - t0
                print(f"  {n}/{args.n} paires  ({dt/n:.1f} s/paire, "
                      f"reste ~{(args.n-n)*dt/n/60:.0f} min)")
        except Exception as e:
            print(f"  echec sur '{phrase[:30]}...' : {str(e)[:80]}")
    manifeste.close()
    print(f"\n{n} paires -> {OUT_DIR}")
    print("CONTROLE OBLIGATOIRE : passer les deux clips de chaque paire au "
          "modele et verifier que la faute S'ENTEND avant toute generation a "
          "l'echelle (c'est ce controle qui a tue le montage audio).")


if __name__ == "__main__":
    main()
