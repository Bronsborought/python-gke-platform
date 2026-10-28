{{- define "python-platform.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "python-platform.selectorLabels" -}}
app.kubernetes.io/name: python-platform
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "python-platform.labels" -}}
{{ include "python-platform.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | quote }}
{{- end -}}
