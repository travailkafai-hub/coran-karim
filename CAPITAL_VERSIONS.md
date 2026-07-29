# Capital des versions v1 → v23 — ce qui est pris, ce qui attend, ce qui est mort

Écrit le 2026-07-29 en construisant la v24. **Rien de ce qui a été essayé ne doit
disparaître** : plusieurs idées sans valeur ajoutée aujourd'hui en auront quand
le contexte aura changé (autre modèle, autre longueur de session, récitation
humaine plutôt qu'un enregistrement rejoué).

Ce document est l'inventaire. Il se lit **avant** de rouvrir un sujet, pour ne
pas repayer une mesure déjà faite.

Méthode : inventaire construit depuis `git show <sha>` et les messages de
commit, jamais de mémoire (cf. `.claude/skills/consolider-versions/SKILL.md`).

---

## 1. CE QUE LA v24 PREND — un seul changement

| apport | commit | mesure |
|---|---|---|
| **`RESYNC_ACTIF = false`** — le resync ne déplace plus l'ancre | v23 `41df3e3` | **8,16 % → 6,12 %**, et corrélation parfaite resync↔décrochage sur 5 sessions |

**Un seul**, délibérément : empiler deux changements avant de mesurer rend le
résultat ininterprétable — c'est ce qui a produit treize versions dont aucune
n'est concluante.

## 2. CE QUE LA BASE (HEAD = v8) CONTIENT DÉJÀ

Vérifié par `grep` sur le blob git, pas de mémoire.

| apport | commit | ce qu'il fait |
|---|---|---|
| secours aligné **avec ses voisins** | v2 `44305da` | la cible du secours devient tous les mots que la fenêtre couvre, plus un mot isolé. Mesure : secours rattrapés 6/17 → 18/25 |
| secours voit les mots **tronqués** | v3 `a97867f` | `expectedText` remonte au natif ; déclenche sur `actual × 3 < expected`. Mesure : rouges quasi disparus, 0 sur 5 des 6 dernières passes |
| **retrait du palliatif** de proportion | v4 `8507b0e` | on ne déplace pas le critère d'acceptation (règle projet) |
| contexte des **deux côtés** + détection de dérive | v8 `363a3a1` | `RIGHT_CONTEXT_SECONDS = 2f`, `ancreALaDerive` |
| horodatage et fenêtre de secours | `10dd819` | `wordStamps`, `horodater`, `fenetreDeRecherche`, `secoursMeilleur` |
| gel **hors du thread audio** | `10dd819` | corrige un blocage du transport (383 ms mesurés). Trous de traitement **3,3/100 s → 0,2/100 s** |
| clips sans duplication | `10dd819` | avant : chaque `conserve` écrit deux fois, clips 319 s pour 310 s de flux brut |

## 3. EN ATTENTE — non mesuré ou non gagnant, à ne PAS jeter

Ces apports existent dans l'historique et sont récupérables par `git show`.
Ils n'entrent pas dans la v24 parce qu'aucune mesure ne les soutient
**aujourd'hui** — pas parce qu'ils sont mauvais.

| apport | commit | ce que dit sa mesure | quand le rouvrir |
|---|---|---|---|
| contexte droit **aussi à la DP** | v10 `6ae0884` | *« Non mesuré sur device »* (le poste portant les téléphones était injoignable) | dès qu'on retouche au contexte : c'est la seule pièce jamais évaluée sur device |
| borne droite de coupe (`targetOffset + radius`) | v11 `f2d61bc` | rend la coupe indépendante de l'ordonnancement — *« CE QUE ÇA NE FAIT PAS : baisser le taux »* (7,0/4,2/4,0 contre 2,8/3,9/5,3) | si un jour la **reproductibilité** du banc devient le problème plutôt que le taux |
| secours étendu aux mots amont (`cibleEtendue`) | v16 `6d07754` | déclenché **1 fois sur 15** mots non verts ; Maryam 15,46 % contre 14,58 % — aucun gain démontrable | si le secours devient le goulot, ou sur un modèle qui aligne mieux |
| coupe **à une fin de mot connue** | v16 `6d07754` | *« 47,4 % des coupes tombaient en plein mot »* ; blancs CTC 45,5 % → 27,3 % en simulation | quand on rouvrira la coupe en plein mot — c'est la piste la plus étayée du lot |
| `MAX_SILENCE_SAMPLES` 0,3 s → 0,9 s | v16 `6d07754` | endroits où couper 12 → 11 ; silence total **8,9 s → 3,6 s (−60 %)** | si le portier RMS revient sur la table |
| resync comparant du **texte** | v18 `4606d64` | Maryam **15,46 % → 9,18 %**, rouges 10 → 6 | **le jour où le rattrapage est reconçu** — sans objet tant que `RESYNC_ACTIF = false` |
| anneau de secours **30 s → 120 s** | testé le 2026-07-29, non commité | `secours IMPOSSIBLE` 6 → **0** alors que l'écart atteignait 79,7 s. Mais décrochage inchangé (41,83 % / 49,34 %) → **réfuté comme cause** | si le secours doit un jour atteindre des mots anciens (sessions longues, rattrapage a posteriori). Coût mémoire : 1,9 → 7,7 Mo, négligeable |

## 4. MORT — mesuré perdant, ne pas réintroduire sans cause nouvelle

| tentative | commit | mesure qui la condamne |
|---|---|---|
| rayon de coupe 2 s | v13 `36c03d0` | *« la variance REVIENT »* : 4,2/9,9/3,7 contre 7,0/4,2/4,0. Annulé le jour même, laissé en commentaire |
| resync arbitré par score, sur **aperçu** | v22 `305db63` | **8,16 % → 13,40 %** ; a sauté les mots 46 à 54 que v21 jugeait VERTS. Annulé par `69de15a` |
| relâchement de la règle de proportion | `a54cfe2` | palliatif : un récitateur ne disant que la moitié d'un mot était validé. Retiré le jour même (`8507b0e`) |
| sonde de 4 lettres | v19, non commité | 9,18 % → 17,89 % |
| garde de frontière (`conserve=0`) | testé le 2026-07-29, non commité | corrélation r = 0,67 sur 45 sessions, séparation sans chevauchement — et **l'intervention l'a réfutée** : `conserve=0` ramené de 89 % à 11 %, décrochage inchangé. Corrélation ≠ causalité |

## 5. PERDU — mesuré, jamais commité

Signalé par `41df3e3` : **neuf versions mesurées n'ont jamais été commitées**
(v5, v5b, v6, v12, v15, v17, v19, v20). Dont :

> **`v5b-derive` est le MEILLEUR résultat du projet — médiane 0,57 %, une passe
> à 0,00 %.**

Le code est irrécupérable (construit depuis l'arbre de travail, écrasé ensuite).
Il reste sa mesure, qui prouve qu'un taux sous 1 % est atteignable — l'objectif
du projet — et qu'aucune version commitée n'y est parvenue.

## 6. CHANTIERS OUVERTS, hors périmètre v24

- **Suivre un récitateur qui RÉPÈTE** (`FONCTIONNALITES_FUTURES.md`, `6dc9759`).
  `findResyncOffset` ne cherche qu'en avant ; répéter un passage est licite et
  courant, l'app ne peut structurellement pas suivre. Demande son propre
  protocole : le banc rejoue un audio linéaire et ne peut pas produire ce cas.
- **Désaccord waqf** : le modèle émet `▁ۖ ▁ۗ ▁ۚ` (26 occurrences sur une seule
  session), `splitExpectedWords` les filtre depuis le 2026-07-06. Décalage non
  déterministe, latent, sans effet démontré sur le décrochage. À corriger côté
  app — jamais par un réentraînement, le vocabulaire les contient déjà.
- **`arbitrer_resync.py`** mesure un gain sans son coût (les mots abandonnés par
  un déplacement d'ancre). Ses prédictions ne valent rien tant qu'il n'est pas
  corrigé.
