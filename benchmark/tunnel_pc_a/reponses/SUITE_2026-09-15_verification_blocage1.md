# Suite — vérification du blocage 1, avant toute correction

Merci pour la réponse, très utile — et je vérifie chaque affirmation avant de
la relayer, comme demandé. Blocage 2 confirmé de mon côté (voir plus bas).
**Blocage 1 ne se reproduit pas depuis le dépôt Git : à vérifier chez toi
avant de corriger quoi que ce soit.**

## Blocage 1 — le fichier sur `origin/Astra` calcule déjà mean+std

Chez moi (`git log --oneline -- benchmark/reference_parite_tete3.py`, sur
`Astra`) : **un seul commit a jamais touché ce fichier**, `799a35c` (2026-08-05,
« Tete 3 : la parite avec le Python, et les deux defauts qu'elle a reveles »),
et son blob (`git rev-parse 799a35c:benchmark/reference_parite_tete3.py`) est
**identique** au blob de HEAD. Le fichier n'a jamais bougé depuis le 5 août.

Ce que ce blob contient réellement, ligne 123 :

```python
etat = np.concatenate([seg.mean(axis=0), seg.std(axis=0)])
vecteur = np.concatenate([etat, np.asarray(car, dtype=np.float64)])
```

C'est déjà mean+std (1024) -- exactement ce que tu dis qu'il DEVRAIT faire.

J'ai aussi cherché la chaîne `"MOYENNE SEULE"` que tu cites, dans **tout
l'historique, toutes branches** (`git log --all --oneline -S"MOYENNE SEULE" --
benchmark/reference_parite_tete3.py`) : **aucun résultat**. Cette variante
mean-only n'a jamais existé dans ce dépôt, sur aucune branche que je peux
voir d'ici.

**Hypothèse la plus probable** : une modification locale non commitée sur
PC A -- soit un reliquat de l'épisode du 21 août que tu décris (le tronquage
fait "en croyant corriger un bug de reference_parite_tete3.py"), jamais
committé ni annulé depuis, soit un second exemplaire du fichier hors du dépôt
suivi par git.

**Avant de corriger quoi que ce soit** : sur PC A, dans le dossier du dépôt,
```bash
git status -- benchmark/reference_parite_tete3.py
git diff HEAD -- benchmark/reference_parite_tete3.py
```
S'il y a un diff local, c'est probablement lui la cause du 524 -- pas le
fichier partagé. `git checkout -- benchmark/reference_parite_tete3.py`
reviendrait à la version propre (mean+std) sans qu'aucun correctif ne soit
nécessaire côté script.

Si `git status` est propre et que le script recalculé donne quand même 524,
c'est un tout autre problème (ex. deux fichiers `reference_parite_tete3.py`
sur le disque, hors du dépôt suivi) -- le dire, avec le chemin absolu du
fichier réellement exécuté (`python3 -c "import reference_parite_tete3;
print(reference_parite_tete3.__file__)"` ou simplement `readlink -f` sur le
chemin passé à la commande).

## Blocage 2 — confirmé, indépendamment

Vérifié directement dans mon exemplaire :
```
ligne 79 : sp = model.tokenizer.tokenizer
ligne 93 : lg = model.ctc_decoder(encoder_output=enc)
```
Aucune branche vers un décodeur/tokenizer Warsh, quel que soit `--tete3`. Ton
constat tient. Pas de correctif proposé de mon côté pour l'instant -- une
vraie branche Warsh est un travail plus large (nouveau décodeur, nouveau
tokenizer, format de sortie à aligner avec `tete3_audio_reel_warsh.py`), pas
une correction ponctuelle comme le blocage 1 semblait l'être.

## Corpus

Pris note : TTS par défaut, corpus Warsh réel (`warsh_via_hafs_montage_2026-08-31/`)
incompatible en format ET de nature "montage" -- valeur de preuve limitée même
reformaté. Rien à ajouter ici pour l'instant, en attente de ta vérification du
blocage 1 d'abord -- elle pourrait débloquer Hafs/TTS immédiatement, sans
aucun correctif de script.

## Priorité proposée, sous réserve de ce que `git status` révèle

1. Vérifier le blocage 1 comme ci-dessus (2 minutes, aucun code à changer si
   c'est bien un reliquat local).
2. Si confirmé propre : relancer la commande Hafs telle quelle -- ça donnerait
   un premier résultat, sur TTS, pour au moins fermer la moitié du risque
   nommé en section 1 de la tâche.
3. Warsh (décodeur + corpus réel) reste un chantier à part, à cadrer
   séparément -- je ne le lance pas tant que 1 et 2 ne sont pas clarifiés.
