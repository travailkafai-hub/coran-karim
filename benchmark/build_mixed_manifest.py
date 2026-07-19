#!/usr/bin/env python3
"""Construit un manifeste d'entrainement MIXTE : Coran + Arabic Speech Corpus + TTS fautif.

POURQUOI (2026-07-16) — le probleme que ce script existe pour resoudre :
    Tous les manifestes "tajweed" precedents contenaient 284823 clips de Coran
    PARFAITEMENT recite, et rien d'autre (verifie : tts=0, augment=0 dans les 4
    manifestes de nemo_manifests_tajweed/). Le modele n'avait donc jamais entendu
    une seule erreur de prononciation de sa vie -- il a appris que "la bonne
    reponse est toujours le texte canonique".
    Consequence mesuree sur device : l'utilisateur prononce deliberement "rabba"
    (fatha), le modele ecrit "rabbi" (kasra, la forme canonique). Le GOP ne peut
    RIEN voir : il mesure forced-free, et si le modele est convaincu du canonique,
    forced == free => gop=0 => vert. L'erreur est structurellement invisible.
    L'augmentation TTS avait ete generee (18084 clips) mais PERDUE lors de la
    reconstruction du manifeste au passage au tokenizer tajweed_bpe_v1 (12/07).

STRATEGIE — pourquoi ces ratios et pas "ajouter le TTS au manifeste" :
    Ajouter ASC (3.8h) + TTS (9.6h) aux 1251h de Coran = 1.1% du temps. Un biais
    construit sur 1251h ne se casse pas avec 1% de contre-exemples. Comme on part
    d'un checkpoint qui maitrise DEJA le Coran (5.6% WER, gop 0.00 sur la Fatiha),
    on n'a pas besoin de re-servir 1251h pour preserver cet acquis -- juste assez
    pour ne pas l'oublier (replay). Le reste du budget va au signal manquant.
      Coran   : sous-echantillonne a ~150h (anti-oubli)
      ASC x10 : ~38h  -- VRAIE voix humaine, arabe NON coranique, entierement
                vocalise => aucun prior canonique n'est applicable, le modele DOIT
                ecouter la harakat. C'est l'antidote direct au biais.
      TTS x5  : ~48h  -- erreurs deliberees (sin/sad, harakat...), apprend les
                confusions precises.
    => ~236h dont ~36% de contre-exemples.

LIMITE CONNUE (a surveiller) : dans les clips TTS, la voix est correlee a 100%
    avec l'erreur (aucun clip TTS n'a le texte correct -- verifie : 0/18084).
    Le modele pourrait apprendre le raccourci "voix synthetique -> j'ecoute
    l'acoustique / vraie voix -> j'applique le prior". L'ASC (vraie voix, pas de
    prior possible) est justement la pour contrer ca. Si l'eval montre que les
    erreurs sont detectees sur TTS mais pas en conditions reelles, ce raccourci
    est le premier suspect -> generer des clips TTS a texte CORRECT (groupe de
    controle) dans les memes voix, ou passer au splice sur audio reel
    (build_confusable_splice_augmentation.py).

VALIDATION : les manifestes de val precedents etaient 100% canoniques -- ils ne
    pouvaient PAS mesurer un progres sur les erreurs. Ici on tient des clips ASC
    et TTS HORS entrainement, et on ecrit un val dedie erreurs (val_errors) pour
    mesurer specifiquement ce qui nous interesse.

Usage :
    python3 build_mixed_manifest.py [--quran-hours 150] [--asc-rep 10] [--tts-rep 5]
"""
import argparse
import contextlib
import json
import random
import wave
from pathlib import Path

# Chemin d'origine (autre machine) : Path("/mnt/ssd5/Coran Karim/benchmark")
# -- remape vers cette machine le 2026-07-19 (meme pattern que les autres
# scripts d'eval de la session).
BASE = Path(__file__).parent
QURAN_TRAIN = BASE / "nemo_manifests_tajweed" / "train_manifest_ubuntu.jsonl"
QURAN_VAL = BASE / "nemo_manifests_tajweed" / "val_manifest_ubuntu.jsonl"
ASC_MANIFEST = BASE / "arabic_speech_corpus" / "asc_manifest.jsonl"
TTS_MANIFEST = BASE / "data" / "tts_augmentation" / "manifest_qa_clean.jsonl"
TTS_WAV = BASE / "data" / "tts_augmentation" / "wav"
OUT_DIR = BASE / "nemo_manifests_mixed"

