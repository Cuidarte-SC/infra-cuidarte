-- =====================================================================
-- Cuidarte+ · Esquema de base de datos (PostgreSQL 14+)
-- Repo: Cuidarte-SC/infra-cuidarte
-- Trazabilidad: RF-1 (sesión), RF-2 (usuarios/pacientes), RF-3 (exámenes),
--               RF-4 (documentos), RF-5 (auditoría), RB-1/2/3 (roles)
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- gen_salt('bf') = bcrypt (NFR-SEG-2)

-- ---------------------------------------------------------------------
-- Utilidades: validación de RUT chileno (dígito verificador módulo 11)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rut_dv(num BIGINT) RETURNS CHAR(1) AS $$
DECLARE
  s INT := 0;
  m INT := 2;
  n BIGINT := num;
  r INT;
BEGIN
  WHILE n > 0 LOOP
    s := s + (n % 10)::INT * m;
    n := n / 10;
    m := CASE WHEN m = 7 THEN 2 ELSE m + 1 END;
  END LOOP;
  r := 11 - (s % 11);
  RETURN CASE r WHEN 11 THEN '0' WHEN 10 THEN 'K' ELSE r::TEXT END;
END;
$$ LANGUAGE plpgsql IMMUTABLE SET search_path = public;

-- Formato esperado: XX.XXX.XXX-D (con puntos y guion, DV 0-9 o K)
-- SET search_path: necesario para que pg_restore valide el CHECK al restaurar.
CREATE OR REPLACE FUNCTION rut_valido(rut TEXT) RETURNS BOOLEAN AS $$
  SELECT CASE
    WHEN rut ~ '^[0-9]{1,2}\.[0-9]{3}\.[0-9]{3}-[0-9K]$'
      THEN rut_dv(replace(split_part(rut, '-', 1), '.', '')::BIGINT) = split_part(rut, '-', 2)
    ELSE FALSE
  END;
$$ LANGUAGE sql IMMUTABLE SET search_path = public;

CREATE OR REPLACE FUNCTION rut_formatear(num BIGINT) RETURNS TEXT AS $$
  SELECT regexp_replace(num::TEXT, '(\d)(?=(\d{3})+$)', '\1.', 'g') || '-' || rut_dv(num);
$$ LANGUAGE sql IMMUTABLE SET search_path = public;

