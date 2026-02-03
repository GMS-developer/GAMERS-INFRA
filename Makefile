.PHONY: docker-up docker-down start stop restart logs ps clean network docker-test-up docker-test-down \
	migrate-up-network migrate-down-network migrate-version-network migrate-force-network \
	deploy force migrate-down

ENV_FILE := .env

ifneq (,$(wildcard $(ENV_FILE)))
    include $(ENV_FILE)
    export
endif

# Docker Compose 파일
COMPOSE_FILE := docker-compose.yaml
TEST_DOCKER_FILE := docker-compose-test.yaml

# gamers-server 이미지를 활용한 Migration (Init Container 패턴)
MIGRATOR_IMAGE := ghcr.io/for-gamers/gamers-be:latest
MIGRATOR_RUN := docker compose -f $(COMPOSE_FILE) run --rm

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
# Docker Network Migration (Init Container 이미지 활용)
# ========================================

migrate-up-network: ## Run migrations via Docker network
	@echo "🔄 Running migrations via Docker network..."
	$(MIGRATOR_RUN) gamers-migrator

migrate-down-network: ## Rollback last migration via Docker network
	@echo "⏪ Rolling back last migration via Docker network..."
	$(MIGRATOR_RUN) --entrypoint "make migrate-down" gamers-migrator

migrate-version-network: ## Show migration version via Docker network
	@echo "📊 Current migration version:"
	$(MIGRATOR_RUN) --entrypoint "make migrate-version" gamers-migrator

migrate-force-network: ## Force set migration version or fix dirty state via Docker network (usage: make migrate-force-network version=3)
	@if [ -z "$(version)" ]; then \
		echo "❌ Error: version parameter is required"; \
		echo "Usage: make migrate-force-network version=3"; \
		echo ""; \
		echo "💡 Tip: This also fixes dirty migration state"; \
		exit 1; \
	fi
	@echo "🔧 Forcing migration version to $(version) via Docker network..."
	$(MIGRATOR_RUN) --entrypoint "make migrate-force version=$(version)" gamers-migrator
	@echo "✅ Migration version set to $(version)"

# ========================================
# Init Container 패턴 기반 배포/마이그레이션
# ========================================

deploy: network ## 자동 배포 (migrator -> server 순서로 실행)
	docker compose -p gamers-infra -f $(COMPOSE_FILE) up -d

force: ## Dirty Flag 해결 (usage: make force version=3)
	@if [ -z "$(version)" ]; then \
		echo "Error: version parameter is required"; \
		echo "Usage: make force version=3"; \
		exit 1; \
	fi
	$(MIGRATOR_RUN) --entrypoint "make migrate-force version=$(version)" gamers-migrator

migrate-down: ## 마이그레이션 롤백
	$(MIGRATOR_RUN) --entrypoint "make migrate-down" gamers-migrator

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
	@echo "Init Container Migration:"
	@echo "  make deploy                           - 자동 배포 (migrator 완료 후 서버 시작)"
	@echo "  make force version=N                   - Dirty Flag 해결 (force version)"
	@echo "  make migrate-down                     - 마이그레이션 롤백"
	@echo ""
	@echo "Docker Network Migration (Legacy):"
	@echo "  make migrate-up-network              - Run migrations via Docker network"
	@echo "  make migrate-down-network             - Rollback last migration via Docker network"
	@echo "  make migrate-version-network          - Show migration version via Docker network"
	@echo "  make migrate-force-network version=N  - Force set migration version via Docker network"
