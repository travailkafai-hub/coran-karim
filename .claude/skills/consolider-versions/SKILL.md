---
name: consolider-versions
description: Regrouper les optimisations éparpillées dans plusieurs versions/commits en UNE version cohérente, sans jamais se fier à la mémoire — chaque affirmation doit être vérifiée dans le code au moment où on l'écrit. À invoquer dès qu'on parle de « fusionner les versions », « garder ce qui marche », « remettre à plat », ou qu'on hésite sur ce que contient une version.
---

# Consolider plusieurs versions en une seule

Ce skill existe parce que le 2026-07-29, treize versions de la chaîne de
récitation (v1 → v23) ont été créées en deux jours, chacune portant une ou deux
optimisations réelles, **sans qu'aucune ne les contienne toutes**. Et parce que
ce jour-là l'agent a affirmé au moins quatre fois depuis sa mémoire des choses
que le code contredisait :

| affirmé de mémoire | ce que disait le code |
|---|---|
| « le modèle déployé est dual-head » | `_kModelSubdir = "models/fastconformer-ctc-causal-v1"` |
| « la DP a échoué à placer le mot » | le message ne teste que la place en frames, jamais la présence |
| « l'anneau est trop petit » | 30 s, et la fenêtre demandée tenait dedans — c'était le calcul de position |
| « conserve=0 cause le décrochage » | corrélation r=0,67, mais l'intervention l'a réfuté |

Chacune a coûté entre vingt minutes et deux heures.

## Règle n°1 — LA MÉMOIRE N'EST PAS UNE SOURCE

**Interdit** d'écrire une affirmation technique sans l'avoir vérifiée dans le
code **au cours du tour où on l'écrit**. Pas « je l'ai lu tout à l'heure », pas
« c'était comme ça dans la version d'avant ».

Sont concernés, sans exception :

- le nom d'un modèle, d'un fichier, d'un dossier, d'une constante ;
- la valeur d'un seuil, d'une durée, d'une taille ;
- ce que fait une fonction, ce qu'elle retourne, qui l'appelle ;
- ce qu'une version contient ou ne contient pas ;
- l'état d'un fichier après un `git checkout` (le balayage en greffe treize).

**Le piège spécifique de ce projet** : `balayage_versions.sh` remplace en
permanence `BufferedTranscriber.kt`, `ForcedAligner.kt` et
`recitation_provider.dart` par la version d'un autre commit. Le fichier qu'on a
lu il y a dix minutes **n'est probablement plus le même**. Toujours relire.

Formulation à employer quand la vérification n'a pas été faite : « je ne l'ai
pas vérifié » — jamais une affirmation au conditionnel qui se lira comme un
fait dans le compte rendu suivant.

## Règle n°2 — Un inventaire se construit depuis git, pas depuis le fil

Avant toute consolidation, produire le tableau des versions **en lisant les
diffs**, pas en se souvenant des commits :

```bash
# ce que CHAQUE version a réellement changé, fichier par fichier
git log --format="%h %ad %s" --date=format:'%m-%d %H:%M' <base>..<tête>
git diff <v_n-1> <v_n> -- <les fichiers de la chaîne>
```

Livrable : `version | commit | ce qu'elle ajoute | mesure associée | statut`.
Une ligne sans mesure est une optimisation **supposée**, à traiter comme telle.

Le statut ne peut prendre que trois valeurs :

- **MESURÉE GAGNANTE** — un chiffre l'atteste, avec son protocole ;
- **MESURÉE PERDANTE** — réfutée, ne jamais la réintroduire sans cause nouvelle ;
- **NON MESURÉE** — plausible, mais inconnue. La majorité des cas.

## Règle n°3 — Fusionner par intention, pas par diff

Deux versions qui touchent la même fonction ne se fusionnent pas en empilant
leurs diffs. Pour chaque optimisation retenue, écrire **l'intention** en une
phrase, puis la réimplémenter dans l'état courant. Un `git checkout` de trois
fichiers d'un commit ancien greffe aussi tout ce qu'il contient d'autre —
c'est ainsi qu'on réintroduit sans le voir un correctif déjà réfuté.

**Test d'incompatibilité, à faire AVANT d'écrire** : deux optimisations qui
agissent sur la même variable, dans la même passe, avec des objectifs opposés
(réactivité contre justesse) ne peuvent pas coexister sans arbitrage explicite.
Les lister par ressource touchée (`alignAnchor`, `samples`, `consumed`,
`deferredOnceIndex`…) et repérer les collisions.

## Règle n°4 — Les effets de bord se cherchent, ils ne se constatent pas

Avant chaque ajout, répondre par écrit à ces trois questions — et si l'une
reste sans réponse vérifiée, ne pas coder :

1. **Qui d'autre lit ou écrit ce que je modifie ?** (`grep` sur la variable, pas
   de mémoire.)
2. **Qu'est-ce qui devient faux ailleurs si je change ça ?** Les commentaires
   du fichier documentent des pièges déjà payés : les lire avant, pas après.
3. **Quel comportement, aujourd'hui correct, pourrait régresser ?** Nommer le
   cas précis, pas « ça devrait aller ».

Règle projet applicable ici sans exception : **un effet de bord identifié
pendant l'analyse interdit l'implémentation directe** — il doit être arbitré
par l'utilisateur.

## Règle n°5 — Une seule optimisation à la fois, mesurée

Empiler deux changements avant de mesurer rend le résultat ininterprétable :
c'est ce qui a produit treize versions dont aucune n'est concluante. La
consolidation se fait donc par **incréments mesurés** :

```
état de référence mesuré (N passes)
   └─ + optimisation 1 → mesure → gardée / rejetée
        └─ + optimisation 2 → mesure → gardée / rejetée
```

Sur ce projet, le banc impose son rythme : trois passes minimum par état, car
un artefact frappe une passe sur trois. Un écart inférieur à l'étendue observée
ne conclut rien.

## Règle n°6 — Le doute porte AUSSI sur ce qu'on vient d'écrire

Après avoir écrit le code, avant de le construire :

- relire le diff **entier**, pas seulement les lignes ajoutées ;
- vérifier que les variables utilisées existent dans la portée (`grep` sur leur
  déclaration) ;
- vérifier qu'aucun commentaire existant n'est devenu faux — et si oui,
  **ajouter** une note à côté sans jamais supprimer l'ancien (règle projet) ;
- vérifier que le tag de build a été changé, sinon la mesure sera attribuée à
  la mauvaise version.

## Ce que ce skill NE fait pas

Il ne remplace ni `recul-architectural` (sortir d'une boucle de correctifs), ni
`solution-de-fond` (distinguer un palliatif d'une cause traitée). Il s'invoque
**après** eux, quand on sait ce qu'on veut garder et qu'il faut l'assembler
proprement.

## Vérification

- [ ] Inventaire construit depuis `git diff`, pas depuis le fil de conversation
- [ ] Chaque optimisation porte un statut MESURÉE GAGNANTE / PERDANTE / NON MESURÉE
- [ ] Les collisions entre optimisations sont listées par ressource touchée
- [ ] Chaque affirmation technique du compte rendu a été vérifiée dans le code ce tour-ci
- [ ] Les trois questions d'effet de bord ont une réponse écrite et vérifiée
- [ ] Un seul changement par mesure, trois passes minimum
- [ ] Diff entier relu, tag de build changé, aucun commentaire existant supprimé
