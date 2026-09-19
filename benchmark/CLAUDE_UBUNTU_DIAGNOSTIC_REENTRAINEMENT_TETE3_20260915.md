# Pour Claude sur Ubuntu : choisir entre tete 3 et encodeur sur une mesure

## Decision proposee

La piste n'est pas declaree morte. La tete actuelle n'apporte pas de gain
demontre dans les replays de l'application. Ne pas lancer un reentrainement
general de l'encodeur sur ce seul constat.

Ordre propose : verifier le decalage entre entrainement et application,
mesurer/reentrainer une tete avec encodeur gele sur les vraies entrees de
l'app, puis seulement envisager un ajustement partiel de l'encodeur.
Ne pas passer des series d'essais a agrandir le MLP ou multiplier les epochs.

Ce document est prepare sur Windows a partir des COPIES rapatriees des
scripts et rapports. Aucun acces au processus, aux caches ni au checkpoint
actuel d'Ubuntu n'est presume. Verifier les empreintes et chemins sur Ubuntu
avant de conclure que les copies decrivent exactement le dernier run.
Aucun entrainement distant n'a ete lance par Codex.

## Ce qui est etabli ici

- Les anciennes entrees Kotlin de la tete n'utilisaient pas le SentencePiece
  d'entrainement. Correction BPE + normalisation verifiee sur 606 342 textes
  Hafs/Warsh, cible et confusions. Cette divergence est maintenant corrigee.
- Deux corrections, testees separement sur JVM : BPE T3 et kashida du vote.
  T805 : faux rouges 10/200 (5 %) -> 5/200 (2,5 %), erreurs signalees
  11/20 (55 %) inchangees. Avec les corrections, vote seul et vote+tete3
  donnent le meme resultat sur ce cas.
- T808 sans mutations : vote seul 3/73 faux rouges (4,1 %), vote+tete3
  4/73 (5,5 %). La tete ajoute donc encore une fausse accusation.
- La politique `JugementTete3.couleur` ne peut pas annuler un rouge texte.
  Elle peut ajouter rouge/doute, pas arbitrer librement les hypothese A/B/C.
  Absence d'alerte T3 n'est d'ailleurs pas une preuve que le mot est correct.
- Les replays ne prouvent pas un plafond definitif : petit ensemble choisi
  pour le diagnostic, fautes construites dont le manifest ne remplace pas
  une verification independante de l'audio, et differences CPU Android/JVM.

Preuves : `CORRECTION_TOKENISATION_TETE3_JVM_20260915.md`,
`replay_chaine_jvm_20260915/{resultats,analyse,provenance}.json`.

## Deux differences du protocole a verifier sur Ubuntu

### 1. Bornes du mot avantagees pendant la generation

Dans la copie `tetes_candidates/hafs_particules_20260915/tete3_audio_reel.py` :

1. `spans_mots(sp, lp, mots)` aligne le texte reel du recitateur.
2. Le script choisit un mot dont cet alignement a trouve des frames.
3. `variante_large` change ensuite le texte attendu.
4. `caracteristiques(lp[f0:f1], sp, texte_variant)` conserve les bornes
   etablies avec le VRAI mot, egalement utilisees pour l'exemple correct.

C'est une methode utilisable pour construire un contraste acoustique, mais
elle donne une information a la generation que l'app ne possede pas. Dans
l'app, le texte attendu peut etre faux par rapport a la recitation et les
bornes viennent de l'alignement de CE texte dans une fenetre. Un mot peut
donc etre coupe, attribue au voisin, ou ne pas avoir de frames exploitables.
La mesure doit inclure ces situations et le taux d'abstention, pas les jeter.

Autre difference : les fautes de ce pipeline sont des cibles modifiees face
a une recitation professionnelle correcte. Elles ne representent pas toutes
les hesitations, erreurs de prononciation et reprises d'une personne.
Verifier la composition exacte du cache de la candidate : le nom du fichier
et une phrase "audio reellement faute" ne suffisent pas a l'etablir.

### 2. Le seuil est choisi sur le jeu nomme test

Dans la copie recue `calibrer_seuils_tete3_2026-09-15.py`, `s[test]` sert a
choisir le quantile des corrects ET a annoncer la detection. Le budget de
2 % y est donc ajuste sur cette population. Ce n'est pas une verification
independante du seuil sur un nouveau jeu.

Le rapport Hafs annonce 99,4 % de detection a ce seuil sur ce cache : ce
chiffre n'est pas un taux de detection en streaming dans l'application.
Separer entrainement, validation/calibration et test final verrouille.

## Experience 1 : localiser la perte, sans reentrainement

Sur les MEMES enregistrements, mot attendu et modele, produire deux entrees :

- borne de reference verifiee independamment, servant uniquement au diagnostic ;
- borne reellement produite par la chaine Kotlin dans chaque fenetre.

Garder le contexte d'encodeur identique pour isoler l'effet de la borne.
Ensuite comparer les contextes de fenetres, en les variant separement.
Conserver les memes mots au denominateur, y compris sans observation ou sans
score ; donner couverture, abstentions, erreurs detectees et faux rouges.

