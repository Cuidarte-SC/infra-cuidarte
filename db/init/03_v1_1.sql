-- =====================================================================
-- Cuidarte+ · Cambios de esquema v1.1
-- RF-2.1 autoregistro · RF-2.7 eliminación lógica de usuarios
-- RF-3.3 eliminación lógica de exámenes y documentos · RF-1.2 refresh token
-- =====================================================================

-- RF-2.1: un paciente autoregistrado aún no tiene ficha clínica vinculada.
-- Se permite paciente_id NULL para rol paciente; los demás roles nunca tienen ficha.
ALTER TABLE usuario DROP CONSTRAINT chk_usuario_paciente;
ALTER TABLE usuario ADD CONSTRAINT chk_usuario_paciente
  CHECK (rol = 'paciente' OR paciente_id IS NULL);

-- RF-2.7: eliminación lógica de usuarios
ALTER TABLE usuario ADD COLUMN eliminado_en TIMESTAMPTZ;

-- RF-3.3: eliminación lógica de exámenes y documentos
ALTER TABLE examen    ADD COLUMN eliminado_en TIMESTAMPTZ;
ALTER TABLE documento ADD COLUMN eliminado_en TIMESTAMPTZ;

-- RF-4.3: un solo documento activo por examen
CREATE UNIQUE INDEX ux_documento_activo_por_examen
  ON documento (examen_id) WHERE eliminado_en IS NULL;

-- RF-1.2 / 3.1.2: refresh token. Solo se guarda el hash SHA-256, nunca el token.
CREATE TABLE refresh_token (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id  INTEGER     NOT NULL REFERENCES usuario(id),
  token_hash  CHAR(64)    NOT NULL UNIQUE,
  expira_en   TIMESTAMPTZ NOT NULL,
  revocado_en TIMESTAMPTZ,
  creado_en   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_refresh_token_usuario ON refresh_token(usuario_id);