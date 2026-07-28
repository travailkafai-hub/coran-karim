#!/usr/bin/env bash
# Pilote adb DISTANT : les telephones sont branches sur le PC B, pas ici.
#
#   ./benchmark/adb_pcb.sh -s <serial> shell ...      -> commande adb
#   ./benchmark/adb_pcb.sh RECUP <serial> <dist> <local>  -> pull + rapatriement
#
# POURQUOI PAS `adb -H`. Le serveur adb du PC B a bien ete mis en ecoute
# (0.0.0.0:5037) et un tunnel SSH l'atteint, mais le client repond
# « protocol fault (couldn't read status) » -- y compris apres avoir aligne les
# versions (34.0.5 ici, 36.0.2 la-bas, testees identiques). On ne s'acharne pas :
# SSH marche, et adb execute SUR le PC B marche. On compose les deux.
#
# POURQUOI UN RAPATRIEMENT SEPARE. Faire transiter du binaire (WAV, tar) par la
# sortie standard de SSH depuis un Windows expose a une traduction CRLF qui
# corrompt silencieusement les fichiers -- un WAV corrompu ne se voit qu'a
# l'analyse, quand il est trop tard. On telecharge donc sur le disque du PC B,
# puis on rapatrie par scp, qui est binaire.
set -uo pipefail

PCB="${PCB:-kafai@100.126.49.93}"
ADB='C:\Users\kafai\platform-tools\adb.exe'
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=15
          -o LogLevel=ERROR)

if [ "${1:-}" = "RECUP" ]; then
  serial="$2"; dist="$3"; local="$4"
  tmp="C:\\Temp\\recup_$$"
  ssh "${SSH_OPTS[@]}" "$PCB" "mkdir \"$tmp\" 2>nul & $ADB -s $serial pull \"$dist\" \"$tmp\"" >/dev/null 2>&1
  mkdir -p "$local"
  scp "${SSH_OPTS[@]}" -q -r "$PCB:$tmp/*" "$local/" 2>/dev/null
  ssh "${SSH_OPTS[@]}" "$PCB" "rmdir /s /q \"$tmp\"" >/dev/null 2>&1
  exit 0
fi

# Les arguments sont ré-échappés UN PAR UN : sans ça, cmd.exe interprete les
# redirections (`<`, `>`) et les pipes de la commande shell Android comme les
# siennes, et la commande part vide sans le moindre message. Constate sur
# `adb shell "wc -l < /sdcard/..."`, qui ne rendait rien.
cmd=""
for a in "$@"; do
  case "$a" in
    *[!A-Za-z0-9_/.:=-]*) cmd="$cmd \"$a\"" ;;
    *) cmd="$cmd $a" ;;
  esac
done
ssh "${SSH_OPTS[@]}" "$PCB" "$ADB$cmd" 2>/dev/null | tr -d '\r'
