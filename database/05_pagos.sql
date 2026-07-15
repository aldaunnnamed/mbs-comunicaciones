-- ================================================================
--  MBS COMUNICACIONES — MÓDULO DE PAGOS
--  Archivo 05 — Ejecutar después de 01_schema.sql
--  Agrega soporte para transacciones reales:
--  PayPal, SPEI / Referencia bancaria
-- ================================================================

-- ================================================================
-- 1. CAMPOS ADICIONALES EN TABLA PEDIDOS
-- ================================================================

-- ID de la transacción en el proveedor de pagos
-- PayPal: "PAY-8RA97X14K8765432L"
-- Conekta/STP: ID de la transferencia SPEI
ALTER TABLE pedidos
  ADD COLUMN IF NOT EXISTS pago_proveedor       VARCHAR(30)   DEFAULT 'ninguno',
  -- 'paypal', 'spei', 'tarjeta', 'contado', 'ninguno'
  ADD COLUMN IF NOT EXISTS pago_proveedor_id    VARCHAR(100),
  -- Estado que reporta el proveedor externo
  -- PayPal:  CREATED → APPROVED → COMPLETED / FAILED / REFUNDED
  -- SPEI:    pendiente → confirmado → vencido
  ADD COLUMN IF NOT EXISTS pago_proveedor_estado VARCHAR(50),
  -- Monto exacto confirmado por el proveedor
  -- Puede diferir del total si hay comisiones cobradas al cliente
  ADD COLUMN IF NOT EXISTS pago_monto_recibido  NUMERIC(12,2),
  -- Moneda de la transacción
  ADD COLUMN IF NOT EXISTS pago_moneda          CHAR(3)       DEFAULT 'MXN',
  -- JSON completo del webhook recibido del proveedor
  -- Sirve para auditoría, conciliación y resolución de disputas
  ADD COLUMN IF NOT EXISTS pago_webhook_data    JSONB;

-- Índice para buscar pedidos por ID de transacción del proveedor
CREATE INDEX IF NOT EXISTS idx_pedidos_pago_proveedor_id
  ON pedidos(pago_proveedor_id)
  WHERE pago_proveedor_id IS NOT NULL;

-- ================================================================
-- 2. TABLA: REFERENCIAS DE PAGO SPEI
-- Cada pedido que se pague por transferencia recibe una
-- referencia única con CLABE, monto exacto y fecha de vencimiento
-- ================================================================

CREATE TABLE IF NOT EXISTS pago_referencias (
  id              SERIAL        PRIMARY KEY,
  pedido_id       INT           NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
  -- CLABE interbancaria de 18 dígitos del banco receptor
  clabe           CHAR(18)      NOT NULL,
  -- Referencia numérica única que el cliente debe incluir en la transferencia
  referencia      VARCHAR(30)   NOT NULL UNIQUE,
  -- Banco receptor (ej: "STP", "Banamex", "BBVA")
  banco           VARCHAR(80)   NOT NULL DEFAULT 'STP',
  -- Nombre del beneficiario que aparece en la transferencia
  beneficiario    VARCHAR(100)  NOT NULL DEFAULT 'MBS Comunicaciones',
  -- Monto exacto que debe transferir el cliente
  monto_esperado  NUMERIC(12,2) NOT NULL,
  -- Fecha límite para realizar el pago
  vence_en        TIMESTAMPTZ   NOT NULL,
  -- Estado de la referencia: 'procesando' y 'fallido' son intermedios del
  -- flujo Stripe (transferencia detectada aún no liquidada / payment_failed)
  estado          VARCHAR(20)   NOT NULL DEFAULT 'pendiente',
  -- Datos del pago recibido
  pagado_en       TIMESTAMPTZ,
  monto_recibido  NUMERIC(12,2),
  -- Clave de rastreo SPEI (24 caracteres, la asigna el banco emisor)
  clave_rastreo   VARCHAR(24),
  -- RFC o nombre del banco emisor (quien hizo la transferencia)
  banco_emisor    VARCHAR(80),
  -- JSON completo del webhook de confirmación SPEI
  webhook_data    JSONB,
  -- Origen del flujo SPEI: 'legacy' (CLABE fija propia) o 'stripe' (CLABE
  -- dinámica generada por Stripe customer_balance), seleccionable con la
  -- clave de configuración 'spei_motor'
  origen                    VARCHAR(20)  NOT NULL DEFAULT 'legacy'
                             CHECK (origen IN ('legacy','stripe')),
  stripe_customer_id        VARCHAR(100),
  stripe_payment_intent_id  VARCHAR(100),
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pago_referencias_estado_check
    CHECK (estado IN ('pendiente','procesando','pagado','vencido','cancelado','fallido'))
);

