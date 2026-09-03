.PHONY: build test lint clean help docker core-context helm-lint smoke-test smoke-test-image helm-template helm-test helm-validate shell-syntax shell-tests shellcheck static metrics-contract scaling-claims compose-config moonshot-demo-claims feature-demo-claims core-pin-gate publish-pipeline oci-image-reference image-editions tls-scope listener-ports published-artifacts installer-availability playground-image edge-unsupported cdc-demo-disabled

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: docker ## Build Docker image

# Image tag produced by `make docker` and consumed by `make smoke-test`.
STREAMLINE_IMAGE ?= streamline:dev
# Build context holding the pinned Streamline core sources.
CORE_CONTEXT ?= .build/core
# Image edition: standard (default cargo features), full (STREAMLINE_FEATURES=full)
# or custom (explicit feature list + capability declaration). See Dockerfile.
STREAMLINE_EDITION ?= standard
STREAMLINE_FEATURES ?=
# Capabilities a custom build declares (auth, clustering, moonshot or "none").
# Must be empty for the standard and full editions.
STREAMLINE_CAPABILITIES ?=

core-context: ## Check out the pinned Streamline core sources (see core-source.env)
	scripts/prepare-core-context.sh --dest $(CORE_CONTEXT)

docker: core-context ## Build the official Streamline image from pinned core sources
	docker build -f Dockerfile $(CORE_CONTEXT) \
		--build-arg STREAMLINE_EDITION=$(STREAMLINE_EDITION) \
		--build-arg STREAMLINE_FEATURES=$(STREAMLINE_FEATURES) \
		--build-arg STREAMLINE_CAPABILITIES=$(STREAMLINE_CAPABILITIES) \
		--build-arg STREAMLINE_CORE_REF=$$(scripts/prepare-core-context.sh --print-ref) \
		-t $(STREAMLINE_IMAGE)

test: helm-lint helm-validate helm-test shell-syntax shell-tests compose-config ## Run validation tests

# `|| exit 1` is load-bearing. A shell `for` loop returns the status of its last
# iteration, so without it a broken docker-compose*.yml anywhere but the very
# last file left the recipe — and `make test` — green. Every stack must be
# validated, and the first invalid one must stop the build.
# `config` parses and interpolates only: it pulls nothing and starts nothing.
compose-config: ## Validate every Compose stack parses (no pull, no run)
	@for file in docker-compose*.yml; do \
		echo "docker compose -f $$file config"; \
		docker compose -f "$$file" config --quiet || exit 1; \
	done

smoke-test: docker ## Run smoke tests against the locally built image
	STREAMLINE_IMAGE=$(STREAMLINE_IMAGE) docker compose -f docker-compose.test.yml \
		up --abort-on-container-exit --exit-code-from smoke-test
	STREAMLINE_IMAGE=$(STREAMLINE_IMAGE) docker compose -f docker-compose.test.yml down -v

# No image is published, so there is no "published image" target: the smoke
# stack has no runnable default and `STREAMLINE_IMAGE` must always name an image
# you built (`make docker`) or pulled yourself.
smoke-test-image: ## Run smoke tests against an image you name in STREAMLINE_IMAGE
	@[ -n "$(STREAMLINE_IMAGE)" ] || { echo "set STREAMLINE_IMAGE=<image you built>"; exit 1; }
	STREAMLINE_IMAGE=$(STREAMLINE_IMAGE) docker compose -f docker-compose.test.yml \
		up --abort-on-container-exit --exit-code-from smoke-test
	STREAMLINE_IMAGE=$(STREAMLINE_IMAGE) docker compose -f docker-compose.test.yml down -v

lint: helm-lint shellcheck ## Run all linting

# `helm lint` renders with the chart's own values, and the chart deliberately
# refuses to render without an image tag (nothing is published). Linting is
# about template health, not about that policy — which helm-validate and the
# unit tests cover explicitly — so pass the same explicit test image here.
helm-lint: ## Lint Helm chart (with an explicit test image)
	helm lint helm/streamline $(HELM_IMAGE_ARGS)

# The chart ships no default image.tag: no Streamline image is published yet, so
# a default would render every workload against a manifest nobody pushed. Local
# validation therefore names an explicit (local, unpublished) test image, which
# is exactly what an operator has to do.
HELM_TEST_IMAGE_REPOSITORY ?= streamline
HELM_TEST_IMAGE_TAG ?= helm-validate
HELM_IMAGE_ARGS = --set image.repository=$(HELM_TEST_IMAGE_REPOSITORY) --set image.tag=$(HELM_TEST_IMAGE_TAG)

