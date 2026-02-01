.PHONY: docker-up docker-down start stop restart logs ps clean network docker-test-up docker-test-down \
	migrate-up-network migrate-down-network migrate-version-network migrate-force-network

ENV_FILE := .env

ifneq (,$(wildcard $(ENV_FILE)))
    include $(ENV_FILE)
    export
endif

# Docker Compose 파일
COMPOSE_FILE := docker-compose.yaml
TEST_DOCKER_FILE := docker-compose-test.yaml

# Docker Network 기반 Migration (gamers-network 내에서 일회성 컨테이너로 실행)
MIGRATE_DOCKER := docker run --rm --network gamers-network \
	-v $(PWD)/db/migrations:/migrations \
	migrate/migrate \
	-path=/migrations \
	-database "mysql://$(DB_USER):$(DB_PASSWORD)@tcp(gamers-mysql:$(DB_PORT))/$(DB_NAME)"

# 네트워크 생성
network:
	docker network create gamers-network 2>/dev/null || true

# 모든 서비스 시작 (백그라운드)
docker-up: network
	docker compose -p gamers-infra -f $(COMPOSE_FILE) up -d

# 모든 서비스 중지 및 컨테이너 제거
docker-down:
	docker compose -f $(COMPOSE_FILE) down

# 중지된 서비스 시작
start:
	docker compose -f $(COMPOSE_FILE) start

# 실행 중인 서비스 중지
stop:
	docker compose -f $(COMPOSE_FILE) stop

# 서비스 재시작
restart:
	docker compose -f $(COMPOSE_FILE) restart

# 로그 확인 (실시간)
logs:
	docker compose -f $(COMPOSE_FILE) logs -f

# 컨테이너 상태 확인
ps:
	docker compose -f $(COMPOSE_FILE) ps

# 볼륨 포함 완전 삭제
clean:
	docker compose -f $(COMPOSE_FILE) down -v --remove-orphans

# 개별 서비스 명령어
mysql-up:
	docker compose -f $(COMPOSE_FILE) up -d mysql

mysql-down:
	docker compose -f $(COMPOSE_FILE) stop mysql

mysql-logs:
	docker compose -f $(COMPOSE_FILE) logs -f mysql

mysql-shell:
	docker exec -it gamers-mysql mysql -u root -p

redis-up:
	docker compose -f $(COMPOSE_FILE) up -d redis

redis-down:
	docker compose -f $(COMPOSE_FILE) stop redis

redis-logs:
	docker compose -f $(COMPOSE_FILE) logs -f redis

redis-cli:
	docker exec -it gamers-redis redis-cli

rabbitmq-up:
	docker compose -f $(COMPOSE_FILE) up -d rabbitmq

rabbitmq-down:
	docker compose -f $(COMPOSE_FILE) stop rabbitmq

rabbitmq-logs:
	docker compose -f $(COMPOSE_FILE) logs -f rabbitmq

docker-test-up: network
	docker compose -p gamers-infra -f $(TEST_DOCKER_FILE) up -d

docker-test-down:
	docker compose -f $(TEST_DOCKER_FILE) down -v

# ========================================
# Docker Network Migration
# ========================================

migrate-up-network: ## Run migrations via Docker network
	@echo "🔄 Running migrations via Docker network..."
	$(MIGRATE_DOCKER) up

migrate-down-network: ## Rollback last migration via Docker network
	@echo "⏪ Rolling back last migration via Docker network..."
	$(MIGRATE_DOCKER) down 1

migrate-version-network: ## Show migration version via Docker network
	@echo "📊 Current migration version:"
	@$(MIGRATE_DOCKER) version

migrate-force-network: ## Force set migration version or fix dirty state via Docker network (usage: make migrate-force-network version=3)
	@if [ -z "$(version)" ]; then \
		echo "❌ Error: version parameter is required"; \
		echo "Usage: make migrate-force-network version=3"; \
		echo ""; \
		echo "💡 Tip: This also fixes dirty migration state"; \
		exit 1; \
	fi
	@echo "🔧 Forcing migration version to $(version) via Docker network..."
	$(MIGRATE_DOCKER) force $(version)
	@echo "✅ Migration version set to $(version)"

# 도움말
help:
	@echo "사용 가능한 명령어:"
	@echo "  make up        - 모든 서비스 시작"
	@echo "  make down      - 모든 서비스 중지 및 제거"
	@echo "  make start     - 중지된 서비스 시작"
	@echo "  make stop      - 실행 중인 서비스 중지"
	@echo "  make restart   - 서비스 재시작"
	@echo "  make logs      - 로그 확인 (실시간)"
	@echo "  make ps        - 컨테이너 상태 확인"
	@echo "  make clean     - 볼륨 포함 완전 삭제"
	@echo ""
	@echo "개별 서비스:"
	@echo "  make mysql-up/down/logs/shell"
	@echo "  make redis-up/down/logs/cli"
	@echo "  make rabbitmq-up/down/logs"
	@echo ""
	@echo "Docker Network Migration:"
	@echo "  make migrate-up-network              - Run migrations via Docker network"
	@echo "  make migrate-down-network             - Rollback last migration via Docker network"
	@echo "  make migrate-version-network          - Show migration version via Docker network"
	@echo "  make migrate-force-network version=N  - Force set migration version via Docker network"
