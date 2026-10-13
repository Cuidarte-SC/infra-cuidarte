#!/usr/bin/env bash
# Respaldo del ambiente QA (NFR-SEG-7 / CP-SEG-04): base de datos y documentos médicos.
# Uso (Linux/macOS/Git Bash): ./scripts/backup.sh     · En Windows PowerShell: scripts/backup.ps1
set -euo pipefail
cd "$(dirname "$0")/.."

FECHA="$(date +%Y%m%d_%H%M%S)"
mkdir -p backups

# 1) Base de datos (el dump se genera dentro del contenedor y se copia)
docker exec cuidarte-db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc -f /tmp/respaldo.dump'
docker cp cuidarte-db:/tmp/respaldo.dump "backups/cuidarte_${FECHA}.dump"
docker exec cuidarte-db rm /tmp/respaldo.dump

# 2) Documentos (ya cifrados en reposo)
docker run --rm -v cuidarte_documentos:/datos:ro -v "$PWD/backups:/respaldo" alpine \
  tar czf "/respaldo/documentos_${FECHA}.tar.gz" -C /datos .

ls -lh backups/*"${FECHA}"*
echo "Respaldo completado. Guarde también la DATA_ENCRYPTION_KEY: sin ella los datos no se pueden descifrar."
