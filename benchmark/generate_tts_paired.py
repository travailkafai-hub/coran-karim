"""Generation TTS APPARIEE correct/fautif (2026-07-22) -- corrige le defaut
central de generate_tts_augmentation.py, documente dans ETAT_CTC_NEMO.md :

    "la voix TTS est correlee a 100% avec la presence d'une erreur dans ces
     clips -> risque que le modele apprenne 'voix synthetique = j'ecoute,
     vraie voix = je corrige' plutot que la vraie lecon"

Ce risque s'est materialise : le biais canonique persiste sur voix humaine
reelle malgre le TTS x5 deja present a l'entrainement (constat device
2026-07-21 : "صراط" recite avec un sin ressort systematiquement corrige en
canonique, sur mixed-e02 ET sur rules-260h).

── LA CORRECTION ──
Pour CHAQUE variante fautive generee, on genere AUSSI le mot CORRECT avec la
MEME voix. Le timbre cesse alors d'etre predictif de la presence d'erreur :
le modele ne peut plus utiliser "c'est une voix synthetique" comme raccourci,
il doit ecouter le contenu. C'est la contre-mesure logique au defaut ci-dessus
(l'ASC humain servait deja de contre-mesure partielle, mais il ne contient
aucune erreur -- donc la correlation restait parfaite dans l'autre sens).

── DIFFERENCES AVEC generate_tts_augmentation.py ──
1. Paires (correct, fautif) meme voix, au lieu de clips fautifs seuls.
2. Chemins corriges pour CETTE machine : `train_wav_local` (et non
   `train_wav`, absent ici), pas de dependance aux youtube_wav du HDD d'une
   autre machine -- l'ancien script ne chargeait AUCUNE voix ici (verifie :
   VOICES aurait ete vide, le filtre `if path.exists()` masquant l'echec).
3. Voix de reference elargies : recitateurs locaux + voix fournies par
   l'utilisateur (enregistrements telephone), pour une diversite de timbres
   qui inclut des voix d'apprenants, pas seulement des professionnels.

Le reste (tables de confusion, variantes harakat, format du manifest) est
IDENTIQUE a generate_tts_augmentation.py -- meme source, meme etiquetage
(`text` = ce qui a REELLEMENT ete demande au TTS, jamais le canonique).

Usage :
    .venv_tts/bin/python generate_tts_paired.py --test          # ~16 clips
    .venv_tts/bin/python generate_tts_paired.py --n-words 500
"""
import os, json, random, argparse, time
os.environ.setdefault("COQUI_TOS_AGREED", "1")
from pathlib import Path

BASE_DIR = Path(__file__).parent
os.environ.setdefault("TTS_HOME", str(BASE_DIR / "tts-cache"))
os.environ.setdefault("HF_HOME", str(BASE_DIR / "hf-cache"))

import torch
# PyTorch >= 2.6 : `torch.load` bascule sur weights_only=True par defaut, ce
# qui refuse le checkpoint XTTS-v2 (anterieur, il embarque ses classes de
# config). Erreur exacte sans ce correctif :
#   _pickle.UnpicklingError: Weights only load failed ... Unsupported global:
#   GLOBAL TTS.tts.configs.xtts_config.XttsConfig
# Le checkpoint vient du cache officiel Coqui deja present dans tts-cache/
# (source de confiance, deja utilisee par generate_tts_augmentation.py), on
# autorise donc explicitement ses classes plutot que de desactiver
# globalement weights_only.
from TTS.tts.configs.xtts_config import XttsConfig
from TTS.tts.models.xtts import XttsAudioConfig, XttsArgs
from TTS.config.shared_configs import BaseDatasetConfig
torch.serialization.add_safe_globals(
    [XttsConfig, XttsAudioConfig, XttsArgs, BaseDatasetConfig])

# torchaudio 2.11 delegue son I/O a torchcodec, dont les .so exigent des
# libs CUDA absentes de cette machine (libnppicc.so.12) -> `torchaudio.load`
# leve "Could not load libtorchcodec" et XTTS ne peut plus lire le WAV de
# reference du clonage. `soundfile` lit le meme fichier sans probleme
# (verifie), on remplace donc l'implementation par un equivalent soundfile
# plutot que de reinstaller toute la pile CUDA du venv TTS.
import numpy as _np
import soundfile as _sf
import torchaudio as _ta