-- ---------------------------------------------------------------------
-- usuario: cuentas con acceso al sistema (RF-1, RF-2)
-- El visitante anónimo no tiene cuenta.
-- ---------------------------------------------------------------------
CREATE TABLE usuario (
  id              SERIAL PRIMARY KEY,
  nombre_usuario  VARCHAR(50)  NOT NULL UNIQUE,
  password_hash   VARCHAR(100) NOT NULL,              -- bcrypt, nunca texto plano
  rol             VARCHAR(20)  NOT NULL CHECK (rol IN ('admin', 'medico', 'paciente')),
  nombre          VARCHAR(120) NOT NULL,
  correo          VARCHAR(120) NOT NULL UNIQUE,
  paciente_id     INTEGER,                            -- solo si rol = 'paciente'
  activo          BOOLEAN      NOT NULL DEFAULT TRUE,
  creado_en       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- paciente: datos personales (Ley 19.628 / 21.719)
-- ---------------------------------------------------------------------
CREATE TABLE paciente (
  id                   SERIAL PRIMARY KEY,
  rut                  VARCHAR(12)  NOT NULL UNIQUE CHECK (rut_valido(rut)),
  nombre               VARCHAR(120) NOT NULL CHECK (length(trim(nombre)) > 0),
  correo               VARCHAR(120) NOT NULL,
  fecha_nacimiento     DATE         NOT NULL,
  consentimiento_datos BOOLEAN      NOT NULL DEFAULT FALSE,
  creado_por           INTEGER      REFERENCES usuario(id),
  creado_en            TIMESTAMPTZ  NOT NULL DEFAULT now(),
  eliminado_en         TIMESTAMPTZ                      -- eliminación lógica
);

ALTER TABLE usuario
  ADD CONSTRAINT fk_usuario_paciente FOREIGN KEY (paciente_id) REFERENCES paciente(id),
  ADD CONSTRAINT chk_usuario_paciente CHECK (
    (rol = 'paciente' AND paciente_id IS NOT NULL) OR (rol <> 'paciente' AND paciente_id IS NULL)
  );

-- ---------------------------------------------------------------------
-- examen: exámenes médicos (RF-3)
-- ---------------------------------------------------------------------
CREATE TABLE examen (
  id              SERIAL PRIMARY KEY,
  paciente_id     INTEGER      NOT NULL REFERENCES paciente(id),
  medico_id       INTEGER      NOT NULL REFERENCES usuario(id),
  tipo_examen     VARCHAR(80)  NOT NULL,
  fecha_examen    DATE         NOT NULL,
  resultado       TEXT,
  estado          VARCHAR(20)  NOT NULL DEFAULT 'pendiente'
                  CHECK (estado IN ('pendiente', 'disponible')),
  creado_en       TIMESTAMPTZ  NOT NULL DEFAULT now(),
  actualizado_en  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_examen_paciente ON examen(paciente_id);

-- ---------------------------------------------------------------------
-- documento: archivos médicos asociados a un examen (RF-4)
-- El archivo vive en el volumen de documentos; aquí solo metadatos.
-- ---------------------------------------------------------------------
CREATE TABLE documento (
  id                   SERIAL PRIMARY KEY,
  examen_id            INTEGER      NOT NULL REFERENCES examen(id),
  paciente_id          INTEGER      NOT NULL REFERENCES paciente(id),
  nombre_archivo       VARCHAR(255) NOT NULL,
  mime_type            VARCHAR(100) NOT NULL CHECK (mime_type IN (
                         'application/pdf',
                         'application/msword',
                         'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                         'application/vnd.ms-powerpoint',
                         'application/vnd.openxmlformats-officedocument.presentationml.presentation',
                         'image/jpeg',
                         'image/png')),
  tamano_bytes         INTEGER      NOT NULL CHECK (tamano_bytes > 0 AND tamano_bytes <= 10485760),
  ruta_almacenamiento  VARCHAR(500) NOT NULL,
  version              INTEGER      NOT NULL DEFAULT 1,
  subido_por           INTEGER      NOT NULL REFERENCES usuario(id),
  subido_en            TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_documento_examen ON documento(examen_id);

-- ---------------------------------------------------------------------
-- auditoria: registro de acciones críticas (RF-5, NFR-SEG-6)
-- Solo inserción: UPDATE, DELETE y TRUNCATE quedan bloqueados.
-- ---------------------------------------------------------------------
CREATE TABLE auditoria (
  id              BIGSERIAL PRIMARY KEY,
  usuario_id      INTEGER      REFERENCES usuario(id),  -- NULL si es anónimo (login fallido)
  accion          VARCHAR(30)  NOT NULL CHECK (accion IN (
                    'CREATE', 'READ', 'UPDATE', 'DELETE',
                    'LOGIN', 'LOGIN_FALLIDO', 'LOGOUT',
                    'ACCESO_DENEGADO', 'DESCARGA')),
  tabla_afectada  VARCHAR(50),
  registro_id     INTEGER,
  paciente_id     INTEGER      REFERENCES paciente(id),
  descripcion     TEXT,
  ip_origen       INET,
  creado_en       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_auditoria_paciente ON auditoria(paciente_id);
CREATE INDEX idx_auditoria_fecha    ON auditoria(creado_en);

CREATE OR REPLACE FUNCTION auditoria_inmutable() RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION 'La tabla auditoria es de solo inserción (RF-5)';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auditoria_sin_cambios
  BEFORE UPDATE OR DELETE ON auditoria
  FOR EACH ROW EXECUTE FUNCTION auditoria_inmutable();

CREATE TRIGGER trg_auditoria_sin_truncate
  BEFORE TRUNCATE ON auditoria
  FOR EACH STATEMENT EXECUTE FUNCTION auditoria_inmutable();

-- ---------------------------------------------------------------------
-- token_revocado: lista de JWT invalidados al cerrar sesión (RF-1)
-- ---------------------------------------------------------------------
CREATE TABLE token_revocado (
  jti          UUID        PRIMARY KEY,
  usuario_id   INTEGER     NOT NULL REFERENCES usuario(id),
  revocado_en  TIMESTAMPTZ NOT NULL DEFAULT now(),
  expira_en    TIMESTAMPTZ NOT NULL
);
