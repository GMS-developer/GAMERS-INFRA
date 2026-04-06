#!/bin/bash
set -e

# ──────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────
DOMAIN="api.gamers.io.kr"
EMAIL="${CERTBOT_EMAIL:-}"          # .env 또는 환경변수에서 읽음
COMPOSE_FILE="docker-compose.yaml"
CERT_DIR="./nginx/ssl/certbot"
WEBROOT_DIR="./nginx/certbot/webroot"
CONF_DIR="./nginx/conf.d"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# .env에서 CERTBOT_EMAIL 읽기 (환경변수 미설정 시)
if [ -z "$EMAIL" ] && [ -f "$SCRIPT_DIR/.env" ]; then
    EMAIL=$(grep -E '^CERTBOT_EMAIL=' "$SCRIPT_DIR/.env" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
fi

if [ -z "$EMAIL" ]; then
    echo "❌ CERTBOT_EMAIL이 설정되지 않았습니다."
    echo "   .env 파일에 CERTBOT_EMAIL=your@email.com 을 추가하거나"
    echo "   환경변수로 export CERTBOT_EMAIL=your@email.com 을 설정하세요."
    exit 1
fi

echo "🔐 Let's Encrypt 인증서 초기화 시작"
echo "   도메인: $DOMAIN"
echo "   이메일: $EMAIL"

# ──────────────────────────────────────────
# 1. 필요 디렉토리 생성
# ──────────────────────────────────────────
echo ""
echo "📁 디렉토리 생성..."
mkdir -p "$CERT_DIR" "$WEBROOT_DIR"

# ──────────────────────────────────────────
# 2. 이미 인증서가 존재하면 스킵
# ──────────────────────────────────────────
if [ -d "$CERT_DIR/live/$DOMAIN" ]; then
    echo "✅ 인증서가 이미 존재합니다. 초기 발급을 건너뜁니다."
    echo "   갱신이 필요하면 ./renew-cert.sh 를 실행하세요."
    exit 0
fi

# ──────────────────────────────────────────
# 3. 기존 nginx 중지
# ──────────────────────────────────────────
echo ""
echo "🛑 기존 nginx 컨테이너 중지..."
docker compose -f "$COMPOSE_FILE" stop nginx 2>/dev/null || true

# ──────────────────────────────────────────
# 4. HTTP-only 설정으로 교체 (HTTPS 블록 없이 nginx 기동)
# ──────────────────────────────────────────
echo ""
echo "🔄 HTTP-only 설정으로 nginx 기동..."
cp "$CONF_DIR/default.conf" "$CONF_DIR/default.conf.bak"
cp "$CONF_DIR/default.conf.init" "$CONF_DIR/default.conf"

docker compose -f "$COMPOSE_FILE" up -d nginx

# nginx 기동 대기
echo "⏳ nginx 기동 대기..."
for i in $(seq 1 15); do
    if docker compose -f "$COMPOSE_FILE" exec -T nginx nginx -t 2>/dev/null; then
        echo "✅ nginx 준비 완료"
        break
    fi
    if [ "$i" -eq 15 ]; then
        echo "❌ nginx 기동 실패"
        cp "$CONF_DIR/default.conf.bak" "$CONF_DIR/default.conf"
        exit 1
    fi
    sleep 2
done

# ──────────────────────────────────────────
# 5. 인증서 발급
# ──────────────────────────────────────────
echo ""
echo "🔐 Let's Encrypt 인증서 발급 중..."
docker compose -f "$COMPOSE_FILE" run --rm certbot certbot certonly \
    --webroot \
    -w /var/www/certbot \
    -d "$DOMAIN" \
    --email "$EMAIL" \
    --agree-tos \
    --no-eff-email \
    --non-interactive

echo "✅ 인증서 발급 완료"

# ──────────────────────────────────────────
# 6. 정식 HTTPS 설정 복원 및 nginx 재시작
# ──────────────────────────────────────────
echo ""
echo "🔄 HTTPS 설정 복원..."
cp "$CONF_DIR/default.conf.bak" "$CONF_DIR/default.conf"

docker compose -f "$COMPOSE_FILE" restart nginx
echo "✅ nginx HTTPS 모드로 재시작 완료"

# ──────────────────────────────────────────
# 7. cron 자동 갱신 등록 (이미 등록된 경우 스킵)
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
