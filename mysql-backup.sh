#!/bin/bash
set -e

BACKUP_DIR="$HOME/mysql-backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/gamers_$DATE.sql.gz"
KEEP_DAYS=7

source "$(dirname "$0")/GAMERS-INFRA-PROD/.env" 2>/dev/null || true

mkdir -p "$BACKUP_DIR"

echo "[$DATE] Starting MySQL backup..."

docker exec gamers-mysql mysqldump \
  -u root -p"$DB_ROOT_PASSWORD" \
  --single-transaction \
  --routines \
  --triggers \
  "$DB_NAME" | gzip > "$BACKUP_FILE"

echo "[$DATE] Backup saved: $BACKUP_FILE ($(du -sh "$BACKUP_FILE" | cut -f1))"

# 오래된 백업 삭제
find "$BACKUP_DIR" -name "gamers_*.sql.gz" -mtime +$KEEP_DAYS -delete
echo "[$DATE] Cleaned backups older than $KEEP_DAYS days"
