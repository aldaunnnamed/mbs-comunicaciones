-- ================================================================
--  MBS COMUNICACIONES — Migración 10: SPEI vía Stripe (customer_balance)
--  Ejecutar: psql -U postgres -d mbs_comunicaciones -f database/migrations/10_spei_stripe.sql
--
--  Mantiene intacto el flujo SPEI casero (fn_crear_referencia_spei,
--  fn_confirmar_pago_spei, webhook con token compartido) para los
--  pedidos ya pendientes. Agrega un flujo en paralelo que usa la CLABE
--  dinámica que genera Stripe (mx_bank_transfer), seleccionable con la
--  clave de configuración 'spei_motor' ('legacy' | 'stripe').
-- ================================================================

-- ── 1. Columnas nuevas en pago_referencias para el origen Stripe ──
ALTER TABLE pago_referencias
  ADD COLUMN IF NOT EXISTS stripe_customer_id       VARCHAR(100),
  ADD COLUMN IF NOT EXISTS stripe_payment_intent_id VARCHAR(100),
  ADD COLUMN IF NOT EXISTS origen                   VARCHAR(20) NOT NULL DEFAULT 'legacy'
                                                     CHECK (origen IN ('legacy','stripe'));

CREATE INDEX IF NOT EXISTS idx_pago_ref_stripe_intent
  ON pago_referencias(stripe_payment_intent_id)
  WHERE stripe_payment_intent_id IS NOT NULL;

-- Nuevos estados intermedios: 'procesando' (transferencia detectada, aún
-- no liquidada) y 'fallido' (Stripe reportó payment_failed), además de
-- los que ya existían.
ALTER TABLE pago_referencias DROP CONSTRAINT IF EXISTS pago_referencias_estado_check;
ALTER TABLE pago_referencias ADD CONSTRAINT pago_referencias_estado_check
  CHECK (estado IN ('pendiente','procesando','pagado','vencido','cancelado','fallido'));

-- ── 2. Clave de configuración para alternar el motor sin re-desplegar ──
INSERT INTO configuracion (clave, valor, tipo, seccion, descripcion) VALUES
('spei_motor', 'legacy', 'texto', 'pagos', 'Motor de transferencia SPEI: legacy (CLABE fija propia) o stripe (CLABE dinámica vía Stripe)')
ON CONFLICT (clave) DO NOTHING;

-- ================================================================
-- 3. Crear referencia SPEI vía Stripe (datos ya generados por la API
--    de Stripe — esta función solo los persiste y actualiza el pedido)
-- ================================================================
CREATE OR REPLACE FUNCTION fn_crear_referencia_spei_stripe(
  p_pedido_id               INT,
  p_clabe                   CHAR(18),
  p_banco                   VARCHAR,
  p_beneficiario            VARCHAR,
  p_referencia              VARCHAR,
  p_stripe_customer_id      VARCHAR,
  p_stripe_payment_intent_id VARCHAR,
  p_horas_vence             INT DEFAULT 48
)
RETURNS TABLE(
  r_referencia   VARCHAR,
  r_clabe        CHAR(18),
  r_banco        VARCHAR,
  r_beneficiario VARCHAR,
  r_monto        NUMERIC,
  r_vence_en     TIMESTAMPTZ
) LANGUAGE plpgsql AS $$
DECLARE
  v_monto  NUMERIC;
  v_vence  TIMESTAMPTZ;
BEGIN
  SELECT total INTO v_monto
    FROM pedidos WHERE id = p_pedido_id AND estatus_pago = 'pendiente';

  IF v_monto IS NULL THEN
    RAISE EXCEPTION 'Pedido % no encontrado o ya pagado', p_pedido_id;
  END IF;

  v_vence := NOW() + (p_horas_vence || ' hours')::INTERVAL;

  INSERT INTO pago_referencias
    (pedido_id, clabe, referencia, banco, beneficiario, monto_esperado, vence_en,
     origen, stripe_customer_id, stripe_payment_intent_id)
  VALUES
    (p_pedido_id, p_clabe, p_referencia, p_banco, p_beneficiario, v_monto, v_vence,
     'stripe', p_stripe_customer_id, p_stripe_payment_intent_id);

  UPDATE pedidos
     SET pago_proveedor = 'spei',
         pago_proveedor_estado = 'pendiente'
   WHERE id = p_pedido_id;

  RETURN QUERY
  SELECT p_referencia, p_clabe, p_banco::VARCHAR, p_beneficiario::VARCHAR, v_monto, v_vence;
END;
$$;

-- ================================================================
-- 4. Confirmar/actualizar el estado de un pago SPEI vía Stripe.
--    p_estado: 'procesando' | 'pagado' | 'fallido' | 'vencido'
--    Llamada desde el webhook de Stripe (payment_intent.processing /
--    .succeeded / .payment_failed) identificando la referencia por
--    stripe_payment_intent_id en vez de por token compartido.
-- ================================================================
CREATE OR REPLACE FUNCTION fn_confirmar_pago_spei_stripe(
  p_stripe_payment_intent_id VARCHAR,
  p_estado                   VARCHAR,
  p_monto                    NUMERIC,
  p_webhook_json             JSONB
)
RETURNS VARCHAR LANGUAGE plpgsql AS $$
DECLARE
  v_pedido_id     INT;
  v_estado_previo VARCHAR;
  v_log_id        INT;
