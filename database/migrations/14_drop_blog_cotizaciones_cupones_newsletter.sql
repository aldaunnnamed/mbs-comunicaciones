-- ================================================================
--  MBS COMUNICACIONES — Migración 14: eliminar módulos huérfanos
--  (blog/CMS, cotizaciones, cupones, newsletter) y las columnas
--  cupon_id en carritos/pedidos
--  Ejecutar: psql -U postgres -d mbs_comunicaciones -f database/migrations/14_drop_blog_cotizaciones_cupones_newsletter.sql
--
--  Estas 9 tablas y 5 funciones existen en la base de datos pero NO
--  están definidas en ningún script versionado (01_schema.sql /
--  02_functions.sql) — son residuo de una versión anterior del
--  esquema, ya limpiada de los scripts en el commit b6413f7 pero
--  nunca eliminada de las bases de datos ya aprovisionadas.
--  0 referencias en mbs_backend/src, 0 filas verificadas en todas:
--    - blog_articulos, blog_categorias, blog_etiquetas,
--      blog_articulo_etiquetas + fn_guardar_articulo
--    - cotizaciones, cotizacion_items
--      + fn_generar_numero_cotizacion, fn_crear_cotizacion, fn_responder_cotizacion
--    - cupones, cupon_usos + fn_carrito_aplicar_cupon
--    - newsletter (sin función asociada)
--
--  carritos.cupon_id y pedidos.cupon_id tampoco están en 01_schema.sql
--  (mismo drift) y apuntan a cupones — se eliminan antes de poder
--  eliminar la tabla. 0 filas con valor no nulo en ambas, verificado.
--
--  Seguridad: el bloque de abajo aborta la migración si alguna de las
--  tablas tiene filas, o si alguna de esas dos columnas tiene un valor
--  no nulo.
-- ================================================================

DO $$
DECLARE
  v_count INT;
  v_tabla TEXT;
BEGIN
  FOREACH v_tabla IN ARRAY ARRAY[
    'cotizacion_items','cotizaciones','cupon_usos','cupones',
    'blog_articulo_etiquetas','blog_articulos','blog_categorias','blog_etiquetas',
    'newsletter'
  ]
  LOOP
    EXECUTE format('SELECT COUNT(*) FROM %I', v_tabla) INTO v_count;
    IF v_count > 0 THEN
      RAISE EXCEPTION 'Abortado: % tiene % fila(s) — revisar antes de eliminar', v_tabla, v_count;
    END IF;
  END LOOP;

  SELECT COUNT(*) INTO v_count FROM carritos WHERE cupon_id IS NOT NULL;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'Abortado: carritos.cupon_id tiene % valor(es) no nulo(s)', v_count;
  END IF;

  SELECT COUNT(*) INTO v_count FROM pedidos WHERE cupon_id IS NOT NULL;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'Abortado: pedidos.cupon_id tiene % valor(es) no nulo(s)', v_count;
  END IF;
END $$;

DROP FUNCTION IF EXISTS fn_generar_numero_cotizacion();
DROP FUNCTION IF EXISTS fn_carrito_aplicar_cupon(INT, INT, VARCHAR);
DROP FUNCTION IF EXISTS fn_crear_cotizacion(INT, VARCHAR, VARCHAR, TEXT, JSONB);
DROP FUNCTION IF EXISTS fn_responder_cotizacion(INT, TEXT, SMALLINT, NUMERIC, JSONB, INT);
DROP FUNCTION IF EXISTS fn_guardar_articulo(INT, VARCHAR, VARCHAR, TEXT, VARCHAR, INT, VARCHAR, VARCHAR, VARCHAR, INT);

ALTER TABLE carritos DROP COLUMN IF EXISTS cupon_id;
ALTER TABLE pedidos  DROP COLUMN IF EXISTS cupon_id;

DROP TABLE IF EXISTS cotizacion_items;
DROP TABLE IF EXISTS cotizaciones;
DROP TABLE IF EXISTS cupon_usos;
DROP TABLE IF EXISTS cupones;
DROP TABLE IF EXISTS blog_articulo_etiquetas;
DROP TABLE IF EXISTS blog_articulos;
DROP TABLE IF EXISTS blog_categorias;
DROP TABLE IF EXISTS blog_etiquetas;
DROP TABLE IF EXISTS newsletter;
