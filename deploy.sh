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

# Prepare grafana provisioning
echo "📁 Preparing grafana provisioning..."
mkdir -p grafana/provisioning/datasources grafana/provisioning/dashboards grafana/dashboards
echo "✅ Grafana provisioning directories ready"

# Prepare prometheus config
echo "📁 Preparing prometheus config..."
sudo mkdir -p prometheus rabbitmq
sudo chown -R "$(whoami)" prometheus rabbitmq
# Remove if mistakenly created as a directory by Docker (root-owned)
if [ -d prometheus/prometheus.yml ]; then
    rm -rf prometheus/prometheus.yml
fi
if [ ! -f prometheus/prometheus.yml ]; then
    cat > prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "gamers-api"
    static_configs:
      - targets: ["web-app:8080"]
    metrics_path: /metrics

  - job_name: "mysql"
    static_configs:
      - targets: ["gamers-mysql-exporter:9104"]

  - job_name: "redis"
    static_configs:
      - targets: ["gamers-redis-exporter:9121"]

  - job_name: "rabbitmq"
    static_configs:
      - targets: ["gamers-rabbitmq:15692"]
    metrics_path: /metrics
EOF
    echo "✅ prometheus.yml created"
else
    echo "✅ prometheus.yml already exists"
fi

# Prepare rabbitmq config
echo "📁 Preparing rabbitmq config..."
# Remove if mistakenly created as a directory by Docker (root-owned)
if [ -d rabbitmq/enabled_plugins ]; then
    rm -rf rabbitmq/enabled_plugins
fi
if [ ! -f rabbitmq/enabled_plugins ]; then
    echo "[rabbitmq_management,rabbitmq_prometheus]." > rabbitmq/enabled_plugins
    echo "✅ enabled_plugins created"
else
    echo "✅ enabled_plugins already exists"
fi

# Stop and remove old containers
echo "🛑 Stopping old containers..."
docker-compose down || true

# Pull latest images
echo "📥 Pulling latest images..."
docker-compose pull

# Read DOMAIN from .env
DOMAIN=$(grep -E '^DOMAIN=' .env | cut -d'=' -f2 | tr -d '"' | tr -d "'")

if [ -z "$DOMAIN" ]; then
    echo "❌ DOMAIN이 .env에 설정되지 않았습니다."
    exit 1
fi

# Issue certificate if not exists, otherwise start full stack directly
if [ ! -d "./nginx/ssl/certbot/live/$DOMAIN" ]; then
    echo "🔐 SSL 인증서가 없습니다. Let's Encrypt 발급을 시작합니다..."
    chmod +x init-letsencrypt.sh
    ./init-letsencrypt.sh
else
    echo "✅ SSL 인증서가 이미 존재합니다."

    # Start infra services first
    echo "🏃 Starting infrastructure services..."
    docker-compose up -d mysql redis rabbitmq

    # Run migrator in foreground so logs are visible
    echo "🔄 Running migrator (foreground)..."
    if ! docker-compose up --no-deps gamers-migrator; then
        echo "❌ Migration failed! Logs:"
        docker-compose logs gamers-migrator
        exit 1
    fi

    # Start remaining services
    echo "🏃 Starting application services..."
    docker-compose up -d
fi

# Wait for services to be healthy
echo "⏳ Waiting for services to be healthy..."
sleep 10

# Check container status
echo "📊 Container status:"
docker-compose ps

echo "✅ Deployment completed successfully!"
