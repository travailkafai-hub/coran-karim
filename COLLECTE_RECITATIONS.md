# Collecte chiffrée des récitations — plan d'implémentation

Décision utilisateur du 2026-09-19. Remplace l'envoi par courriel, qui ne
fonctionne pas : *« rares les personnes qui vont envoyer via mail comme
maintenant, oubli… »*. Le défaut n'est pas dans le formulaire, il est dans le
geste qu'il exige.

**Décidé** : Cloudflare R2, envoi automatique après consentement explicite,
chiffré de bout en bout.
**Objet** : alimenter le réentraînement du modèle ASR avec de vraies
récitations d'utilisateurs, et pas seulement les nôtres.

---

## 1. Les chiffres qui commandent le reste

Mesurés sur l'appareil de test le 2026-09-19 (`stream_*.wav`, 120 364 octets
pour ~3,8 s) : la capture est du **PCM 16 kHz mono 16 bits**, soit **32 Ko par
seconde**.

| | |
|---|---:|
| 5 min de récitation, brut | ~9,6 Mo |
| la même en FLAC (sans perte) | ~5 Mo |
| **segments signalés seuls, FLAC** | **~500 Ko** |
| journal d'une session | ~250 Ko |

⇒ Le palier gratuit R2 (10 Go) porte donc **~20 000 sessions**. À 50
utilisateurs quotidiens, cela tient plus d'un an, et le dépassement se compte
ensuite en centimes.

⚠️ **Ne pas passer à l'Opus sans mesure.** Il diviserait encore par cinq, mais
avec perte, alors que le modèle est entraîné sur du 16 kHz non compressé.
Collecter en masse de l'audio dégradé produirait des données qui **abîment**
l'entraînement. Le FLAC est sans perte : il divise par deux sans aucun risque,
c'est le choix par défaut. Toute idée d'Opus passe d'abord par le banc
(comparer le WER sur un corpus recompressé).

### Pourquoi R2 et pas AWS

Le trafic dominant n'est pas l'envoi, c'est **le rapatriement vers PC A** pour
entraîner. C'est précisément ce qu'AWS facture (~0,09 $/Go) et que R2 ne
facture pas : 1 To rapatrié coûte ~90 $ chez S3, 0 $ chez R2 — et ce coût
revient à chaque nouveau run. R2 parlant le protocole S3, la bascule inverse
resterait possible en une heure si l'entraînement partait un jour sur des GPU
cloud.

---

## 2. Architecture — trois morceaux

```
  app (Flutter/Kotlin)            Worker (Cloudflare)         R2
  ─────────────────────           ───────────────────         ──
  1. segments + journal
  2. FLAC
  3. chiffre (clé PUBLIQUE)  ──►  4. vérifie, signe      ──►  5. dépose
                                     l'URL d'envoi            l'objet chiffré
                                                               │
  PC A  ◄────────────────────────────────────────────────────  6. rclone/aws-cli
  7. déchiffre (clé PRIVÉE), filtre, verse au corpus
```

### Pourquoi un Worker, et pas l'app qui écrit directement dans R2

**La clé du bucket ne doit jamais être dans l'APK.** Un APK se décompile en
quelques minutes ; une clé qui y figure permet à n'importe qui d'effacer ou de
remplir le bucket. Le Worker (palier gratuit : 100 000 requêtes/jour) délivre
une **URL d'envoi signée, valable une fois et quelques minutes**. Il porte
aussi le garde-fou de volume : refuser un paquet trop gros, limiter le nombre
d'envois par appareil et par jour.

### Chiffrement de bout en bout

`libsodium` *sealed box* (`crypto_box_seal`) :

- l'app embarque la **clé publique** — inutile à qui la vole ;
- la **clé privée ne quitte jamais PC A** ;
- même si le bucket fuit, l'audio est illisible, y compris pour Cloudflare.

C'est le sens de la demande (« envoi automatique crypté »), et le seul niveau
qui tienne sur des données religieuses. TLS seul ne protège qu'en transit.

⚠️ **Si la clé privée est perdue, tout le corpus collecté est perdu.** Elle doit
être sauvegardée hors de PC A avant le premier envoi, et son empreinte publique
notée ici au moment du déploiement.

---

## 3. Le paquet envoyé

Une archive par session, nommée `<idAppareil>/<horodatage>.bin` :

