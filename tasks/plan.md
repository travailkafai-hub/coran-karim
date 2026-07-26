# Plan d'implémentation : streaming causal FastConformer

## Vue d'ensemble

La bascule est menée du contrat vers l'application. Le risque le plus élevé,
l'export ONNX stateful, est prouvé hors device avant toute modification du flux
de récitation. L'activation applicative reste réversible.

## Décisions d'architecture

- Conserver le contexte entraîné `[70,13]` au lieu de muter le modèle à
  `[70,1]` pendant l'export.
- Exporter un petit fichier de métadonnées avec les dimensions de streaming,
  afin que Kotlin ne dépende plus des constantes de l'ancien modèle.
- Séparer l'état d'inférence causal du moteur stateless et ne garder qu'une
  session lourde en mémoire.
- Réutiliser `ForcedAligner` et le format de payload existant.
- Conserver `BufferedTranscriber` intact comme fallback.

## Dépendances

```text
Export stateful validé
    -> contrat/métadonnées
        -> session Kotlin et tests
            -> MethodChannel
                -> orchestration Dart
                    -> validation device
```

## Phases

### Phase 1 : contrat du modèle

- Ajouter un test de contrat qui échoue sur l'exporteur historique.
- Exporter le checkpoint causal entraîné avec ses caches.
- Valider plusieurs chunks PyTorch contre ONNX et produire les métadonnées.

### Point de contrôle 1

- Entrées ONNX : `audio_signal`, `length`, trois caches.
- Cache temporel de 8 frames, fenêtre de 121, avance de 112.
- Écart numérique multi-chunks inférieur à `1e-3`.

### Phase 2 : moteur Android

- Tester puis implémenter la configuration de streaming.
- Tester puis implémenter le collapse CTC inter-chunks et le reset.
- Adapter la session ONNX et exposer les log-probabilités incrémentales à
  l'alignement.

### Point de contrôle 2

- Tests Android verts.
- Build Android/Flutter réussi.
- Aucun chargement simultané des deux sessions lourdes.

### Phase 3 : orchestration Flutter

- Résoudre le modèle stateful depuis le même dossier causal.
- Utiliser le causal pour le mode continu.
- Retomber explicitement sur `BufferedTranscriber` si le stateful est absent.
- Réinitialiser l'état sur arrêt, correction et nouvelle session.

### Point de contrôle 3

- Tests Flutter connus comparés à la ligne de base.
- APK debug installé.
- Log device : modèle causal stateful chargé, cache croissant, texte non vide.

## Risques et mitigations

| Risque | Impact | Mitigation |
|---|---|---|
| Contrat ONNX différent du prototype | Crash natif | Métadonnées exportées et validation multi-chunks |
| Normalisation en ligne instable | Texte vide au début | Comparaison Python puis test réel avant activation définitive |
| Session double en mémoire | OOM sur téléphone 6 Go | Fermeture explicite avant changement de moteur |
| Doublon CTC à la frontière | Mots répétés | Test unitaire avec token identique sur deux chunks |
| État réutilisé après correction | Mauvais alignement | Reset atomique caches + décodeur + alignement |
| Régression de jugement | Faux verdicts | Payload existant, fallback conservé, activation réversible |

## Questions ouvertes pendant l'implémentation

- La normalisation cumulative du prototype est-elle suffisante avec le modèle
  réellement causal ? La validation multi-chunks et le device doivent trancher.
- Le gel des erreurs doit-il rester lié aux pauses lors de ce premier portage,
  ou les sorties couvertes et stables suffisent-elles ? Le comportement actuel
  est conservé tant que le nouveau flux n'est pas mesuré.
