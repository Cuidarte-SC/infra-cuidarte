# Respaldo del ambiente QA en Windows (NFR-SEG-7 / CP-SEG-04)
# Respalda la base de datos y los documentos médicos (cifrados en reposo).
# Uso, desde la carpeta infra-cuidarte:  .\scripts\backup.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

$fecha = Get-Date -Format 'yyyyMMdd_HHmmss'
New-Item -ItemType Directory -Force -Path backups | Out-Null

# 1) Base de datos: el dump se genera dentro del contenedor y se copia con docker cp
#    (redirigir con ">" en PowerShell corrompe los archivos binarios)
docker exec cuidarte-db sh -c "pg_dump -U `$POSTGRES_USER -d `$POSTGRES_DB -Fc -f /tmp/respaldo.dump"
docker cp cuidarte-db:/tmp/respaldo.dump "backups/cuidarte_$fecha.dump"
docker exec cuidarte-db rm /tmp/respaldo.dump

# 2) Documentos: el volumen se empaqueta tal cual (los archivos ya están cifrados)
docker run --rm -v cuidarte_documentos:/datos:ro -v "${PWD}/backups:/respaldo" alpine `
  tar czf "/respaldo/documentos_$fecha.tar.gz" -C /datos .

Get-ChildItem "backups/*$fecha*" | Format-Table Name, Length, LastWriteTime
Write-Host "Respaldo completado. Guarde también la DATA_ENCRYPTION_KEY: sin ella los datos no se pueden descifrar."
