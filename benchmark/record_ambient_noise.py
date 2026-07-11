"""
Capture du bruit ambiant réel via le microphone.

Usage:
  python record_ambient_noise.py [clips] [duration_s]
    clips       : nombre de clips à enregistrer (défaut: 20)
    duration_s  : durée de chaque clip en secondes (défaut: 30)

Résultat:
  - Clips WAV 16kHz mono dans data/ambient_noise/
  - Mise à jour de noise_augment.py pour utiliser ces clips réels

Instructions:
  1. Lance ce script
  2. Place le micro dans l'environnement que tu veux capturer
     (pièce calme, rue, mosquée, salon TV allumée...)
  3. Appuie sur Entrée entre chaque clip pour changer d'environnement
  4. Les clips seront utilisés automatiquement dans l'entraînement Phase 4
"""
import sys, os, time, json
import numpy as np
import soundfile as sf

try:
    import sounddevice as sd
except ImportError:
    print("sounddevice non installé. Installe-le avec :")
    print("  pip install sounddevice")
    sys.exit(1)

ROOT     = os.path.dirname(os.path.abspath(__file__))
OUT_DIR  = os.path.join(ROOT, "data", "ambient_noise")
MANIFEST = os.path.join(ROOT, "data", "manifest_ambient.jsonl")
os.makedirs(OUT_DIR, exist_ok=True)

N_CLIPS   = int(sys.argv[1]) if len(sys.argv) > 1 else 20
DURATION  = int(sys.argv[2]) if len(sys.argv) > 2 else 30
SR        = 16000

# Labels d'environnement pour varier les bruit
ENVIRONMENTS = [
    "salon_silence",    # salon calme
    "salon_tv",         # TV en fond
    "cuisine",          # cuisine (frigo, hotte)
    "rue_passage",      # rue peu passante
    "rue_trafic",       # trafic dense
    "mosquee_attente",  # mosquée avant prière
    "bureau_climatiseur",# bureau avec clim
    "transport",        # bus/metro
]

def list_devices():
    print("\nDisponibles :")
    print(sd.query_devices())
    print()

def record_clip(env_label: str, clip_num: int, duration: int) -> str | None:
    fname = f"{env_label}_{clip_num:03d}.wav"
    fpath = os.path.join(OUT_DIR, fname)

    if os.path.exists(fpath):
        print(f"  Clip existe déjà : {fname}, skipping")
        return fpath

    print(f"\n--- Clip {clip_num} : {env_label} ({duration}s) ---")
    input("  Appuie sur Entrée pour commencer l'enregistrement...")
    print(f"  Enregistrement en cours... ({duration}s)")

    try:
        audio = sd.rec(
            int(duration * SR),
            samplerate=SR,
            channels=1,
            dtype='float32',
        )
        sd.wait()
        audio = audio.flatten()

        # Normalise légèrement pour éviter le silence total
        rms = float(np.sqrt(np.mean(audio ** 2)))
        print(f"  RMS bruit : {rms:.5f} ({20*np.log10(rms+1e-9):.1f} dB)")
        if rms < 1e-5:
            print("  ATTENTION : signal très faible, vérifie le micro !")

        sf.write(fpath, audio, SR, subtype='PCM_16')
        print(f"  Sauvegardé : {fname}")
        return fpath
    except Exception as e:
        print(f"  Erreur : {e}")
        return None

def main():
    print("=== Capture de bruit ambiant réel ===")
    print(f"  Objectif : {N_CLIPS} clips × {DURATION}s à 16kHz mono")
    print(f"  Sortie   : {OUT_DIR}")

    # Affiche les périphériques
    try:
        default_dev = sd.query_devices(kind='input')
        print(f"\nMicro sélectionné : {default_dev['name']}")
    except Exception:
        list_devices()
        return

    # Charge les clips déjà enregistrés
    existing = []
    if os.path.exists(MANIFEST):
        for l in open(MANIFEST, encoding="utf-8"):
            existing.append(json.loads(l))
    already_done = len(existing)
    print(f"\n{already_done} clips déjà enregistrés.")

    rows = list(existing)
    clip_idx = already_done

    print(f"\nEnvironnements suggérés :")
    for i, e in enumerate(ENVIRONMENTS):
        print(f"  {i+1}. {e.replace('_', ' ')}")

    for i in range(N_CLIPS - already_done):
        print(f"\n[{clip_idx + 1}/{N_CLIPS}]")
        print("Quel environnement ? (entrer le numéro ou un label libre)")
        for j, e in enumerate(ENVIRONMENTS):
            print(f"  {j+1}. {e}")
        choice = input("  Choix [1-8 ou label] : ").strip()

        if choice.isdigit() and 1 <= int(choice) <= len(ENVIRONMENTS):
            env = ENVIRONMENTS[int(choice) - 1]
        elif choice:
            env = choice.replace(' ', '_').lower()
        else:
            env = 'inconnu'

        fpath = record_clip(env, clip_idx, DURATION)
        if fpath:
            row = {
                "audio": os.path.relpath(fpath, ROOT).replace("\\", "/"),
                "environment": env,
                "duration_s": DURATION,
                "sr": SR,
            }
            rows.append(row)
            clip_idx += 1

            # Sauvegarde immédiate
            with open(MANIFEST, "w", encoding="utf-8") as f:
                for r in rows:
                    f.write(json.dumps(r, ensure_ascii=False) + "\n")

        cont = input("\nContinuer ? [Entrée = oui / n = arrêter] : ").strip()
        if cont.lower() == 'n':
            break

    print(f"\n=== DONE — {len(rows)} clips dans {MANIFEST} ===")
    print("\nPour utiliser dans l'entraînement : le module noise_augment.py")
    print("chargera automatiquement ces clips si manifest_ambient.jsonl existe.")

if __name__ == "__main__":
    main()
