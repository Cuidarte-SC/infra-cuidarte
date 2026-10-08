#!/usr/bin/env bash
# Respaldo de la BD de QA (NFR-SEG-7 / CP-SEG-04)
# Uso: ./scripts/backup.sh
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

mkdir -p backups
ARCHIVO="backups/cuidarte_$(date +%Y%m%d_%H%M%S).dump"

docker exec cuidarte-db pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc > "$ARCHIVO"

echo "Respaldo creado: $ARCHIVO ($(du -h "$ARCHIVO" | cut -f1))"
