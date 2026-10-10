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
- MongoDB embarqué (défaut) : nœuds x86-64 avec AVX (exigence de MongoDB ≥ 5.0)
  et une StorageClass pour le volume de données.

## Installation

Le chart est publié sur GHCR (OCI). Partez d'un des fichiers d'exemple et
éditez-le (au minimum `conf.host_id`, voir plus bas) :

```bash
helm install pritunl oci://ghcr.io/matvi-consulting/charts/pritunl \
  --version 2.0.1 -n vpn --create-namespace \
  -f values-wg-only-ovh.yaml
```

Depuis les sources :

```bash
helm dependency build
helm install pritunl . -n vpn --create-namespace \
  -f examples/values-wg-only-ovh.yaml
```

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

## Plusieurs serveurs Pritunl

Chaque serveur Pritunl écoute sur **son propre port**. Le créer dans l'UI ne
suffit pas : tant que le port n'est pas publié sur le Service, le LoadBalancer ne
route rien et le client time-out. Déclarez un `service.extraPorts` par serveur
au-delà du premier :

```yaml
service:
  openvpn:
    enabled: false
  wireguard:
    enabled: true
    port: 1195            # serveur « prod »
  extraPorts:
    - { name: wg-staging, port: 1197 }                    # serveur « staging »
    - { name: ovpn-partners, port: 1198, protocol: TCP }  # serveur OpenVPN
```

- `name` : contrainte IANA_SVC_NAME (minuscules, chiffres, tirets, ≤ 15 caractères).
- `port` : numéro **distinct de tous les autres**, protocoles confondus (443 inclus).
- `protocol` : `UDP` par défaut (WireGuard), `TCP` pour un serveur OpenVPN.

Le chart valide ces trois règles au rendu et échoue avec un message explicite
plutôt que de produire un Service silencieusement amputé d'un port.

Tous les ports partagent le **même** Service, donc la même IP publique : la
Public Address reste valable pour l'ensemble des serveurs et les profils clients
déjà distribués ne sont pas invalidés.

> **Piège Pritunl.** Un serveur a deux ports : son port serveur (`Port` +
> `Protocol`, OpenVPN) *et* son `WireGuard Port`. Pritunl impose l'unicité des
> deux **entre tous les serveurs**, y compris pour le port OpenVPN que vous
> n'exposez pas. Prévoyez donc un couple de numéros libres par serveur, et ne
> publiez ici que le port réellement utilisé par les clients.

> **Réplicas.** Restez à `replicas: 1`. L'état WireGuard (handshakes, peers) est
> local au pod : avec plusieurs réplicas, le LoadBalancer répartit les flux UDP
> et les sessions cassent de façon aléatoire.

## MongoDB & secrets

Trois stratégies, sélectionnées par les valeurs :

| Stratégie | Activation | Pour qui |
| --------- | ---------- | -------- |
| **(a) Auto-contenu** (défaut) | `mongodb.enabled: true`, rien d'autre | Déploiement simple, tout-en-un |
| **(b) existingSecret** | `mongoDBUriSecretName: <secret>` (+ `mongodb.enabled: false` si Mongo externe) | GitOps (SealedSecrets/ExternalSecrets), Mongo managé |
| **(c) URI inline** | `mongoURI: mongodb://...` | Outils qui injectent la valeur au déploiement (Pulumi/Terraform) — **jamais committé** |

- **(a)** Le chart déploie MongoDB à partir de l'image Docker officielle
  (`mongo` sur Docker Hub, 8.0 par défaut) et auto-génère les mots de passe
  (Secret `<release>-mongodb`, clés `mongodb-passwords` pour l'utilisateur
  applicatif et `mongodb-root-password` pour `root`). Le chart construit l'URI
  et injecte le mot de passe en variable `PRITUNL_MONGODB_PASSWORD`. Aucun
  secret à fournir. Le PVC est annoté `helm.sh/resource-policy: keep` : il
  survit à un `helm uninstall`.
- **(b)** Le Secret doit contenir l'URI complète sous la clé `mongoDBUriSecretKey`
  (défaut `PRITUNL_MONGODB_URI`).
- **(c)** Le chart crée un Secret `<release>-mongo-secrets`. Ne mettez jamais de
  vraie valeur `mongoURI` dans un fichier committé.

### Mise à jour depuis le chart 1.x (MongoDB Bitnami)

Le chart 2.0 remplace le subchart Bitnami par l'image officielle `mongo`. Le
`helm upgrade` reprend **en place** le PVC, le Secret (mêmes mots de passe) et
le Service `<release>-mongodb` : pas de dump/restore. MongoDB passe de 7.0 à 8.0
au démarrage ; la *featureCompatibilityVersion* reste à `7.0`, ce qui permet de
revenir en arrière.

1. Retirez de vos values les clés propres à Bitnami (`mongodb.image.registry`,
   `mongodb.architecture`, `mongodb.strategyType`, `mongodb.auth.enabled`…). Le
   chart refuse de s'installer si `mongodb.image.registry` est encore présent.
2. `helm upgrade pritunl oci://ghcr.io/matvi-consulting/charts/pritunl --version 2.0.1 -n vpn -f <vos-values>.yaml`
   (MongoDB est indisponible le temps du redémarrage).
3. Une fois validé, montez la FCV (étape nécessaire avant une future 9.0, mais
   qui rend le retour à 7.0 impossible) :

   ```bash
   kubectl -n vpn exec deploy/pritunl-mongodb -- sh -c \
     'mongosh -u root -p "$MONGO_INITDB_ROOT_PASSWORD" --quiet \
       --eval "db.adminCommand({setFeatureCompatibilityVersion: \"8.0\", confirm: true})"'
   ```

**Retour au chart 1.x** (tant que la FCV est à `7.0`) : arrêtez d'abord MongoDB,
car l'ancien chart démarre le nouveau pod avant d'arrêter l'ancien et bute sur
le verrou des données :

```bash
kubectl -n vpn scale deploy/pritunl-mongodb --replicas=0
helm rollback pritunl <révision> -n vpn
```

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
| `service.extraPorts` | `[]` | Ports des serveurs Pritunl additionnels (`name`/`port`/`protocol`) |
| `service.web.enabled` / `.port` | `true` / `443` | Expose HTTPS (auth WG) — requis |
| `service.annotations` | `{}` | Annotations LB (ex. octavia) |
| `mongodb.enabled` | `true` | MongoDB embarqué (image officielle `mongo`) |
| `mongodb.image.repository` / `.tag` | `mongo` / `8.0.32` | Image MongoDB |
| `mongodb.persistence.size` / `.storageClass` | `10Gi` / `""` | Volume des données |
| `mongodb.resources` | 100m/256Mi → 750m/768Mi | Ressources du conteneur MongoDB |
| `mongoDBUriSecretName` / `mongoDBUriSecretKey` | `""` / `PRITUNL_MONGODB_URI` | Secret externe (stratégie b) |
| `conf.host_id` | `""` | Identifiant d'instance (à définir) |

## Publier une version

1. Monter `version` dans `Chart.yaml` (SemVer : majeure si les values ou les
   ressources changent de façon incompatible) et compléter le
   [CHANGELOG](CHANGELOG.md).
2. Après merge sur `main`, taguer le commit : `git tag -a vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z`.
3. Le workflow *Release Chart* publie `oci://ghcr.io/matvi-consulting/charts/pritunl:X.Y.Z`.

## Licence

Voir [LICENSE](LICENSE).
