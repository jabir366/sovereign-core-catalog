{{/*
Expand the name of the chart.
*/}}
{{- define "mongodb-vm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name (base, without member index).
*/}}
{{- define "mongodb-vm.fullname" -}}
{{- if .Values.instance.name }}
{{- .Values.instance.name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Per-member VM name  — called with a dict: (dict "Values" .Values "Chart" .Chart "Release" .Release "index" $i)
Standalone:  <fullname>
HA member:   <fullname>-<index>   e.g. my-instance-0
*/}}
{{- define "mongodb-vm.memberName" -}}
{{- $base := include "mongodb-vm.fullname" . -}}
{{- if .Values.ha.enabled -}}
{{- printf "%s-%d" $base (int .index) | trunc 63 | trimSuffix "-" }}
{{- else -}}
{{- $base }}
{{- end }}
{{- end }}

{{/*
Per-member DataVolume name.
Standalone:  <fullname>-disk
HA member:   <fullname>-<index>-disk
*/}}
{{- define "mongodb-vm.memberDvName" -}}
{{- $base := include "mongodb-vm.fullname" . -}}
{{- if .Values.ha.enabled -}}
{{- printf "%s-%d-disk" $base (int .index) | trunc 63 | trimSuffix "-" }}
{{- else -}}
{{- printf "%s-disk" $base }}
{{- end }}
{{- end }}

{{/*
DataVolume name — legacy helper kept for backward compatibility (standalone path).
*/}}
{{- define "mongodb-vm.dvName" -}}
{{ include "mongodb-vm.fullname" . }}-disk
{{- end }}

{{/*
Headless service name (HA only) — used as the DNS domain for replica-set member discovery.
Members are reachable at <memberName>.<headlessSvcName>.<namespace>.svc.cluster.local
*/}}
{{- define "mongodb-vm.headlessSvcName" -}}
{{- printf "%s-headless" (include "mongodb-vm.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mongodb-vm.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "mongodb-vm.name" . }}
app.kubernetes.io/instance: {{ include "mongodb-vm.fullname" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "mongodb-vm.annotations" -}}
{{- with .Values.commonAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Cloud-init userdata — standalone (no replica set).
*/}}
{{- define "mongodb-vm.userdata" -}}
#cloud-config
user: root
password: {{ .Values.mongodb.vmRootPassword }}
chpasswd:
  expire: false
ssh_pwauth: true
write_files:
  - path: /etc/mongo-init-env
    content: |
      DB_NAME={{ .Values.mongodb.databaseName }}
      DB_USER={{ .Values.mongodb.databaseUser }}
      DB_PASS={{ .Values.mongodb.databasePassword }}
      ADMIN_PASS={{ .Values.mongodb.rootPassword }}
    permissions: '0600'
runcmd:
  - set -a && . /etc/mongo-init-env && set +a && /usr/local/bin/mongo-first-boot.sh
{{- end }}

{{/*
Cloud-init userdata — HA replica-set member.
Called with a dict: (dict "Values" .Values "Chart" .Chart "Release" .Release "index" $i)

Every member:
  - writes /etc/mongo-init-env (credentials + replica-set config)
  - calls /usr/local/bin/mongo-first-boot.sh (must handle RS mode via MONGO_RS_* env vars)

Member-0 additionally:
  - calls /usr/local/bin/mongo-rs-init.sh which runs rs.initiate() with all member hosts
*/}}
{{- define "mongodb-vm.userdata.ha" -}}
{{- $base    := include "mongodb-vm.fullname" . -}}
{{- $svc     := include "mongodb-vm.headlessSvcName" . -}}
{{- $ns      := .Values.namespaceOverride | default .Release.Namespace -}}
{{- $rsName  := .Values.ha.replicaSetName -}}
{{- $port    := int .Values.ha.port -}}
{{- $count   := int .Values.ha.replicaCount -}}
{{- $idx     := int .index -}}
{{- $selfHost := printf "%s-%d.%s.%s.svc.cluster.local" $base $idx $svc $ns -}}
{{- /* Build the full member host list for rs.initiate() on member-0 */ -}}
{{- $members := list -}}
{{- range $i := until $count -}}
{{- $host := printf "%s-%d.%s.%s.svc.cluster.local:%d" $base $i $svc $ns $port -}}
{{- $members = append $members $host -}}
{{- end -}}
{{- $memberList := join "," $members -}}
{{- /*
  keyFile is generated ONCE in virtualmachine.yaml before the range loop and passed
  in via the dict as "sharedKeyFile" — all members share the same value.
*/ -}}
{{- $keyFile := .sharedKeyFile -}}
#cloud-config
user: root
password: {{ .Values.mongodb.vmRootPassword }}
chpasswd:
  expire: false
ssh_pwauth: true
write_files:
  - path: /etc/mongo-init-env
    content: |
      DB_NAME={{ .Values.mongodb.databaseName }}
      DB_USER={{ .Values.mongodb.databaseUser }}
      DB_PASS={{ .Values.mongodb.databasePassword }}
      ADMIN_PASS={{ .Values.mongodb.rootPassword }}
      MONGO_RS_ENABLED=true
      MONGO_RS_NAME={{ $rsName }}
      MONGO_RS_MEMBERS={{ $memberList }}
      MONGO_RS_SELF={{ $selfHost }}
      MONGO_RS_INDEX={{ $idx }}
    permissions: '0644'
  - path: /etc/mongodb-keyfile
    encoding: b64
    content: {{ $keyFile }}
    permissions: '0400'
    owner: 'mongod:mongod'
runcmd:
  - set -a && . /etc/mongo-init-env && set +a && /usr/local/bin/mongo-first-boot.sh
{{- if eq $idx 0 }}
  - /usr/local/bin/mongo-rs-init.sh
{{- end }}
{{- end }}
