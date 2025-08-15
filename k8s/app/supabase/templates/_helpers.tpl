{{/*
Expand the name of the chart.
*/}}
{{- define "supabase.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "supabase.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "supabase.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "supabase.labels" -}}
helm.sh/chart: {{ include "supabase.chart" . }}
{{ include "supabase.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "supabase.selectorLabels" -}}
app.kubernetes.io/name: {{ include "supabase.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "supabase.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "supabase.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* Render key/value env pairs from a map */}}
{{- define "supabase.renderEnv" -}}
{{- $env := . -}}
{{- range $k, $v := $env }}
						- name: {{ $k }}
							value: {{ $v | quote }}
{{- end }}
{{- end }}

{{/* Init container to verify EBS hostPath mount is present with sentinel file */}}
{{- define "supabase.initEbsCheck" -}}
				- name: init-ebs-check
					image: busybox:1.37.0
					command: ["sh","-c","for i in $(seq 1 5); do echo Checking EBS mount attempt $i; if [ -f /host_ebs_volume/DONT_DELETE ]; then echo OK; exit 0; fi; sleep 10; done; echo FAIL; exit 1"]
					volumeMounts:
						- name: host-ebs-root
							mountPath: /host_ebs_volume
{{- end }}

{{/* Init container to wait for Postgres TCP port to be reachable */}}
{{- define "supabase.waitForDb" -}}
				- name: wait-for-db
					image: busybox:1.37.0
					command: ["sh","-c","for i in $(seq 1 60); do nc -z -w 2 {{ . | default "supabase-postgres" }} 5432 && exit 0; echo waiting for db; sleep 2; done; echo timed out; exit 1"]
{{- end }}
