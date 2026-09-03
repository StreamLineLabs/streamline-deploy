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
  # The panels below query metric names that have not been confirmed against
  # Streamline core (audit finding DEP-D-1); see monitoring/METRICS.md.
  streamline.dev/metric-status: "unverified"
{{- end }}

{{/*
Capabilities advertised by the configured image, as a comma-separated list.

TLS is deliberately NOT a capability: Streamline core builds TLS support into
the default binary, so every edition can terminate TLS and the chart never gates
`tls.enabled` on the image.

The edition mirrors the image build contract in `Dockerfile`:

  standard — built with default cargo features (STREAMLINE_FEATURES empty).
             TLS works, but SASL auth and clustering do not.
  full     — built with STREAMLINE_EDITION=full, which accepts exactly
             STREAMLINE_FEATURES=full (core's own meta-feature) and therefore
             has a known capability set: auth and clustering.
  custom   — built with STREAMLINE_EDITION=custom and an arbitrary
             STREAMLINE_FEATURES list. Nothing about such a build is
             inferable, so the chart REFUSES TO GUESS: `image.capabilities`
             must declare what the image supports (matching the
             `dev.streamline.capabilities` label the custom build records).

`image.capabilities` is accepted only with `edition: custom`. Allowing it to
override `standard`/`full` would mean two sources of truth for the same image,
and the losing one is always the one an operator read.

"moonshot" is accepted inside a custom capability list to describe such a build,
but the chart cannot configure moonshot features yet (see
streamline.rejectUnwiredMoonshotSettings).
*/}}
{{- define "streamline.imageCapabilities" -}}
{{- $edition := .Values.image.edition | default "full" -}}
{{- $declared := .Values.image.capabilities | default (list) -}}
{{- if eq $edition "custom" -}}
{{- if not $declared -}}
{{- fail "streamline: image.edition=custom requires an explicit image.capabilities list (e.g. {auth} or {auth,clustering}). A custom build is STREAMLINE_EDITION=custom with an arbitrary STREAMLINE_FEATURES list, so the chart cannot infer whether it supports SASL auth or clustering — and guessing \"yes\" would deploy an unauthenticated broker while the values file says auth is on. Declare the capabilities the image records in its dev.streamline.capabilities label, or use image.edition=standard/full." -}}
{{- end -}}
{{- join "," $declared -}}
{{- else if $declared -}}
{{- fail (printf "streamline: image.capabilities is only accepted with image.edition=custom (edition is %q). The standard and full editions describe fixed builds — standard has no optional capabilities, full is built with STREAMLINE_FEATURES=full and supports auth and clustering — so an explicit list here would be a second, conflicting source of truth. Set image.edition=custom to keep the list, or drop image.capabilities." $edition) -}}
{{- else if eq $edition "full" -}}
auth,clustering
{{- else if eq $edition "standard" -}}
{{- else -}}
{{- fail (printf "streamline: unsupported image.edition %q (expected \"standard\", \"full\" or \"custom\")." $edition) -}}
{{- end -}}
{{- end }}

{{/*
Fully qualified image reference.

There is no default tag: no Streamline image is published yet
(.github/workflows/docker-publish.yml has pushed nothing while core-source.env
carries no pinned commit), so shipping one would point every install at a
manifest that does not exist. Build an image from the pinned core commit and
name it explicitly.
*/}}
{{- define "streamline.imageRef" -}}
{{- $repository := .Values.image.repository | default "" -}}
{{- $tag := .Values.image.tag | default "" -}}
{{- if not $repository -}}
{{- fail "streamline: image.repository is empty. Set it to the registry path of an image you can pull." -}}
{{- end -}}
{{- if not $tag -}}
{{- fail "streamline: image.tag is empty and this chart ships no default tag, because no Streamline image is published yet. Build one from the pinned core commit (scripts/prepare-core-context.sh, then `make docker`), push it where your cluster can pull it, and set image.repository and image.tag explicitly — e.g. --set image.repository=my-registry/streamline --set image.tag=<tag>. Rendering a workload against a tag nobody published would fail with ImagePullBackOff after install instead of here." -}}
{{- end -}}
{{- printf "%s:%s" $repository $tag -}}
{{- end }}

