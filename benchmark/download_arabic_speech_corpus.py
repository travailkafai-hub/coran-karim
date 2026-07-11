"""
Télécharge et extrait l'Arabic Speech Corpus (Nawar Halabi, en.arabicspeechcorpus.com).
~1.8h de parole arabe, transcriptions en Buckwalter (avec diacritiques/harakat).
Corpus construit pour la synthèse vocale — texte entièrement vocalisé.

NB: ce n'est PAS "SLR61" d'OpenSLR (SLR61 = corpus espagnol argentin, erreur de
numéro identifiée en cours de route). Ce corpus est hébergé indépendamment.

URL: http://en.arabicspeechcorpus.com/
Sortie : benchmark/arabic_speech_corpus/
  arabic_speech_corpus/wav/                    ← fichiers WAV bruts (48 kHz probable)
  arabic_speech_corpus/orthographic-transcript.txt ← transcriptions Buckwalter brutes

Usage:
    "D:/Coran Karim/benchmark/.venv/Scripts/python.exe" -X utf8 download_arabic_speech_corpus.py
"""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
try:
    import truststore; truststore.inject_into_ssl()
except ImportError:
    pass

import sys, zipfile, shutil, time
from pathlib import Path
import requests

BASE_DIR  = Path(__file__).parent
OUT_DIR   = BASE_DIR / "arabic_speech_corpus"
WAV_DIR   = OUT_DIR / "wav"
ZIP_PATH  = OUT_DIR / "arabic-speech-corpus.zip"

CORPUS_URL = "http://en.arabicspeechcorpus.com/arabic-speech-corpus.zip"
MAX_RETRIES = 8

OUT_DIR.mkdir(parents=True, exist_ok=True)


def _download_attempt() -> int:
    """
    Télécharge en streaming avec reprise (Range) si un fichier partiel existe déjà.
    Retourne la taille totale attendue (déduite de la réponse HTTP elle-même,
    PAS d'un HEAD séparé — ce serveur ne renvoie pas toujours Content-Length sur HEAD).
    """
    resume_from = ZIP_PATH.stat().st_size if ZIP_PATH.exists() else 0
    headers = {"Range": f"bytes={resume_from}-"} if resume_from else {}
    mode = "ab" if resume_from else "wb"

    with requests.get(CORPUS_URL, headers=headers, stream=True, timeout=60) as r:
        r.raise_for_status()
        content_length = r.headers.get("Content-Length")
        # Content-Length sur une requête Range = octets RESTANTS, pas le total.
        total_size = (resume_from + int(content_length)) if content_length else 0

        downloaded = resume_from
        with open(ZIP_PATH, mode) as f:
            for chunk in r.iter_content(chunk_size=1024 * 1024):
                if not chunk:
                    continue
                f.write(chunk)
                downloaded += len(chunk)
                if total_size:
                    pct = downloaded / total_size * 100
                    print(f"\r  {pct:.1f}%  ({downloaded // 1024 // 1024}/{total_size // 1024 // 1024} Mo)",
                          end="", flush=True)
                else:
                    print(f"\r  {downloaded // 1024 // 1024} Mo téléchargés...", end="", flush=True)
    print()

    final_size = ZIP_PATH.stat().st_size
    if total_size and final_size < total_size:
        raise IOError(f"Téléchargement incomplet : {final_size} / {total_size} octets")
    return final_size


def download():
    print(f"Téléchargement de {CORPUS_URL}")
    print(f"  → {ZIP_PATH}")

    prev_size = -1
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            _download_attempt()
            break
        except Exception as e:
            cur_size = ZIP_PATH.stat().st_size if ZIP_PATH.exists() else 0
            print(f"\n  [Tentative {attempt}/{MAX_RETRIES}] échec : {e}  (fichier partiel: {cur_size} octets)")
            if attempt == MAX_RETRIES:
                raise
            if cur_size == prev_size:
                # Aucune progression depuis la dernière tentative : le serveur ne
                # supporte peut-être pas Range correctement -> repartir de zéro.
                print("  Aucune progression — on repart de zéro.")
                ZIP_PATH.unlink(missing_ok=True)
            prev_size = cur_size
            time.sleep(5)
            print("  Reprise du téléchargement...")

    size_mb = ZIP_PATH.stat().st_size // 1024 // 1024
    print(f"  OK — {size_mb} Mo.")
    if size_mb < 1:
        raise RuntimeError(f"Zip suspect ({size_mb} Mo) — vérifier l'URL / le contenu téléchargé.")


def extract():
    if WAV_DIR.exists() and any(WAV_DIR.glob("*.wav")):
        print(f"WAV déjà extraits dans {WAV_DIR} — skip extraction.")
        return
    print(f"Extraction de {ZIP_PATH}...")
    with zipfile.ZipFile(ZIP_PATH) as zf:
        members = zf.namelist()
        print(f"  {len(members)} fichiers dans l'archive.")
        zf.extractall(OUT_DIR)

    # L'archive peut mettre le contenu dans un sous-dossier — remonter à plat
    subdirs = [p for p in OUT_DIR.iterdir() if p.is_dir() and p.name not in ("wav",)]
    for sd in subdirs:
        wav_sub = sd / "wav"
        if wav_sub.exists():
            if not WAV_DIR.exists():
                shutil.move(str(wav_sub), str(WAV_DIR))
            else:
                for wf in wav_sub.glob("*.wav"):
                    shutil.move(str(wf), str(WAV_DIR / wf.name))
        for pattern in ("*.txt", "*.TextGrid"):
            for f in sd.rglob(pattern):
                dest = OUT_DIR / f.name
                if not dest.exists():
                    shutil.move(str(f), str(dest))
    print(f"  Terminé.")


def main():
    download()
    extract()

    n_wav = len(list(WAV_DIR.glob("*.wav"))) if WAV_DIR.exists() else 0
    print(f"\nFichiers WAV : {n_wav}")

    print(f"\nContenu de {OUT_DIR} (premier niveau) :")
    for p in sorted(OUT_DIR.iterdir()):
        print(f"  {p.name}")

    if n_wav == 0:
        print("\nERREUR: aucun WAV trouvé après extraction. Inspecter le contenu ci-dessus.")
        sys.exit(1)

    txt_files = list(OUT_DIR.glob("*.txt"))
    print(f"\nFichiers texte trouvés : {[f.name for f in txt_files]}")

    print("\nCorpus téléchargé et extrait.")
    print("Étape suivante : python prepare_arabic_speech_corpus_manifest.py")


if __name__ == "__main__":
    main()
