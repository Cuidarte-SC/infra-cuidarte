-- =====================================================================
-- Cuidarte+ · Datos de prueba SINTÉTICOS (ambiente QA)
-- Ningún dato corresponde a personas reales (Ley 19.628 / 21.719).
-- Volumen alineado a CP-PERF-01: 500 pacientes y 2.000 exámenes.
-- Contraseñas: solo para QA; se almacenan con bcrypt costo 12.
-- =====================================================================

-- 1) Usuarios de staff (admin y médicos)
INSERT INTO usuario (id, nombre_usuario, password_hash, rol, nombre, correo) VALUES
  (1, 'admin',     crypt('AdminPass123!',  gen_salt('bf', 12)), 'admin',  'Administrador QA', 'admin@cuidarte.test'),
  (2, 'dr_carlos', crypt('SecurePass123!', gen_salt('bf', 12)), 'medico', 'Carlos Muñoz',     'dr.carlos@cuidarte.test'),
  (3, 'dra_ana',   crypt('SecurePass123!', gen_salt('bf', 12)), 'medico', 'Ana Rojas',        'dra.ana@cuidarte.test');

-- 2) 500 pacientes sintéticos con RUT válido (DV calculado)
INSERT INTO paciente (id, rut, nombre, correo, fecha_nacimiento, consentimiento_datos, creado_por)
SELECT
  g,
  rut_formatear(10000000 + g * 7919),
  (ARRAY['María','José','Camila','Pedro','Javiera','Luis','Fernanda','Diego','Valeria','Jorge'])[1 + (g % 10)]
    || ' ' ||
  (ARRAY['González','Muñoz','Rojas','Díaz','Pérez','Soto','Contreras','Silva','Martínez','Sepúlveda'])[1 + ((g / 10) % 10)]
    || ' ' ||
  (ARRAY['Morales','Fuentes','Castillo','Torres','Araya','Flores','Espinoza','Valenzuela','Reyes','Vargas'])[1 + ((g / 100) % 10)],
  'paciente' || g || '@cuidarte.test',
  DATE '1940-01-01' + (g * 37 % 25000),
  TRUE,
  1
FROM generate_series(1, 500) AS g;

-- Paciente 101: usado por CP-INT-01 (EP01)
UPDATE paciente
   SET nombre = 'Juan Pérez García', fecha_nacimiento = DATE '1962-05-15'
 WHERE id = 101;

-- 3) Usuarios con rol paciente (vinculados a su ficha)
--    50 -> paciente 101 (CP-SEG-01) · 51 -> paciente 102 (acceso cruzado)
INSERT INTO usuario (id, nombre_usuario, password_hash, rol, nombre, correo, paciente_id) VALUES
  (50, 'paciente_juan',  crypt('PacientePass123!', gen_salt('bf', 12)), 'paciente', 'Juan Pérez García', 'juan.perez@cuidarte.test', 101),
  (51, 'paciente_maria', crypt('PacientePass123!', gen_salt('bf', 12)), 'paciente',
       (SELECT nombre FROM paciente WHERE id = 102), 'paciente102@cuidarte.test', 102);

-- 4) 2.000 exámenes (4 por paciente)
INSERT INTO examen (paciente_id, medico_id, tipo_examen, fecha_examen, resultado, estado, creado_en, actualizado_en)
SELECT
  ((e - 1) % 500) + 1,
  CASE WHEN e % 2 = 0 THEN 2 ELSE 3 END,
  (ARRAY['Hemograma','Perfil lipídico','Glicemia','Orina completa','Perfil tiroideo'])[1 + (e % 5)],
  DATE '2026-01-01' + (e % 270),
  'Resultado sintético #' || e || ': valores dentro de rango normal',
  'disponible',
  now(), now()
FROM generate_series(1, 2000) AS e;

-- 5) Ajustar secuencias tras insertar IDs explícitos
SELECT setval(pg_get_serial_sequence('usuario',  'id'), (SELECT max(id) FROM usuario));
SELECT setval(pg_get_serial_sequence('paciente', 'id'), (SELECT max(id) FROM paciente));
SELECT setval(pg_get_serial_sequence('examen',   'id'), (SELECT max(id) FROM examen));
