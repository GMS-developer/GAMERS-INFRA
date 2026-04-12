#!/bin/sh
set -e

DB_URL="mysql://${DB_USER}:${DB_PASSWORD}@tcp(gamers-mysql:3306)/${DB_NAME}"

echo "🔄 Running database migrations..."

if ! migrate -path ./db/migrations -database "$DB_URL" up; then
    echo "❌ Migration failed. Check the error above."
    exit 1
fi

echo "✅ Migrations completed successfully"