Comparer d'abord les scores continus de la tete seule, puis le verdict de
la chaine complete. Calibrer sur validation avant de mesurer le test. Ne
pas changer simultanement les poids du vote et les poids de la tete.

Lecture du resultat :

| Resultat | Priorite |
|---|---|
| Bonne separation avec borne de reference, perte avec bornes de l'app | Attribution/cadrage et apprentissage sur ces conditions |
| Scores utiles mais gain perdu dans les statuts | Regle d'agregation, couverture ou verrouillage |
| Mauvaise separation meme avec bonnes bornes | Corpus, representation du mot ou encodeur a examiner |

La derniere ligne ne prouve PAS a elle seule que l'encodeur a perdu
l'information : moyenne/ecart-type peuvent aussi masquer un detail temporel.

## Experience 2 : tete seule, encodeur gele

Produire un cache depuis le chemin acoustique et l'alignement de l'app,
avec le tokenizer corrige. Les logs actuels contiennent les scores mais
pas tous les vecteurs : ne pas pretendre pouvoir reentrainer avec ces logs
seuls. Il faut exporter les etats et caracteristiques depuis le banc JVM,
ou executer ce meme chemin sur Ubuntu. Une recreation Python doit prouver
sa parite avant de fournir le cache, notamment pour le mel et les bornes.

Chaque exemple doit porter : source audio/empreinte, riwaya, attendu,
annotation de ce qui est reellement prononce, nature de faute, occurrence,
fenetre et bornes absolues, etat encodeur, 12 traits, tokens, masque de
disponibilite et motif d'exclusion. Un fragment d'observation d'un mot juste
n'est pas automatiquement une faute de l'utilisateur.

Inclure : fautes audibles proches, mots corrects confondus par l'ASR,
variations de contexte, frontieres et waqf licites. Ne pas utiliser le
verdict actuel de l'app comme verite terrain pour entrainer son remplaçant.

Commencer par la meme petite tete et le meme encodeur gele : la variable
testee est le corpus/extraction. En cas de plafond, un essai borne de tete
sur la sequence des etats du mot permet de verifier la perte par moyennage.
Ce n'est pas une invitation a rechercher indefiniment une architecture.

Toutes les fenetres, variantes et crops d'une meme source restent dans le
meme split. Tenir compte aussi des clips donneurs reutilises dans les
montages. Prevoir des voix de test absentes de l'entrainement. T805/T023/T005
sont deja inspectes : jeux de regression, pas nouveau test aveugle.

## Experience 3 : encodeur partiellement ajuste, si les mesures le justifient

Garder le checkpoint actuel comme temoin. Debloquer d'abord une partie
limitee des dernieres couches, avec un objectif de distinction correct/faute
conditionne par l'attendu, et un objectif de transcription pour proteger
l'ASR. Les labels de transcription doivent decrire ce qui est prononce,
jamais corriger une faute vers le texte canonique pendant l'entrainement.

Verifier avant tout ce qui a deja ete entraine contrastivement sur le
checkpoint courant : le graphe contient d'anciens runs, leurs resultats ne
se transferent pas automatiquement au modele deploye de septembre.

Un encodeur modifie impose de reextraire les caracteristiques et de
reentrainer/recalibrer la tete 3 dessus. Controler aussi les autres sorties
du modele partage : transcription Hafs/Warsh, tajwid et latence. Une tete
entrainee sur l'ancien espace d'etats ne devient pas compatible par son nom.

## Critere d'adoption et livrables

Le critere est un gain de detection **a faux positifs comparables**, avec
couverture, decrochages et latence egalement mesures. Un meilleur score par
mot sur des bornes de reference ne suffit pas a adopter une couleur en app.
Fixer le budget de faux positifs sur validation et rapporter le taux obtenu
sur test, meme s'il depasse ce budget ; ne pas recalibrer ensuite sur le test.
Donner les taux par famille et l'incertitude par enregistrement, sans compter
les fenetres recouvrantes comme autant d'erreurs independantes.

Rendre un rapport avec temoins, empreintes, composition des splits, verite
audio verifiee, courbes de separation, rappel/precision, faux rouges,
abstentions, couverture et replay final de la chaine. Exporter les poids
seulement avec references de parite et provenance du cache.

## Liens avec les connaissances deja presentes

Graphe : `regle_le_plafond_de_tete3_est_en_amont_delle`,
`mesure_tete3_audio_reel_complete_le_tts_sans_le_remplacer`,
`piege_parite_tete3_ignore_tokenisation_20260915`,
`mesure_jvm_bpe_kashida_20260915`. Les essais anciens de taille/epochs ont
deja decevu ; la nouvelle cause a tester ici est l'ecart d'extraction en app.

Des travaux ont obtenu des gains en adaptant des representations de parole
et une tete a la detection de prononciation :
[Xu et al., Interspeech 2021](https://www.isca-archive.org/interspeech_2021/xu21k_interspeech.html)
et [Yang et al., Interspeech 2022](https://www.isca-archive.org/interspeech_2022/yang22c_interspeech.html).
Ils rendent ces essais plausibles ; ils ne prouvent aucun gain pour notre
FastConformer, Hafs/Warsh ou nos fenetres. La decision reste celle du replay.
