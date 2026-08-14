{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "pritunl.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "pritunl.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "pritunl.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "pritunl.labels" -}}
app: {{ include "pritunl.name" . }}
helm.sh/chart: {{ include "pritunl.chart" . }}
release: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "pritunl.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "pritunl.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Pritunl mongodb uri template
*/}}
{{- define "pritunl.mongodbUriTemplate" -}}
{{- if .Values.mongodbUriTemplate -}}
{{ .Values.mongodbUriTemplate }}
{{- else if and .Values.mongodb.auth.username .Values.mongodb.auth.database -}}
{{- $fullName := include "pritunl.fullname" . -}}
{{- printf "mongodb://%s:$PRITUNL_MONGODB_PASSWORD@%s-mongodb/%s" .Values.mongodb.auth.username $fullName .Values.mongodb.auth.database -}}
{{- end -}}
{{- end -}}

{{/*
Liste canonique des ports VPN (nom, numéro, protocole), partagée par le Service
et le Deployment pour éviter de dupliquer la logique. Un serveur Pritunl = un
port : les serveurs au-delà du premier se déclarent dans service.extraPorts.
Le port https n'y figure pas, son conteneur écoute toujours 443.
*/}}
{{- define "pritunl.vpnPorts" -}}
{{- $ports := list -}}
{{- if .Values.service.openvpn.enabled -}}
{{- $ports = append $ports (dict "name" "openvpn" "port" (.Values.service.port | int) "protocol" .Values.service.protocol) -}}
{{- end -}}
{{- if .Values.service.wireguard.enabled -}}
{{- $ports = append $ports (dict "name" "wireguard" "port" (.Values.service.wireguard.port | int) "protocol" "UDP") -}}
{{- end -}}
{{- range .Values.service.extraPorts -}}
{{- $ports = append $ports (dict "name" .name "port" (.port | int) "protocol" (default "UDP" .protocol)) -}}
{{- end -}}
{{- toYaml $ports -}}
{{- end -}}

{{/*
Garde-fous sur les ports du Service. Deux entrées de même numéro se recouvrent :
la clé de fusion des ports côté Kubernetes est le NUMÉRO seul, donc un doublon
TCP/UDP fait disparaître silencieusement l'une des deux à l'upgrade. Les noms
doivent par ailleurs respecter IANA_SVC_NAME (<= 15 caractères, minuscules).
*/}}
{{- define "pritunl.validatePorts" -}}
{{- $all := fromYamlArray (include "pritunl.vpnPorts" .) -}}
{{- if .Values.service.web.enabled -}}
{{- $all = append $all (dict "name" "https" "port" (.Values.service.web.port | int)) -}}
{{- end -}}
{{- $names := dict -}}
{{- $numbers := dict -}}
{{- range $all -}}
{{- $name := .name -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $name) -}}
{{- fail (printf "pritunl: nom de port %q invalide (minuscules, chiffres et tirets uniquement)" $name) -}}
{{- end -}}
{{- if gt (len $name) 15 -}}
{{- fail (printf "pritunl: nom de port %q trop long (15 caractères maximum)" $name) -}}
{{- end -}}
{{- if hasKey $names $name -}}
{{- fail (printf "pritunl: nom de port %q déclaré deux fois" $name) -}}
{{- end -}}
{{- $_ := set $names $name true -}}
{{- $number := printf "%d" (.port | int) -}}
{{- if hasKey $numbers $number -}}
{{- fail (printf "pritunl: port %s déclaré deux fois ; chaque serveur Pritunl doit avoir un numéro distinct, protocoles confondus" $number) -}}
{{- end -}}
{{- $_ := set $numbers $number true -}}
{{- end -}}
{{- end -}}

{{/*
Return true if cert-manager required annotations for TLS signed certificates are set in the Ingress annotations
Ref: https://cert-manager.io/docs/usage/ingress/#supported-annotations
*/}}
{{- define "pritunl.ingress.certManagerRequest" -}}
{{ if or (hasKey . "cert-manager.io/cluster-issuer") (hasKey . "cert-manager.io/issuer") (hasKey . "kubernetes.io/tls-acme") }}
    {{- true -}}
{{- end -}}
{{- end -}}
