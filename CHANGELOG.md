# Changelog

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) ;
versions du chart en [SemVer](https://semver.org/lang/fr/).

## [2.2.0] - 2026-10-29

### Ajouté

- Valeur `strategy` pour le Deployment Pritunl (vide par défaut : comportement
  inchangé). `type: Recreate` + `rollingUpdate: null` évite qu'une mise à jour
  reste bloquée sur un cluster sans marge CPU (nouveau pod Pending tant que
  l'ancien tourne).

## [2.1.0] - 2026-10-10

### Supprimé

- Dépendance à la bibliothèque Bitnami `common` (dépôt d'archive gelé) : le
  chart n'a plus aucune dépendance, plus besoin de `helm dependency build`.

### Corrigé

- Ingress : `pathType` manquant (refusé par l'API `networking.k8s.io/v1`) et
  backend pointant vers un port 80 inexistant sur le Service `-web` (443).

### Ajouté

- Valeurs par défaut `ingress.className`, `hostname`, `path`, `annotations`.

## [2.0.1] - 2026-10-10

### Modifié

- Image MongoDB référencée `mongo` (Docker Hub) au lieu de
  `docker.io/library/mongo` : même image, mais Dependabot peut désormais la
  suivre (il traitait l'hôte explicite comme un registre privé).

### Documentation

- README : installation depuis GHCR, procédure de publication ; ajout de ce
  CHANGELOG.

## [2.0.0] - 2026-10-10

### Modifié (incompatible)

- Le MongoDB embarqué utilise l'image Docker officielle `mongo` (8.0.32) à la
  place du subchart Bitnami (image `bitnamilegacy/mongodb` 7.0, gelée). Les
  clés de values propres à Bitnami (`mongodb.image.registry`,
  `mongodb.architecture`, `mongodb.strategyType`, `mongodb.auth.enabled`…) ne
  sont plus supportées ; nouvelles clés : `mongodb.image.repository`/`tag`,
  `mongodb.persistence.storageClass`, `mongodb.resources`.
- Migration depuis 1.x **en place** (même PVC, mêmes mots de passe) : voir
  « Mise à jour depuis le chart 1.x » dans le README.

### Ajouté

- PVC MongoDB annoté `helm.sh/resource-policy: keep`.
- Erreur explicite si des values Bitnami sont encore présentes.

### Corrigé

- L'URI MongoDB pointait vers un Service inexistant quand le nom de release ne
  contenait pas « pritunl ».
- Stratégie `Recreate` réellement appliquée au MongoDB (volume RWO).

### Dépendances

- `common` 2.41.0 (Bitnami).

## [1.1.0] - 2026-08-14

### Ajouté

- Plusieurs serveurs Pritunl : ports additionnels via `service.extraPorts`.

## [1.0.0] - 2026-07-13

- Première version : chart Pritunl mutualisé multi-client (OpenVPN, WireGuard
  opt-in, MongoDB embarqué ou externe).

[2.1.0]: https://github.com/MATVI-CONSULTING/pritunl-helm/compare/v2.0.1...v2.1.0
[2.0.1]: https://github.com/MATVI-CONSULTING/pritunl-helm/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/MATVI-CONSULTING/pritunl-helm/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/MATVI-CONSULTING/pritunl-helm/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/MATVI-CONSULTING/pritunl-helm/releases/tag/v1.0.0
