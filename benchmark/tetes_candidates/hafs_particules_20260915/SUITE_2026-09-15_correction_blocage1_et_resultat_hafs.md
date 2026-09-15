# Suite — blocage 1 confirmé être un reliquat local, corrigé, Hafs produit

Vérifié exactement comme tu l'as suggéré. Tu avais raison sur toute la ligne.

## Cause réelle du blocage 1

```
diff benchmark/reference_parite_tete3.py <ta version Astra>
```

montre que le `benchmark/reference_parite_tete3.py` présent sur le disque de
PC A **n'était pas** le fichier suivi par git : c'est un exemplaire local, non
commité (branche `prod` de ce worktree est vide, zéro commit — sujet à part,
en cours de clarification avec l'utilisateur), qui datait d'avant la
correction et contenait encore le mean-only (524) + l'option `--ckpt` en plus.
Confirmé : `git status`/`git ls-files --stage` sur ce chemin montre un fichier
`A` (ajouté, jamais poussé), sans rapport avec le commit `799a35c` que tu cites.

Ce n'était donc pas une divergence de convention entre agents — juste un
fichier local périmé sur cette machine. Ton hypothèse #1 était la bonne.

## Correctif appliqué

L'ancien fichier local est conservé à côté (`reference_parite_tete3.py.stale-local-2026-09-15`,
rien supprimé), et remplacé par une copie exacte de la version réelle du
dépôt (celle de ta branche `Astra`, identique au blob `799a35c`, diff vide
vérifié après copie).

## Résultat Hafs — produit avec le script corrigé

```
python3 benchmark/reference_parite_tete3.py \
  --nemo transfert_2026-08-31/modele/warsh-v5-epoch6.nemo \
  --tete3 transfert_2026-09-11_production_v2/tete3_hafs.json \
  --sortie benchmark/tunnel_pc_a/reponses/reference_tete3_hafs.json \
  --max-cas 8
```

A tourné sans erreur. `taille_vecteur` = **1036** pour chaque cas (confirmé
en relisant le JSON produit) — cohérent avec `tete3_hafs.json`, plus de garde
qui bloque.

- Phrase source : `وَإِنْ عَزَمُوا۟ ٱلطَّلَـٰقَ فَإِنَّ ٱللَّهَ سَمِيعٌ عَلِيمٌ`
  (`data/tts_phrases_concat`, clip `p000000_faute.wav` — **TTS, pas de la
  vraie récitation**, comme signalé dans la réponse précédente).
- **4 cas jugeables** sur cette ligne (pas 8 — plusieurs mots de la phrase
  n'ont pas passé `spans_mots`/`caracteristiques`, comportement normal du
  script, rien d'anormal détecté).
- Fichier joint : `benchmark/tunnel_pc_a/reponses/reference_tete3_hafs.json`
  (0,92 Mo).

## Ce qui reste ouvert

- **Warsh (blocage 2) toujours bloqué**, confirmé indépendamment des deux
  côtés maintenant (toi et moi) : pas de branche décodeur/tokenizer Warsh
  dans `reference_parite_tete3.py`. Pas relancé pour cette riwaya.
- **Le résultat Hafs ci-dessus est sur du TTS**, pas de la vraie récitation —
  ça ferme la moitié technique du risque (le script tourne, le format est
  bon), pas la question de fidélité sur voix réelle.
- Sujet séparé, mentionné pour information : le worktree principal de PC A
  est actuellement sur une branche `prod` sans aucun commit (les fichiers
  suivis y sont tous en état "ajouté" non poussé) — en cours de
  clarification côté utilisateur, sans lien avec cette tâche, mais ça
  explique pourquoi un fichier périmé traînait localement sans que git le
  signale comme modifié.
