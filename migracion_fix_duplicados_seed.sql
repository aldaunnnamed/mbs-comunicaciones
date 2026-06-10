-- ================================================================
--  MBS COMUNICACIONES — CORRECCIÓN DE DUPLICADOS POR RE-EJECUCIÓN
--  DE 03_seed_data.sql (script de un solo uso)
--
--  03_seed_data.sql se ejecutó ~13 veces sobre esta base de datos.
--  La mayoría de los INSERT estaban protegidos con ON CONFLICT,
--  pero metodos_envio, marcas, producto_especificaciones,
--  variantes_longitud y direcciones no lo estaban (o su ON CONFLICT
--  no tenía una restricción UNIQUE real detrás), generando 13 copias
--  de cada fila.
--
--  Este script:
--   1) Re-apunta pedidos.metodo_envio_id de filas duplicadas hacia
--      la fila canónica (id más bajo) con el mismo nombre.
--   2) Elimina las filas duplicadas, conservando en cada grupo
--      la de id más bajo.
--   3) Agrega las restricciones UNIQUE correspondientes (ya
--      incluidas en 01_schema.sql para instalaciones nuevas) para
--      que ON CONFLICT funcione y esto no vuelva a ocurrir.
--
--  NO ejecutar más de una vez: el paso 3 falla si las restricciones
--  ya existen (lo cual es la señal de que el script ya corrió).
-- ================================================================

BEGIN;

-- 1) Re-apuntar pedidos que referencian metodos_envio duplicados
--    hacia la fila canónica (id más bajo) con el mismo nombre.
UPDATE pedidos pe
SET metodo_envio_id = canonico.id
FROM metodos_envio dup
JOIN metodos_envio canonico ON canonico.nombre = dup.nombre
WHERE pe.metodo_envio_id = dup.id
  AND canonico.id <> dup.id
  AND canonico.id = (SELECT MIN(id) FROM metodos_envio m2 WHERE m2.nombre = dup.nombre);

-- 2) Eliminar duplicados, conservando el id más bajo por grupo natural
DELETE FROM metodos_envio a
USING metodos_envio b
WHERE a.nombre = b.nombre AND a.id > b.id;

DELETE FROM marcas a
USING marcas b
WHERE a.nombre = b.nombre AND a.id > b.id;

DELETE FROM producto_especificaciones a
USING producto_especificaciones b
WHERE a.producto_id = b.producto_id AND a.clave = b.clave AND a.id > b.id;

DELETE FROM variantes_longitud a
USING variantes_longitud b
WHERE a.producto_id = b.producto_id AND a.etiqueta = b.etiqueta AND a.id > b.id;

DELETE FROM direcciones a
USING direcciones b
WHERE a.usuario_id = b.usuario_id AND a.calle_numero = b.calle_numero AND a.id > b.id;

-- 3) Restricciones UNIQUE para prevenir recurrencia
ALTER TABLE marcas
  ADD CONSTRAINT uq_marcas_nombre UNIQUE (nombre);

ALTER TABLE metodos_envio
  ADD CONSTRAINT uq_metodos_envio_nombre UNIQUE (nombre);

ALTER TABLE producto_especificaciones
  ADD CONSTRAINT uq_producto_especificaciones_producto_clave UNIQUE (producto_id, clave);

ALTER TABLE variantes_longitud
  ADD CONSTRAINT uq_variantes_longitud_producto_etiqueta UNIQUE (producto_id, etiqueta);

COMMIT;

-- Verificación de conteos finales (esperado: 5, 6, 8, 6, 2)
SELECT 'metodos_envio' tabla, COUNT(*) FROM metodos_envio
UNION ALL SELECT 'marcas', COUNT(*) FROM marcas
UNION ALL SELECT 'producto_especificaciones', COUNT(*) FROM producto_especificaciones
UNION ALL SELECT 'variantes_longitud', COUNT(*) FROM variantes_longitud
UNION ALL SELECT 'direcciones', COUNT(*) FROM direcciones;