def _load_via_soundfile(path, *a, **k):
    data, sr = _sf.read(str(path), dtype="float32", always_2d=True)
    return torch.from_numpy(_np.ascontiguousarray(data.T)), sr


_ta.load = _load_via_soundfile

from TTS.api import TTS

WORD_TOKENS_PATH = (BASE_DIR / "models" / "fastconformer-quran-tajweed" /
                    "deploy" / "fastconformer-ctc-tajweed" / "word_tokens.json")
OUT_DIR = BASE_DIR / "data" / "tts_paired_v3"
OUT_MANIFEST = OUT_DIR / "manifest.jsonl"

# Identiques a generate_tts_augmentation.py / voice_calibration_words.dart
CONFUSABLE_PAIRS = [
    ("ص", "س"), ("س", "ص"), ("ط", "ت"), ("ت", "ط"),
    ("ض", "د"), ("د", "ض"), ("ذ", "ز"), ("ز", "ذ"),
    ("ح", "ه"), ("ه", "ح"), ("ق", "ك"), ("ك", "ق"),
    ("ع", "ء"), ("ء", "ع"),
]
FATHA, DAMMA, KASRA, SUKUN = "َ", "ُ", "ِ", "ْ"
SHORT_HARAKAT = {FATHA, DAMMA, KASRA, SUKUN}

# Recitateurs WARSH (riwaya differente de Hafs 'an 'Asim -- mots, hamza et
# madd differents par endroits) -- liste verifiee manuellement dans
# build_hafs_only_manifest.py (assabile.com + test audio sur versets
# discriminants). ~21% du dataset unifie du projet etait contamine ainsi par
# le passe ("a contamine tous les trainings CTC precedents"). Trouve le
# 2026-07-22 (remarque utilisateur) : cette liste n'avait PAS ete appliquee
# ici -- 25%/22,8% des clips tts_paired/tts_paired_v2 avaient ete clones a
# partir d'une de ces voix. Le TEXTE genere restait du Hafs correct (XTTS
# clone le timbre, ne recite pas de memoire), mais le risque residuel
# (prosodie/accent Warsh transferes dans le clonage) suffit a exclure ces
# voix pour un dataset propre.
WARSH_RECITERS = {
    "AbdelKabirHadidi_assajda", "AbdelhamidHssain_assajda", "AbdelmoujibBenkirane_assajda",
    "AbdurrahimNabulsi_assajda", "FaysalWizar_assajda", "HosseinBousseksso_assajda",
    "LaayounKouchi_assajda", "MohamedChahboun_assajda", "MohamedElIraoui_assajda",
    "MohamedHamdan_assajda", "MohamedKantaoui_assajda", "MustaphaGharbi_assajda",
    "NurdinMaghriby_assajda", "OmarKazabri_assajda", "RachidBelaachya_assajda",
    "RachidBelalia_assajda", "RachidIfrad_assajda", "SamirBelaachya_assajda",
    "YassenJazairi_assajda", "YoussefEdghouch_assajda", "ZakariaHamama_assajda",
    "OmarQazabri_128kbps", "HassanSaleh_assajda", "AbdulRashidSufi_assajda",
}

LOCAL_WAV = BASE_DIR / "data" / "train_wav_local"
# Voix fournies par l'utilisateur (enregistrements telephone, recuperes le
# 2026-07-22 depuis /storage/emulated/0/Recordings/Voice Recorder/).
# Interet : timbres d'APPRENANTS, absents du corpus de recitateurs
# professionnels -- c'est precisement le domaine ou le modele echoue.
USER_VOICES_DIR = BASE_DIR / "data" / "voix_utilisateur"


# Qualite exigee d'un clip de REFERENCE pour le clonage (seuils derives d'une
# mesure sur le 1er run de 12 000 clips, 2026-07-22 -- les rejets n'etaient
# PAS aleatoires, ils se concentraient sur des references defectueuses) :
#   MohamedElIraoui  rms=0,0053 (17x trop faible) -> 40 % de clips rejetes
#   MustaphaLahouni  rms=0,2359 (presque 3x trop fort, sature) -> 29 %
#   voix saines      rms 0,083-0,090              -> ~5 %
# XTTS clone le timbre A PARTIR de ce clip : une reference trop faible ou
# saturee produit une voix degradee sur TOUS les clips qu'elle genere.
REF_MIN_RMS, REF_MAX_RMS = 0.02, 0.20
REF_MIN_DUR = 4.0          # XTTS clone mieux avec >=4-6 s qu'avec 2,6 s
REF_TARGET_RMS = 0.087     # niveau median des references saines observees


