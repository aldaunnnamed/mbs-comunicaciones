-- ================================================================
--  MBS COMUNICACIONES — Archivo 06
--  Crea la carpeta de uploads (ya gestionada por Node/multer)
--  Este archivo es solo referencia; la tabla producto_imagenes
--  ya existe en 01_schema.sql (línea 163).
-- ================================================================

-- Asegurar índice si no existe
CREATE INDEX IF NOT EXISTS idx_prod_imagenes_prod
  ON producto_imagenes(producto_id);

CREATE INDEX IF NOT EXISTS idx_prod_imagenes_principal
  ON producto_imagenes(producto_id, es_principal)
  WHERE es_principal = TRUE;
