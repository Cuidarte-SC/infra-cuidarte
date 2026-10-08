#!/usr/bin/env bash
# Restauración de la BD de QA desde un respaldo (NFR-SEG-7 / CP-SEG-04)
# Uso: ./scripts/restore.sh backups/cuidarte_AAAAMMDD_HHMMSS.dump
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

ARCHIVO="${1:?Indica el archivo .dump a restaurar}"

docker exec -i cuidarte-db pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  --clean --if-exists --no-owner < "$ARCHIVO"

docker exec cuidarte-db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
  "SELECT (SELECT count(*) FROM paciente) AS pacientes,
          (SELECT count(*) FROM examen)   AS examenes,
          (SELECT count(*) FROM auditoria) AS auditoria;"

echo "Restauración completada desde $ARCHIVO"
