#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="docker-compose.yaml"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 인증서 갱신 시작..."

cd "$SCRIPT_DIR"

# certbot renew (만료 30일 이내일 때만 실제 갱신)
docker compose -f "$COMPOSE_FILE" run --rm certbot certbot renew \
    --webroot \
    -w /var/www/certbot \
    --non-interactive \
    --quiet

# nginx에 새 인증서 적용 (reload는 기존 연결 유지하며 설정만 갱신)
docker compose -f "$COMPOSE_FILE" exec -T nginx nginx -s reload

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 갱신 완료 (또는 갱신 불필요)"
