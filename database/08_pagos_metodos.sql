-- ================================================================
--  MBS COMUNICACIONES — Script 08: Métodos de pago y pasarelas
--  Ejecutar: psql -U postgres -d mbs_comunicaciones -f database/08_pagos_metodos.sql
-- ================================================================

CREATE TABLE IF NOT EXISTS metodos_pago (
  id            SERIAL PRIMARY KEY,
  clave         VARCHAR(50) UNIQUE NOT NULL,
  nombre        VARCHAR(100) NOT NULL,
  descripcion   VARCHAR(255),
  comision      NUMERIC(5,2)  DEFAULT 0,
  comision_fija NUMERIC(10,2) DEFAULT 0,
  activo        BOOLEAN DEFAULT TRUE,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO metodos_pago (clave, nombre, descripcion, comision, comision_fija, activo) VALUES
('tarjeta',  'Tarjeta crédito/débito',  'Visa y Mastercard via Stripe',          2.9, 3.0, true),
('paypal',   'PayPal',                   'Pagos nacionales e internacionales',     3.5, 0.0, true),
('spei',     'Transferencia SPEI',       'Depósito bancario. Sin comisión',        0.0, 0.0, true),
('entrega',  'Pago contra entrega',      'Solo Querétaro. Pedidos < $5,000',       0.0, 0.0, true),
('msi',      'Meses sin intereses',      '3, 6 y 12 MSI con tarjetas',             0.0, 0.0, false)
ON CONFLICT (clave) DO NOTHING;

-- Claves de API de pasarelas en tabla configuracion
INSERT INTO configuracion (clave, valor, tipo, seccion, descripcion) VALUES
('stripe_mode',                'sandbox', 'texto',   'pagos', 'Modo Stripe: sandbox o live'),
('stripe_pk_test',             '',        'texto',   'pagos', 'Stripe Publishable Key (test)'),
('stripe_sk_test',             '',        'texto', 'pagos', 'Stripe Secret Key (test)'),
('stripe_webhook_secret_test', '',        'texto', 'pagos', 'Stripe Webhook Signing Secret (test)'),
('stripe_pk_live',             '',        'texto',   'pagos', 'Stripe Publishable Key (live)'),
('stripe_sk_live',             '',        'texto', 'pagos', 'Stripe Secret Key (live)'),
('stripe_webhook_secret_live', '',        'texto', 'pagos', 'Stripe Webhook Signing Secret (live)')
ON CONFLICT (clave) DO NOTHING;

-- PayPal (migración de .env → configuracion)
INSERT INTO configuracion (clave, valor, tipo, seccion, descripcion) VALUES
('paypal_mode',             'sandbox', 'texto',   'pagos', 'Modo PayPal: sandbox o live'),
('paypal_client_id_test',   '',        'texto',   'pagos', 'PayPal Client ID (sandbox)'),
('paypal_secret_test',      '',        'texto', 'pagos', 'PayPal Secret (sandbox)'),
('paypal_webhook_id_test',  '',        'texto',   'pagos', 'PayPal Webhook ID (sandbox)'),
('paypal_client_id_live',   '',        'texto',   'pagos', 'PayPal Client ID (live)'),
('paypal_secret_live',      '',        'texto', 'pagos', 'PayPal Secret (live)'),
('paypal_webhook_id_live',  '',        'texto',   'pagos', 'PayPal Webhook ID (live)')
ON CONFLICT (clave) DO NOTHING;
