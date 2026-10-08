# infra-cuidarte

Infraestructura del ambiente QA de **Cuidarte+**, el sistema de exámenes médicos. Levanta PostgreSQL con el esquema y los datos de prueba sintéticos y, con el perfil `app`, también la API y el frontend.

## Estructura de la organización

```
Cuidarte-SC/
├── infra-cuidarte/     # este repo: compose, esquema BD, seed, respaldos
├── api-cuidarte/       # Node.js/Express: JWT, bcrypt, RBAC, auditoría
├── frontend-cuidarte/  # React SPA
└── qa-cuidarte/        # Postman, JMeter, Cypress, ZAP y evidencias EP02
```

Clona los cuatro repos en la misma carpeta padre: el `compose.yml` construye la API y el frontend desde `../api-cuidarte` y `../frontend-cuidarte`.

## Uso

```bash
cp .env.example .env               # editar las claves
docker compose up -d               # solo PostgreSQL
docker compose ps                  # db debe estar "healthy"
docker compose --profile app up -d --build   # sistema completo (cuando existan api y frontend)
```

Para reiniciar la BD desde cero (el seed se ejecuta solo con el volumen vacío):

```bash
docker compose down -v && docker compose up -d
```

## Base de datos

| Tabla | Propósito | Requerimiento |
|---|---|---|
| `usuario` | Cuentas con rol `admin`, `medico` o `paciente`; contraseña con bcrypt | RF-1, RF-2, NFR-SEG-2 |
| `paciente` | Datos personales; RUT único con dígito verificador validado; eliminación lógica | RF-2, Ley 19.628 |
| `examen` | Exámenes médicos por paciente | RF-3 |
| `documento` | Metadatos de archivos (PDF, DOC/DOCX, PPT/PPTX, JPG, PNG; máx. 10 MB) | RF-4 |
| `auditoria` | Registro de acciones; **solo inserción** (UPDATE/DELETE/TRUNCATE bloqueados por trigger) | RF-5, NFR-SEG-6 |
| `token_revocado` | JWT invalidados al cerrar sesión | RF-1 |

## Datos de prueba (sintéticos)

500 pacientes y 2.000 exámenes, el volumen usado en CP-PERF-01. Ningún dato corresponde a personas reales.

| Usuario | Contraseña | Rol | Uso en casos |
|---|---|---|---|
| `admin` | `AdminPass123!` | admin | Administración |
| `dr_carlos` | `SecurePass123!` | medico | CP-FUN-01, CP-FUN-02, CP-INT-01, CP-USA-01 |
| `dra_ana` | `SecurePass123!` | medico | Segundo médico |
| `paciente_juan` (id 50) | `PacientePass123!` | paciente → paciente 101 | CP-SEG-01 |
| `paciente_maria` (id 51) | `PacientePass123!` | paciente → paciente 102 | Acceso cruzado entre pacientes |

El paciente 101 es **Juan Pérez García** (CP-INT-01). Las contraseñas son exclusivas del ambiente QA.

## Respaldo y restauración (NFR-SEG-7 · CP-SEG-04)

```bash
./scripts/backup.sh                                  # crea backups/cuidarte_FECHA.dump
./scripts/restore.sh backups/cuidarte_FECHA.dump     # restaura y muestra conteos
```