BEGIN
  IF p_estado NOT IN ('procesando','pagado','fallido','vencido') THEN
    RAISE EXCEPTION 'Estado % no válido para fn_confirmar_pago_spei_stripe', p_estado;
  END IF;

  INSERT INTO pago_webhooks_log (proveedor, evento, payload, proveedor_event_id)
  VALUES ('stripe_spei', p_estado, p_webhook_json, p_stripe_payment_intent_id)
  RETURNING id INTO v_log_id;

  SELECT pr.pedido_id, pr.estado INTO v_pedido_id, v_estado_previo
    FROM pago_referencias pr
   WHERE pr.stripe_payment_intent_id = p_stripe_payment_intent_id;

  IF v_pedido_id IS NULL THEN
    UPDATE pago_webhooks_log
       SET procesado = FALSE, error = 'PaymentIntent no encontrado en pago_referencias'
     WHERE id = v_log_id;
    RETURN 'ERROR: payment_intent no encontrado';
  END IF;

  -- Webhooks duplicados/reenviados: si ya estaba pagado, no repetir efectos.
  IF v_estado_previo = 'pagado' THEN
    UPDATE pago_webhooks_log SET procesado = TRUE, procesado_en = NOW() WHERE id = v_log_id;
    RETURN 'OK: ya estaba pagado';
  END IF;

  UPDATE pago_referencias
     SET estado         = p_estado,
         monto_recibido = COALESCE(p_monto, monto_recibido),
         pagado_en      = CASE WHEN p_estado = 'pagado' THEN NOW() ELSE pagado_en END,
         webhook_data   = p_webhook_json
   WHERE stripe_payment_intent_id = p_stripe_payment_intent_id;

  IF p_estado = 'pagado' THEN
    UPDATE pedidos
       SET estatus_pago          = 'pagado',
           fecha_pago            = NOW(),
           pago_proveedor_estado = 'confirmado',
           pago_proveedor_id     = p_stripe_payment_intent_id,
           pago_monto_recibido   = p_monto,
           pago_webhook_data     = p_webhook_json
     WHERE id = v_pedido_id;

    INSERT INTO notificaciones (usuario_id, tipo, titulo, mensaje, url)
    SELECT usuario_id,
           'pago_confirmado',
           'Pago recibido — Pedido ' || numero,
           'Recibimos tu transferencia SPEI por $' || p_monto || ' MXN.',
           '/mi-cuenta/pedidos/' || numero
      FROM pedidos WHERE id = v_pedido_id;

    INSERT INTO auditoria (accion, tabla, registro_id, detalle)
    VALUES ('confirmar_pago_spei_stripe', 'pedidos', v_pedido_id,
            jsonb_build_object('stripe_payment_intent_id', p_stripe_payment_intent_id, 'monto', p_monto));

  ELSIF p_estado = 'procesando' THEN
    UPDATE pedidos SET pago_proveedor_estado = 'procesando' WHERE id = v_pedido_id;

  ELSIF p_estado = 'fallido' THEN
    UPDATE pedidos SET pago_proveedor_estado = 'fallido' WHERE id = v_pedido_id;
  END IF;

  UPDATE pago_webhooks_log SET procesado = TRUE, procesado_en = NOW() WHERE id = v_log_id;
  RETURN 'OK';
END;
$$;

-- ================================================================
-- 5. Marcado manual de pago (panel admin) — para pedidos legacy sin
--    webhook real, o cualquier caso fuera de banda (SPEI/tarjeta/otros).
-- ================================================================
CREATE OR REPLACE FUNCTION fn_marcar_pedido_pagado_manual(
  p_pedido_id INT,
  p_admin_id  INT,
  p_nota      TEXT DEFAULT NULL
)
RETURNS VARCHAR LANGUAGE plpgsql AS $$
DECLARE
  v_estatus_previo VARCHAR;
  v_numero         VARCHAR;
  v_usuario_id     INT;
BEGIN
  SELECT estatus_pago, numero, usuario_id INTO v_estatus_previo, v_numero, v_usuario_id
    FROM pedidos WHERE id = p_pedido_id;

  IF v_numero IS NULL THEN
    RETURN 'ERROR: pedido no encontrado';
  END IF;

  IF v_estatus_previo = 'pagado' THEN
    RETURN 'ERROR: el pedido ya estaba marcado como pagado';
  END IF;

  UPDATE pedidos
     SET estatus_pago          = 'pagado',
         fecha_pago            = NOW(),
         pago_proveedor_estado = 'confirmado_manual'
   WHERE id = p_pedido_id;

  -- Si tenía una referencia SPEI pendiente/procesando, cerrarla también
  UPDATE pago_referencias
     SET estado = 'pagado', pagado_en = NOW()
   WHERE pedido_id = p_pedido_id
     AND estado IN ('pendiente','procesando');

  INSERT INTO notificaciones (usuario_id, tipo, titulo, mensaje, url)
  VALUES (v_usuario_id, 'pago_confirmado',
          'Pago recibido — Pedido ' || v_numero,
          'Tu pago fue confirmado manualmente por el equipo de MBS.',
          '/mi-cuenta/pedidos/' || v_numero);

  INSERT INTO auditoria (accion, tabla, registro_id, detalle, usuario_id)
  VALUES ('marcar_pedido_pagado_manual', 'pedidos', p_pedido_id,
          jsonb_build_object('nota', p_nota), p_admin_id);

  RETURN 'OK';
END;
$$;
