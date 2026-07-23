"""
Generation TTS a grande echelle pour l'augmentation "erreurs delibérées"
(FONCTIONNALITES_FUTURES.md §8, complement 2026-07-14 -- piste validee a
l'oreille par l'utilisateur le 2026-07-14 sur "ٱلنَّاسِ"/"ٱلنَّاصِ" via XTTS-v2).

Deux types de variantes "fautives" generees par mot source (vocabulaire
coranique reel, 19001 mots deja recuperes via api.quran.com -- meme source
que word_tokens.json/build_word_token_lookup_tajweed.py) :

1. LETTRE CONFUSABLE (tajweed classique, makharij proches) -- meme table
   que app/lib/data/voice_calibration_words.dart / build_confusable_splice_augmentation.py.
2. HARAKAT SUBSTITUEE -- pour chaque position de harakat courte (fatha/damma/
   kasra/sukun) dans le mot, une variante avec une AUTRE harakat a cette
   position (ex: attendu damma, genere fatha) -- objectif : que le modele
   apprenne a distinguer les harakat, pas seulement a les reconnaitre sur
   des mots toujours bien prononces (meme bug de biais que §8, teste et
   confirme reel le 2026-07-14 sur substitution ص/س de Sourate An-Nas).

Plusieurs voix XTTS-v2 (parmi 58 integrees) par variante, pour la diversite
acoustique -- evite le sur-ajustement a un seul timbre synthetique.

Etiquette du clip = texte REELLEMENT demande au TTS (avec la substitution),
jamais le texte canonique -- meme principe que §8/§8bis/§8ter.

Usage :
    .venv_tts/bin/python generate_tts_augmentation.py --test        # ~20 clips, verifie le pipeline
    .venv_tts/bin/python generate_tts_augmentation.py --n-words 500 # generation complete (des heures)
"""
import os, json, re, random, argparse, time
os.environ.setdefault("COQUI_TOS_AGREED", "1")
from pathlib import Path

BASE_DIR = Path(__file__).parent
os.environ.setdefault("TTS_HOME", str(BASE_DIR / "tts-cache"))
os.environ.setdefault("HF_HOME", str(BASE_DIR / "hf-cache"))

import torch
from TTS.api import TTS

WORD_TOKENS_PATH = BASE_DIR / "models" / "fastconformer-quran-tajweed" / "deploy" / "fastconformer-ctc-tajweed" / "word_tokens.json"
OUT_DIR = BASE_DIR / "data" / "tts_augmentation"
OUT_MANIFEST = OUT_DIR / "manifest.jsonl"

# Memes paires que voice_calibration_words.dart / build_confusable_splice_augmentation.py
CONFUSABLE_PAIRS = [
    ("ص", "س"), ("س", "ص"),
    ("ط", "ت"), ("ت", "ط"),
    ("ض", "د"), ("د", "ض"),
    ("ذ", "ز"), ("ز", "ذ"),
    ("ح", "ه"), ("ه", "ح"),
    ("ق", "ك"), ("ك", "ق"),
    ("ع", "ء"), ("ء", "ع"),
]

# Harakat courtes substituables entre elles (voyelles brèves -- fatha/damma/
# kasra/sukun). Tanwin et shadda geres a part (moins prioritaire, exclus ici
# pour rester sur le cas le plus frequent/le mieux compris par tajweed).
FATHA, DAMMA, KASRA, SUKUN = "َ", "ُ", "ِ", "ْ"
SHORT_HARAKAT = {FATHA, DAMMA, KASRA, SUKUN}