helm-template: ## Render Helm templates (explicit test image)
	helm template test-release helm/streamline $(HELM_IMAGE_ARGS)

helm-validate: ## Validate all Helm templates render with various value combinations
	@echo "=== No image tag must fail: no Streamline image is published yet ==="
	@if helm template test helm/streamline >/dev/null 2>&1; then \
		echo "expected an empty image.tag to be rejected"; exit 1; \
	fi
	@helm template test helm/streamline 2>&1 | grep -q "image.tag is empty" \
		|| { echo "expected the empty-tag failure to explain that no image is published"; exit 1; }
	@echo "=== Default values (explicit test image) ==="
	helm template test helm/streamline $(HELM_IMAGE_ARGS) > /dev/null
	@echo "=== With ingress enabled ==="
	helm template test helm/streamline $(HELM_IMAGE_ARGS) --set ingress.enabled=true > /dev/null
	@echo "=== With auth (users-file Secret) and Kafka TLS ==="
	helm template test helm/streamline $(HELM_IMAGE_ARGS) --set auth.enabled=true --set auth.existingSecret=streamline-auth --set tls.enabled=true --set tls.certData=Y2VydA== --set tls.keyData=a2V5 > /dev/null
	@echo "=== With Kafka TLS on a custom standard-edition image ==="
	helm template test helm/streamline $(HELM_IMAGE_ARGS) --set image.edition=standard --set tls.enabled=true --set tls.certData=Y2VydA== --set tls.keyData=a2V5 > /dev/null
	@echo "=== With the Kafka TLS example values ==="
	helm template test helm/streamline $(HELM_IMAGE_ARGS) -f helm/streamline/values-tls.yaml > /dev/null
	@echo "=== Clustering must fail until peer bootstrap is implemented ==="
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set image.edition=full --set config.clusterEnabled=true >/dev/null 2>&1; then echo "expected clustering render to fail"; exit 1; fi
	@echo "=== Multiple replicas must fail until peer bootstrap is implemented ==="
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set replicaCount=3 >/dev/null 2>&1; then echo "expected multi-replica render to fail"; exit 1; fi
	@echo "=== With extra server arguments ==="
	helm template test helm/streamline $(HELM_IMAGE_ARGS) --set-json config.extraArgs='["--max-message-bytes","10485760"]' > /dev/null
	@echo "=== With PrometheusRule ==="
	helm template test helm/streamline $(HELM_IMAGE_ARGS) --set metrics.prometheusRule.enabled=true > /dev/null
	@echo "=== Autoscalers must fail: they would scale the StatefulSet past one broker ==="
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set autoscaling.enabled=true 2>&1 \
		| grep -q "autoscaling.enabled=true is not supported by this chart yet"; then :; else \
		echo "expected autoscaling.enabled to be rejected until peer bootstrap exists"; exit 1; \
	fi
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set keda.enabled=true 2>&1 \
		| grep -q "keda.enabled=true is not supported by this chart yet"; then :; else \
		echo "expected keda.enabled to be rejected until peer bootstrap exists"; exit 1; \
	fi
	@echo "=== ... and no autoscaler may be rendered on a clustering-capable image ==="
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set image.edition=full --set keda.enabled=true >/dev/null 2>&1; then \
		echo "expected keda.enabled to be rejected regardless of image edition"; exit 1; \
	fi
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set autoscaling.enabled=true 2>/dev/null | grep -q 'kind: HorizontalPodAutoscaler'; then \
		echo "expected no HorizontalPodAutoscaler to be rendered"; exit 1; \
	fi
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set keda.enabled=true 2>/dev/null | grep -q 'kind: ScaledObject'; then \
		echo "expected no KEDA ScaledObject to be rendered"; exit 1; \
	fi
	@echo "=== With ServiceAccount disabled ==="
	helm template test helm/streamline $(HELM_IMAGE_ARGS) --set serviceAccount.create=false > /dev/null
	@echo "=== Auth on a standard-edition image must fail ==="
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set image.edition=standard --set auth.enabled=true --set auth.existingSecret=streamline-auth > /dev/null 2>&1; then \
		echo "expected SASL auth on a standard-edition image to be rejected"; exit 1; \
	fi
	@echo "=== Auth without a users-file Secret must fail ==="
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set auth.enabled=true > /dev/null 2>&1; then \
		echo "expected auth.enabled without auth.existingSecret to be rejected"; exit 1; \
	fi
	@echo "=== Inline SASL credentials must be rejected, never silently hashed ==="
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set auth.enabled=true --set auth.existingSecret=streamline-auth --set auth.sasl.username=admin 2>&1 \
		| grep -q "auth.sasl.username / auth.sasl.password are no longer supported"; then :; else \
		echo "expected inline SASL credentials to be rejected with a migration hint"; exit 1; \
	fi
	@echo "=== A custom-edition image must declare its capabilities ==="
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set image.edition=custom 2>&1 \
		| grep -q "image.edition=custom requires an explicit image.capabilities list"; then :; else \
		echo "expected a custom edition without image.capabilities to be rejected"; exit 1; \
	fi
	@echo "=== ... and the chart must never infer auth for a custom image ==="
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set image.edition=custom --set image.capabilities='{clustering}' --set auth.enabled=true --set auth.existingSecret=streamline-auth >/dev/null 2>&1; then \
		echo "expected auth on a custom image that declares only clustering to be rejected"; exit 1; \
	fi
	@echo "=== ... while a declared capability is honoured ==="
	helm template test helm/streamline $(HELM_IMAGE_ARGS) --set image.edition=custom --set image.capabilities='{auth}' --set auth.enabled=true --set auth.existingSecret=streamline-auth > /dev/null
	@echo "=== An explicit capability list outside the custom edition must fail ==="
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set image.capabilities='{auth}' 2>&1 \
		| grep -q "image.capabilities is only accepted with image.edition=custom"; then :; else \
		echo "expected image.capabilities on a non-custom edition to be rejected"; exit 1; \
	fi
	@echo "=== Moonshot features must fail: the chart does not wire them ==="
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set moonshot.semanticTopics.enabled=true 2>&1 \
		| grep -q "moonshot features are enabled"; then :; else \
		echo "expected moonshot features to be rejected as unwired"; exit 1; \
	fi
	@echo "=== ... even when a custom image declares the moonshot capability ==="
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set image.edition=custom --set image.capabilities='{moonshot}' --set moonshot.semanticTopics.enabled=true > /dev/null 2>&1; then \
		echo "expected moonshot features to be rejected even with image.capabilities"; exit 1; \
	fi
	@echo "=== Listener ports are fixed: 9092 (Kafka) and 9094 (HTTP) ==="
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set service.kafkaPort=19092 >/dev/null 2>&1; then \
		echo "expected a custom service.kafkaPort to be rejected"; exit 1; \
	fi
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set service.httpPort=19094 >/dev/null 2>&1; then \
		echo "expected a custom service.httpPort to be rejected"; exit 1; \
	fi
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set externalService.enabled=true --set externalService.kafkaPort=19092 >/dev/null 2>&1; then \
		echo "expected a custom externalService.kafkaPort to be rejected"; exit 1; \
	fi
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set config.kafkaAddr=0.0.0.0:19092 >/dev/null 2>&1; then \
		echo "expected a Kafka listen address on another port to be rejected"; exit 1; \
	fi
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set config.httpAddr=0.0.0.0:8080 >/dev/null 2>&1; then \
		echo "expected an HTTP listen address on another port to be rejected"; exit 1; \
	fi
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set config.interBrokerPort=9095 >/dev/null 2>&1; then \
		echo "expected a custom config.interBrokerPort to be rejected"; exit 1; \
	fi
	@echo "=== ... and the rendered Services/probes/NetworkPolicy stay on them ==="
	@helm template test helm/streamline $(HELM_IMAGE_ARGS) | grep -q 'containerPort: 9092' \
		|| { echo "expected the Kafka container port to stay 9092"; exit 1; }
	@helm template test helm/streamline $(HELM_IMAGE_ARGS) | grep -q 'containerPort: 9094' \
		|| { echo "expected the HTTP container port to stay 9094"; exit 1; }
	@echo "=== autoCreateTopics must always reach the server explicitly ==="
	@helm template test helm/streamline $(HELM_IMAGE_ARGS) | grep -q 'STREAMLINE_AUTO_CREATE_TOPICS: "false"' \
		|| { echo "expected STREAMLINE_AUTO_CREATE_TOPICS to render as \"false\" by default"; exit 1; }
	@helm template test helm/streamline $(HELM_IMAGE_ARGS) --set config.autoCreateTopics=true \
		| grep -q 'STREAMLINE_AUTO_CREATE_TOPICS: "true"' \
		|| { echo "expected STREAMLINE_AUTO_CREATE_TOPICS to render as \"true\" when enabled"; exit 1; }
	@echo "=== Renamed tls.mutualTls must be rejected, never silently ignored ==="
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set tls.enabled=true --set tls.existingSecret=streamline-tls --set tls.mutualTls=true 2>&1 \
		| grep -q "tls.mutualTls was renamed to tls.clientAuth"; then :; else \
		echo "expected tls.mutualTls to be rejected with a migration hint"; exit 1; \
	fi
	@echo "=== A leftover top-level extraArgs must be rejected ==="
	@if helm template test helm/streamline $(HELM_IMAGE_ARGS) --set-json extraArgs='["--max-message-bytes","10485760"]' 2>&1 \
		| grep -q "top-level extraArgs moved to config.extraArgs"; then :; else \
		echo "expected a top-level extraArgs to be rejected with a migration hint"; exit 1; \
	fi
	@echo "=== All templates valid ✓ ==="