{{/*
Whether the configured image advertises a capability.
Usage: include "streamline.hasCapability" (dict "root" . "capability" "tls")
*/}}
{{- define "streamline.hasCapability" -}}
{{- $caps := compact (splitList "," (include "streamline.imageCapabilities" .root)) -}}
{{- if and (has .capability $caps) (not (has "none" $caps)) -}}true{{- end -}}
{{- end }}

{{/*
Fail closed when a feature is switched on that the configured image cannot
provide. Rendering a workload that silently ignores TLS or authentication is
worse than refusing to render at all.
Usage: include "streamline.requireCapability" (dict "root" . "capability" "tls" "setting" "tls.enabled")
*/}}
{{- define "streamline.requireCapability" -}}
{{- if not (include "streamline.hasCapability" (dict "root" .root "capability" .capability)) -}}
{{- $caps := include "streamline.imageCapabilities" .root -}}
{{- $advertised := ternary "(none)" $caps (eq $caps "") -}}
{{- $hint := "Use a full-edition image (see Dockerfile: STREAMLINE_EDITION=full with STREAMLINE_FEATURES=full) and set image.edition=full, or for a custom build set image.edition=custom and declare image.capabilities explicitly." -}}
{{- fail (printf "streamline: %s=true requires an image that supports %q, but image edition %q supports: %s. %s" .setting .capability (.root.Values.image.edition | default "full") $advertised $hint) -}}
{{- end -}}
{{- end }}

{{/*
The moonshot settings that are switched on, as a comma-separated list of the
value paths that were set (e.g. "moonshot.semanticTopics.enabled=true").
*/}}
{{- define "streamline.moonshotEnabledSettings" -}}
{{- $m := .Values.moonshot | default dict -}}
{{- $enabled := list -}}
{{- range $key := (list "semanticTopics" "agentMemory" "contracts" "branches") -}}
{{- if dig $key "enabled" false $m -}}
{{- $enabled = append $enabled (printf "moonshot.%s.enabled=true" $key) -}}
{{- end -}}
{{- end -}}
{{- join ", " $enabled -}}
{{- end }}

{{/*
Reject moonshot settings outright. No template turns them into server
configuration: they reach neither the ConfigMap nor the container arguments.
Accepting them — even on an image that advertises the "moonshot" capability —
would deploy a server that ignores every one of them while the values file
claims the feature is on, which is exactly the silent-drop failure mode the
other guards in this file exist to prevent.
*/}}
{{- define "streamline.rejectUnwiredMoonshotSettings" -}}
{{- $enabled := include "streamline.moonshotEnabledSettings" . -}}
{{- if $enabled -}}
{{- fail (printf "streamline: moonshot features are enabled (%s) but this chart does not wire them: no template renders moonshot settings into the ConfigMap or the container arguments, so the deployed server would ignore them. Keep every moonshot.*.enabled at false until the chart configures them; declaring \"moonshot\" in image.capabilities does not make these settings take effect." $enabled) -}}
{{- end -}}
{{- end }}

{{/*
Reject autoscalers. An HPA or a KEDA ScaledObject targets the StatefulSet and
raises `.spec.replicas` on its own, so accepting either would route around the
`replicaCount > 1` guard below: the extra pods come up as independent brokers
with their own data directory and topic metadata, not as members of a cluster.
Because the autoscaler writes the replica count after install, the operator
would not even see it in the values file. Both stay rejected until peer
bootstrap exists; the values keys are kept to document the intended shape.
*/}}
{{- define "streamline.rejectUnsupportedAutoscaling" -}}
{{- $enabled := list -}}
{{- if dig "enabled" false (.Values.autoscaling | default dict) -}}
{{- $enabled = append $enabled "autoscaling.enabled=true" -}}
{{- end -}}
{{- if dig "enabled" false (.Values.keda | default dict) -}}
{{- $enabled = append $enabled "keda.enabled=true" -}}
{{- end -}}
{{- if $enabled -}}
{{- fail (printf "streamline: %s is not supported by this chart yet. The autoscaler scales the StatefulSet above one replica, which this chart rejects (replicaCount > 1) because peer bootstrap is not implemented: the extra pods would start as independent brokers with their own data, not as cluster members. Keep autoscaling.enabled and keda.enabled at false until clustered mode exists; scale vertically with resources instead." (join ", " $enabled)) -}}
{{- end -}}
{{- end }}

