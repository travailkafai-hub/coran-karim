#!/usr/bin/env bash
# Recette de la chaine v2 sur UN SEUL telephone, a partir d'un WAV.
#
# ── POURQUOI CE SCRIPT EXISTE (2026-08-21) ────────────────────────────────────
# `recette_2tel.sh` reste la recette de reference : un telephone joue le
# recitateur, l'autre ecoute au micro -- c'est la seule facon de mesurer la
# CHAINE COMPLETE, capture acoustique comprise. Mais elle exige deux appareils
# branches en meme temps, ce qui n'est pas toujours le cas.
#
# Ce script-ci mesure la MEME chaine v2 sur le MEME modele, mais en rejouant un
# WAV deterministe au lieu de passer par le micro. MODE `ecoute` ET NON `v2`
# les deux prennent le WAV comme source deterministe (`wavRejoue`), mais seul
# `ecoute` porte `autoDemarrer: true` et OUVRE la recitation. Avec `v2`,
# l'ecran s'ouvre et ATTEND : rien ne se lance. Piege paye le 2026-08-21.
#
# ── CE QU'IL MESURE, ET CE QU'IL NE MESURE PAS ────────────────────────────────
# MESURE  : decodage, alignement force, fenetrage, fusion, decision -- tout ce
#           qui produit un verdict a partir de logprobs.
# NE MESURE PAS : le micro, le portier RMS, le bruit de la piece, la distance
#           au telephone. Un chiffre obtenu ici n'est donc PAS comparable a
#           celui de `recette_2tel.sh` : il est structurellement meilleur,
#           puisque l'audio est parfait. Il sert a comparer DEUX VERSIONS DU
#           CODE entre elles, jamais a annoncer la qualite percue.
#
# ── USAGE ─────────────────────────────────────────────────────────────────────
#   ./benchmark/recette_1tel_v2.sh [sourate] [versets] [serial]
#   ./benchmark/recette_1tel_v2.sh 2 20
#
# Le WAV est fabrique en concatenant les versets d'Al-Afasy deja presents dans
# `benchmark/data/train_wav_local/Alafasy_mp3quran/` -- aucune dependance
# reseau, et le meme audio d'une passe a l'autre, ce qui est tout l'interet.
set -euo pipefail

SOURATE="${1:-2}"
VERSETS="${2:-20}"
#  a la racine puis chemins RELATIFS : sous Git Bash, $(pwd) rend un
# chemin de la forme /c/Users/... que le Python de Windows ne sait pas ouvrir.
# Le passer tel quel a python3 faisait echouer la recherche des versets avec un
# message trompeur ("aucun verset trouve") alors que les 6 236 fichiers etaient
# bien la.
cd "$(dirname "$0")/.."
RACINE="."
ADB="${ADB:-adb}"
SERIAL="${3:-}"
[ -n "$SERIAL" ] && ADB="$ADB -s $SERIAL"

PKG=com.corankarim.coran_karim
SRC="$RACINE/benchmark/data/train_wav_local/Alafasy_mp3quran"
HORO="$(date +%Y%m%d-%H%M%S)"
SORTIE="$RACINE/benchmark/recettes/${HORO}-s${SOURATE}-1tel"
mkdir -p "$SORTIE"
WAV="$SORTIE/audio.wav"

mort() { echo "❌ $*" >&2; exit 1; }

# ── 1. le WAV, fabrique localement ────────────────────────────────────────────
[ -d "$SRC" ] || mort "audio de reference absent : $SRC"
python3 - "$SRC" "$SOURATE" "$VERSETS" "$WAV" <<'PY'
import sys, wave, os
src, sourate, n, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
fichiers = [f"{src}/{sourate}_{i}.wav" for i in range(1, n + 1)]
fichiers = [f for f in fichiers if os.path.exists(f)]
if not fichiers:
    raise SystemExit(f"aucun verset trouve pour la sourate {sourate}")
w0 = wave.open(fichiers[0]); p = w0.getparams(); w0.close()
o = wave.open(out, 'wb'); o.setparams(p)
total = 0
for f in fichiers:
    w = wave.open(f); o.writeframes(w.readframes(w.getnframes()))
    total += w.getnframes(); w.close()
o.close()
print(f"  {len(fichiers)} versets, {total/p.framerate:.1f} s")
PY

# ── 2. sur l'appareil ─────────────────────────────────────────────────────────
$ADB get-state >/dev/null 2>&1 || mort "aucun appareil (adb devices)"
# ── LE WAV VA DANS LE DOSSIER DE L APP, PAS DANS Download (2026-08-21) ──────
# Depuis Android 11, une app sans MANAGE_EXTERNAL_STORAGE ne lit QUE son propre
# repertoire. Depuis /sdcard/Download, la source deterministe est bien prise,
# la chaine v2 bien activee -- et le flux meurt aussitot :
#   [ASR] SOURCE DETERMINISTE : /sdcard/Download/recette_v2.wav
#   [ASR] Erreur sur le flux PCM : PathAccessException: Permission denied
# Zero verdict, sans que rien d autre ne le signale. Le dossier ci-dessous est
# accessible par adb push ET lisible par l app : c est celui ou le modele est
# deja deploye.
DIST=/sdcard/Android/data/$PKG/files/recette_v2.wav
$ADB push "$WAV" "$DIST" >/dev/null || mort "push du WAV impossible"

