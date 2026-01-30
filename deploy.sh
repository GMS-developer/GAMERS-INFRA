#!/bin/bash
set -e

echo "🚀 Starting deployment..."

# Check if Docker is installed
if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
    echo "📦 Setting up Docker repository and installing..."

    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg

    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update

    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    sudo usermod -aG docker $USER
    echo "✅ Docker and Docker Compose installed successfully"
else
    echo "✅ Docker and Docker Compose are already available"
fi

if ! sudo systemctl is-active --quiet docker; then
    echo "⚙️ Starting Docker daemon..."
    sudo systemctl start docker
fi

sudo chmod 666 /var/run/docker.sock || true

# Check if docker compose (V2) is available, install plugin if not
if ! docker compose version &> /dev/null; then
    echo "📦 Installing docker-compose-plugin..."
    sudo apt-get update
    sudo apt-get install -y docker-compose-plugin
    echo "✅ docker-compose-plugin installed"
else
    echo "✅ docker compose is available"
fi

# Create Docker network if it doesn't exist
if ! docker network ls | grep -q gamers-network; then
    echo "🌐 Creating Docker network..."
    docker network create gamers-network
    echo "✅ Network created"
else
    echo "✅ Network already exists"
fi

# Stop and remove old containers
echo "🛑 Stopping old containers..."
docker compose down || true

# Pull latest images
echo "📥 Pulling latest images..."
docker compose pull

# Start containers
echo "🏃 Starting containers..."
docker compose up -d

# Wait for services to be healthy
echo "⏳ Waiting for services to be healthy..."
sleep 10

# Check container status
echo "📊 Container status:"
docker compose ps

echo "✅ Deployment completed successfully!"