{{/*
Reject custom listener ports.

The chart wires exactly two listeners, and it wires them in several places that
a single value could never keep in step: the container's `ports:` block, the
`kafka`/`http` named ports the probes and Services target, the NetworkPolicy
ingress rules, the ServiceMonitor endpoint and the Prometheus scrape
annotations all hard-code 9092 and 9094. `service.kafkaPort` and
`config.kafkaAddr` used to look like they could move a listener; changing either
one produced a workload whose Service pointed at a port nothing listened on,
whose probes still targeted the old container port, and whose NetworkPolicy
blocked the new one — i.e. a broker that never became ready, for a reason
nothing in the values file explained.

Until every one of those places is rendered from one source, the conservative
answer is the honest one: the ports are fixed. Publish a different port
*outside* the pod with your own Service, an ingress or a port-forward, none of
which needs the server to listen elsewhere.

values.schema.json rejects the same values before the templates run; this guard
covers renders that bypass schema validation and gives the actionable message.
*/}}
{{- define "streamline.rejectCustomListenerPorts" -}}
{{- $kafkaPort := 9092 -}}
{{- $httpPort := 9094 -}}
{{- $interBrokerPort := 9093 -}}
{{- $hint := "The chart hard-codes these ports in the container ports, probes, Services, NetworkPolicy and metrics wiring; expose a different port outside the pod instead (Service, ingress or port-forward)." -}}
{{- $service := .Values.service | default dict -}}
{{- if and $service.kafkaPort (ne (int $service.kafkaPort) $kafkaPort) -}}
{{- fail (printf "streamline: service.kafkaPort must be %d (got %v). %s" $kafkaPort $service.kafkaPort $hint) -}}
{{- end -}}
{{- if and $service.httpPort (ne (int $service.httpPort) $httpPort) -}}
{{- fail (printf "streamline: service.httpPort must be %d (got %v). %s" $httpPort $service.httpPort $hint) -}}
{{- end -}}
{{- $external := .Values.externalService | default dict -}}
{{- if and $external.kafkaPort (ne (int $external.kafkaPort) $kafkaPort) -}}
{{- fail (printf "streamline: externalService.kafkaPort must be %d (got %v); it targets the same fixed container port. %s" $kafkaPort $external.kafkaPort $hint) -}}
{{- end -}}
{{- $config := .Values.config | default dict -}}
{{- if and $config.kafkaAddr (not (hasSuffix (printf ":%d" $kafkaPort) ($config.kafkaAddr | toString))) -}}
{{- fail (printf "streamline: config.kafkaAddr must end in :%d (got %q). %s" $kafkaPort ($config.kafkaAddr | toString) $hint) -}}
{{- end -}}
{{- if and $config.httpAddr (not (hasSuffix (printf ":%d" $httpPort) ($config.httpAddr | toString))) -}}
{{- fail (printf "streamline: config.httpAddr must end in :%d (got %q). %s" $httpPort ($config.httpAddr | toString) $hint) -}}
{{- end -}}
{{- if and $config.interBrokerPort (ne (int $config.interBrokerPort) $interBrokerPort) -}}
{{- fail (printf "streamline: config.interBrokerPort must be %d (got %v); the headless Service and the container port are fixed at %d, and clustering is rejected by this chart anyway." $interBrokerPort $config.interBrokerPort $interBrokerPort) -}}
{{- end -}}
{{- $netpol := .Values.networkPolicy | default dict -}}
{{- range $ruleIndex, $rule := ($netpol.ingress | default (list)) -}}
{{- range $portIndex, $port := ($rule.ports | default (list)) -}}
{{- if $port.port -}}
{{- if not (has (int $port.port) (list 9092 9094)) -}}
{{- fail (printf "streamline: networkPolicy.ingress[%d].ports[%d].port is %v; the workload listens on %d (Kafka) and %d (HTTP) only, so any other port would allow traffic nothing serves while blocking traffic that matters. Put extra rules in networkPolicy.additionalIngress if you need them." $ruleIndex $portIndex $port.port $kafkaPort $httpPort) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Name of the Secret holding TLS material (generated or operator-provided).
*/}}
{{- define "streamline.tlsSecretName" -}}
{{- .Values.tls.existingSecret | default (printf "%s-tls" (include "streamline.fullname" .)) -}}
{{- end }}

