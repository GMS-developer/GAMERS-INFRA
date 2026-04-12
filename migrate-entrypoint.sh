#!/bin/sh

DB_URL="mysql://${DB_USER}:${DB_PASSWORD}@tcp(gamers-mysql:3306)/${DB_NAME}?multiStatementEnabled=true"

echo "🔄 Running database migrations..."

MIGRATE_OUTPUT=$(migrate -path ./db/migrations -database "$DB_URL" up 2>&1)
MIGRATE_EXIT=$?
echo "$MIGRATE_OUTPUT"

if [ $MIGRATE_EXIT -eq 0 ]; then
    echo "✅ Migrations completed successfully"
    exit 0
fi

# Dirty state 자동 복구 (1회)
if echo "$MIGRATE_OUTPUT" | grep -q "Dirty database version"; then
    VERSION=$(echo "$MIGRATE_OUTPUT" | grep -oE "Dirty database version [0-9]+" | grep -oE "[0-9]+$")
    PREV=$((VERSION - 1))
    echo "⚠️  Dirty state at version $VERSION → forcing to $PREV and retrying..."
    migrate -path ./db/migrations -database "$DB_URL" force $PREV

    RETRY_OUTPUT=$(migrate -path ./db/migrations -database "$DB_URL" up 2>&1)
    RETRY_EXIT=$?
    echo "$RETRY_OUTPUT"

    if [ $RETRY_EXIT -eq 0 ]; then
        echo "✅ Migrations recovered and completed"
        exit 0
    fi

    echo "❌ Migration failed after recovery attempt"
    exit 1
fi

echo "❌ Migration failed"
exit 1
