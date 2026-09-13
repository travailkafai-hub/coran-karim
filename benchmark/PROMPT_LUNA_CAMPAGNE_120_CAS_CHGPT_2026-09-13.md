# Prompt pour ChatGPT Luna - campagne de validation 120 cas

Document prepare par **ChGPT**, le 13 septembre 2026, pour l'application
`Coran_Karim_portable`.

## Mission

Tu es l'agent de preparation et d'execution d'une campagne de test de la
chaine de verification de recitation. Tu dois produire des cas audio
deterministes, executer l'application sur la version et le modele figes, puis
livrer un rapport exploitable pour decider **quoi investiguer**.

Cette campagne ne donne aucune autorisation de modifier l'algorithme. Ne
modifie ni le modele, ni les seuils, ni l'alignement, ni le code de production
pendant la campagne. Si un changement devient necessaire, arrete-toi, cree une
hypothese documentee et demande une campagne ulterieure.

## Regle absolue: ne rien inventer

Avant de fabriquer un seul cas, verifie et archive:

1. la provenance du texte et la riwaya de chaque extrait;
2. la provenance du fichier audio, le recitateur, la sourate et la plage de
   versets;
3. le hash du fichier source et du WAV final;
4. la methode independante qui a determine les frontieres de mots;
5. la presence reelle du mot ou de l'erreur dans le WAV;
6. la version de l'application, le commit Git, le hash du modele, le tokenizer,
   l'appareil et le mode de verification.

Une API de texte ne prouve pas la presence d'un mot dans un audio. Une decoupe
estimee ne doit pas etre presentee comme un minutage mot a mot exact. Si une
preuve manque, marque le cas `NON_DECIDABLE` et ne l'utilise pas pour conclure.

Pour Warsh, utilise exclusivement du texte Warsh et un audio Warsh verifie.
Ne remplace jamais Warsh par Hafs. Si aucun audio Warsh correctement associe
au texte et au recitateur n'est disponible, le bilan Warsh est `BLOQUE`, sans
conclusion sur les performances Warsh.

## Volume obligatoire

Produis exactement **120 cas distincts**:

| Riwaya | Correct original | Decoupe/recollage sans erreur | Transformes | Total |
|---|---:|---:|---:|---:|
| Hafs | 20 | 10 | 30 | 60 |
| Warsh | 20 | 10 | 30 | 60 |

Les 30 cas transformes de chaque riwaya sont repartis en six familles, cinq
cas par famille:

- omission;
- substitution;
- insertion;
- permutation;
- mot tronque;
- interruption puis reprise.

Une reprise legitime, une repetiton propre au recitateur, ou un passage repete
par choix pedagogique n'est pas une faute. Le manifeste doit porter
`repetition_legitime=true` quand cela s'applique.

## Diversite du corpus

Pour chaque riwaya:

- couvre au moins six sourates; vise huit sourates si les sources le permettent;
- varie les longueurs: mot court, groupe de mots, demi-verset, verset et
  frontiere entre deux versets;
- varie la position de l'alteration: debut, milieu, fin, jonction de segment;
- varie la distance entre la faute et les mots voisins;
- evite deux cas qui ne differeraient que par le nom du fichier ou une lettre
  sans interet pour l'algorithme;
- utilise deux recitateurs par riwaya quand deux sources completes et verifiees
  existent. Sinon, indique explicitement le recitateur manquant et la raison.

Le depot indique actuellement deux sources Warsh candidates chez EveryAyah
(`Ibrahim Al-Dosary` et `Yassin Al-Jazaery`) et une source Warsh chez MP3Quran.
Cela doit etre verifie par requete et par ecoute avant utilisation. Pour Hafs,
verifie aussi que le texte, la voix et la source de minutage correspondent.

## Fabrication des audio

### Cas corrects originaux

Utilise un extrait reel, non modifie, avec une reference textuelle complete.
Conserve le flux brut ainsi que la version envoyee a l'application.

### Cas decoupes et recollages propres

Decoupe des unites dont le texte est connu, puis recolle-les dans l'ordre
canonique sans supprimer, ajouter, remplacer ni permuter de mot. Le contenu
doit donc rester correct. Enregistre separement:

- les frontieres de coupe;
- les durees de silence ajoutees ou supprimees;
- le type de raccord, notamment fondu ou coupe seche;
- les artefacts audibles eventuels.