| contenu | pourquoi |
|---|---|
| segments FLAC autour des **mots signalés** | ce sont eux qui portent l'information : faux positifs et vraies fautes |
| `verdicts.json` — mot attendu, statut, `gop`, `forced`, `free`, `frames`, `entendu` | permet de retrouver hors appareil ce que la chaîne a conclu |
| `sourate:verset` de chaque segment | l'étiquette d'entraînement, sans laquelle l'audio ne sert à rien |
| journal de la session | c'est lui qui a permis de trouver le défaut de tokenisation du 2026-09-18 |
| version du modèle, du build, riwāya | sans quoi une mesure relue plus tard est ambiguë (piège déjà payé sur `fastconformer-ctc-mixed-e02`) |

**Ne PAS envoyer** : nom, courriel, position, identifiant d'appareil réel. Un
`idAppareil` **aléatoire** est tiré à la première activation et stocké
localement — il ne sert qu'à honorer une demande d'effacement, et il est affiché
dans les Réglages pour que l'utilisateur puisse le communiquer.

### Périmètre : segments, pas la récitation entière

Dix fois moins de données, dix fois moins de sensibilité, et l'essentiel de
l'information. Élargissable plus tard si l'entraînement montre qu'il manque des
exemples corrects — l'inverse (réduire après avoir tout collecté) ne se
rattrape pas.

---

## 4. Déclenchement

- **Wi-Fi et en charge**, en tâche de fond (`WorkManager`), file persistante
  avec reprise. C'est ce qui règle le vrai problème : le courriel échoue parce
  qu'il demande un geste.
- Rien ne part tant que le consentement n'est pas donné. Les sessions
  antérieures à l'accord ne sont **pas** envoyées rétroactivement.
- Un paquet envoyé est supprimé de la file, jamais des captures locales : le
  diagnostic sur l'appareil reste ce qu'il est aujourd'hui.

---

## 5. Consentement

Interrupteur **désactivé par défaut**, jamais pré-coché, dans les Réglages.
L'écran dit en clair : ce qui part (des extraits de votre récitation), pourquoi
(améliorer la reconnaissance), combien de temps c'est conservé, et comment
retirer son accord.

Le retrait coupe les envois futurs et affiche l'identifiant permettant de
demander l'effacement de ce qui est déjà parti.

### Textes à réécrire EN MÊME TEMPS que la fonctionnalité

L'application promet aujourd'hui le contraire, et ces phrases deviendraient
fausses le jour du premier envoi :

```
aboutPrivacyMic     « votre récitation est analysée sur l'appareil,
                       jamais envoyée ailleurs. »
aboutPrivacyNetwork « Réseau — seulement pour télécharger les récitations
                       et invocations que vous demandez. »
```

Même chose dans l'en-tête de `voice_lora_clip_service.dart` (« Stockage
on-device UNIQUEMENT […] jamais synchronisée en arrière-plan ») et dans la page
« Vos données » de l'onboarding.

⇒ Livrer le code sans ces textes ferait mentir l'app **au moment précis où elle
demande un accord**. Les deux vont ensemble, dans le même commit.

---

## 6. Étapes

| # | étape | où |
|---|---|---|
| 1 | créer le bucket R2 + le Worker, noter l'empreinte de la clé publique | Cloudflare |
| 2 | générer la paire de clés, sauvegarder la privée hors de PC A | PC A |
| 3 | extraction des segments signalés + encodage FLAC | app |
| 4 | chiffrement, file persistante, `WorkManager` | app |
| 5 | écran de consentement + réécriture des textes de confidentialité | app |
| 6 | script de rapatriement et de déchiffrement | PC A |
| 7 | versement au corpus d'entraînement après écoute d'un échantillon | PC A |

Rien ne part avant que 1, 2 et 5 ne soient faits.

---

## 7. Ce qui reste ouvert

- **Durée de conservation** : à fixer avant le premier envoi, et à annoncer
  dans l'écran de consentement.
- **Opus** : à mesurer au banc avant d'y toucher (cf. §1).
- **Quotas gratuits** : ceux cités ici datent du printemps 2026 et changent
  régulièrement — à revérifier au moment de créer le bucket.
- **Vérification humaine** : le stockage ne coûte rien, mais trier et écouter
  ces sessions demande du temps. C'est le vrai facteur limitant, et il plaide
  pour la collecte étroite retenue au §3.
