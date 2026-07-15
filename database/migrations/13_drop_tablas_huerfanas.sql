-- ================================================================
--  MBS COMUNICACIONES — Migración 13: eliminar tablas huérfanas
--  Ejecutar: psql -U postgres -d mbs_comunicaciones -f database/migrations/13_drop_tablas_huerfanas.sql
--
--  Elimina 3 tablas definidas en 01_schema.sql que nunca se llegaron
--  a usar (0 referencias en mbs_backend/src, 0 filas verificadas):
--    - sesiones               → JWT es stateless, nunca se persistió sesión en servidor.
--    - recuperacion_password  → reemplazada por password_resets (07_contacto.sql),
--                                que sí usa auth.routes.js.
--    - tarjetas_guardadas     → nunca se implementó guardado de tarjetas;
--                                los pagos con tarjeta van directo a Stripe/PayPal.
--
--  Seguridad: el bloque de abajo aborta la migración si alguna de las
--  tablas tiene filas, en vez de asumir que este entorno está en el
--  mismo estado que el que se auditó.
-- ================================================================

DO $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count FROM sesiones;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'Abortado: sesiones tiene % fila(s) — revisar antes de eliminar', v_count;
  END IF;

  SELECT COUNT(*) INTO v_count FROM recuperacion_password;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'Abortado: recuperacion_password tiene % fila(s) — revisar antes de eliminar', v_count;
  END IF;

  SELECT COUNT(*) INTO v_count FROM tarjetas_guardadas;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'Abortado: tarjetas_guardadas tiene % fila(s) — revisar antes de eliminar', v_count;
  END IF;
END $$;

DROP TABLE IF EXISTS sesiones;
DROP TABLE IF EXISTS recuperacion_password;
DROP TABLE IF EXISTS tarjetas_guardadas;
