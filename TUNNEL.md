# Déploiement à distance via NordVPN Meshnet

## Topologie
- **PC A** (dev, ce PC) : `100.93.87.133`
- **PC B** (avec téléphone branché) : `100.126.49.93` — user `kafai`
- Téléphone Android : `R3CY20XW7TD` (Samsung S931B)
- Réseau : NordVPN Meshnet (les deux PCs doivent avoir Meshnet actif)

---

## Prérequis (déjà configurés, ne pas refaire)

### Sur PC B
- Serveur SSH installé et démarré automatiquement (`sshd`)
- Clé SSH de PC A autorisée dans `C:\ProgramData\ssh\administrators_authorized_keys`
- ADB disponible à `C:\Users\kafai\platform-tools\adb.exe`
- Permissions du fichier authorized_keys : SYSTEM + Administrateurs uniquement

### Sur PC A
- Clé SSH privée : `C:\Users\Adam\.ssh\id_ed25519`
- ADB : `C:\Users\Adam\AppData\Local\Android\Sdk\platform-tools\adb.exe`

---

## Procédure à chaque session

### Étape 0 — Sur PC A : libérer le port 5037 AVANT toute chose
Un `adb.exe` local (déjà lancé plus tôt dans la session, ex. par un simple
`adb devices` sans tunnel) squatte souvent 127.0.0.1:5037 — le tunnel de
l'étape 2 échoue alors en silence côté IPv4 ("bind ... Permission denied",
visible seulement dans les logs du tunnel) et retombe sur IPv6 seul, qu'adb
n'utilise pas. **Ne JAMAIS lancer de commande `adb` locale entre l'étape 0 et
la vérification de l'étape 2** (ça respawn un serveur local et recasse tout).
```bash
netstat -ano | grep ":5037"
# Si une ligne LISTENING apparaît, tuer le PID correspondant :
powershell -Command "Stop-Process -Id <PID> -Force"
```

### Étape 1 — Sur PC A : lancer une session SSH PERSISTANTE qui garde ADB
vivant sur PC B (bloque exprès en arrière-plan)
Un simple `ssh ... "adb start-server"` qui retourne immédiatement NE SUFFIT
PAS sur Windows : OpenSSH lie les processus enfants de la session à un Job
Object qui les tue tous dès que la session se termine — le serveur adb meurt
avec elle (constaté 2026-07-11, `protocol fault` côté PC A malgré un
`adb devices` réussi côté PC B juste avant). Il faut une session qui NE FERME
JAMAIS :
```bash
/c/Windows/System32/OpenSSH/ssh.exe -o StrictHostKeyChecking=no \
  -i ~/.ssh/id_ed25519 kafai@100.126.49.93 \
  "C:\\Users\\kafai\\platform-tools\\adb.exe start-server && ping -t localhost > NUL"
```
Lancer via `run_in_background: true` (Bash tool) et **laisser tourner** tout
le long de la session de travail — c'est elle qui maintient le serveur adb en
vie côté PC B, pas une commande one-shot.

### Étape 2 — Sur PC A : ouvrir le tunnel SSH (session séparée, elle aussi persistante)
```bash
/c/Windows/System32/OpenSSH/ssh.exe -o StrictHostKeyChecking=no -o ConnectTimeout=15 \
  -i ~/.ssh/id_ed25519 -N -L 5037:127.0.0.1:5037 kafai@100.126.49.93
```
Lancer aussi via `run_in_background: true`. Vérifier qu'un SEUL PID écoute
sur LES DEUX `127.0.0.1:5037` ET `[::1]:5037` (pas deux PID différents — signe
que le bind IPv4 a échoué, cf. étape 0) :
```bash
netstat -ano | grep ":5037.*LISTENING"
```

### Étape 3 — Sur PC A : vérifier et lancer Flutter
```powershell
$ADB = "C:\Users\Adam\AppData\Local\Android\Sdk\platform-tools\adb.exe"
& $ADB devices
# Doit afficher R3CY20XW7TD  device

cd "D:\Coran Karim\app"
flutter run -d R3CY20XW7TD
# ou pour juste installer un APK déjà buildé :
& $ADB install -r "D:\Coran Karim\app\build\app\outputs\flutter-apk\app-debug.apk"
```

---

## Points importants

- **Ne jamais lancer `adb kill-server` depuis PC A** quand le tunnel est actif — ça tue le serveur ADB sur PC B.
- Si le tunnel est déjà actif (port 5037 occupé), vérifier avec `netstat -ano | findstr :5037` avant de relancer.
- Si le téléphone affiche `unauthorized` : accepter la popup "Autoriser le débogage USB" sur l'écran du téléphone.
- Le tunnel SSH est sans mot de passe grâce à la clé ed25519 configurée.

---

## Dépannage

| Symptôme | Cause | Solution |
|---|---|---|
| `bind [127.0.0.1]:5037: Permission denied` (dans les logs du tunnel) | Un `adb.exe` local (PC A) a respawné un serveur et squatte déjà le port IPv4 — le tunnel ne récupère alors que l'IPv6 | Tuer le PID adb local (`netstat -ano \| grep ":5037"` puis `Stop-Process`), tuer aussi le tunnel cassé, relancer le tunnel EN PREMIER, ne plus toucher à `adb` local avant |
| `protocol fault (couldn't read status)` côté PC A alors que `adb devices` réussit côté PC B juste avant | Le serveur adb sur PC B est mort avec la session SSH qui l'a lancé (Job Object Windows tue les enfants à la fermeture de session — un `ssh ... "adb start-server"` qui retourne immédiatement ne suffit PAS) | Relancer via une session SSH qui reste ouverte exprès (`adb start-server && ping -t localhost > NUL`, en arrière-plan, jamais fermée) — cf. étape 1 |
| Deux PID différents écoutent sur `127.0.0.1:5037` et `[::1]:5037` | Bind IPv4 du tunnel échoué (cf. 1ère ligne), un autre process (souvent adb local) a pris l'IPv4 | Même fix que la 1ère ligne |
| `unauthorized` | Téléphone n'a pas accepté le debug USB | Accepter la popup "Autoriser le débogage USB" sur l'écran du téléphone |
| `Permission denied (publickey)` | Clé SSH mal configurée sur PC B | Vérifier `C:\ProgramData\ssh\administrators_authorized_keys` — doit être une seule ligne |
| Liaison mesh très instable (pertes de paquets élevées, `ping` PC A→PC B montre >50% de perte) — le tunnel ne tient jamais assez longtemps pour un `adb install` (constaté 2026-07-11, ~62% de perte, sessions coupées en quelques secondes) | Le lien réseau lui-même est dégradé (pas juste adb/SSH) | **Contourner le tunnel entièrement** : `scp` l'APK directement vers PC B (`scp -i ~/.ssh/id_ed25519 app.apk kafai@100.126.49.93:/Users/kafai/`), puis `adb install` **localement sur PC B** via une commande SSH exec (pas de forwarding de port impliqué). scp ne reprend pas un transfert interrompu — relancer en boucle (`while ! scp ...; do sleep 5; done`) jusqu'à tomber sur une fenêtre assez longue plutôt que de retenter à la main. Un APK volumineux (build debug ~340 Mo) aggrave le problème — un `flutter build apk --release` réduit nettement la taille si le lien reste mauvais |