# Clonage vocal XTTS-v2 (speaker_wav) sur de VRAIS recitateurs du corpus
# (demande utilisateur 2026-07-14 : "utilise les voix que ce soit de youtube
# ou des recitateurs") -- bien plus adapte que les 58 voix generiques
# integrees (noms occidentaux, timbre non coranique) : le TTS clone le
# timbre/l'accent d'un vrai recitateur a partir d'un extrait de reference,
# pour une diversite acoustique realiste dans le domaine cible.
# Recitateurs MODERNES uniquement (correction 2026-07-14, retour utilisateur
# "j'ai l'impression que c'etait une voix vieille") -- Husary/Minshawy sont
# des enregistrements des annees 1950-70 (qualite d'epoque, meme si la
# recitation elle-meme est excellente) ; ceux-ci sont tous des enregistrements
# recents haute fidelite (Alafasy, Sudais, Shuraym... reciteurs contemporains
# tres populaires, cf. imams des Haramain), bien mieux adaptes comme reference
# de clonage vocal XTTS.
HDD_YT_BASE = Path("/mnt/hdd/Coran Karim/benchmark")
RECITER_REFS = {
    # Voix YouTube EN PRIORITE (retour utilisateur 2026-07-14 : "ceux de YT
    # c plus interessant", valide a l'oreille contre les recitateurs
    # "officiels" vintage ET modernes) -- clips deja tries par WER (cf.
    # filter_youtube_wer.py / manifest_youtube_clean.jsonl), 7 videos
    # distinctes pour la diversite.
    "YT_sajdah": HDD_YT_BASE / "data" / "youtube_wav" / "s032_as_sajdah" / "8x7ZomOnDgM_0014.wav",
    "YT_sad": HDD_YT_BASE / "data" / "youtube_wav" / "s038_sad" / "SHk2wS_TBkA_0021.wav",
    "YT_zukhruf": HDD_YT_BASE / "data" / "youtube_wav" / "s043_az_zukhruf" / "jRAfz5fIT40_0031.wav",
    "YT_waqiah": HDD_YT_BASE / "data" / "youtube_wav" / "s056_al_waqiah" / "N78PGdl2-Wo_0013.wav",
    "YT_haqqah": HDD_YT_BASE / "data" / "youtube_wav" / "s069_al_haqqah" / "uOWWZNrNwms_0016.wav",
    "YT_mutaffifin": HDD_YT_BASE / "data" / "youtube_wav" / "s083_al_mutaffifin" / "LepYjjJKJk4_0006.wav",
    "YT_ghashiya": HDD_YT_BASE / "data" / "youtube_wav" / "s088_al_ghashiya" / "HGjfpcox47s_0005.wav",
    "YT_balad1": HDD_YT_BASE / "data" / "youtube_wav" / "s090_al_balad" / "-76NwqIBO20_0003.wav",
    "YT_balad2": HDD_YT_BASE / "data" / "youtube_wav" / "s090_al_balad" / "PlXaz9onniw_0004.wav",
    "YT_sharh": HDD_YT_BASE / "data" / "youtube_wav" / "s094_ash_sharh" / "rvHM0vYvUnY_0001.wav",
    "YT_tin": HDD_YT_BASE / "data" / "youtube_wav" / "s095_at_tin" / "0eyMtHBDDUE_0002.wav",
    "YT_qaria": HDD_YT_BASE / "data" / "youtube_wav" / "s101_al_qaria" / "5k1FKAi-6-E_0002.wav",
    "YT_takathur": HDD_YT_BASE / "data" / "youtube_wav" / "s102_at_takathur" / "0Rk-iaxZ6Nk_0002.wav",
    "YT_humaza": HDD_YT_BASE / "data" / "youtube_wav" / "s104_al_humaza" / "aur0tKeKDRM_0003.wav",
    "YT_maun": HDD_YT_BASE / "data" / "youtube_wav" / "s107_al_maun" / "l2w9VBTdcIo_0001.wav",
    "YT_falaq": HDD_YT_BASE / "data" / "youtube_wav" / "s113_al_falaq" / "MaOepE0iVP0_0001.wav",
    # Quelques recitateurs modernes "officiels" en complement (diversite
    # supplementaire, qualite haute-fidelite confirmee).
    "Alafasy": BASE_DIR / "data" / "train_wav" / "Alafasy_128kbps" / "53_14.wav",
    "Sudais": BASE_DIR / "data" / "train_wav" / "Abdurrahmaan_As-Sudais_192kbps" / "82_5.wav",
}
VOICES = [name for name, path in RECITER_REFS.items() if path.exists()]


def load_vocab():
    return list(json.load(open(WORD_TOKENS_PATH, encoding="utf-8")).keys())


def confusable_variants(word):
    out = []
    for src, dst in CONFUSABLE_PAIRS:
        if src in word:
            out.append((word.replace(src, dst, 1), f"{src}->{dst}"))
    return out