{{/*
Name of the Secret holding the SASL users file. There is no generated
alternative: Streamline core authenticates against a YAML users file that holds
precomputed password hashes / SCRAM credentials, which the chart cannot derive
from a plaintext value, so the operator must supply the Secret.
*/}}
{{- define "streamline.authSecretName" -}}
{{- required "streamline: auth.enabled=true requires auth.existingSecret." .Values.auth.existingSecret -}}
{{- end }}

{{/*
Key inside auth.existingSecret that holds the YAML users file.
*/}}
{{- define "streamline.authUsersFileKey" -}}
{{- .Values.auth.usersFileKey | default "users.yaml" -}}
{{- end }}

{{/*
Absolute path of the mounted users file inside the container.
*/}}
{{- define "streamline.authUsersFilePath" -}}
{{- printf "%s/%s" (.Values.auth.mountPath | default "/etc/streamline/auth" | trimSuffix "/") (include "streamline.authUsersFileKey" .) -}}
{{- end }}

{{/*
Comma-separated list of SASL mechanisms to advertise.
*/}}
{{- define "streamline.authSaslMechanisms" -}}
{{- $sasl := .Values.auth.sasl | default dict -}}
{{- join "," (default (list) $sasl.mechanisms) -}}
{{- end }}

{{/*
Reject settings that were removed because core never honoured them. Silently
ignoring a credential the operator believes is in effect is the worst possible
outcome, so these fail the render with an explicit migration hint.
*/}}
{{- define "streamline.rejectRemovedAuthSettings" -}}
{{- $sasl := .Values.auth.sasl | default dict -}}
{{- if or $sasl.username $sasl.password -}}
{{- fail "streamline: auth.sasl.username / auth.sasl.password are no longer supported. Streamline core authenticates against a YAML users file containing precomputed hashes or SCRAM credentials and does not read credentials from the environment. Create that file yourself, store it in a Secret and set auth.existingSecret (see helm/README.md)." -}}
{{- end -}}
{{- if $sasl.mechanism -}}
{{- fail "streamline: auth.sasl.mechanism was replaced by the list auth.sasl.mechanisms (core reads STREAMLINE_AUTH_SASL_MECHANISMS). Set e.g. auth.sasl.mechanisms={SCRAM-SHA-256}." -}}
{{- end -}}
{{- if or .Values.auth.usernameKey .Values.auth.passwordKey -}}
{{- fail "streamline: auth.usernameKey / auth.passwordKey are no longer supported; the chart mounts a users file instead. Use auth.usersFileKey to name the key inside auth.existingSecret." -}}
{{- end -}}
{{- if .Values.auth.extraSecrets -}}
{{- fail "streamline: auth.extraSecrets is no longer supported; the chart no longer generates an auth Secret. Put any additional material in auth.existingSecret." -}}
{{- end -}}
{{- end }}