def _ref_quality(path):
    """(ok, rms, duree) d'un clip candidat comme reference de clonage."""
    try:
        a, sr = _sf.read(str(path), dtype="float32", always_2d=False)
    except Exception:
        return False, 0.0, 0.0
    if a.ndim > 1:
        a = a.mean(axis=1)
    dur = len(a) / sr
    rms = float(_np.sqrt((a ** 2).mean())) if len(a) else 0.0
    ok = (dur >= REF_MIN_DUR and REF_MIN_RMS <= rms <= REF_MAX_RMS)
    return ok, rms, dur


def _pick_reference(d, cache_dir):
    """Meilleur clip de reference d'un recitateur : le premier qui passe les
    criteres de qualite, NORMALISE en volume dans cache_dir.
    Normaliser plutot que juste filtrer : deux references saines mais a des
    niveaux differents donnent des clones de qualite inegale."""
    for w in sorted(d.glob("*.wav"))[:12]:      # cherche au-dela du 1er fichier
        ok, rms, dur = _ref_quality(w)
        if not ok:
            continue
        a, sr = _sf.read(str(w), dtype="float32", always_2d=False)
        if a.ndim > 1:
            a = a.mean(axis=1)
        a = a * (REF_TARGET_RMS / max(rms, 1e-9))
        a = _np.clip(a, -1.0, 1.0)
        out = cache_dir / f"{d.name[:40]}.wav"
        _sf.write(str(out), a, sr)
        return out
    return None


def build_refs():
    """Voix de reference reellement presentes sur CETTE machine.
    Contrairement a l'ancien script, on LOGUE ce qui manque au lieu de le
    filtrer en silence (l'echec y etait invisible : VOICES vide sans erreur).
    Depuis 2026-07-22 : filtre AUSSI sur la qualite de la reference et
    normalise son volume (cf. REF_MIN_RMS ci-dessus)."""
    refs, manquants = {}, []
    cache = BASE_DIR / "data" / "tts_ref_normalisees"
    cache.mkdir(parents=True, exist_ok=True)
    ecartes = []
    # Recitateurs locaux : un clip de reference par recitateur, choisi pour sa
    # qualite (pas juste le premier fichier venu, cf. mesure ci-dessus).
    if LOCAL_WAV.exists():
        for d in sorted(LOCAL_WAV.iterdir()):
            if not d.is_dir():
                continue
            if d.name in WARSH_RECITERS:
                ecartes.append(f"{d.name[:28]}(Warsh)")
                continue
            ref = _pick_reference(d, cache)
            if ref is not None:
                refs[f"rec_{d.name[:24]}"] = ref
            else:
                ecartes.append(d.name[:28])
    else:
        manquants.append(str(LOCAL_WAV))
    if ecartes:
        print(f"   {len(ecartes)} recitateurs ecartes (aucune reference de "
              f"qualite suffisante) : {', '.join(ecartes[:6])}"
              f"{'...' if len(ecartes) > 6 else ''}")
    # Voix utilisateur : memes criteres de qualite + normalisation que les
    # recitateurs (un enregistrement telephone n'a aucune raison d'etre au bon
    # niveau -- et c'est justement le timbre le plus precieux, celui d'un
    # apprenant, donc autant lui donner la meilleure chance de bien cloner).
    if USER_VOICES_DIR.exists():
        for w in sorted(USER_VOICES_DIR.glob("*.wav")):
            ok, rms, dur = _ref_quality(w)
            if not ok:
                print(f"   voix utilisateur ECARTEE : {w.name} "
                      f"(rms={rms:.4f}, {dur:.1f}s)")
                continue
            a, sr = _sf.read(str(w), dtype="float32", always_2d=False)
            if a.ndim > 1:
                a = a.mean(axis=1)
            a = _np.clip(a * (REF_TARGET_RMS / max(rms, 1e-9)), -1.0, 1.0)
            out = cache / f"user_{w.stem}.wav"
            _sf.write(str(out), a, sr)
            refs[f"user_{w.stem}"] = out
    else:
        manquants.append(str(USER_VOICES_DIR))
    if manquants:
        print(f"⚠️  sources de voix ABSENTES : {manquants}")
    return refs


