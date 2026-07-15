-- ================================================================
--  MBS COMUNICACIONES — Script 08: Métodos de pago y pasarelas
--  Ejecutar: psql -U postgres -d mbs_comunicaciones -f database/08_pagos_metodos.sql
-- ================================================================

-- El seed de metodos_pago vive únicamente en 03_seed_data.sql (claves:
-- tarjeta, paypal, spei, contado, msi, cripto) — no se repite aquí para
-- evitar filas duplicadas por ON CONFLICT (clave) DO NOTHING con una
-- clave distinta para el mismo método (ej. 'entrega' vs 'contado').
-- Este archivo solo siembra la configuración de pasarelas.

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
