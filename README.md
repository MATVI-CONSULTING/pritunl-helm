# pritunl-helm

Chart Helm mutualisé pour déployer [Pritunl](https://pritunl.com/) (VPN OpenVPN /
WireGuard) auto-hébergé sur Kubernetes, avec MongoDB embarqué ou externe.

Par défaut, le chart déploie **OpenVPN** (TCP 1194). WireGuard est une **variante
opt-in** (voir [WireGuard : points clés](#wireguard--points-clés) et
`examples/values-wg-only-ovh.yaml`).

## Prérequis

- Kubernetes ≥ 1.26 (multi-protocole LoadBalancer TCP+UDP requis pour WireGuard).
- Un provider de LoadBalancer (ex. OVHcloud Octavia).
- Le pod tourne en `privileged` + `NET_ADMIN` (création de l'interface tun/WG) —
  vérifiez vos Pod Security Standards / PSA.
- Helm 3.

## Installation

```bash
helm dependency build
helm install pritunl . -n vpn --create-namespace \
  -f examples/values-wg-only-ovh.yaml
```

Éditez d'abord l'exemple choisi (au minimum `conf.host_id`, voir plus bas).

## Variantes

| Fichier d'exemple | Cas d'usage |
| ----------------- | ----------- |
| `examples/values-wg-only-ovh.yaml` | WireGuard seul, OVHcloud (LB Octavia), MongoDB embarqué |
| `examples/values-external-mongo.yaml` | MongoDB externe / GitOps via `existingSecret` |
| `examples/values-openvpn.yaml` | OpenVPN + WireGuard |

## WireGuard : points clés

WireGuard n'est **pas** activé par défaut (le défaut est OpenVPN). Pour l'activer :

- **WireGuard seul** = `service.openvpn.enabled: false`, `service.wireguard.enabled: true`
  (UDP), `service.web.enabled: true` (TCP 443). Voir `examples/values-wg-only-ovh.yaml`.
- **Le port 443 est OBLIGATOIRE** : l'authentification WireGuard de Pritunl fait
  d'abord une requête HTTPS sur 443 (port codé en dur en version gratuite) pour
  récupérer la clé publique du serveur, avant d'ouvrir le tunnel UDP. Sans 443
  joignable à la Public Address, le client reste bloqué (`wg_server_pub_key=false`).
- **Même IP publique** : le client utilise une seule Public Address pour l'auth
  HTTPS et le tunnel UDP → le LoadBalancer doit porter TCP 443 **et** UDP 1195 à
  la même IP.
- **OVHcloud** : annotation `loadbalancer.ovhcloud.com/class: octavia` sur le
  Service (requise pour un LB multi-protocole). Voir l'exemple OVH.
- **Ports distincts** : WireGuard (1195) ≠ OpenVPN (1194) — un même numéro
  TCP/UDP entre en collision sur la fusion des ports.
- **Client** : l'app WireGuard native ne fonctionne pas avec Pritunl ; utiliser le
  client Pritunl officiel et choisir le mode **WG**. (Détails et pièges macOS dans
  la doc `pritunl-docker-image/docs/wireguard.md`.)

## MongoDB & secrets

Trois stratégies, sélectionnées par les valeurs :

| Stratégie | Activation | Pour qui |
| --------- | ---------- | -------- |
| **(a) Auto-contenu** (défaut) | `mongodb.enabled: true`, rien d'autre | Déploiement simple, tout-en-un |
| **(b) existingSecret** | `mongoDBUriSecretName: <secret>` (+ `mongodb.enabled: false` si Mongo externe) | GitOps (SealedSecrets/ExternalSecrets), Mongo managé |
| **(c) URI inline** | `mongoURI: mongodb://...` | Outils qui injectent la valeur au déploiement (Pulumi/Terraform) — **jamais committé** |

- **(a)** Le subchart Bitnami auto-génère le mot de passe (Secret `<release>-mongodb`,
  clé `mongodb-passwords`). Le chart construit l'URI et injecte le mot de passe en
  variable `PRITUNL_MONGODB_PASSWORD`. Aucun secret à fournir.
- **(b)** Le Secret doit contenir l'URI complète sous la clé `mongoDBUriSecretKey`
  (défaut `PRITUNL_MONGODB_URI`).
- **(c)** Le chart crée un Secret `<release>-mongo-secrets`. Ne mettez jamais de
  vraie valeur `mongoURI` dans un fichier committé.

## `conf.host_id` (à définir par instance)

`conf.host_id` identifie l'instance et **persiste les réglages** (dont la Public
Address) entre redémarrages. Il est **vide par défaut** : chaque déploiement doit
fixer une valeur unique.

```bash
openssl rand -hex 16
```

## Post-installation

```bash
# Mot de passe admin par défaut
POD=$(kubectl get pod -n vpn -l app=pritunl,release=pritunl -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n vpn -it "$POD" -- pritunl default-password

# IP publique du LoadBalancer
kubectl get svc -n vpn pritunl -o wide
```

Puis, dans l'UI Pritunl (Settings du serveur) : régler la **Public Address** sur
l'IP du LoadBalancer et le **WG Port** sur `service.wireguard.port` (1195).

## Valeurs principales

| Clé | Défaut | Description |
| --- | ------ | ----------- |
| `image.repository` / `image.tag` | image Matvi épinglée au SHA | Image Pritunl |
| `service.type` | `LoadBalancer` | Type de Service |
| `service.openvpn.enabled` | `true` | Expose OpenVPN (TCP 1194) |
| `service.wireguard.enabled` / `.port` | `false` / `1195` | Expose WireGuard (UDP) — opt-in |
| `service.web.enabled` / `.port` | `true` / `443` | Expose HTTPS (auth WG) — requis |
| `service.annotations` | `{}` | Annotations LB (ex. octavia) |
| `mongodb.enabled` | `true` | MongoDB embarqué (subchart Bitnami) |
| `mongoDBUriSecretName` / `mongoDBUriSecretKey` | `""` / `PRITUNL_MONGODB_URI` | Secret externe (stratégie b) |
| `conf.host_id` | `""` | Identifiant d'instance (à définir) |

## Licence

Voir [LICENSE](LICENSE).
