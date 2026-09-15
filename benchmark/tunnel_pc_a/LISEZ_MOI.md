# Tunnel vers PC A -- pas de connexion directe, GitHub fait le pont

## Pourquoi ce dossier existe

Ce PC (portable, Windows) et PC A (Ubuntu, RTX 5080, `.venv_nemo`) ne sont
**pas** dans la même session : aucun agent tournant ici ne peut en appeler un
sur PC A directement (`ListAgents` le confirme -- session locale uniquement).

Un chemin RESEAU existe (`100.126.49.93`, un VPN Tailscale -- `ssh` s'y
connecte et se fait refuser proprement, `Permission denied
(publickey,password,keyboard-interactive)`), mais aucune clé privée n'est
présente sur ce PC pour s'y authentifier. Je ne force rien de ce côté : pas de
mot de passe à deviner, pas de connexion interactive possible depuis un outil
non interactif.

Le canal qui marche vraiment est celui déjà utilisé pour tout le reste de ce
projet : `origin` (`github.com/travailkafai-hub/coran-karim`), commun aux deux
machines. Ce dossier est donc une **boîte aux lettres**, pas un tunnel réseau
au sens propre :

1. Une demande est écrite ici (`DEMANDE_*.md`), committée, poussée sur GitHub.
2. Sur PC A, quelqu'un (toi, ou l'agent qui y tourne) tire la branche, lit la
   demande, l'exécute.
3. Le résultat est écrit dans `reponses/`, committé, poussé à son tour.
4. Ici, on tire la branche et on lit `reponses/`.

Rien d'automatique : chaque sens demande un `git pull`/`git push` manuel (ou
une invocation explicite), exactement comme les documents `TACHE_CLAUDE_*.md`
que Codex a déjà laissés à la racine de `benchmark/` -- ce dossier reprend le
même principe, simplement regroupé et à double sens (`reponses/` en plus).

## Convention d'une demande

Un fichier `DEMANDE_<date>_<sujet>.md` : ce qui manque ici pour l'exécuter
(dépendance absente, GPU, corpus), ce qui doit être produit, où l'écrire. La
même rigueur que les documents déjà échangés sur ce projet : préciser un
chemin, une empreinte à vérifier, jamais une intention vague ("vérifie la
parité" ne suffit pas -- "vérifie que le SHA-256 de tel fichier avant de
l'utiliser" est le niveau attendu).