def harakat_variants(word, max_per_word=2):
    """Pour jusqu'a [max_per_word] positions de harakat courte, genere une
    variante avec une AUTRE harakat courte a cette position."""
    positions = [i for i, c in enumerate(word) if c in SHORT_HARAKAT]
    random.shuffle(positions)
    out = []
    for pos in positions[:max_per_word]:
        original = word[pos]
        alt = random.choice([h for h in SHORT_HARAKAT if h != original])
        variant = word[:pos] + alt + word[pos + 1:]
        out.append((variant, f"harakat@{pos}:{original}->{alt}"))
    return out


def build_plan(n_words, seed=7):
    vocab = load_vocab()
    random.seed(seed)
    random.shuffle(vocab)
    plan = []  # (correct_word, wrong_word, kind, detail)
    for w in vocab:
        if len(plan) >= n_words * 2:  # ~2 variantes/mot en moyenne visees
            break
        added = False
        for variant, detail in confusable_variants(w):
            plan.append((w, variant, "letter", detail))
            added = True
            break  # une seule variante lettre par mot, pour diversifier les mots couverts
        for variant, detail in harakat_variants(w, max_per_word=1):
            plan.append((w, variant, "harakat", detail))
            added = True
        if not added:
            continue
    return plan


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--test", action="store_true", help="~20 clips seulement, verifie le pipeline")
    p.add_argument("--n-words", type=int, default=500)
    p.add_argument("--voices", type=int, default=3, help="nb de voix par variante")
    args = p.parse_args()

    n_words = 8 if args.test else args.n_words

    plan = build_plan(n_words)
    # Repartition par PLAGE (demande utilisateur 2026-07-14 : "je prefere
    # plusieurs voix mais chaque voix dit une plage de mots" -- plutot que
    # de repeter le MEME mot sur 5 voix (peu d'info nouvelle par clip), une
    # seule voix par variante, mais la plage entiere (toutes les variantes)
    # decoupee en autant de tranches contigues que de voix disponibles :
    # couvre 5x plus de mots distincts pour le meme budget de clips, tout en
    # gardant plusieurs timbres sur l'ensemble du dataset genere.
    random.shuffle(plan)  # evite tout biais d'ordre (mots plus frequents en tete de vocab.json)
    n_v = len(VOICES)
    chunk = (len(plan) + n_v - 1) // n_v
    voice_assignment = []
    for idx in range(len(plan)):
        voice_assignment.append(VOICES[min(idx // chunk, n_v - 1)])

    print(f"Plan : {len(plan)} variantes (mots source cibles : {n_words}), "
          f"{n_v} voix, ~{chunk} variantes/voix -> {len(plan)} clips au total")

    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Chargement XTTS-v2 sur {device}...")
    tts = TTS("tts_models/multilingual/multi-dataset/xtts_v2").to(device)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    wav_dir = OUT_DIR / "wav"
    wav_dir.mkdir(exist_ok=True)

    done = 0
    t0 = time.time()
    with open(OUT_MANIFEST, "a", encoding="utf-8") as mf:
        for i, (correct, wrong, kind, detail) in enumerate(plan):
            v = voice_assignment[i]
            clip_name = f"tts_{i}.wav"
            out_path = wav_dir / clip_name
            try:
                tts.tts_to_file(text=wrong, file_path=str(out_path),
                                 speaker_wav=str(RECITER_REFS[v]), language="ar")
            except Exception as e:
                print(f"  [erreur] mot={wrong!r} voix={v}: {e}")
                continue
            mf.write(json.dumps({
                "clip": clip_name, "text": wrong, "correct_text": correct,
                "kind": kind, "detail": detail, "voice": v,
            }, ensure_ascii=False) + "\n")
            mf.flush()
            done += 1
            if (i + 1) % 50 == 0:
                elapsed = time.time() - t0
                rate = done / elapsed if elapsed > 0 else 0
                remaining = (len(plan) - done) / rate if rate > 0 else 0
                print(f"  {i+1}/{len(plan)} clips generes ({rate:.2f} clips/s, "
                      f"{elapsed/60:.1f}min ecoulees, ~{remaining/60:.1f}min restantes)")

    print(f"\nTermine : {done} clips generes dans {wav_dir}, manifest -> {OUT_MANIFEST}")


if __name__ == "__main__":
    main()
