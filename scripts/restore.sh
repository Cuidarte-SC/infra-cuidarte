#!/usr/bin/env bash
# Restauración del ambiente QA (NFR-SEG-7 / CP-SEG-04)
# Uso: ./scripts/restore.sh 20261013_153000      · En Windows PowerShell: scripts/restore.ps1 -Fecha ...
set -euo pipefail
cd "$(dirname "$0")/.."

FECHA="${1:?Indique la fecha del respaldo (AAAAMMDD_HHMMSS)}"
DUMP="backups/cuidarte_${FECHA}.dump"
DOCS="backups/documentos_${FECHA}.tar.gz"
[ -f "$DUMP" ] || { echo "No existe $DUMP"; exit 1; }

docker cp "$DUMP" cuidarte-db:/tmp/respaldo.dump
docker exec cuidarte-db sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner /tmp/respaldo.dump'
docker exec cuidarte-db rm /tmp/respaldo.dump

if [ -f "$DOCS" ]; then
  docker run --rm -v cuidarte_documentos:/datos -v "$PWD/backups:/respaldo:ro" alpine \
    sh -c "rm -rf /datos/* && tar xzf /respaldo/documentos_${FECHA}.tar.gz -C /datos"
fi

docker exec cuidarte-db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT (SELECT count(*) FROM paciente) AS pacientes, (SELECT count(*) FROM examen) AS examenes, (SELECT count(*) FROM documento) AS documentos, (SELECT count(*) FROM auditoria) AS auditoria;"'
echo "Restauración completada desde ${FECHA}"
