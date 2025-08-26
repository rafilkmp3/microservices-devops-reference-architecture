# Microservices DevOps Challenge Makefile
# Author: DevOps Engineer
# Description: Comprehensive build, test, and deployment automation

# Variables
DOCKER_REGISTRY ?= ghcr.io
IMAGE_PREFIX ?= microservices
VERSION ?= latest
NAMESPACE ?= microservices

# Service names
CONFIG_SERVICE = configuration-service
LOG_SERVICE = log-aggregator-service

# Docker image names
CONFIG_IMAGE = $(DOCKER_REGISTRY)/$(IMAGE_PREFIX)/$(CONFIG_SERVICE):$(VERSION)
LOG_IMAGE = $(DOCKER_REGISTRY)/$(IMAGE_PREFIX)/$(LOG_SERVICE):$(VERSION)

# Colors for output
RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[0;33m
BLUE = \033[0;34m
NC = \033[0m # No Color

# Default target
.DEFAULT_GOAL := help

##@ General Commands

.PHONY: help
help: ## Display this help message
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.PHONY: clean
clean: ## Clean up all generated files, containers, and images
	@echo "$(YELLOW)🧹 Cleaning up...$(NC)"
	@docker-compose down -v --remove-orphans 2>/dev/null || true
	@docker system prune -f
	@rm -rf */node_modules
	@rm -rf */logs
	@rm -rf */coverage
	@rm -f *.log
	@echo "$(GREEN)✅ Cleanup completed$(NC)"

##@ Development

.PHONY: install
install: ## Install dependencies for all services
	@echo "$(BLUE)📦 Installing dependencies...$(NC)"
	@cd $(CONFIG_SERVICE) && npm ci
	@cd $(LOG_SERVICE) && npm ci
	@echo "$(GREEN)✅ Dependencies installed$(NC)"

.PHONY: setup
setup: install setup-env ## Setup development environment
	@echo "$(BLUE)🔧 Setting up development environment...$(NC)"
	@docker network create microservices-network 2>/dev/null || true
	@echo "$(GREEN)✅ Development environment ready$(NC)"

.PHONY: setup-env
setup-env: ## Setup environment files
	@echo "$(BLUE)⚙️  Setting up environment files...$(NC)"
	@cp $(CONFIG_SERVICE)/.env.example $(CONFIG_SERVICE)/.env 2>/dev/null || true
	@cp $(LOG_SERVICE)/.env.example $(LOG_SERVICE)/.env 2>/dev/null || true
	@mkdir -p $(LOG_SERVICE)/logs
	@echo "$(GREEN)✅ Environment files created$(NC)"

.PHONY: dev
dev: setup-deps ## Start development environment with hot reload
	@echo "$(BLUE)🚀 Starting development environment...$(NC)"
	@docker-compose -f docker-compose.dev.yml up -d mysql redis
	@sleep 10
	@echo "$(YELLOW)Starting services in development mode...$(NC)"
	@make -j2 dev-config dev-logs

.PHONY: dev-config
dev-config: ## Start Configuration Service in development mode
	@cd $(CONFIG_SERVICE) && npm run dev

.PHONY: dev-logs  
dev-logs: ## Start Log Aggregator Service in development mode
	@cd $(LOG_SERVICE) && npm run dev

.PHONY: setup-deps
setup-deps: ## Start only database dependencies
	@echo "$(BLUE)🗄️  Starting database dependencies...$(NC)"
	@docker-compose up -d mysql redis
	@echo "$(YELLOW)⏳ Waiting for databases to be ready...$(NC)"
	@sleep 30
	@echo "$(GREEN)✅ Dependencies ready$(NC)"

##@ Testing

.PHONY: test
test: test-config test-logs ## Run all tests
	@echo "$(GREEN)✅ All tests completed$(NC)"

.PHONY: test-config
test-config: ## Run Configuration Service tests
	@echo "$(BLUE)🧪 Testing Configuration Service...$(NC)"
	@cd $(CONFIG_SERVICE) && npm test

.PHONY: test-logs
test-logs: ## Run Log Aggregator Service tests
	@echo "$(BLUE)🧪 Testing Log Aggregator Service...$(NC)"
	@cd $(LOG_SERVICE) && npm test

##@ Multi-Environment Testing

.PHONY: test-all-envs
test-all-envs: ## Run tests across all environments (dev, act, k8s)
	@echo "$(BLUE)🌍 Running tests across all environments...$(NC)"
	@chmod +x scripts/test-runner.sh
	@./scripts/test-runner.sh

.PHONY: test-dev
test-dev: ## Run comprehensive development environment tests
	@echo "$(BLUE)🔧 Running development environment tests...$(NC)"
	@chmod +x scripts/test-dev-full.sh
	@./scripts/test-dev-full.sh

.PHONY: test-act
test-act: ## Run GitHub Actions local testing
	@echo "$(BLUE)🎭 Running act (GitHub Actions) tests...$(NC)"
	@chmod +x scripts/test-act-full.sh
	@./scripts/test-act-full.sh

.PHONY: test-k8s-local
test-k8s-local: ## Run Kubernetes local testing
	@echo "$(BLUE)☸️  Running Kubernetes local tests...$(NC)"
	@chmod +x scripts/test-k8s-full.sh
	@./scripts/test-k8s-full.sh

.PHONY: test-compare
test-compare: ## Compare test results across environments
	@echo "$(BLUE)📊 Comparing test results across environments...$(NC)"
	@if [ -f "test-results/comparison-report.md" ]; then \
		cat test-results/comparison-report.md; \
	else \
		echo "$(YELLOW)⚠️ No comparison data found. Run 'make test-all-envs' first$(NC)"; \
	fi

.PHONY: test-integration
test-integration: setup-deps ## Run integration tests
	@echo "$(BLUE)🔗 Running integration tests...$(NC)"
	@sleep 5
	@make test
	@make test-api

.PHONY: test-api
test-api: ## Run API tests against running services
	@echo "$(BLUE)🌐 Testing API endpoints...$(NC)"
	@chmod +x scripts/test-api.sh
	@./scripts/test-api.sh

.PHONY: test-coverage
test-coverage: ## Generate test coverage reports
	@echo "$(BLUE)📊 Generating test coverage...$(NC)"
	@cd $(CONFIG_SERVICE) && npm run test:coverage
	@cd $(LOG_SERVICE) && npm run test:coverage
	@echo "$(GREEN)✅ Coverage reports generated$(NC)"

.PHONY: lint
lint: ## Run linting for all services
	@echo "$(BLUE)🔍 Linting code...$(NC)"
	@cd $(CONFIG_SERVICE) && npm run lint
	@cd $(LOG_SERVICE) && npm run lint
	@echo "$(GREEN)✅ Linting completed$(NC)"

##@ Building

.PHONY: build
build: build-config build-logs ## Build all Docker images
	@echo "$(GREEN)✅ All images built$(NC)"

.PHONY: build-config
build-config: ## Build Configuration Service Docker image
	@echo "$(BLUE)🏗️  Building Configuration Service image...$(NC)"
	@docker build -t $(CONFIG_IMAGE) ./$(CONFIG_SERVICE)
	@echo "$(GREEN)✅ Configuration Service image built$(NC)"

.PHONY: build-logs
build-logs: ## Build Log Aggregator Service Docker image
	@echo "$(BLUE)🏗️  Building Log Aggregator Service image...$(NC)"
	@docker build -t $(LOG_IMAGE) ./$(LOG_SERVICE)
	@echo "$(GREEN)✅ Log Aggregator Service image built$(NC)"

.PHONY: build-no-cache
build-no-cache: ## Build all images without cache
	@echo "$(BLUE)🏗️  Building images without cache...$(NC)"
	@docker build --no-cache -t $(CONFIG_IMAGE) ./$(CONFIG_SERVICE)
	@docker build --no-cache -t $(LOG_IMAGE) ./$(LOG_SERVICE)
	@echo "$(GREEN)✅ Images built without cache$(NC)"

##@ Docker Compose Operations

.PHONY: up
up: ## Start all services with Docker Compose
	@echo "$(BLUE)🚀 Starting all services...$(NC)"
	@docker-compose up -d
	@echo "$(YELLOW)⏳ Waiting for services to be ready...$(NC)"
	@sleep 30
	@make health-check
	@echo "$(GREEN)✅ All services are running$(NC)"

.PHONY: down
down: ## Stop all services
	@echo "$(BLUE)🛑 Stopping all services...$(NC)"
	@docker-compose down
	@echo "$(GREEN)✅ Services stopped$(NC)"

.PHONY: restart
restart: down up ## Restart all services
	@echo "$(GREEN)✅ Services restarted$(NC)"

.PHONY: logs
logs: ## View logs from all services
	@docker-compose logs -f

.PHONY: logs-config
logs-config: ## View Configuration Service logs
	@docker-compose logs -f $(CONFIG_SERVICE)

.PHONY: logs-logs
logs-logs: ## View Log Aggregator Service logs
	@docker-compose logs -f $(LOG_SERVICE)

.PHONY: ps
ps: ## Show running containers
	@docker-compose ps

##@ Kubernetes Operations

.PHONY: k8s-setup-local
k8s-setup-local: ## Setup local Kubernetes with OrbStack
	@echo "$(BLUE)☸️  Setting up local Kubernetes with OrbStack...$(NC)"
	@chmod +x scripts/setup-k8s-local.sh
	@./scripts/setup-k8s-local.sh

.PHONY: k8s-deploy-local
k8s-deploy-local: build ## Deploy to local Kubernetes (OrbStack)
	@echo "$(BLUE)☸️  Deploying to local Kubernetes...$(NC)"
	@kubectx orbstack || echo "$(YELLOW)⚠️ Switch to OrbStack context manually$(NC)"
	@kubectl apply -f k8s-manifests/namespace.yaml
	@kubectl apply -f k8s-manifests/mysql-deployment.yaml
	@kubectl apply -f k8s-manifests/redis-deployment.yaml
	@echo "$(YELLOW)⏳ Waiting for databases to be ready...$(NC)"
	@kubectl wait --for=condition=ready pod -l app=mysql --timeout=120s -n microservices || true
	@kubectl wait --for=condition=ready pod -l app=redis --timeout=120s -n microservices || true
	@kubectl apply -f k8s-manifests/configuration-service.yaml
	@kubectl apply -f k8s-manifests/log-aggregator-service.yaml
	@echo "$(YELLOW)⏳ Waiting for services to be ready...$(NC)"
	@kubectl wait --for=condition=ready pod -l app=configuration-service --timeout=120s -n microservices || true
	@kubectl wait --for=condition=ready pod -l app=log-aggregator-service --timeout=120s -n microservices || true
	@echo "$(GREEN)✅ Deployed to local Kubernetes$(NC)"

.PHONY: k8s-deploy
k8s-deploy: build k8s-push ## Deploy to Kubernetes
	@echo "$(BLUE)☸️  Deploying to Kubernetes...$(NC)"
	@kubectl apply -f k8s-manifests/namespace.yaml
	@kubectl apply -f k8s-manifests/mysql-deployment.yaml
	@kubectl apply -f k8s-manifests/redis-deployment.yaml
	@sleep 30
	@kubectl apply -f k8s-manifests/configuration-service.yaml
	@kubectl apply -f k8s-manifests/log-aggregator-service.yaml
	@echo "$(GREEN)✅ Deployed to Kubernetes$(NC)"

.PHONY: k8s-push
k8s-push: ## Push images to registry
	@echo "$(BLUE)📤 Pushing images to registry...$(NC)"
	@docker push $(CONFIG_IMAGE)
	@docker push $(LOG_IMAGE)
	@echo "$(GREEN)✅ Images pushed$(NC)"

.PHONY: k8s-status
k8s-status: ## Check Kubernetes deployment status
	@echo "$(BLUE)☸️  Checking Kubernetes status...$(NC)"
	@kubectl get all -n $(NAMESPACE)
	@kubectl get pvc -n $(NAMESPACE)

.PHONY: k8s-logs
k8s-logs: ## View Kubernetes logs
	@kubectl logs -f deployment/$(CONFIG_SERVICE) -n $(NAMESPACE)

.PHONY: k8s-delete
k8s-delete: ## Delete Kubernetes deployment
	@echo "$(BLUE)🗑️  Deleting Kubernetes deployment...$(NC)"
	@kubectl delete namespace $(NAMESPACE)
	@echo "$(GREEN)✅ Kubernetes deployment deleted$(NC)"

##@ Monitoring & Health

.PHONY: health-check
health-check: ## Perform health check on all services
	@echo "$(BLUE)🏥 Performing health checks...$(NC)"
	@curl -f http://localhost:3001/health && echo "$(GREEN)✅ Configuration Service healthy$(NC)" || echo "$(RED)❌ Configuration Service unhealthy$(NC)"
	@curl -f http://localhost:3002/health && echo "$(GREEN)✅ Log Aggregator Service healthy$(NC)" || echo "$(RED)❌ Log Aggregator Service unhealthy$(NC)"

.PHONY: smoke-test
smoke-test: ## Run smoke tests against deployed services
	@echo "$(BLUE)💨 Running smoke tests...$(NC)"
	@chmod +x scripts/smoke-test.sh
	@./scripts/smoke-test.sh

.PHONY: load-test
load-test: ## Run load tests (requires k6)
	@echo "$(BLUE)⚡ Running load tests...$(NC)"
	@k6 run scripts/load-test.js

##@ Security

.PHONY: security-scan
security-scan: ## Run security scans on Docker images
	@echo "$(BLUE)🔒 Running security scans...$(NC)"
	@docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy image $(CONFIG_IMAGE)
	@docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy image $(LOG_IMAGE)

.PHONY: audit
audit: ## Run npm security audit
	@echo "$(BLUE)🔍 Running security audit...$(NC)"
	@cd $(CONFIG_SERVICE) && npm audit --audit-level=high
	@cd $(LOG_SERVICE) && npm audit --audit-level=high
	@echo "$(GREEN)✅ Security audit completed$(NC)"

##@ Database

.PHONY: db-reset
db-reset: ## Reset database data
	@echo "$(BLUE)🗄️  Resetting database...$(NC)"
	@docker-compose exec mysql mysql -uroot -ppassword -e "DROP DATABASE IF EXISTS microservices_db; CREATE DATABASE microservices_db;"
	@docker-compose exec redis redis-cli FLUSHALL
	@echo "$(GREEN)✅ Database reset$(NC)"

.PHONY: db-backup
db-backup: ## Backup database
	@echo "$(BLUE)💾 Backing up database...$(NC)"
	@mkdir -p backups
	@docker-compose exec mysql mysqldump -uroot -ppassword microservices_db > backups/backup-$(shell date +%Y%m%d-%H%M%S).sql
	@echo "$(GREEN)✅ Database backed up$(NC)"

.PHONY: db-restore
db-restore: ## Restore database from backup (usage: make db-restore BACKUP=filename.sql)
	@echo "$(BLUE)📥 Restoring database...$(NC)"
	@docker-compose exec -T mysql mysql -uroot -ppassword microservices_db < backups/$(BACKUP)
	@echo "$(GREEN)✅ Database restored$(NC)"

##@ Utility

.PHONY: shell-config
shell-config: ## Shell into Configuration Service container
	@docker-compose exec $(CONFIG_SERVICE) /bin/sh

.PHONY: shell-logs
shell-logs: ## Shell into Log Aggregator Service container
	@docker-compose exec $(LOG_SERVICE) /bin/sh

.PHONY: shell-mysql
shell-mysql: ## Shell into MySQL container
	@docker-compose exec mysql mysql -uroot -ppassword microservices_db

.PHONY: shell-redis
shell-redis: ## Shell into Redis container
	@docker-compose exec redis redis-cli

.PHONY: format
format: ## Format code using prettier
	@echo "$(BLUE)💄 Formatting code...$(NC)"
	@cd $(CONFIG_SERVICE) && npx prettier --write "**/*.js"
	@cd $(LOG_SERVICE) && npx prettier --write "**/*.js"
	@echo "$(GREEN)✅ Code formatted$(NC)"

##@ CI/CD

.PHONY: ci
ci: install lint test build ## Run CI pipeline locally
	@echo "$(GREEN)✅ CI pipeline completed successfully$(NC)"

.PHONY: cd
cd: ci k8s-deploy smoke-test ## Run full CD pipeline locally
	@echo "$(GREEN)✅ CD pipeline completed successfully$(NC)"

##@ Documentation

.PHONY: docs
docs: ## Generate documentation
	@echo "$(BLUE)📚 Generating documentation...$(NC)"
	@cd $(CONFIG_SERVICE) && npm run docs 2>/dev/null || echo "Docs not configured for Configuration Service"
	@cd $(LOG_SERVICE) && npm run docs 2>/dev/null || echo "Docs not configured for Log Aggregator Service"
	@echo "$(GREEN)✅ Documentation generated$(NC)"

##@ Benchmarks

.PHONY: benchmark
benchmark: ## Run performance benchmarks
	@echo "$(BLUE)⚡ Running benchmarks...$(NC)"
	@chmod +x scripts/benchmark.sh
	@./scripts/benchmark.sh

##@ Git Hooks

.PHONY: install-hooks
install-hooks: ## Install Git hooks
	@echo "$(BLUE)🪝 Installing Git hooks...$(NC)"
	@cp scripts/pre-commit .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
	@echo "$(GREEN)✅ Git hooks installed$(NC)"

##@ GitHub Actions Local Testing

.PHONY: act-install
act-install: ## Install act for local GitHub Actions testing
	@echo "$(BLUE)🎭 Installing act...$(NC)"
	@if command -v brew >/dev/null 2>&1; then \
		brew install act; \
	elif command -v curl >/dev/null 2>&1; then \
		curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash; \
	else \
		echo "$(RED)❌ Please install act manually: https://github.com/nektos/act$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✅ act installed$(NC)"

.PHONY: act-setup
act-setup: ## Setup act configuration and secrets
	@echo "$(BLUE)🔧 Setting up act configuration...$(NC)"
	@if [ ! -f ".secrets" ]; then \
		cp .secrets.example .secrets; \
		echo "$(YELLOW)⚠️ Please edit .secrets file with your actual secrets$(NC)"; \
	fi
	@echo "$(GREEN)✅ act configuration ready$(NC)"

.PHONY: act-test
act-test: act-setup ## Test GitHub Actions locally with act
	@echo "$(BLUE)🎭 Testing GitHub Actions locally...$(NC)"
	@chmod +x scripts/test-act.sh
	@./scripts/test-act.sh list
	@./scripts/test-act.sh ci 2>/dev/null || echo "$(YELLOW)⚠️ CI workflow not found, creating basic test$(NC)"

.PHONY: act-ci
act-ci: act-setup ## Run CI workflow locally
	@echo "$(BLUE)🎭 Running CI workflow locally...$(NC)"
	@./scripts/test-act.sh ci

.PHONY: act-all
act-all: act-setup ## Run all workflows locally
	@echo "$(BLUE)🎭 Running all workflows locally...$(NC)"
	@./scripts/test-act.sh all

##@ Development Mode Enhancements

.PHONY: dev-status
dev-status: ## Check status of development services
	@echo "$(BLUE)📊 Development Services Status...$(NC)"
	@echo "\n$(YELLOW)Docker Containers:$(NC)"
	@docker ps --filter "name=mysql\|redis\|configuration-service\|log-aggregator-service" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "No containers running"
	@echo "\n$(YELLOW)Service Health:$(NC)"
	@curl -f -s http://localhost:3001/health 2>/dev/null && echo "✅ Configuration Service (3001)" || echo "❌ Configuration Service (3001)"
	@curl -f -s http://localhost:3002/health 2>/dev/null && echo "✅ Log Aggregator Service (3002)" || echo "❌ Log Aggregator Service (3002)"

.PHONY: dev-logs
dev-logs: ## View development logs
	@echo "$(BLUE)📋 Development Logs...$(NC)"
	@echo "\n$(YELLOW)Docker Compose Logs:$(NC)"
	@docker-compose logs --tail=50 mysql redis 2>/dev/null || echo "No docker-compose services running"

.PHONY: dev-restart
dev-restart: ## Restart development environment
	@echo "$(BLUE)🔄 Restarting development environment...$(NC)"
	@pkill -f "npm run dev" 2>/dev/null || true
	@docker-compose restart mysql redis 2>/dev/null || true
	@sleep 5
	@make dev

.PHONY: dev-stop
dev-stop: ## Stop development services
	@echo "$(BLUE)🛑 Stopping development services...$(NC)"
	@pkill -f "npm run dev" 2>/dev/null || true
	@docker-compose stop mysql redis 2>/dev/null || true
	@echo "$(GREEN)✅ Development services stopped$(NC)"

.PHONY: dev-clean
dev-clean: ## Clean development data and restart fresh
	@echo "$(BLUE)🧹 Cleaning development environment...$(NC)"
	@make dev-stop
	@docker-compose down -v 2>/dev/null || true
	@docker volume prune -f
	@rm -rf */node_modules/.cache 2>/dev/null || true
	@echo "$(GREEN)✅ Development environment cleaned$(NC)"

# Enhanced development mode with better process management
.PHONY: dev-full
dev-full: setup ## Start full development environment with monitoring
	@echo "$(BLUE)🚀 Starting full development environment...$(NC)"
	@make setup-deps
	@echo "$(YELLOW)Starting services with hot reload...$(NC)"
	@trap 'make dev-stop' INT TERM EXIT; \
	(cd $(CONFIG_SERVICE) && npm run dev) & \
	(cd $(LOG_SERVICE) && npm run dev) & \
	echo "$(GREEN)✅ Services started. Press Ctrl+C to stop all services$(NC)"; \
	echo "$(BLUE)📊 Service URLs:$(NC)"; \
	echo "  Configuration Service: http://localhost:3001"; \
	echo "  Log Aggregator Service: http://localhost:3002"; \
	wait

# Help target that lists all available targets
.PHONY: list
list: ## List all available targets
	@make help