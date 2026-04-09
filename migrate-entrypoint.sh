#!/bin/sh
set -e

DB_URL="mysql://${DB_USER}:${DB_PASSWORD}@tcp(gamers-mysql:3306)/${DB_NAME}"

echo "🔄 Running database migrations..."

output=$(make migrate-up 2>&1)
exit_code=$?

echo "$output"

if [ $exit_code -eq 0 ]; then
    echo "✅ Migrations completed successfully"
    exit 0
fi

# Dirty state 감지 → 자동 복구
if echo "$output" | grep -q "Dirty database version"; then
    VERSION=$(echo "$output" | grep -oE "Dirty database version [0-9]+" | grep -oE "[0-9]+$")
    PREV=$((VERSION - 1))
    echo "⚠️  Dirty migration detected at version $VERSION → forcing to $PREV..."
    migrate -path ./db/migrations -database "$DB_URL" force $PREV
    echo "🔄 Retrying migrations..."
    make migrate-up
    echo "✅ Migrations recovered and completed"
    exit 0
fi

echo "❌ Migration failed"
exit 1
