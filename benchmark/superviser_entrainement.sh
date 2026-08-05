#!/bin/bash
# Relance un entrainement interrompu, aussi longtemps qu'il reste du travail.
#
# ── POURQUOI CE SCRIPT EXISTE (2026-08-05) ──────────────────────────────────
#
# Un run de 3 epoques sur 529,6 h est mort a 51 % de l'epoque 1 sur
# `cudaErrorLaunchTimeout` -- la carte graphique pilote aussi l'ecran, et un
# changement de son etat d'alimentation tue les noyaux CUDA en cours. Le
# processus a disparu, la machine est restee inactive six minutes, et c'est
# l'utilisateur qui l'a remarque, pas le systeme.
#
# CE QUE CE SCRIPT NE PRETEND PAS FAIRE. Il ne corrige PAS la cause. Trois
# faits ont ete etablis et aucun ne l'explique :
#   - l'ecran est branche sur la RTX 5080, qui calcule aussi -- vrai, mais
#     c'est le cas depuis toujours et cela n'avait jamais coupe un run ;
#   - rien cote systeme ne demandait de veille (idle-delay 0, verrouillage
#     desactive, aucun inhibiteur concurrent) ;
#   - la mort est instantanee : 13,19 it/s jusqu'au pas 13701, puis plus rien.
#     Ce n'est donc pas une ecriture de checkpoint qui bloque, ni une derive.
#
# CE QU'IL FAIT, ET POURQUOI C'EST LE BON NIVEAU. Faute de tenir la cause, on
# rend la panne SANS CONSEQUENCE : `last.ckpt` contient modele, optimiseur,
# planificateur et compteur de pas, donc une reprise ne perd que les minutes
# ecoulees depuis la derniere validation. Le seul cout reel d'une coupure
# etait le temps pendant lequel PERSONNE ne s'en apercevait -- c'est
# exactement ce que ce script supprime.
#
# ⚠️ IL NE BOUCLE PAS INDEFINIMENT. Un run qui meurt immediatement apres
# chaque relance signale un vrai defaut (donnees corrompues, memoire
# insuffisante, checkpoint illisible) : le relancer en boucle masquerait ce
# defaut et brulerait le GPU pour rien. Deux garde-fous :
#   - une reprise qui ne survit pas [MIN_VIE] secondes ne compte pas comme un
#     progres ;
#   - au-dela de [MAX_ECHECS] reprises steriles consecutives, on s'arrete et
#     on laisse la trace.
#
# Usage :
#   ./superviser_entrainement.sh <script_de_lancement> <journal> [sortie_ckpt]
set -u

LANCEUR="${1:?script de lancement attendu}"
JOURNAL="${2:?fichier de journal attendu}"
SORTIE="${3:-}"

MIN_VIE=300          # secondes : en deca, la reprise n'a rien produit
MAX_ECHECS=3
PAUSE=20             # laisse le pilote graphique se remettre avant de reprendre

echecs=0
tour=0
while :; do
  tour=$((tour + 1))
  debut=$(date +%s)
  echo "=== [superviseur] lancement #$tour a $(date '+%F %T') ===" >> "$JOURNAL"
  "$LANCEUR" >> "$JOURNAL" 2>&1
  code=$?
  duree=$(( $(date +%s) - debut ))

  if [ "$code" -eq 0 ]; then
    echo "=== [superviseur] termine normalement apres ${duree}s ===" >> "$JOURNAL"
    exit 0
  fi

  # `last.ckpt` est la seule preuve qu'un tour a servi a quelque chose : sans
  # lui, une reprise repartirait de zero et la boucle tournerait a vide.
  if [ -n "$SORTIE" ] && [ ! -f "$SORTIE/last.ckpt" ]; then
    echo "=== [superviseur] ARRET : aucun last.ckpt dans $SORTIE, une reprise" \
         "repartirait de zero ===" >> "$JOURNAL"
    exit 1
  fi

  if [ "$duree" -lt "$MIN_VIE" ]; then
    echecs=$((echecs + 1))
    echo "=== [superviseur] mort en ${duree}s (code $code) -- reprise sterile" \
         "$echecs/$MAX_ECHECS ===" >> "$JOURNAL"
    if [ "$echecs" -ge "$MAX_ECHECS" ]; then
      echo "=== [superviseur] ARRET : $MAX_ECHECS reprises sans progres." \
           "Ce n'est plus une coupure, c'est un defaut a diagnostiquer. ===" \
           >> "$JOURNAL"
      exit 1
    fi
  else
    # Le run a vecu : la coupure est un accident, pas un defaut permanent.
    echecs=0
    echo "=== [superviseur] coupure apres ${duree}s (code $code) -- reprise ===" \
         >> "$JOURNAL"
  fi
  sleep "$PAUSE"
done