Un verdict negatif sur ce groupe doit etre examine comme possible
`FAUX_POSITIF_MONTAGE`, et ne doit pas etre confondu avec une faute de
recitation.

### Cas transformes

Chaque transformation doit avoir une reference machine-lisible:

```json
{
  "mot_attendu": "...",
  "forme_presente_dans_audio": "...",
  "operation": "omission|substitution|insertion|permutation|troncature|interruption_reprise",
  "position": 3,
  "preuve_audio": "chemin ou plage temporelle",
  "faute_a_detecter": true
}
```

Les substitutions doivent etre audibles et confirmees, pas seulement
remplacees dans le texte du manifeste. Les troncatures et interruptions
doivent indiquer exactement si le mot a ete coupe au debut, au milieu ou a la
fin, ainsi que la plage temporelle attendue.

Si une transformation est obtenue par TTS, marque-la `AUDIO_SYNTHETIQUE` et
separe-la des conclusions sur un recitateur humain. Privilegie un montage de
segments reels lorsque les frontieres sont verifiables independamment.

## Repartition pre-enregistree et validation reservee

Prepare le manifeste complet avant la premiere execution, avec un seed fixe
et archive le hash du manifeste. Ne change jamais la repartition apres avoir
vu les resultats.

Par riwaya, reserve 20 cas sur 60 pour la validation ulterieure:

- 14 cas de developpement et 6 cas reserves parmi les 20 corrects;
- 7 cas de developpement et 3 cas reserves parmi les 10 recollages propres;
- 19 cas de developpement et 11 cas reserves parmi les 30 transformes.

Le tiers reserve est marque `split=heldout`, connu avant execution, et ne sert
ni a choisir une regle, ni a ajuster un seuil, ni a choisir les cas
representatifs.

Les cas restants sont `split=development`. Les conclusions principales sur
une hypothese doivent d'abord etre formulees sur ce split; le held-out ne sera
ouvert qu'apres gel de l'hypothese et du correctif candidat.

## Relectures et total d'executions

Choisis avant execution 10 cas representatifs par riwaya, de facon stratifiee
par type de cas et par recitateur. Ces 20 cas sont executes **trois fois au
total** avec le meme WAV, le meme modele et la meme version de l'application.

Le total attendu est donc:

```text
100 cas executes une fois + 20 cas executes trois fois = 160 executions
```

Les trois lectures d'un meme cas ne sont pas trois observations independantes.
Dans le rapport, presente:

- le resultat par cas distinct;
- les trois observations liees dans une section de variabilite;
- le nombre de cas stables et instables;
- les transitions de verdict entre relectures identiques.

## Protocole d'execution

Pour chaque execution:

1. reinitialise uniquement l'etat de session necessaire;
2. utilise le replay WAV deterministe de l'application;
3. conserve le log complet, le flux WAV brut recu par le modele et les WAV de
   fenetres lorsqu'ils existent;
4. note `CTL` et `V2`, le numero de mot, le texte attendu et entendu, le statut,
   GOP, `forced`, `free`, le nombre de frames et les marges;
5. enregistre le chemin d'alignement et la cause du non-verdict;
6. verifie dans le WAV brut si le mot est effectivement present avant de
   conclure a un defaut de chaine;
7. ne supprime jamais un cas non juge: classe-le `NON_JUGE` ou `NON_DECIDABLE`.

Utilise les marqueurs de la chaine v2. Les anciens marqueurs v1 tels que
`segment FIGE`, `secours` ou `GOP lock=true` ne doivent pas etre utilises pour
attribuer une cause a une session v2.

Pour tout mot non vert, produis une ligne de ce type:

```text
mot | attendu | entendu | etat | gop | forced | free | frames | marge | cause | present_dans_WAV | mecanisme
```

Le balayage du flux brut doit couvrir toute la duree avec au moins deux
largeurs de fenetre. Les clips de sortie ne remplacent pas le flux brut pour
les positions temporelles.

## Classification des resultats

Au niveau du mot et du cas, utilise une nomenclature stable:

- `CORRECT_ACCEPTE`: audio correct et accepte;
- `FAUX_POSITIF`: audio correct mais signale comme faute;
- `FAUX_POSITIF_MONTAGE`: audio semantiquement correct, alarme liee au raccord
  ou a l'absence de contexte du montage;
