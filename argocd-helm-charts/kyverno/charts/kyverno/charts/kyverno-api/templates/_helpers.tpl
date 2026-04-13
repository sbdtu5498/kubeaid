{{/* vim: set filetype=mustache: */}}

{{- define "kyverno-api.chartVersion" -}}
{{- .Chart.Version | replace "+" "_" -}}
{{- end -}}

{{- define "kyverno-api.labels" -}}
{{- if .Values.labels -}}
{{- tpl (toYaml .Values.labels) . -}}
{{- end -}}
{{- end -}}

{{- define "kyverno-api.annotations" -}}
{{- if .Values.annotations -}}
{{- tpl (toYaml .Values.annotations) . -}}
{{- end -}}
{{- end -}}
