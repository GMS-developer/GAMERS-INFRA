#!/bin/bash
set -e

# ──────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────
DOMAIN="api.gamers.io.kr"
COMPOSE_FILE="docker-compose.yaml"
CERT_DIR="./nginx/ssl/certbot"
CLOUDFLARE_INI="./nginx/certbot/cloudflare.ini"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# .env에서 값 읽기
if [ -f "$SCRIPT_DIR/.env" ]; then
    EMAIL=$(grep -E '^CERTBOT_EMAIL=' "$SCRIPT_DIR/.env" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
    CF_TOKEN=$(grep -E '^CLOUDFLARE_API_TOKEN=' "$SCRIPT_DIR/.env" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
fi

EMAIL="${CERTBOT_EMAIL:-$EMAIL}"
CF_TOKEN="${CLOUDFLARE_API_TOKEN:-$CF_TOKEN}"

if [ -z "$EMAIL" ]; then
    echo "❌ CERTBOT_EMAIL이 설정되지 않았습니다. .env를 확인하세요."
    exit 1
fi

if [ -z "$CF_TOKEN" ]; then
    echo "❌ CLOUDFLARE_API_TOKEN이 설정되지 않았습니다. .env를 확인하세요."
    exit 1
fi

echo "🔐 Let's Encrypt 인증서 초기화 시작 (DNS-01 / Cloudflare)"
echo "   도메인: $DOMAIN"
echo "   이메일: $EMAIL"

# ──────────────────────────────────────────
# 1. 필요 디렉토리 생성
# ──────────────────────────────────────────
echo ""
echo "📁 디렉토리 생성..."
mkdir -p "$CERT_DIR" "$(dirname "$CLOUDFLARE_INI")"

# ──────────────────────────────────────────
# 2. 이미 인증서가 존재하면 스킵
# ──────────────────────────────────────────
if [ -d "$CERT_DIR/live/$DOMAIN" ]; then
    echo "✅ 인증서가 이미 존재합니다. 초기 발급을 건너뜁니다."
    echo "   갱신이 필요하면 ./renew-cert.sh 를 실행하세요."
    exit 0
fi

# ──────────────────────────────────────────
# 3. Cloudflare 자격증명 파일 생성
# ──────────────────────────────────────────
echo ""
echo "🔑 Cloudflare 자격증명 파일 생성..."
cat > "$CLOUDFLARE_INI" <<EOF
dns_cloudflare_api_token = ${CF_TOKEN}
EOF
chmod 600 "$CLOUDFLARE_INI"
echo "✅ cloudflare.ini 생성 완료"

# ──────────────────────────────────────────
# 4. 인증서 발급 (DNS-01, nginx 중단 불필요)
# ──────────────────────────────────────────
echo ""
echo "🔐 Let's Encrypt 인증서 발급 중..."
docker compose -f "$COMPOSE_FILE" run --rm certbot certonly \
    --dns-cloudflare \
    --dns-cloudflare-credentials /etc/cloudflare/cloudflare.ini \
    --dns-cloudflare-propagation-seconds 30 \
    -d "$DOMAIN" \
    --email "$EMAIL" \
    --agree-tos \
    --no-eff-email \
    --non-interactive

echo "✅ 인증서 발급 완료"

# ──────────────────────────────────────────
# 5. nginx 시작 (또는 재시작)
# ──────────────────────────────────────────
echo ""
echo "🔄 nginx 시작..."
docker compose -f "$COMPOSE_FILE" up -d
echo "✅ 전체 스택 기동 완료"

# ──────────────────────────────────────────
# 6. cron 자동 갱신 등록 (이미 등록된 경우 스킵)
# ──────────────────────────────────────────
echo ""
echo "⏰ 자동 갱신 cron 등록..."
CRON_JOB="0 3 * * * cd $SCRIPT_DIR && ./renew-cert.sh >> $SCRIPT_DIR/logs/certbot-renew.log 2>&1"
CRON_MARKER="renew-cert.sh"

if crontab -l 2>/dev/null | grep -q "$CRON_MARKER"; then
    echo "✅ 이미 cron이 등록되어 있습니다."
else
    mkdir -p "$SCRIPT_DIR/logs"
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "✅ cron 등록 완료 (매일 새벽 3시 갱신 시도)"
fi

echo ""
echo "🎉 Let's Encrypt 설정 완료!"
echo "   인증서 위치: $CERT_DIR/live/$DOMAIN/"
echo "   자동 갱신:   매일 새벽 3시 (만료 30일 전부터 갱신)"