# Les chemins ASC du manifeste source datent de l'epoque Windows ; les
# chemins Coran (nemo_manifests_tajweed) datent d'une session Ubuntu
# differente (points de montage /mnt/... propres a cette autre machine).
# Remape directement vers cette machine (2026-07-19, meme pattern que les
# scripts d'eval de la session).
WIN_PREFIX = "D:/Coran Karim/benchmark"
NIX_PREFIX = str(BASE)
HDD_PREFIX_OLD = "/mnt/hdd/Coran Karim/benchmark"
HDD_PREFIX_NEW = "/run/media/kafai/HDD/Coran Karim/benchmark"
# Copie locale complete verifiee le 2026-07-19 (414569/414569 clips, meme
# nombre que le HDD, hash identique sur echantillon) -- utiliser le SSD
# local (NVMe) plutot que le HDD externe : lectures aleatoires (dataloader
# shuffle) bien plus rapides, et evite l'usure/la saturation du HDD sur un
# entrainement de plusieurs heures.
LOCAL_TRAIN_WAV = str(BASE / "data" / "train_wav_local")


def remap_audio_path(p: str) -> str:
    if p.startswith(HDD_PREFIX_OLD):
        return LOCAL_TRAIN_WAV + p[len(HDD_PREFIX_OLD + "/data/train_wav"):]
    if p.startswith(HDD_PREFIX_NEW):
        return LOCAL_TRAIN_WAV + p[len(HDD_PREFIX_NEW + "/data/train_wav"):]
    return p

SEED = 1337
HOLDOUT_FRAC = 0.10  # part d'ASC/TTS tenue hors entrainement, pour mesurer