{{/*
Reject TLS settings that were renamed when the chart started wiring the
certificate material through to the server. These keys used to appear in
values-tls.yaml but were never read by any template, so leaving them in place
is actively dangerous: `mutualTls: true` looks like mTLS is enforced while the
rendered workload accepts unauthenticated clients.
*/}}
{{- define "streamline.rejectRemovedTlsSettings" -}}
{{- $tls := .Values.tls | default dict -}}
{{- if not (kindIs "invalid" $tls.mutualTls) -}}
{{- fail "streamline: tls.mutualTls was renamed to tls.clientAuth. It was never read by any template, so leaving it set would advertise mutual TLS while the server accepts unauthenticated clients. Set tls.clientAuth instead." -}}
{{- end -}}
{{- if $tls.certSecretName -}}
{{- fail "streamline: tls.certSecretName was renamed to tls.existingSecret (a kubernetes.io/tls Secret holding tls.crt, tls.key and optionally ca.crt)." -}}
{{- end -}}
{{- if or $tls.certFile (or $tls.keyFile $tls.caFile) -}}
{{- fail "streamline: tls.certFile / tls.keyFile / tls.caFile are no longer supported. The chart mounts the Secret at tls.mountPath and derives the file locations itself (STREAMLINE_TLS_CERT / STREAMLINE_TLS_KEY / STREAMLINE_TLS_CA_CERT). Set tls.mountPath if you need a different directory." -}}
{{- end -}}
{{- end }}

{{/*
Reject top-level settings that moved under a sub-key. The server arguments are
now assembled in one place (templates/statefulset.yaml) so that extra arguments
are appended to the image defaults rather than replacing them; a leftover
top-level `extraArgs` would be dropped without a word.
*/}}
{{- define "streamline.rejectRemovedTopLevelSettings" -}}
{{- if .Values.extraArgs -}}
{{- fail "streamline: top-level extraArgs moved to config.extraArgs. Extra arguments are now appended to the image's default --listen-addr / --data-dir flags instead of replacing them; a top-level value would be silently ignored." -}}
{{- end -}}
{{- end }}

{{/*
Validate the requested configuration against the image and against itself.
Included by every template that participates in the workload so that an
unsupported or incomplete configuration fails at render time.
*/}}
{{- define "streamline.validateConfiguration" -}}
{{- $_ := include "streamline.imageCapabilities" . -}}
{{- $_ = include "streamline.imageRef" . -}}
{{- include "streamline.rejectRemovedTopLevelSettings" . -}}
{{- include "streamline.rejectRemovedAuthSettings" . -}}
{{- include "streamline.rejectRemovedTlsSettings" . -}}
{{- include "streamline.rejectUnwiredMoonshotSettings" . -}}
{{- include "streamline.rejectUnsupportedAutoscaling" . -}}
{{- include "streamline.rejectCustomListenerPorts" . -}}
{{- if .Values.tls.enabled -}}
{{- if not (or .Values.tls.existingSecret (and .Values.tls.certData .Values.tls.keyData)) -}}
{{- fail "streamline: tls.enabled=true requires either tls.existingSecret or both tls.certData and tls.keyData." -}}
{{- end -}}
{{- if and .Values.tls.clientAuth (not (or .Values.tls.caData .Values.tls.existingSecret)) -}}
{{- fail "streamline: tls.clientAuth=true requires CA material (tls.caData, or tls.existingSecret containing ca.crt)." -}}
{{- end -}}
{{- end -}}
{{- if .Values.auth.enabled -}}
{{- include "streamline.requireCapability" (dict "root" . "capability" "auth" "setting" "auth.enabled") -}}
{{- if not .Values.auth.existingSecret -}}
{{- fail "streamline: auth.enabled=true requires auth.existingSecret holding the YAML users file (key: auth.usersFileKey, default \"users.yaml\") with precomputed password hashes or SCRAM credentials. The chart cannot generate those from a plaintext password." -}}
{{- end -}}
{{- if not (include "streamline.authSaslMechanisms" .) -}}
{{- fail "streamline: auth.enabled=true requires a non-empty auth.sasl.mechanisms list (e.g. {SCRAM-SHA-256})." -}}
{{- end -}}
{{- end -}}
{{- if .Values.config.clusterEnabled -}}
{{- fail "streamline: config.clusterEnabled is not supported by this chart yet; peer IDs and seed-node bootstrap are not rendered. Keep clusterEnabled=false and replicaCount=1." -}}
{{- end -}}
{{- if gt (int .Values.replicaCount) 1 -}}
{{- fail "streamline: replicaCount greater than 1 is not supported yet; without peer bootstrap it would create independent brokers rather than a cluster." -}}
{{- end -}}
{{- end }}