JOURNAL=/sdcard/Android/data/$PKG/files/recitation_diagnostic.log
$ADB shell "echo '' >> $JOURNAL" 2>/dev/null || true
MARQUE="RECETTE-1TEL-$HORO"
$ADB shell "echo '=== $MARQUE ===' >> $JOURNAL" 2>/dev/null || true

# -- REVEILLER ET DEVERROUILLER, SINON RIEN NE DEMARRE (2026-08-22) --------
# Telephone verrouille : l activite se lance, l ecran de recitation s affiche
# bien... et reste sur "Touche l ecran pour commencer". autoDemarrer ne prend
# pas derriere l ecran de verrouillage. Le journal s arrete alors juste apres
# "fichier natif relie", sans une seule ligne d erreur -- on croit a un
# probleme de modele. Deux commandes suffisent, et elles sont sans effet si
# le telephone est deja reveille.
$ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB shell wm dismiss-keyguard >/dev/null 2>&1 || true

$ADB shell am force-stop $PKG
$ADB shell am start -n $PKG/.MainActivity \
    --es recette ecoute --es wav "$DIST" \
    --ei sourate "$SOURATE" --ei versets "$VERSETS" >/dev/null

echo "  ecoute lancee (auto-demarrage) -- attente de la fin de session"
# Le banc rejoue tout l'audio dans la chaine : compter sur la ligne finale
# plutot que sur une duree, qui dependrait de la machine et du modele.
for _ in $(seq 1 120); do
    if $ADB shell "tail -c 200000 $JOURNAL" 2>/dev/null | sed -n "/$MARQUE/," | grep -qa "session fermee"; then
        break
    fi
    sleep 5
done

$ADB pull "$JOURNAL" "$SORTIE/full.log" >/dev/null 2>&1 || mort "journal illisible"

# ── 3. le chiffre ─────────────────────────────────────────────────────────────
python3 - "$SORTIE/full.log" "$SORTIE/resume.txt" "$SOURATE" "$VERSETS" "$MARQUE" <<'PY'
import io, re, sys
log, out, sourate, versets = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
L = io.open(log, encoding='utf-8', errors='replace').read().splitlines()
# On part de la MARQUE posee juste avant le lancement : le journal contient
# les sessions precedentes, et chercher un motif dans tout le fichier fait
# analyser une passe qui n est pas la notre. Piege paye le 2026-08-21.
marque = sys.argv[5] if len(sys.argv) > 5 else None
deb = None
if marque:
    deb = max((i for i, l in enumerate(L) if marque in l), default=None)
if deb is None:
    deb = max((i for i, l in enumerate(L) if 'RECETTE' in l and 'ECOUTE' in l), default=None)
if deb is None:
    raise SystemExit("le banc n'a rien ecrit -- le WAV n'a pas ete pris comme source")
S = L[deb:]
lignes = [l for l in S if 'PARAMS] cible=' in l or 'RECETTE' in l]

verdicts = {}
for l in S:
    m = re.search(r'mot=(\d+) "([^"]*)" -> ([a-z:]+)', l)
    if m:
        verdicts[int(m.group(1))] = (m.group(2), m.group(3))

r = []
r.append(f"sourate={sourate} versets={versets} (banc v2, UN telephone, WAV deterministe)")
for l in lignes[:12]:
    r.append('  ' + l.split('] ', 1)[-1])
if verdicts:
    # Denominateur = ANCRE MAX, jamais le nombre de mots juges : un mot saute
    # doit compter comme non vert, sinon plus le fenetrage casse, meilleur le
    # taux parait (regle du projet, mesuree le 2026-07-29).
    ancre = max(verdicts) + 1
    signales = [k for k, v in verdicts.items() if not v[1].endswith('vert')]
    # LE COMMENTAIRE CI-DESSUS L EXIGEAIT, LE CODE NE LE FAISAIT PAS (2026-08-22)
    # `signales` ne voit que les mots QUI ONT UN VERDICT. Un mot saute n a
    # AUCUNE ligne : il restait au denominateur sans jamais compter au
    # numerateur, si bien que chaque mot perdu par le fenetrage FAISAIT BAISSER
    # le taux. C est precisement l erreur que la regle du projet nomme et que
    # ce commentaire pretendait avoir evitee. Mesure du 2026-08-22 : 2 non verts
    # signales et 2 mots jamais juges -> 0,9 % annonce contre 1,7 % reel.
    manquants = [k for k in range(ancre) if k not in verdicts]
    nv = len(signales) + len(manquants)
    r.append("")
    r.append(f"mots juges = {len(verdicts)} / ancre max = {ancre}")
    r.append(f"  signales non verts = {len(signales)}")
    r.append(f"  jamais juges       = {len(manquants)}  {manquants[:15]}")
    r.append(f"NON VERTS  = {nv}  soit {100*nv/ancre:.1f} % de l'ancre")
else:
    r.append("")
    r.append("aucun verdict par mot dans le journal")
txt = '\n'.join(r)
io.open(out, 'w', encoding='utf-8').write(txt + '\n')
print(txt)
PY

echo
echo "  -> $SORTIE"
