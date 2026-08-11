# Courrier à Quran Foundation — version anglaise (à envoyer) + traduction française

## À QUI ENVOYER

**developers@quran.com**

C'est l'adresse désignée par leurs propres Developer Terms of Service, et pas
seulement une adresse de support : le document précise que « **Notices to QF
must be in writing and are deemed given when sent to developers@quran.com** ».
Une demande d'autorisation envoyée là est donc une notification formelle,
opposable — c'est exactement ce qu'on cherche, puisque la clause de
conservation exige une autorisation *expresse*.

Garde une copie de l'envoi et de leur réponse : c'est cette réponse écrite qui
te met en conformité, pas le courrier lui-même.

(La page quran.com/developers, elle, ne publie aucune adresse et renvoie vers
une *issue* GitHub — inadapté à une demande d'autorisation.)

Champs à compléter avant envoi : nom, adresse e-mail.

**Ton de la §5 — à garder tel quel.** Elle dit que tu as une solution de repli
(Tanzil pour le texte, ton propre pipeline pour la coloration tajwid). Ce n'est
PAS un moyen de pression, et le texte est écrit pour que ça ne puisse pas se
lire ainsi : c'est une information qui leur épargne du temps et qui montre que
tu demandes par respect de leurs conditions, pas parce que tu es coincé. Ne la
durcis pas.

---

## VERSION ANGLAISE — à envoyer

**Subject:** Request for written permission — offline storage of QF Content in a free Qur'an recitation app

Dear Quran Foundation team,

I am an independent developer. I am building an Android application, *Coran Karim*, which helps a user memorise and recite the Qur'an: the application listens to the recitation through the microphone and checks it word by word against the text, using a speech-recognition model that runs entirely on the device.

I have read the Developer Terms of Service, and I am writing because my application does not currently comply with one of its clauses. I would rather ask for permission than continue without it.

### 1. Which QF Content the application uses

- **Audio recitations** — file URLs obtained from `/recitations/{id}/by_chapter/{chapter}`, with the audio files themselves downloaded from `verses.quran.com`. This is the part that matters most to the application.
- **Word-by-word timings** — obtained from `/recitations/{id}/by_ayah/{verse_key}` with `fields=segments`. They are used to replay only the word a user mispronounced, rather than the whole verse.
- **Qur'anic text** — verses in Uthmani script, verse and Mushaf page divisions, tajweed markup and a French translation, obtained from `api.quran.com/api/v4`.

### 2. Where the application does not comply

The Terms state: *"Cache or store QF Content longer than 1 week unless expressly permitted."*

My application exceeds this in two places:

- When a user chooses to download a surah for offline listening, the audio files are stored in the application's private storage until the user deletes them.
- The Qur'anic text (about 8 MB of JSON) is fetched once and bundled inside the application package, so it is permanently present on the user's device.

There is a distinction between these two that may matter to you, and I would rather put it to you than decide it myself.

The audio is never downloaded on the application's own initiative. It is downloaded only when a user explicitly asks for a given surah; it is written to the application's private storage on that user's own device, where no other application can read it; and the user can delete it at any time from within the app. Nothing is copied to any server of mine, nothing is aggregated, and nothing is re-served to anyone else. In substance this is the user keeping a copy of what they chose to listen to, on their own phone. Whether that still counts as *my* storage under the Terms is your call, not mine.

I make no such argument for the bundled Qur'anic text: it is present before any user action, and it is plainly stored by me.

### 3. Why the application is built this way

The application is designed to work with no network connection at all. Its speech-recognition model runs on the device, and it is used in prayer rooms, mosques and homes with poor or no connectivity.

In an earlier version, the Qur'anic text was fetched from the API at every launch. A DNS failure on one user's phone made the Qur'an itself unreadable inside the application — that is the reason the text was moved into the package. The intent is not to redistribute your data, but to ensure that reading and reciting the Qur'an never depends on a network.

### 4. What I am asking

1. **Express written permission** to store QF Content beyond one week, specifically: (a) audio recitations stored on the end user's own device following a download that the user initiated, and (b) the Qur'anic text bundled inside the application package.
2. **Whether the attribution is acceptable.** The application's "About" screen credits *"Qur'anic text and recitations: Quran.com"*. I will gladly use any specific wording you prefer.
3. **Guidance on one point about the future.** The application is free and has no revenue today. I am considering accepting voluntary donations to cover costs. I would like to know whether, in your view, that would constitute commercial use requiring a separate license agreement.
4. **Whether I should migrate** from the legacy `api.quran.com/api/v4` endpoints to the current Quran.Foundation API with client credentials.

### 5. So that a refusal costs neither of us time

I want to be straightforward with you about my situation, because I would rather you knew it than guessed it.

If offline storage is not something you can permit, I can rebuild the Qur'anic text and its page and juz metadata from the Tanzil Project, whose terms allow verbatim redistribution with attribution, and I can generate the tajweed colouring from my own annotation pipeline, which the application already ships. So I am not writing because I have no alternative.

I am writing because I would rather stay within your terms than leave them. Your data is better maintained than anything I would assemble myself, and your word-by-word `segments` timings have no equivalent I am aware of. If you would prefer that I move off your API for the offline parts, please say so plainly — I will do it without any hard feelings, and I will keep the attribution.

### 6. Commitments

- The text of the Qur'an is never modified.
- QF Content is never resold, sublicensed, or redistributed outside the end-user experience of the application.
- No QF Content is used in any other product, dataset, or service.
- Attribution to Quran.com is displayed inside the application.
- If you would prefer that I stop bundling the text, or stop offering offline audio downloads, I will comply.

Thank you for the work you do, and for the time you give to this request.

Kind regards,

[Name]
[Email address]
Android package: `com.corankarim.coran_karim`

---

## TRADUCTION FRANÇAISE — pour ta lecture

**Objet :** Demande d'autorisation écrite — conservation hors ligne de contenu QF dans une application gratuite de récitation du Coran

Chère équipe de Quran Foundation,

Je suis un développeur indépendant. Je réalise une application Android, *Coran Karim*, qui aide à mémoriser et à réciter le Coran : l'application écoute la récitation au micro et la vérifie mot à mot par rapport au texte, à l'aide d'un modèle de reconnaissance de la parole qui fonctionne entièrement sur l'appareil.

J'ai lu vos conditions d'utilisation pour les développeurs, et je vous écris parce que mon application n'est aujourd'hui pas conforme à l'une de leurs clauses. Je préfère demander l'autorisation plutôt que de continuer sans elle.

### 1. Quel contenu QF l'application utilise

- **Récitations audio** — les URL des fichiers via `/recitations/{id}/by_chapter/{chapter}`, les fichiers eux-mêmes téléchargés depuis `verses.quran.com`. C'est la partie qui compte le plus pour l'application.
- **Minutage mot à mot** — via `/recitations/{id}/by_ayah/{verse_key}` avec `fields=segments`. Il sert à rejouer uniquement le mot mal prononcé, plutôt que le verset entier.
- **Texte coranique** — versets en graphie uthmanienne, découpage en versets et en pages du Mushaf, balisage tajwid et une traduction française, obtenus depuis `api.quran.com/api/v4`.

### 2. En quoi l'application n'est pas conforme

Vos conditions indiquent : « Cache or store QF Content longer than 1 week unless expressly permitted. » Mon application dépasse cette limite à deux endroits :

- Lorsqu'un utilisateur télécharge une sourate pour l'écouter hors ligne, les fichiers audio sont conservés dans le stockage privé de l'application jusqu'à ce qu'il les supprime.
- Le texte coranique (environ 8 Mo de JSON) est récupéré une fois puis embarqué dans le paquet de l'application : il est donc présent en permanence sur l'appareil.

Il existe entre ces deux cas une distinction qui peut compter pour vous, et je préfère vous la soumettre plutôt que de la trancher moi-même.

L'audio n'est jamais téléchargé à l'initiative de l'application. Il ne l'est que lorsqu'un utilisateur demande explicitement une sourate donnée ; il est écrit dans le stockage privé de l'application, sur l'appareil de cet utilisateur, où aucune autre application ne peut le lire ; et l'utilisateur peut l'effacer à tout moment depuis l'app. Rien n'est copié sur un serveur m'appartenant, rien n'est agrégé, rien n'est re-servi à qui que ce soit. Sur le fond, c'est l'utilisateur qui conserve une copie de ce qu'il a choisi d'écouter, sur son propre téléphone. Savoir si cela reste *mon* stockage au sens de vos conditions vous revient, pas à moi.

Je ne fais pas cet argument pour le texte coranique embarqué : il est présent avant toute action de l'utilisateur, et il est manifestement stocké par moi.

### 3. Pourquoi l'application est conçue ainsi

Elle est faite pour fonctionner sans aucune connexion. Son modèle de reconnaissance s'exécute sur l'appareil, et elle est utilisée dans des salles de prière, des mosquées et des foyers où la connectivité est mauvaise ou inexistante. Dans une version antérieure, le texte était récupéré à chaque lancement ; une panne DNS sur le téléphone d'un utilisateur a rendu le Coran lui-même illisible dans l'application — c'est pour cela que le texte a été déplacé dans le paquet. L'intention n'est pas de redistribuer vos données, mais de garantir que la lecture et la récitation du Coran ne dépendent jamais du réseau.

### 4. Ce que je demande

1. **Une autorisation écrite expresse** de conserver du contenu QF au-delà d'une semaine : (a) les récitations audio conservées sur l'appareil de l'utilisateur après un téléchargement qu'il a demandé, et (b) le texte coranique embarqué dans le paquet de l'application.
2. **Si l'attribution vous convient** : l'écran « À propos » crédite « Texte du Coran et récitations : Quran.com ». J'utiliserai volontiers la formulation que vous préférez.
3. **Un avis sur un point d'avenir** : l'application est gratuite et sans revenu. J'envisage d'accepter des dons volontaires pour couvrir les frais, et je souhaiterais savoir si cela constituerait selon vous un usage commercial nécessitant un accord distinct.
4. **S'il me faut migrer** des points d'accès historiques `api.quran.com/api/v4` vers l'API Quran.Foundation actuelle, avec identifiants client.

### 5. Pour qu'un refus ne coûte de temps à personne

Je préfère être direct sur ma situation, plutôt que vous laisser la deviner.

Si la conservation hors ligne n'est pas quelque chose que vous pouvez autoriser, je peux reconstruire le texte coranique et ses métadonnées de pages et de juz à partir du Tanzil Project, dont les conditions permettent la redistribution verbatim avec attribution, et je peux générer la coloration tajwid à partir de ma propre chaîne d'annotation, déjà embarquée dans l'application. Je ne vous écris donc pas faute d'alternative.

Je vous écris parce que je préfère rester dans le cadre de vos conditions plutôt qu'en sortir. Vos données sont mieux tenues que tout ce que j'assemblerais moi-même, et votre minutage mot à mot (`segments`) n'a, à ma connaissance, aucun équivalent. Si vous préférez que je quitte votre API pour les parties hors ligne, dites-le-moi simplement : je le ferai sans rancune, et je conserverai l'attribution.

### 6. Engagements

- Le texte du Coran n'est jamais modifié.
- Le contenu QF n'est jamais revendu, sous-licencié ni redistribué hors de l'expérience utilisateur de l'application.
- Aucun contenu QF n'est utilisé dans un autre produit, jeu de données ou service.
- L'attribution à Quran.com est affichée dans l'application.
- Si vous préférez que je cesse d'embarquer le texte ou d'offrir les téléchargements hors ligne, je m'y conformerai.

Merci pour votre travail, et pour le temps consacré à cette demande.

Cordialement,

[Nom]
[Adresse e-mail]
Paquet Android : `com.corankarim.coran_karim`

---
---

# RELANCE — 2026-08-10, après leur accord

**Ils ont dit oui** (réponse du 2026-08-10) : stockage hors ligne de l'audio ET
du texte autorisé, attribution « Qur'anic text and recitations: Quran.com »
validée, dons acceptés **sans licence commerciale séparée**.

Trois conditions à retenir :
1. **Contrôle des changements au moins tous les 7 jours** dès que le réseau est
   disponible, avec rattrapage au retour de connectivité, et application
   effective des mises à jour / suppressions / remplacements. L'app peut
   continuer à embarquer une copie de base, mais doit pouvoir la mettre à jour.
   → **À développer, ça n'existe pas aujourd'hui.**
2. **Migration** vers les Content APIs actuelles avec identifiants client.
3. Leur accord **ne couvre pas les tiers** : traductions (Montada) et
   récitations gardent leurs propres licences et attributions.

Cette relance ne porte que sur **un point technique de la migration** :
l'application n'a aucun serveur, or leur documentation impose de garder les
identifiants côté serveur et délivre des clients *confidentiels* par défaut.

À envoyer **en réponse dans le même fil**, à `developers@quran.com`.

## Version anglaise — à envoyer

Dear Quran Foundation team,

Thank you for such a fast and clear answer, and for granting the permission. It is noted along with its conditions: the content stays integral to the application, the Qur'anic text is never modified, and I will keep third-party attributions separate from yours.

I have started work on the seven-day check. The application will look for content changes whenever connectivity is available, apply any updates, deletions or replacements, and perform the overdue check when it comes back online after a period offline. I will use Content Sync for the supported resources and refresh the rest from the current API on the same schedule.

One question before I migrate to the Content APIs.

*Coran Karim* has no backend of any kind. The speech-recognition model runs on the device, and there is no server of mine anywhere in the architecture — that is the whole point of the application. Your documentation states that credentials must be stored server-side only, and that clients issued through Request Access are confidential by default. A `client_secret` shipped inside an Android package can be extracted from it, and it would be my client that is then abused.

**Would you be able to issue a public client for this application** — one without a client secret, and if it helps, restricted to the Android application ID `com.corankarim.coran_karim` and to its signing certificate?

If that is not possible, I will put a minimal token broker in front of the API: a small server-side endpoint that holds the secret and hands the application nothing but short-lived access tokens. I would rather ask than assume — if that is the pattern you expect from mobile applications, please say so and I will build it that way.

Thank you again for your time.

Kind regards,

[Name]
[Email address]
Android package: `com.corankarim.coran_karim`

## Traduction française — pour ta lecture

Chère équipe de Quran Foundation,

Merci pour cette réponse aussi rapide que claire, et pour l'autorisation accordée. Elle est bien notée, avec ses conditions : le contenu reste indissociable de l'application, le texte coranique n'est jamais modifié, et je maintiendrai les attributions des tiers distinctes de la vôtre.

J'ai commencé le travail sur le contrôle à sept jours. L'application recherchera les changements de contenu dès qu'une connexion est disponible, appliquera les mises à jour, suppressions ou remplacements, et effectuera le contrôle en retard au retour de la connectivité après une période hors ligne. J'utiliserai Content Sync pour les ressources prises en charge et rafraîchirai les autres depuis l'API actuelle au même rythme.

Une question avant d'entreprendre la migration vers les Content APIs.

*Coran Karim* n'a aucun serveur. Le modèle de reconnaissance de la parole s'exécute sur l'appareil, et il n'existe aucun serveur m'appartenant dans l'architecture — c'est précisément la raison d'être de l'application. Votre documentation indique que les identifiants doivent être conservés côté serveur uniquement, et que les clients délivrés via Request Access sont confidentiels par défaut. Or un `client_secret` embarqué dans un paquet Android peut en être extrait, et c'est alors mon client qui serait utilisé abusivement.

**Pourriez-vous délivrer un client public pour cette application** — sans secret client, et si cela vous est utile, restreint à l'identifiant d'application Android `com.corankarim.coran_karim` et à son certificat de signature ?

Si ce n'est pas possible, je placerai un relais de jetons minimal devant l'API : un petit point d'accès côté serveur qui détient le secret et ne transmet à l'application que des jetons d'accès de courte durée. Je préfère demander plutôt que supposer — si c'est le schéma que vous attendez des applications mobiles, dites-le-moi et je le construirai ainsi.

Merci encore pour votre temps.

Cordialement,

[Nom]
[Adresse e-mail]
Paquet Android : `com.corankarim.coran_karim`
