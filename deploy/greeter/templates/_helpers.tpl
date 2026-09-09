{{/*
Minimal, hand-written helpers. Just names and labels — nothing generated.
*/}}

{{- define "greeter.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully-qualified name: "<release>-<chart>", collapsed to "<release>" when the
release is already named after the chart, so we don't get "greeter-greeter".
*/}}
{{- define "greeter.fullname" -}}
{{- $name := include "greeter.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Labels on every object. */}}
{{- define "greeter.labels" -}}
app.kubernetes.io/name: {{ include "greeter.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
{{- end -}}

{{/* Immutable subset used for the Deployment selector and Service selector. */}}
{{- define "greeter.selectorLabels" -}}
app.kubernetes.io/name: {{ include "greeter.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