- `ERREUR_DETECTEE`: transformation presente et signalee;
- `ERREUR_MANQUEE`: transformation prouvee mais non signalee;
- `NON_JUGE`: l'application n'a pas produit de verdict exploitable;
- `NON_DECIDABLE`: preuve audio, texte ou riwaya insuffisante;
- `BLOQUE`: execution impossible ou source indisponible.

Ne classe pas automatiquement un mot absent des attestations comme absent du
WAV. Cela peut etre un probleme de fenetre, d'ancre, de decoupage ou de
montage.

## Fichiers a livrer

Livre un dossier date contenant au minimum:

```text
manifest_cases.jsonl
manifest_hash.txt
audio_sources.jsonl
executions.jsonl
word_observations.jsonl
logs/
wav_brut/
wav_cases/
rapport.md
tables.csv
```

Chaque ligne de `manifest_cases.jsonl` doit contenir au minimum:

```json
{
  "case_id": "H-001",
  "riwaya": "Hafs",
  "split": "development|heldout",
  "famille": "correct_original|splice_clean|omission|substitution|insertion|permutation|troncature|interruption_reprise",
  "sourate": 2,
  "versets": "1-3",
  "recitateur": "...",
  "texte_attendu": "...",
  "texte_present_audio": "...",
  "audio_source_sha256": "...",
  "wav_final_sha256": "...",
  "preuve_frontieres": "...",
  "repetition_legitime": false,
  "representatif": false
}
```

`executions.jsonl` doit inclure le numero de run, le build, le modele, le
device, le cas, la date, la duree, le statut de fin et les chemins des traces.

## Analyse statistique obligatoire

Presente toujours les effectifs `x/n`, puis le pourcentage. Ajoute un intervalle
de confiance a 95 % adapte a un petit echantillon (Wilson ou
Clopper-Pearson), en precisant que les cas d'une meme relecture ne sont pas
independants.

Fournis au minimum:

1. faux positifs sur les 20 audio corrects de chaque riwaya;
2. faux positifs sur les 10 recollages propres, separes des artefacts de
   montage;
3. detection et omissions des 30 cas transformes, par famille;
4. ventilation par sourate et recitateur;
5. Hafs contre Warsh, uniquement si les deux corpus sont valides;
6. stabilite des 20 cas relus trois fois;
7. nombre de cas `NON_JUGE`, `NON_DECIDABLE` et `BLOQUE`;
8. limites de puissance: une absence de defaut dans quelques cas ne prouve
   pas l'absence generale du defaut.

Pour les relectures, donne par exemple `cas stables / 20`, et non seulement un
taux calcule comme si 60 lignes etaient independantes.

## Structure des conclusions

Le rapport final doit separer clairement:

### Defauts reproductibles

Un defaut est reproductible seulement si le meme phenomene est observe sur des
cas distincts ou sur les trois executions d'un meme cas, avec preuve dans le
WAV et une trace de la chaine.

### Faux positifs audio correct

Distingue un faux positif sur un audio original d'un faux positif cause par un
raccord, une coupure seche, une perte de contexte ou un silence artificiel.

### Difference Hafs/Warsh

Ne la declare que si les deux sources sont correctes, les textes sont ceux de
leur riwaya et les recitateurs sont identifies. Sinon indique `comparaison
impossible`.

### Variabilite des relectures

Indique les cas ou le verdict varie, la variation exacte et si elle vient du
modele, de la fenetre, du nombre de frames ou de l'etat de session.

### Hypotheses faibles

Liste les hypotheses qui demandent des tests supplementaires, par exemple:

- frontiere de mot mal estimee;
- audio correct mais raccord non naturel;
- modele instable sur une lettre ou une haraka;
- difference de riwaya confondue avec une erreur;
- interruption legitime confondue avec omission;
- effet specifique d'un recitateur.

Pour chaque hypothese, donne les cas requis pour la confirmer ou la refuter.

## Decision finale interdite

Ne termine pas par « corriger le seuil » ou « modifier l'alignement » comme si
le test l'autorisait. Termine par:

1. les faits observes;
2. les defauts reproductibles;
3. les faux positifs et les trous de preuve;
4. les hypotheses classees par priorite;
5. le protocole de validation ulterieure, sur le tiers `heldout` uniquement.

Un resultat incomplet mais honnete doit dire exactement ce qui manque. Il vaut
mieux un bilan Hafs complet et un Warsh bloque qu'un faux bilan Warsh fabrique
a partir de Hafs.