CREATE INDEX IF NOT EXISTS idx_pago_ref_pedido    ON pago_referencias(pedido_id);
CREATE INDEX IF NOT EXISTS idx_pago_ref_referencia ON pago_referencias(referencia);
CREATE INDEX IF NOT EXISTS idx_pago_ref_estado     ON pago_referencias(estado);
CREATE INDEX IF NOT EXISTS idx_pago_ref_stripe_intent
  ON pago_referencias(stripe_payment_intent_id)
  WHERE stripe_payment_intent_id IS NOT NULL;
CREATE OR REPLACE FUNCTION fn_pago_referencias_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;
CREATE TRIGGER trg_pago_referencias_updated_at
  BEFORE UPDATE ON pago_referencias
  FOR EACH ROW EXECUTE FUNCTION fn_pago_referencias_updated_at();

-- ================================================================
-- 3. TABLA: TRANSACCIONES PAYPAL
-- Guarda el ciclo completo de vida de un pago PayPal
-- ================================================================

CREATE TABLE IF NOT EXISTS pago_paypal (
  id              SERIAL        PRIMARY KEY,
  pedido_id       INT           NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
  -- ID de la orden creada en PayPal (paso 1)
  order_id        VARCHAR(100)  NOT NULL UNIQUE,
  -- ID de la captura cuando el pago es aprobado (paso 2)
  capture_id      VARCHAR(100),
  -- Estado del ciclo en PayPal
  -- CREATED → APPROVED → COMPLETED / VOIDED / REFUNDED
  estado          VARCHAR(30)   NOT NULL DEFAULT 'CREATED',
  -- Moneda y montos
  moneda          CHAR(3)       NOT NULL DEFAULT 'MXN',
  monto_ordenado  NUMERIC(12,2) NOT NULL,
  monto_capturado NUMERIC(12,2),
  -- Comisión cobrada por PayPal
  comision_paypal NUMERIC(10,2),
  -- Monto neto recibido después de comisión
  monto_neto      NUMERIC(12,2),
  -- Email de la cuenta PayPal del comprador
  email_pagador   VARCHAR(180),
  -- URL de aprobación que se muestra al cliente
  url_aprobacion  VARCHAR(500),
  -- JSON del webhook de confirmación de PayPal
  webhook_data    JSONB,
  -- Timestamps de cada evento
  aprobado_en     TIMESTAMPTZ,
  capturado_en    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pago_paypal_pedido    ON pago_paypal(pedido_id);
CREATE INDEX IF NOT EXISTS idx_pago_paypal_order_id  ON pago_paypal(order_id);
CREATE INDEX IF NOT EXISTS idx_pago_paypal_capture   ON pago_paypal(capture_id)
  WHERE capture_id IS NOT NULL;
CREATE OR REPLACE FUNCTION fn_pago_paypal_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;
CREATE TRIGGER trg_pago_paypal_updated_at
  BEFORE UPDATE ON pago_paypal
  FOR EACH ROW EXECUTE FUNCTION fn_pago_paypal_updated_at();

-- ================================================================
-- 4. TABLA: LOG DE WEBHOOKS
-- Registra TODOS los webhooks recibidos de cualquier proveedor
-- Sirve para depuración, auditoría y reintento de eventos fallidos
-- ================================================================

CREATE TABLE IF NOT EXISTS pago_webhooks_log (
  id              SERIAL        PRIMARY KEY,
  proveedor       VARCHAR(30)   NOT NULL,
  -- 'paypal', 'conekta', 'stp', 'clip'
  evento          VARCHAR(100)  NOT NULL,
  -- PayPal: 'PAYMENT.CAPTURE.COMPLETED'
  -- STP:    'LIQUIDACION', 'DEVOLUCION'
  payload         JSONB         NOT NULL,
  -- ID que manda el proveedor para identificar el evento
  proveedor_event_id VARCHAR(100),
  -- Si ya fue procesado por el backend
  procesado       BOOLEAN       NOT NULL DEFAULT FALSE,
  procesado_en    TIMESTAMPTZ,
  -- Si falló el procesamiento
  error           TEXT,
  ip_origen       VARCHAR(45),
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_webhooks_proveedor  ON pago_webhooks_log(proveedor);
CREATE INDEX IF NOT EXISTS idx_webhooks_procesado  ON pago_webhooks_log(procesado);
CREATE INDEX IF NOT EXISTS idx_webhooks_event_id   ON pago_webhooks_log(proveedor_event_id)
  WHERE proveedor_event_id IS NOT NULL;

-- ================================================================
-- 5. FUNCIONES DEL MÓDULO DE PAGOS
-- ================================================================

-- Crear referencia SPEI para un pedido
CREATE OR REPLACE FUNCTION fn_crear_referencia_spei(
  p_pedido_id    INT,
  p_clabe        CHAR(18),
  p_banco        VARCHAR,
  p_beneficiario VARCHAR,
  p_horas_vence  INT DEFAULT 48
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
  v_referencia  VARCHAR;
  v_monto       NUMERIC;
  v_numero      VARCHAR;
BEGIN
  -- Obtener total del pedido
  SELECT total, numero INTO v_monto, v_numero
    FROM pedidos WHERE id = p_pedido_id AND estatus_pago = 'pendiente';

  IF v_monto IS NULL THEN
    RAISE EXCEPTION 'Pedido % no encontrado o ya pagado', p_pedido_id;
  END IF;

  -- Generar referencia única: año + pedido_id + 4 dígitos aleatorios
  v_referencia := TO_CHAR(NOW(), 'YY')
                  || LPAD(p_pedido_id::TEXT, 6, '0')
                  || LPAD((RANDOM() * 9999)::INT::TEXT, 4, '0');

  -- Insertar referencia
  INSERT INTO pago_referencias
    (pedido_id, clabe, referencia, banco, beneficiario,
     monto_esperado, vence_en)
  VALUES
    (p_pedido_id, p_clabe, v_referencia, p_banco, p_beneficiario,
     v_monto, NOW() + (p_horas_vence || ' hours')::INTERVAL);

  -- Actualizar proveedor en pedido
  UPDATE pedidos
     SET pago_proveedor = 'spei',
         pago_proveedor_estado = 'pendiente'
   WHERE id = p_pedido_id;

  RETURN QUERY
  SELECT v_referencia,
         p_clabe,
         p_banco::VARCHAR,
         p_beneficiario::VARCHAR,
         v_monto,
         NOW() + (p_horas_vence || ' hours')::INTERVAL;
END;
$$;

-- Confirmar pago SPEI recibido (llamado desde el webhook del banco)
CREATE OR REPLACE FUNCTION fn_confirmar_pago_spei(
  p_referencia    VARCHAR,
  p_monto         NUMERIC,
  p_clave_rastreo VARCHAR,
  p_banco_emisor  VARCHAR,
  p_webhook_json  JSONB
)
RETURNS VARCHAR LANGUAGE plpgsql AS $$
DECLARE
  v_pedido_id    INT;
  v_monto_esp    NUMERIC;
  v_log_id       INT;
BEGIN
  -- Registrar webhook recibido
  INSERT INTO pago_webhooks_log (proveedor, evento, payload, proveedor_event_id)
  VALUES ('spei', 'LIQUIDACION', p_webhook_json, p_clave_rastreo)
  RETURNING id INTO v_log_id;

  -- Buscar la referencia pendiente
  SELECT pr.pedido_id, pr.monto_esperado
    INTO v_pedido_id, v_monto_esp
    FROM pago_referencias pr
   WHERE pr.referencia = p_referencia
     AND pr.estado = 'pendiente';

  IF v_pedido_id IS NULL THEN
    UPDATE pago_webhooks_log
       SET procesado = FALSE, error = 'Referencia no encontrada o ya procesada'
     WHERE id = v_log_id;
    RETURN 'ERROR: referencia no encontrada';
  END IF;

  -- Actualizar la referencia
  UPDATE pago_referencias
     SET estado          = 'pagado',
         pagado_en       = NOW(),
         monto_recibido  = p_monto,
         clave_rastreo   = p_clave_rastreo,
         banco_emisor    = p_banco_emisor,
         webhook_data    = p_webhook_json
   WHERE referencia = p_referencia;

  -- Actualizar el pedido
  UPDATE pedidos
     SET estatus_pago          = 'pagado',
         fecha_pago            = NOW(),
         pago_proveedor_estado = 'confirmado',
         pago_proveedor_id     = p_clave_rastreo,
         pago_monto_recibido   = p_monto,
         pago_webhook_data     = p_webhook_json
   WHERE id = v_pedido_id;

  -- Notificar al cliente
  INSERT INTO notificaciones (usuario_id, tipo, titulo, mensaje, url)
  SELECT usuario_id,
         'pago_confirmado',
         'Pago recibido — Pedido ' || numero,
         'Recibimos tu transferencia SPEI por $' || p_monto || ' MXN.',
         '/mi-cuenta/pedidos/' || numero
    FROM pedidos WHERE id = v_pedido_id;

  -- Auditoría
  INSERT INTO auditoria (accion, tabla, registro_id, detalle)
  VALUES ('confirmar_pago_spei', 'pedidos', v_pedido_id,
          jsonb_build_object('referencia', p_referencia,
                             'monto', p_monto,
                             'clave_rastreo', p_clave_rastreo));

  -- Marcar webhook como procesado
  UPDATE pago_webhooks_log SET procesado = TRUE, procesado_en = NOW()
   WHERE id = v_log_id;

  RETURN 'OK';
END;
$$;

-- Crear orden PayPal (guarda los datos iniciales antes de redirigir al cliente)
CREATE OR REPLACE FUNCTION fn_crear_orden_paypal(
  p_pedido_id    INT,
  p_order_id     VARCHAR,
  p_url_aprobacion VARCHAR
)
RETURNS VARCHAR LANGUAGE plpgsql AS $$
DECLARE v_monto NUMERIC;
BEGIN
  SELECT total INTO v_monto FROM pedidos WHERE id = p_pedido_id;

  INSERT INTO pago_paypal
    (pedido_id, order_id, estado, monto_ordenado, url_aprobacion)
  VALUES
    (p_pedido_id, p_order_id, 'CREATED', v_monto, p_url_aprobacion);

  UPDATE pedidos
     SET pago_proveedor        = 'paypal',
         pago_proveedor_id     = p_order_id,
         pago_proveedor_estado = 'CREATED'
   WHERE id = p_pedido_id;

  RETURN 'OK';
END;
$$;

-- Confirmar pago PayPal (llamado desde el webhook de PayPal)
CREATE OR REPLACE FUNCTION fn_confirmar_pago_paypal(
  p_order_id     VARCHAR,
  p_capture_id   VARCHAR,
  p_estado       VARCHAR,
  p_monto        NUMERIC,
  p_comision     NUMERIC,
  p_email_pagador VARCHAR,
  p_webhook_json JSONB
)
RETURNS VARCHAR LANGUAGE plpgsql AS $$
DECLARE
  v_pedido_id     INT;
  v_log_id        INT;
  v_estado_previo VARCHAR;
BEGIN
  -- Registrar webhook
  INSERT INTO pago_webhooks_log
    (proveedor, evento, payload, proveedor_event_id)
  VALUES
    ('paypal', 'PAYMENT.CAPTURE.' || p_estado, p_webhook_json, p_capture_id)
  RETURNING id INTO v_log_id;

  -- Buscar pedido y estado previo de la transacción
  SELECT pedido_id, estado INTO v_pedido_id, v_estado_previo
    FROM pago_paypal WHERE order_id = p_order_id;

  IF v_pedido_id IS NULL THEN
    UPDATE pago_webhooks_log
       SET procesado = FALSE, error = 'Order ID no encontrado'
     WHERE id = v_log_id;
    RETURN 'ERROR: order_id no encontrado';
  END IF;

  -- PayPal puede reenviar el mismo evento (entrega "al menos una vez").
  -- Si ya se había marcado como COMPLETED, no repetir notificación/auditoría.
  IF v_estado_previo = 'COMPLETED' AND p_estado = 'COMPLETED' THEN
    UPDATE pago_webhooks_log
       SET procesado = TRUE, procesado_en = NOW()
     WHERE id = v_log_id;
    RETURN 'OK: pago ya estaba confirmado';
  END IF;

  -- Actualizar transacción PayPal
  UPDATE pago_paypal
     SET capture_id      = p_capture_id,
         estado          = p_estado,
         monto_capturado = p_monto,
         comision_paypal = p_comision,
         monto_neto      = p_monto - COALESCE(p_comision, 0),
         email_pagador   = p_email_pagador,
         webhook_data    = p_webhook_json,
         aprobado_en     = CASE WHEN p_estado = 'APPROVED'   THEN NOW() ELSE aprobado_en   END,
         capturado_en    = CASE WHEN p_estado = 'COMPLETED'  THEN NOW() ELSE capturado_en  END
   WHERE order_id = p_order_id;

  -- Actualizar pedido si el pago fue completado
  IF p_estado = 'COMPLETED' THEN
    UPDATE pedidos
       SET estatus_pago          = 'pagado',
           fecha_pago            = NOW(),
           pago_proveedor_estado = 'COMPLETED',
           pago_proveedor_id     = p_capture_id,
           pago_monto_recibido   = p_monto,
           pago_webhook_data     = p_webhook_json
     WHERE id = v_pedido_id;

    -- Notificar al cliente
    INSERT INTO notificaciones (usuario_id, tipo, titulo, mensaje, url)
    SELECT usuario_id,
           'pago_confirmado',
           'Pago PayPal confirmado — Pedido ' || numero,
           'Tu pago de $' || p_monto || ' MXN fue procesado exitosamente.',
           '/mi-cuenta/pedidos/' || numero
      FROM pedidos WHERE id = v_pedido_id;

    INSERT INTO auditoria (accion, tabla, registro_id, detalle)
    VALUES ('confirmar_pago_paypal', 'pedidos', v_pedido_id,
            jsonb_build_object('order_id', p_order_id,
                               'capture_id', p_capture_id,
                               'monto', p_monto));
  END IF;

  UPDATE pago_webhooks_log
     SET procesado = TRUE, procesado_en = NOW()
   WHERE id = v_log_id;

  RETURN 'OK';
END;
$$;

-- Consultar estado de pago de un pedido (resume toda la info de pago)
CREATE OR REPLACE FUNCTION fn_estado_pago_pedido(p_pedido_id INT)
RETURNS TABLE(
  r_pedido_numero       VARCHAR,
  r_total               NUMERIC,
  r_estatus_pago        VARCHAR,
  r_proveedor           VARCHAR,
  r_proveedor_estado    VARCHAR,
  r_monto_recibido      NUMERIC,
  r_fecha_pago          TIMESTAMPTZ,
  -- SPEI
  r_spei_referencia     VARCHAR,
  r_spei_clabe          CHAR(18),
  r_spei_vence_en       TIMESTAMPTZ,
  r_spei_estado         VARCHAR,
  -- PayPal
  r_paypal_order_id     VARCHAR,
  r_paypal_capture_id   VARCHAR,
  r_paypal_url          VARCHAR,
  r_paypal_estado       VARCHAR
) LANGUAGE sql AS $$
  SELECT
    p.numero,
    p.total,
    p.estatus_pago,
    p.pago_proveedor,
    p.pago_proveedor_estado,
    p.pago_monto_recibido,
    p.fecha_pago,
    -- SPEI
    pr.referencia,
    pr.clabe,
    pr.vence_en,
    pr.estado,
    -- PayPal
    pp.order_id,
    pp.capture_id,
    pp.url_aprobacion,
    pp.estado
  FROM pedidos p
  LEFT JOIN pago_referencias pr ON pr.pedido_id = p.id
  LEFT JOIN pago_paypal       pp ON pp.pedido_id = p.id
  WHERE p.id = p_pedido_id;
$$;

-- Crear referencia SPEI vía Stripe (datos ya generados por la API de
-- Stripe — esta función solo los persiste y actualiza el pedido)
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

-- Confirmar/actualizar el estado de un pago SPEI vía Stripe.
-- p_estado: 'procesando' | 'pagado' | 'fallido' | 'vencido'
-- Llamada desde el webhook de Stripe (payment_intent.processing /
-- .succeeded / .payment_failed) identificando la referencia por
-- stripe_payment_intent_id en vez de por token compartido.
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

-- Marcado manual de pago (panel admin) — para pedidos legacy sin webhook
-- real, o cualquier caso fuera de banda (SPEI/tarjeta/otros).
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

-- ================================================================
-- 6. ACTUALIZAR SEED: Configuración de proveedores de pago
--    Las credenciales de PayPal NO se guardan en esta tabla:
--    se leen desde variables de entorno (PAYPAL_MODE, PAYPAL_CLIENT_ID,
--    PAYPAL_SECRET, PAYPAL_WEBHOOK_ID en .env), igual que JWT_SECRET.
-- ================================================================

INSERT INTO configuracion (clave, valor, tipo, seccion, descripcion) VALUES
('spei_clabe',         '',         'texto', 'pagos', 'CLABE interbancaria de MBS para recibir transferencias'),
('spei_banco',         'STP',      'texto', 'pagos', 'Banco o proveedor SPEI (STP, Conekta, Clip)'),
('spei_beneficiario',  'MBS Comunicaciones', 'texto', 'pagos', 'Nombre del beneficiario en la transferencia'),
('spei_horas_vence',   '48',       'numero','pagos', 'Horas antes de que venza una referencia SPEI'),
('spei_motor',         'legacy',   'texto', 'pagos', 'Motor de transferencia SPEI: legacy (CLABE fija propia) o stripe (CLABE dinámica vía Stripe)')
ON CONFLICT (clave) DO NOTHING;