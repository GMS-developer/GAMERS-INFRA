#!/bin/bash
set -e

echo "🚀 Starting deployment..."

sudo chmod 666 /var/run/docker.sock || true

# Create Docker network if it doesn't exist
if ! docker network ls | grep -q gamers-network; then
    echo "🌐 Creating Docker network..."
    docker network create gamers-network
    echo "✅ Network created"
else
    echo "✅ Network already exists"
fi

# Prepare certbot directories
echo "📁 Preparing certbot directories..."
mkdir -p nginx/ssl/certbot nginx/certbot/webroot logs
echo "✅ Directories ready"

# Stop and remove old containers
echo "🛑 Stopping old containers..."
docker compose down || true

# Pull latest images
echo "📥 Pulling latest images..."
docker compose pull

# Issue certificate if not exists, otherwise start full stack directly
if [ ! -d "./nginx/ssl/certbot/live/api.gamers.io.kr" ]; then
    echo "🔐 SSL 인증서가 없습니다. Let's Encrypt 발급을 시작합니다..."
    chmod +x init-letsencrypt.sh
    ./init-letsencrypt.sh
else
    echo "✅ SSL 인증서가 이미 존재합니다."
    echo "🏃 Starting containers..."
    docker compose up -d
fi

# Wait for services to be healthy
echo "⏳ Waiting for services to be healthy..."
sleep 10

# Check container status
echo "📊 Container status:"
docker compose ps

echo "✅ Deployment completed successfully!"