def load_vocab():
    return list(json.load(open(WORD_TOKENS_PATH, encoding="utf-8")).keys())


def confusable_variants(word):
    out = []
    for src, dst in CONFUSABLE_PAIRS:
        if src in word:
            out.append((word.replace(src, dst, 1), f"{src}->{dst}"))
    return out


def harakat_variants(word, max_per_word=1):
    positions = [i for i, c in enumerate(word) if c in SHORT_HARAKAT]
    random.shuffle(positions)
    out = []
    for pos in positions[:max_per_word]:
        original = word[pos]
        alt = random.choice([h for h in SHORT_HARAKAT if h != original])
        out.append((word[:pos] + alt + word[pos + 1:],
                    f"harakat@{pos}:{original}->{alt}"))
    return out


def build_plan(n_words, seed=7):
    vocab = load_vocab()
    random.seed(seed)
    random.shuffle(vocab)
    plan = []
    for w in vocab:
        if len(plan) >= n_words * 2:
            break
        for variant, detail in confusable_variants(w):
            plan.append((w, variant, "letter", detail))
            break
        for variant, detail in harakat_variants(w):
            plan.append((w, variant, "harakat", detail))
    return plan


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--test", action="store_true")
    p.add_argument("--n-words", type=int, default=500)
    args = p.parse_args()

    refs = build_refs()
    voices = sorted(refs)
    if not voices:
        raise SystemExit("aucune voix de reference disponible -- rien a generer")
    n_user = sum(1 for v in voices if v.startswith("user_"))
    print(f"Voix de reference : {len(voices)} "
          f"({n_user} utilisateur, {len(voices)-n_user} recitateurs)")

    n_words = 4 if args.test else args.n_words
    plan = build_plan(n_words)
    random.shuffle(plan)

    # Une voix par variante (meme principe de "plage de mots" que l'ancien
    # script), mais la MEME voix dit le correct ET le fautif -> le timbre
    # n'est plus predictif de l'erreur.
    chunk = (len(plan) + len(voices) - 1) // len(voices)
    assign = [voices[min(i // chunk, len(voices) - 1)] for i in range(len(plan))]

    print(f"Plan : {len(plan)} paires -> {2*len(plan)} clips "
          f"(1 correct + 1 fautif par paire, meme voix)")

    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Chargement XTTS-v2 sur {device}...")
    tts = TTS("tts_models/multilingual/multi-dataset/xtts_v2").to(device)

    wav_dir = OUT_DIR / "wav"
    wav_dir.mkdir(parents=True, exist_ok=True)

    done, t0 = 0, time.time()
    with open(OUT_MANIFEST, "a", encoding="utf-8") as mf:
        for i, (correct, wrong, kind, detail) in enumerate(plan):
            v = assign[i]
            spk = str(refs[v])
            # (texte a dire, nom du clip, is_error)
            for text, name, is_err in (
                    (correct, f"pair{i}_ok.wav", False),
                    (wrong, f"pair{i}_err.wav", True)):
                out_path = wav_dir / name
                try:
                    tts.tts_to_file(text=text, file_path=str(out_path),
                                    speaker_wav=spk, language="ar")
                except Exception as e:
                    print(f"  [erreur] {text!r} voix={v}: {e}")
                    continue
                mf.write(json.dumps({
                    "clip": name, "text": text, "correct_text": correct,
                    "is_error": is_err, "kind": kind if is_err else "correct",
                    "detail": detail if is_err else "", "voice": v,
                    "pair_id": i,
                }, ensure_ascii=False) + "\n")
                mf.flush()
                done += 1
            if (i + 1) % 25 == 0:
                el = time.time() - t0
                rate = done / el if el else 0
                left = (2 * len(plan) - done) / rate if rate else 0
                print(f"  {done}/{2*len(plan)} clips ({rate:.2f}/s, "
                      f"{el/60:.1f}min ecoulees, ~{left/60:.1f}min restantes)")

    print(f"\nTermine : {done} clips -> {wav_dir}\nmanifest -> {OUT_MANIFEST}")


if __name__ == "__main__":
    main()
