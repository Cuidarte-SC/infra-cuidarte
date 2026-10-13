# Restauración del ambiente QA en Windows (NFR-SEG-7 / CP-SEG-04)
# Uso, desde la carpeta infra-cuidarte:
#   .\scripts\restore.ps1 -Fecha 20261013_153000
param([Parameter(Mandatory = $true)][string]$Fecha)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

$dump = "backups/cuidarte_$Fecha.dump"
$docs = "backups/documentos_$Fecha.tar.gz"
if (-not (Test-Path $dump)) { throw "No existe $dump" }

# 1) Base de datos
docker cp $dump cuidarte-db:/tmp/respaldo.dump
docker exec cuidarte-db sh -c "pg_restore -U `$POSTGRES_USER -d `$POSTGRES_DB --clean --if-exists --no-owner /tmp/respaldo.dump"
docker exec cuidarte-db rm /tmp/respaldo.dump

# 2) Documentos (si hay respaldo de ellos)
if (Test-Path $docs) {
  docker run --rm -v cuidarte_documentos:/datos -v "${PWD}/backups:/respaldo:ro" alpine `
    sh -c "rm -rf /datos/* && tar xzf /respaldo/documentos_$Fecha.tar.gz -C /datos"
}

# 3) Verificación
docker exec cuidarte-db sh -c "psql -U `$POSTGRES_USER -d `$POSTGRES_DB -c 'SELECT (SELECT count(*) FROM paciente) AS pacientes, (SELECT count(*) FROM examen) AS examenes, (SELECT count(*) FROM documento) AS documentos, (SELECT count(*) FROM auditoria) AS auditoria;'"
Write-Host "Restauración completada desde $Fecha"
