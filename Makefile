.PHONY: build test lint clean help docker helm-lint smoke-test

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: docker ## Build Docker image

docker: ## Build Streamline Docker image
	docker build -t streamline:dev .

test: helm-lint ## Run validation tests
	docker compose config --quiet
	docker compose -f docker-compose.demo.yml config --quiet
	docker compose -f docker-compose.test.yml config --quiet

smoke-test: docker ## Run smoke tests against a live Streamline instance
	docker compose -f docker-compose.test.yml up --build --abort-on-container-exit --exit-code-from smoke-test
	docker compose -f docker-compose.test.yml down -v

lint: helm-lint ## Run all linting

helm-lint: ## Lint Helm chart
	helm lint helm/streamline

helm-template: ## Render Helm templates
	helm template test-release helm/streamline

clean: ## Clean up containers
	docker compose down -v 2>/dev/null || true

up: ## Start Streamline via Docker Compose
	docker compose up -d

down: ## Stop Streamline
	docker compose down
# bump base image to latest Alpine