helm-test: ## Run helm-unittest tests (requires helm-unittest plugin)
	helm unittest helm/streamline

# Include new-but-not-yet-committed scripts so they are checked before review.
SHELL_FILES = $$(git ls-files --cached --others --exclude-standard '*.sh')

shell-syntax: ## Validate shell script syntax
	@for file in $(SHELL_FILES); do bash -n "$$file" || exit 1; done

shell-tests: ## Run shell characterization tests
	@for suite in tests/*_test.sh; do echo "--- $$suite"; bash "$$suite" || exit 1; done

metrics-contract: ## Fail if deployment artifacts reference undocumented metrics
	bash tests/metrics-contract_test.sh

scaling-claims: ## Fail if artifacts omit explicit raw config or advertise unsupported scaling
	bash tests/scaling-claims_test.sh

moonshot-demo-claims: ## Fail if the moonshot demo promises features its image cannot have
	bash tests/moonshot-demo_test.sh

feature-demo-claims: ## Fail if any feature-gated demo claims compile-time features at run time
	bash tests/feature-gated-demos_test.sh

core-pin-gate: ## Fail if an unpinned core commit could produce a green image gate
	bash tests/core-pin-gate_test.sh

publish-pipeline: ## Fail if the publisher tags before validating, or promotes anything but the validated digest
	bash tests/publish-pipeline_test.sh

oci-image-reference: ## Validate OCI comparison keys without rewriting registry ports
	bash tests/oci-image-reference_test.sh

image-editions: ## Fail if an edition could claim capabilities its build cannot have
	bash tests/image-editions_test.sh

tls-scope: ## Fail if TLS docs claim more than the Kafka listener is protected
	bash tests/tls-scope_test.sh

listener-ports: ## Fail if a listener port could be changed without rewiring the chart
	bash tests/listener-ports_test.sh

published-artifacts: ## Fail if anything presents an unpublished image/chart as installable
	bash tests/published-artifacts_test.sh

installer-availability: ## Fail if the unavailable installer advertises an endpoint or release
	bash tests/installer-availability_test.sh

playground-image: ## Fail if the playground image breaks its data-dir/health/start contract
	bash tests/playground-image_test.sh

edge-unsupported: ## Fail if a runnable edge surface or an MQTT/1883 claim comes back
	bash tests/edge-unsupported_test.sh

cdc-demo-disabled: ## Fail if the unverified CDC demo becomes runnable again
	bash tests/cdc-demo-disabled_test.sh

# Release gates. Every one is hermetic: text/JSON inspection plus this
# repository's own scripts, with no cluster, registry, network or docker.
#
# NOTE: these gates pass today while the CI *image* gate fails, and both are
# correct. `make static` checks that the artifacts make no false claims;
# .github/workflows/ci.yml's image-build job checks that the pinned core commit
# still builds, and it stays red until core-source.env names one.
static: ## Static checks that need no cluster or registry (CI gate)
	bash tests/dockerfile-context_test.sh
	bash tests/workflow-publisher_test.sh
	bash tests/core-pin-gate_test.sh
	bash tests/publish-pipeline_test.sh
	bash tests/oci-image-reference_test.sh
	bash tests/published-artifacts_test.sh
	bash tests/installer-availability_test.sh
	bash tests/image-editions_test.sh
	bash tests/tls-scope_test.sh
	bash tests/listener-ports_test.sh
	bash tests/playground-image_test.sh
	bash tests/edge-unsupported_test.sh
	bash tests/cdc-demo-disabled_test.sh
	bash tests/metrics-contract_test.sh
	bash tests/scaling-claims_test.sh
	bash tests/moonshot-demo_test.sh
	bash tests/feature-gated-demos_test.sh
	bash tests/makefile-compose-gate_test.sh

shellcheck: ## Run ShellCheck on shell scripts
	shellcheck -x -P docker $(SHELL_FILES)

clean: ## Clean up containers
	docker compose down -v 2>/dev/null || true

up: ## Start Streamline via Docker Compose
	docker compose up -d

down: ## Stop Streamline
	docker compose down
