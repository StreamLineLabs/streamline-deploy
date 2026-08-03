.PHONY: build test lint clean help docker helm-lint smoke-test helm-template helm-test helm-validate shell-syntax shell-tests shellcheck

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: docker ## Build Docker image

docker: ## Build Streamline Docker image
	docker build -t streamline:dev .

test: helm-lint helm-validate helm-test shell-syntax shell-tests ## Run validation tests
	docker compose config --quiet
	docker compose -f docker-compose.demo.yml config --quiet
	docker compose -f docker-compose.test.yml config --quiet

smoke-test: docker ## Run smoke tests against a live Streamline instance
	docker compose -f docker-compose.test.yml up --build --abort-on-container-exit --exit-code-from smoke-test
	docker compose -f docker-compose.test.yml down -v

lint: helm-lint shellcheck ## Run all linting

helm-lint: ## Lint Helm chart
	helm lint helm/streamline

helm-template: ## Render Helm templates (default values)
	helm template test-release helm/streamline

helm-validate: ## Validate all Helm templates render with various value combinations
	@echo "=== Default values ==="
	helm template test helm/streamline > /dev/null
	@echo "=== With ingress enabled ==="
	helm template test helm/streamline --set ingress.enabled=true > /dev/null
	@echo "=== With auth and TLS ==="
	helm template test helm/streamline --set auth.enabled=true --set auth.sasl.username=admin --set auth.sasl.password=pass --set tls.enabled=true --set tls.certData=Y2VydA== --set tls.keyData=a2V5 > /dev/null
	@echo "=== With PrometheusRule ==="
	helm template test helm/streamline --set metrics.prometheusRule.enabled=true > /dev/null
	@echo "=== With autoscaling ==="
	helm template test helm/streamline --set autoscaling.enabled=true > /dev/null
	@echo "=== With ServiceAccount disabled ==="
	helm template test helm/streamline --set serviceAccount.create=false > /dev/null
	@echo "=== All templates valid ✓ ==="

helm-test: ## Run helm-unittest tests (requires helm-unittest plugin)
	helm unittest helm/streamline

shell-syntax: ## Validate tracked shell script syntax
	@for file in $$(git ls-files '*.sh'); do bash -n "$$file"; done

shell-tests: ## Run shell characterization tests
	bash tests/seed-data_test.sh

shellcheck: ## Run ShellCheck on tracked shell scripts
	shellcheck $$(git ls-files '*.sh')

clean: ## Clean up containers
	docker compose down -v 2>/dev/null || true

up: ## Start Streamline via Docker Compose
	docker compose up -d

down: ## Stop Streamline
	docker compose down
