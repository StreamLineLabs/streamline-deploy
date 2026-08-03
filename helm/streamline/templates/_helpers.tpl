{{/*
Expand the name of the chart.
*/}}
{{- define "streamline.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "streamline.fullname" -}}
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
{{- define "streamline.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "streamline.labels" -}}
helm.sh/chart: {{ include "streamline.chart" . }}
{{ include "streamline.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "streamline.selectorLabels" -}}
app.kubernetes.io/name: {{ include "streamline.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the headless service
*/}}
{{- define "streamline.headlessServiceName" -}}
{{- printf "%s-headless" (include "streamline.fullname" .) }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "streamline.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "streamline.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Shared metadata for Grafana dashboard ConfigMaps.
Usage: include "streamline.grafanaDashboardMetadata" (dict "root" . "name" "overview")
*/}}
{{- define "streamline.grafanaDashboardMetadata" -}}
name: {{ include "streamline.fullname" .root }}-grafana-{{ .name }}
namespace: {{ .root.Values.metrics.grafanaDashboards.namespace | default .root.Release.Namespace }}
labels:
  {{- include "streamline.labels" .root | nindent 2 }}
  grafana_dashboard: "1"
  {{- with .root.Values.metrics.grafanaDashboards.labels }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
annotations:
  grafana_folder: {{ .root.Values.metrics.grafanaDashboards.folder | default "Streamline" | quote }}
{{- end }}
