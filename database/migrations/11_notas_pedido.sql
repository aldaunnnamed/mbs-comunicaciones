-- ================================================================
--  MBS COMUNICACIONES — Migración 11: guardar notas internas de pedido
--  Ejecutar: psql -U postgres -d mbs_comunicaciones -f database/migrations/11_notas_pedido.sql
--
--  El panel admin ya intentaba llamar a un endpoint /pedidos/:id/notas
--  que nunca existió (el frontend llamaba a una ruta 404). No se reutiliza
--  fn_actualizar_estado_pedido porque esa función siempre notifica al
--  cliente por email/notificación de "cambio de estado", incluso si el
--  estado no cambió — no queremos disparar eso solo por guardar una nota
--  interna.
-- ================================================================

CREATE OR REPLACE FUNCTION fn_guardar_notas_pedido(
  p_pedido_id INT,
  p_notas     TEXT,
  p_admin_id  INT
)
RETURNS VARCHAR LANGUAGE plpgsql AS $$
BEGIN
  UPDATE pedidos
     SET notas_internas = p_notas
   WHERE id = p_pedido_id;

  IF NOT FOUND THEN
    RETURN 'ERROR: pedido no encontrado';
  END IF;

  INSERT INTO auditoria (usuario_id, accion, tabla, registro_id, detalle)
  VALUES (p_admin_id, 'guardar_notas_pedido', 'pedidos', p_pedido_id,
          jsonb_build_object('notas', p_notas));

  RETURN 'OK';
END;
$$;
