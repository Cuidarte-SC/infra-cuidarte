# infra-cuidarte

Infraestructura del ambiente QA de **Cuidarte+**, el sistema de exámenes médicos del Caso B (ISY1102). Levanta PostgreSQL con el esquema y los datos de prueba sintéticos y, con el perfil `app`, también la API y el frontend.

**Versión bajo prueba EP02:** `v1.1.0` en los 4 repositorios.

## Estructura de la organización

```
Cuidarte-SC/
├── infra-cuidarte/     # este repo: compose, esquema BD, seed, respaldos
├── api-cuidarte/       # Node.js/Express: JWT, bcrypt, RBAC, cifrado en reposo, auditoría
├── frontend-cuidarte/  # React SPA servida por nginx con HTTPS
└── qa-cuidarte/        # colección Postman, reportes y evidencias de la EP02
```

Clona los cuatro repos en la misma carpeta padre: el `compose.yml` construye la API y el frontend desde `../api-cuidarte` y `../frontend-cuidarte`.

## Uso

```powershell
Copy-Item .env.example .env                    # luego editar las 3 claves (ver abajo)
docker compose --profile app up -d --build     # sistema completo: db + api + frontend
docker compose --profile app ps                # los 3 servicios deben estar "Up"
```

| Servicio | URL |
|---|---|
| Frontend | https://localhost:8443 (certificado autofirmado: *Avanzado → Continuar*) |
| API | http://localhost:4000/api/salud |
| Swagger | http://localhost:4000/api/docs |
| PostgreSQL | `localhost:5432` (solo desde esta máquina) |

Para reiniciar la BD desde cero (los scripts de `db/init` se ejecutan solo con el volumen vacío):

```powershell
docker compose --profile app down -v
docker compose --profile app up -d --build
```

## Variables de entorno (`.env`, nunca se sube a Git)

| Variable | Uso | Cómo generarla |
|---|---|---|
| `POSTGRES_PASSWORD` | Clave de la BD | Cualquier clave robusta |
| `JWT_SECRET` | Firma de los JWT (NFR-SEG-9) | 64 caracteres hexadecimales aleatorios |
| `DATA_ENCRYPTION_KEY` | Clave AES-256 del cifrado en reposo (NFR-SEG-3) | 64 caracteres hexadecimales aleatorios, **distinta** de `JWT_SECRET` |

Para generar una clave en PowerShell:

```powershell
$b = New-Object byte[] 32; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); ($b | ForEach-Object { $_.ToString('x2') }) -join ''
```

Si se pierde `DATA_ENCRYPTION_KEY`, los resultados de exámenes y los documentos cifrados **no se pueden recuperar**.

## Base de datos

| Script | Contenido |
|---|---|
| `db/init/01_schema.sql` | Esquema v1.0: tablas, validación de RUT y auditoría inmutable |
| `db/init/02_seed.sql` | Datos de prueba sintéticos |
| `db/init/03_v1_1.sql` | Cambios v1.1: eliminación lógica, refresh token y documento único por examen |

| Tabla | Propósito | Requerimiento |
|---|---|---|
| `usuario` | Cuentas con rol `admin`, `medico` o `paciente`; contraseña con bcrypt; eliminación lógica | RF-1, RF-2, NFR-SEG-2 |
| `paciente` | Datos personales; RUT único con dígito verificador validado; eliminación lógica | RF-2, Ley 19.628 |
| `examen` | Exámenes médicos; el `resultado` se guarda **cifrado** (AES-256-GCM); eliminación lógica | RF-3, NFR-SEG-3 |
| `documento` | Metadatos de archivos (PDF, DOC/DOCX, PPT/PPTX, JPG, PNG; máx. 10 MB); un documento activo por examen | RF-4 |
| `auditoria` | Registro de acciones; **solo inserción** (UPDATE/DELETE/TRUNCATE bloqueados por trigger) | RF-5, NFR-SEG-6 |
| `token_revocado` | JWT invalidados al cerrar sesión | RF-1.2 |
| `refresh_token` | Hash SHA-256 de los refresh tokens, con revocación y expiración | RF-1.2 |

Los resultados del seed se cargan en texto plano y **la API los cifra al arrancar**: la migración es idempotente y queda registrada en el log (`[cifrado] migración en reposo: …`).

## Datos de prueba (sintéticos)

500 pacientes y 2.000 exámenes, el volumen usado en CP-PERF-01. Ningún dato corresponde a personas reales.

| Usuario | Contraseña | Rol | Uso en casos |
|---|---|---|---|
| `admin` | `AdminPass123!` | admin | Gestión de usuarios y auditoría |
| `dr_carlos` | `SecurePass123!` | medico | CP-FUN-01, CP-FUN-02, CP-INT-01, CP-USA-01 |
| `dra_ana` | `SecurePass123!` | medico | Segundo médico; pruebas de carga |
| `paciente_juan` (id 50) | `PacientePass123!` | paciente → ficha 101 | CP-SEG-01, CP-INT-03 |
| `paciente_maria` (id 51) | `PacientePass123!` | paciente → ficha 102 | Acceso cruzado entre pacientes |

El paciente 101 es **Juan Pérez García** (CP-INT-01). Las contraseñas son exclusivas del ambiente QA.

## Respaldo y restauración (NFR-SEG-7 · CP-SEG-04)

Respaldan la **base de datos y el volumen de documentos**.

```powershell
# Windows PowerShell (desde infra-cuidarte)
powershell -ExecutionPolicy Bypass -File .\scripts\backup.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\restore.ps1 -Fecha 20261013_153000
```

```bash
# Linux, macOS o Git Bash
./scripts/backup.sh
./scripts/restore.sh 20261013_153000
```

Los respaldos quedan en `backups/` (excluida de Git). Son **manuales**: el ambiente QA no programa respaldos diarios (riesgo residual de NFR-SEG-7).
