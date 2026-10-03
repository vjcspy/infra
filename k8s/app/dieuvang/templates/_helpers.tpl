{{- define "dieuvang.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: dieuvang
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* selector labels: call with (dict "root" . "component" "magento") */}}
{{- define "dieuvang.selector" -}}
app.kubernetes.io/name: dieuvang
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "dieuvang.appVolume" -}}
- name: app-volume
  hostPath:
    path: {{ .Values.hostPaths.appVolume }}
    type: Directory
{{- end }}

{{- define "dieuvang.dbVolume" -}}
- name: db-volume
  hostPath:
    path: {{ .Values.hostPaths.dbVolume }}
    type: Directory
{{- end }}

{{/* Sentinel init container: refuses to start unless DONT_DELETE exists on each mounted volume.
     call with (dict "root" . "db" true|false) */}}
{{- define "dieuvang.sentinel" -}}
- name: check-ebs-volumes
  image: {{ .root.Values.images.busybox }}
  command:
    - sh
    - -c
    - 'for d in "$@"; do ok=0; for i in 1 2 3 4 5; do if [ -f "$d/DONT_DELETE" ]; then ok=1; break; fi; echo "waiting for $d ($i)"; sleep 10; done; [ "$ok" = 1 ] || { echo "sentinel missing in $d"; exit 1; }; done' 
    - sh
    - /host/app
    {{- if .db }}
    - /host/db
    {{- end }}
  volumeMounts:
    - name: app-volume
      mountPath: /host/app
      readOnly: true
    {{- if .db }}
    - name: db-volume
      mountPath: /host/db
      readOnly: true
    {{- end }}
{{- end }}
