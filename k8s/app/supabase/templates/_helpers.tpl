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

{{/* Render environment variables for a specific service, injecting secrets */}}
{{- define "supabase.renderServiceEnv" -}}
{{- $root := index . 0 -}}
{{- $serviceName := index . 1 -}}
{{- $serviceEnv := index $root.Values $serviceName "env" -}}
{{- range $k, $v := $serviceEnv }}
            - name: {{ $k }}
              value: {{ $v | quote }}
{{- end }}
{{/* Inject secrets based on service */}}
{{- if eq $serviceName "postgres" }}
            - name: POSTGRES_PASSWORD
              value: {{ $root.Values.secrets.postgresPassword | quote }}
            - name: PGPASSWORD
              value: {{ $root.Values.secrets.postgresPassword | quote }}
            - name: JWT_SECRET
              value: {{ $root.Values.secrets.jwtSecret | quote }}
{{- else if eq $serviceName "supavisor" }}
            - name: POSTGRES_PASSWORD
              value: {{ $root.Values.secrets.postgresPassword | quote }}
            - name: DATABASE_URL
              value: {{ include "supabase.supavisor.databaseUrl" $root | quote }}
            - name: SECRET_KEY_BASE
              value: {{ $root.Values.secrets.secretKeyBase | quote }}
            - name: VAULT_ENC_KEY
              value: {{ $root.Values.secrets.vaultEncKey | quote }}
            - name: API_JWT_SECRET
              value: {{ $root.Values.secrets.jwtSecret | quote }}
            - name: METRICS_JWT_SECRET
              value: {{ $root.Values.secrets.jwtSecret | quote }}
{{- else if eq $serviceName "auth" }}
            - name: GOTRUE_DB_DATABASE_URL
              value: {{ include "supabase.auth.databaseUrl" $root | quote }}
            - name: GOTRUE_JWT_SECRET
              value: {{ $root.Values.secrets.jwtSecret | quote }}
{{- else if eq $serviceName "rest" }}
            - name: PGRST_DB_URI
              value: {{ include "supabase.rest.databaseUri" $root | quote }}
            - name: PGRST_JWT_SECRET
              value: {{ $root.Values.secrets.jwtSecret | quote }}
            - name: PGRST_APP_SETTINGS_JWT_SECRET
              value: {{ $root.Values.secrets.jwtSecret | quote }}
            - name: PGRST_APP_SETTINGS_JWT_EXP
              value: "3600"
{{- else if eq $serviceName "realtime" }}
            - name: DB_PASSWORD
              value: {{ $root.Values.secrets.postgresPassword | quote }}
            - name: API_JWT_SECRET
              value: {{ $root.Values.secrets.jwtSecret | quote }}
            - name: SECRET_KEY_BASE
              value: {{ $root.Values.secrets.secretKeyBase | quote }}
{{- else if eq $serviceName "storage" }}
            - name: ANON_KEY
              value: {{ $root.Values.secrets.anonKey | quote }}
            - name: SERVICE_KEY
              value: {{ $root.Values.secrets.serviceRoleKey | quote }}
            - name: PGRST_JWT_SECRET
              value: {{ $root.Values.secrets.jwtSecret | quote }}
            - name: DATABASE_URL
              value: {{ include "supabase.storage.databaseUrl" $root | quote }}
{{- else if eq $serviceName "meta" }}
            - name: PG_META_DB_PASSWORD
              value: {{ $root.Values.secrets.postgresPassword | quote }}
{{- else if eq $serviceName "functions" }}
            - name: JWT_SECRET
              value: {{ $root.Values.secrets.jwtSecret | quote }}
            - name: SUPABASE_ANON_KEY
              value: {{ $root.Values.secrets.anonKey | quote }}
            - name: SUPABASE_SERVICE_ROLE_KEY
              value: {{ $root.Values.secrets.serviceRoleKey | quote }}
            - name: SUPABASE_DB_URL
              value: {{ include "supabase.functions.databaseUrl" $root | quote }}
{{- else if eq $serviceName "analytics" }}
            - name: DB_PASSWORD
              value: {{ $root.Values.secrets.postgresPassword | quote }}
            - name: POSTGRES_BACKEND_URL
              value: {{ include "supabase.analytics.databaseUrl" $root | quote }}
{{- else if eq $serviceName "kong" }}
            - name: SUPABASE_ANON_KEY
              value: {{ $root.Values.secrets.anonKey | quote }}
            - name: SUPABASE_SERVICE_KEY
              value: {{ $root.Values.secrets.serviceRoleKey | quote }}
            - name: DASHBOARD_PASSWORD
              value: {{ $root.Values.secrets.dashboardPassword | quote }}
{{- else if eq $serviceName "studio" }}
            - name: POSTGRES_PASSWORD
              value: {{ $root.Values.secrets.postgresPassword | quote }}
            - name: SUPABASE_ANON_KEY
              value: {{ $root.Values.secrets.anonKey | quote }}
            - name: SUPABASE_SERVICE_KEY
              value: {{ $root.Values.secrets.serviceRoleKey | quote }}
            - name: AUTH_JWT_SECRET
              value: {{ $root.Values.secrets.jwtSecret | quote }}
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

{{/*
Build database URLs and complex environment variables from values
*/}}
{{- define "supabase.auth.databaseUrl" -}}
postgres://supabase_auth_admin:{{ .Values.secrets.postgresPassword }}@supabase-postgres:5432/{{ .Values.postgres.env.POSTGRES_DB }}
{{- end }}

{{- define "supabase.rest.databaseUri" -}}
postgres://authenticator:{{ .Values.secrets.postgresPassword }}@supabase-postgres:5432/{{ .Values.postgres.env.POSTGRES_DB }}
{{- end }}

{{- define "supabase.storage.databaseUrl" -}}
postgres://supabase_storage_admin:{{ .Values.secrets.postgresPassword }}@supabase-postgres:5432/{{ .Values.postgres.env.POSTGRES_DB }}
{{- end }}

{{- define "supabase.functions.databaseUrl" -}}
postgresql://postgres:{{ .Values.secrets.postgresPassword }}@supabase-postgres:5432/{{ .Values.postgres.env.POSTGRES_DB }}
{{- end }}

{{- define "supabase.analytics.databaseUrl" -}}
postgresql://supabase_admin:{{ .Values.secrets.postgresPassword }}@supabase-postgres:5432/_supabase
{{- end }}

{{- define "supabase.supavisor.databaseUrl" -}}
ecto://supabase_admin:{{ .Values.secrets.postgresPassword }}@supabase-postgres:5432/_supabase
{{- end }}