def load_jsonl(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def wav_duration(path):
    try:
        with contextlib.closing(wave.open(str(path))) as w:
            return w.getnframes() / float(w.getframerate())
    except Exception:
        return None


def hours(rows):
    return sum(float(r.get("duration", 0) or 0) for r in rows) / 3600


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quran-hours", type=float, default=150.0)
    ap.add_argument("--asc-rep", type=int, default=10)
    ap.add_argument("--tts-rep", type=int, default=5)
    args = ap.parse_args()
    rng = random.Random(SEED)

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # ── Coran : sous-echantillonnage aleatoire jusqu'au budget d'heures ──────
    quran = load_jsonl(QURAN_TRAIN)
    for r in quran:
        r["audio_filepath"] = remap_audio_path(r["audio_filepath"])
    missing_q = [r for r in quran if not Path(r["audio_filepath"]).exists()]
    if missing_q:
        raise SystemExit(f"Coran : {len(missing_q)} fichiers introuvables, ex. {missing_q[0]['audio_filepath']}")
    print(f"Coran source          : {len(quran):>7} clips, {hours(quran):>7.1f} h")
    rng.shuffle(quran)
    kept, acc = [], 0.0
    budget = args.quran_hours * 3600
    for r in quran:
        d = float(r.get("duration", 0) or 0)
        if acc + d > budget:
            continue
        kept.append(r)
        acc += d
    quran_train = kept
    print(f"Coran sous-echantillon: {len(quran_train):>7} clips, {hours(quran_train):>7.1f} h")

    # ── ASC : conversion des chemins, split train/holdout, oversampling ──────
    asc = load_jsonl(ASC_MANIFEST)
    for r in asc:
        r["audio_filepath"] = r["audio_filepath"].replace(WIN_PREFIX, NIX_PREFIX)
    missing = [r for r in asc if not Path(r["audio_filepath"]).exists()]
    if missing:
        raise SystemExit(f"ASC : {len(missing)} fichiers introuvables, ex. {missing[0]['audio_filepath']}")
    rng.shuffle(asc)
    n_hold = int(len(asc) * HOLDOUT_FRAC)
    asc_val, asc_train_base = asc[:n_hold], asc[n_hold:]
    asc_train = asc_train_base * args.asc_rep
    print(f"ASC                   : {len(asc_train_base):>7} clips x{args.asc_rep} = "
          f"{len(asc_train)}, {hours(asc_train):>7.1f} h  (+{len(asc_val)} tenus pour eval)")

    # ── TTS : durees calculees depuis les wav, split, oversampling ───────────
    tts_raw = load_jsonl(TTS_MANIFEST)
    tts = []
    for r in tts_raw:
        p = TTS_WAV / r["clip"]
        d = wav_duration(p)
        if d is None:
            continue
        tts.append({
            "audio_filepath": str(p),
            "duration": round(d, 3),
            # IMPORTANT : `text` est le texte REELLEMENT prononce (fautif).
            # C'est tout l'interet : apprendre a transcrire ce qui est dit,
            # pas ce qui devrait etre dit.
            "text": r["text"],
            # Metadonnees conservees pour l'eval (mesurer par type d'erreur).
            "err_kind": r.get("kind"),
            "err_detail": r.get("detail"),
            "correct_text": r.get("correct_text"),
        })
    print(f"TTS lus               : {len(tts):>7} clips, {hours(tts):>7.1f} h")
    rng.shuffle(tts)
    n_hold = int(len(tts) * HOLDOUT_FRAC)
    tts_val, tts_train_base = tts[:n_hold], tts[n_hold:]
    tts_train = tts_train_base * args.tts_rep
    print(f"TTS                   : {len(tts_train_base):>7} clips x{args.tts_rep} = "
          f"{len(tts_train)}, {hours(tts_train):>7.1f} h  (+{len(tts_val)} tenus pour eval)")

    # ── Ecriture ────────────────────────────────────────────────────────────
    # NeMo ignore les cles supplementaires, mais on les retire du train pour
    # garder un manifeste propre (elles ne servent qu'a l'eval).
    def strip(r):
        return {k: v for k, v in r.items()
                if k in ("audio_filepath", "duration", "text")}

    train = [strip(r) for r in (quran_train + asc_train + tts_train)]
    rng.shuffle(train)

    val_canon = load_jsonl(QURAN_VAL)
    # BUG corrige le 2026-07-19 : contrairement a QURAN_TRAIN (ligne ~130),
    # ce remap manquait ici -- val_canonical.jsonl gardait des chemins morts
    # /mnt/hdd/... (mount temporaire disparu), en silence jusqu'a ce qu'un
    # eval tente vraiment de lire ces fichiers (FileNotFoundError).
    for r in val_canon:
        r["audio_filepath"] = remap_audio_path(r["audio_filepath"])
    missing_v = [r for r in val_canon if not Path(r["audio_filepath"]).exists()]
    if missing_v:
        raise SystemExit(f"Coran val : {len(missing_v)} fichiers introuvables, ex. {missing_v[0]['audio_filepath']}")
    val_errors = tts_val + asc_val  # ce qu'on veut REELLEMENT mesurer

    def write(path, rows):
        with open(path, "w", encoding="utf-8") as f:
            for r in rows:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
        print(f"  -> {path.name:<28} {len(rows):>7} lignes, {hours(rows):>7.1f} h")

    # val_mixed = ce sur quoi on SELECTIONNE le meilleur checkpoint.
    # Choix deliberé : monitorer le val 100% canonique (ce que faisaient tous
    # les runs precedents) revient a selectionner le checkpoint qui recite le
    # mieux du Coran parfait -- exactement le comportement qu'on cherche a
    # corriger : un modele qui "corrige" tout vers le canonique y obtiendrait
    # le meilleur score. Inversement, monitorer uniquement les erreurs
    # laisserait se degrader la reconnaissance coranique qui marche bien
    # aujourd'hui (gop 0.00 sur la Fatiha). D'ou un val equilibre ~50/50 en
    # nombre de clips. Le canonique est sous-echantillonne (66h -> ~2h) : la
    # validation tourne a chaque epoch, 66h la rendrait plus lente que
    # l'entrainement lui-meme pour zero information supplementaire.
    rng.shuffle(val_canon)
    val_canon_sample = val_canon[:len(val_errors)]
    val_mixed = [strip(r) for r in (val_canon_sample + val_errors)]
    rng.shuffle(val_mixed)

    print("\nEcriture :")
    write(OUT_DIR / "train_mixed.jsonl", train)
    write(OUT_DIR / "val_mixed.jsonl", val_mixed)
    write(OUT_DIR / "val_canonical.jsonl", val_canon)
    write(OUT_DIR / "val_errors.jsonl", [strip(r) for r in val_errors])
    # version annotee : garde err_kind/detail pour analyser l'eval par type
    with open(OUT_DIR / "val_errors_annotated.jsonl", "w", encoding="utf-8") as f:
        for r in val_errors:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    # ── Bilan ───────────────────────────────────────────────────────────────
    th = hours(train)
    qh, ah, tth = hours(quran_train), hours(asc_train), hours(tts_train)
    print(f"\n{'source':<24}{'heures':>9}{'part':>8}")
    print("-" * 41)
    for name, h in (("Coran (replay)", qh), ("ASC x%d" % args.asc_rep, ah),
                    ("TTS x%d" % args.tts_rep, tth)):
        print(f"{name:<24}{h:>9.1f}{100*h/th:>7.1f}%")
    print("-" * 41)
    print(f"{'TOTAL':<24}{th:>9.1f}")
    print(f"\ncontre-exemples (ASC+TTS) : {100*(ah+tth)/th:.1f}% du temps")
    print(f"(etait 0.0% dans tous les manifestes tajweed precedents)")


if __name__ == "__main__":
    main()
