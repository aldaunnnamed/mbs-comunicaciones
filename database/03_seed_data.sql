-- ================================================================
--  MBS COMUNICACIONES — DATOS INICIALES  PostgreSQL
--  Archivo 03 — Seed data compatible con PG
-- ================================================================

-- ── CONFIGURACIÓN ────────────────────────────────────────────
INSERT INTO configuracion (clave, valor, tipo, seccion, descripcion) VALUES
('site_nombre',         'MBS Comunicaciones',                         'texto',    'general',        'Nombre del sitio web'),
('site_slogan',         'Insumos de fibra optica para profesionales', 'texto',    'general',        'Slogan'),
('site_url',            'https://mbscomunicaciones.mx',               'texto',    'general',        'URL del sitio'),
('site_email',          'ventas@mbscomunicaciones.mx',                'texto',    'general',        'Email de contacto'),
('site_telefono',       '+52 (442) 000-0000',                        'texto',    'general',        'Telefono principal'),
('site_whatsapp',       '5214420000000',                              'texto',    'general',        'WhatsApp CTA'),
('site_direccion',      'Av. Constituyentes 100, Queretaro, Qro.',   'texto',    'general',        'Direccion fisica'),
('site_moneda',         'MXN',                                        'texto',    'general',        'Moneda'),
('site_iva_pct',        '16',                                         'numero',   'general',        'Porcentaje IVA'),
('site_precios_con_iva','true',                                       'booleano', 'general',        'Mostrar precios con IVA'),
('site_facebook',       'https://facebook.com/mbscomunicaciones',    'texto',    'general',        'Facebook'),
('site_instagram',      'https://instagram.com/mbs_comunicaciones',  'texto',    'general',        'Instagram'),
('notif_admin_email',   'admin@mbscomunicaciones.mx',                 'texto',    'notificaciones', 'Email del admin'),
('notif_nuevo_pedido',  'true',  'booleano', 'notificaciones', 'Alertar nuevo pedido'),
('notif_stock_bajo',    'true',  'booleano', 'notificaciones', 'Alertar stock bajo'),
('notif_cliente_confirmacion','true','booleano','notificaciones','Email confirmacion pedido'),
('notif_cliente_estado','true',  'booleano', 'notificaciones', 'Email cambio de estado'),
('seg_2fa_activo',      'true',  'booleano', 'seguridad',      '2FA Google Authenticator')
ON CONFLICT (clave) DO NOTHING;

-- ── CONFIGURACIÓN DE PASARELAS DE PAGO (Stripe/PayPal) ────────
-- (antes vivía en 08_pagos_metodos.sql; el seed de metodos_pago en sí
-- sigue estando solo en la sección de abajo, no se repite aquí)
INSERT INTO configuracion (clave, valor, tipo, seccion, descripcion) VALUES
('stripe_mode',                'sandbox', 'texto',   'pagos', 'Modo Stripe: sandbox o live'),
('stripe_pk_test',             '',        'texto',   'pagos', 'Stripe Publishable Key (test)'),
('stripe_sk_test',             '',        'texto', 'pagos', 'Stripe Secret Key (test)'),
('stripe_webhook_secret_test', '',        'texto', 'pagos', 'Stripe Webhook Signing Secret (test)'),
('stripe_pk_live',             '',        'texto',   'pagos', 'Stripe Publishable Key (live)'),
('stripe_sk_live',             '',        'texto', 'pagos', 'Stripe Secret Key (live)'),
('stripe_webhook_secret_live', '',        'texto', 'pagos', 'Stripe Webhook Signing Secret (live)'),
('paypal_mode',             'sandbox', 'texto',   'pagos', 'Modo PayPal: sandbox o live'),
('paypal_client_id_test',   '',        'texto',   'pagos', 'PayPal Client ID (sandbox)'),
('paypal_secret_test',      '',        'texto', 'pagos', 'PayPal Secret (sandbox)'),
('paypal_webhook_id_test',  '',        'texto',   'pagos', 'PayPal Webhook ID (sandbox)'),
('paypal_client_id_live',   '',        'texto',   'pagos', 'PayPal Client ID (live)'),
('paypal_secret_live',      '',        'texto', 'pagos', 'PayPal Secret (live)'),
('paypal_webhook_id_live',  '',        'texto',   'pagos', 'PayPal Webhook ID (live)')
ON CONFLICT (clave) DO NOTHING;

-- ── MARCAS ────────────────────────────────────────────────────
INSERT INTO marcas (nombre, activa) VALUES
('Corning',   TRUE), ('CommScope', TRUE), ('Panduit', TRUE),
('Siemon',    TRUE), ('Belden',    TRUE), ('MBS',     TRUE)
ON CONFLICT DO NOTHING;

-- ── CATEGORÍAS ────────────────────────────────────────────────
INSERT INTO categorias (nombre, slug, descripcion, icono, orden) VALUES
('Cables de fibra', 'cables-de-fibra', 'Monomodo y multimodo', 'cables',       1),
('Conectores',      'conectores',      'LC, SC, ST, FC, MTP',  'conectores',   2),
('Patch Cords',     'patch-cords',     'SM, MM y armados',     'patch',        3),
('Equipos activos', 'equipos-activos', 'Transceivers, SFP',    'equipos',      4),
('Herramientas',    'herramientas',    'Fusionadoras, OTDR',   'herramientas', 5),
('Accesorios',      'accesorios',      'Cajas, mangas, tubos', 'accesorios',   6)
ON CONFLICT (slug) DO NOTHING;

-- ── MÉTODOS DE ENVÍO ─────────────────────────────────────────
INSERT INTO metodos_envio
  (nombre, descripcion, precio, precio_tipo, dias_min, dias_max, activo, orden, monto_gratis)
VALUES
('FedEx Express',    'Estandar 3-5 dias habiles. Rastreo incluido', 120.00,'fijo',   3,5,TRUE,1,2000),
('FedEx Overnight',  'Express 1-2 dias habiles. Mismo dia <2 PM',  280.00,'fijo',   1,2,TRUE,2,NULL),
('Recoger sucursal', 'Av. Constituyentes 100, Qro. Lun-Vie 9-7',    0.00,'gratis', 0,0,TRUE,3,NULL),
('Envio gratuito',   'Para pedidos mayores a $2,000',                0.00,'gratis', 3,5,TRUE,4,2000),
('Estafeta Nacional','Para pedidos de volumen',                       0.00,'cotizar',5,8,FALSE,5,NULL)
ON CONFLICT (nombre) DO NOTHING;

-- ── MÉTODOS DE PAGO ──────────────────────────────────────────
INSERT INTO metodos_pago (clave, nombre, descripcion, comision, comision_fija, activo) VALUES
('tarjeta', 'Tarjeta credito/debito', 'Visa y Mastercard via Stripe', 0.0360, 3.00, TRUE),
('paypal',  'PayPal',                 'Pagos nacionales e internacionales', 0.0390, NULL, TRUE),
('spei',    'Transferencia SPEI',     'Deposito bancario. Sin comision',  0.0000, NULL, TRUE),
('contado', 'Pago contra entrega',    'Solo Queretaro. Pedidos < $5,000', 0.0000, NULL, TRUE),
('msi',     'Meses sin intereses',    '3, 6 y 12 MSI con tarjetas',       0.0000, NULL, TRUE),
('cripto',  'Criptomonedas',          'Bitcoin, USDT via Bitpay',         0.0000, NULL, FALSE)
ON CONFLICT (clave) DO NOTHING;

-- ── PRODUCTOS ────────────────────────────────────────────────
INSERT INTO productos
  (sku, nombre, slug, descripcion_corta, categoria_id, marca_id,
   precio_venta, precio_antes, stock_actual, stock_minimo, estado, badge, destacado, ventas_totales)
VALUES
('FO-SM-SC-001','Cable FO Monomodo SC/UPC 3mm Drop 1 hilo LSZH',
 'cable-fo-monomodo-sc-upc-3mm',
 'Cable FO monomodo para instalaciones drop FTTH/FTTX. Cubierta LSZH. Baja atenuacion.',
 1,1, 349.00, 410.00, 84, 20,'activo','nuevo',   TRUE, 84),

('CN-LC-SM-002','Conector LC/UPC SM Ceramica 2.0mm',
 'conector-lc-upc-sm-ceramica-2mm',
 'Conector LC monomodo ferrule ceramico. Perdida de insercion ≤0.3 dB.',
 2,1,  89.00, 120.00,  3, 20,'activo','oferta',  TRUE, 58),

('PC-LCLC-SM-3M','Patch Cord LC-LC SM 9/125 Duplex 3m',
 'patch-cord-lc-lc-sm-duplex-3m',
 'Patch cord monomodo LC-LC duplex certificado. Cubierta PVC amarillo.',
 3,1, 145.00, NULL,   42, 10,'activo','top_venta',TRUE, 62),

('TR-SFP10G-SR','Transceiver SFP+ 10G SR 850nm 300m',
 'transceiver-sfp-plus-10g-sr',
 'Transceiver SFP+ 10 Gbps multimodo. Compatible Cisco, Huawei, TP-Link.',
 4,6, 980.00, NULL,   18,  5,'activo', NULL,     FALSE,24),

('HT-FSM-60S','Fusionadora de Fibra Optica Portatil FSM-60S',
 'fusionadora-fo-fsm-60s',
 'Fusionadora de fibra optica con alineacion automatica de nucleo.',
 5,6,14500.00, NULL,   0,  5,'activo', NULL,     FALSE, 0),

('AD-SC-APC-DX','Adaptador SC/APC Duplex SM Verde',
 'adaptador-sc-apc-duplex-verde',
 'Adaptador SC/APC duplex para empalme de conectores. Cuerpo verde.',
 2,3,  42.00, NULL,    5, 15,'activo', NULL,     FALSE, 0),

('AC-MNG-24H','Manga de Empalme FO Aerea 24 hilos',
 'manga-empalme-fo-aerea-24h',
 'Manga para empalme FO aerea. Sellado hermetico IP68.',
 6,6, 560.00, NULL,    4, 10,'activo', NULL,     FALSE, 0),

('HT-OTDR-SM01','OTDR Portatil SM/MM 1310/1550nm',
 'otdr-portatil-sm-mm',
 'Reflectometro optico portatil. Rango dinamico 36 dB. Pantalla tactil.',
 5,6,8200.00, NULL,    6,  3,'activo', NULL,     FALSE, 0),

('FO-MM-OM3-12H','Cable FO MM OM3 50/125 LSZH 12 hilos',
 'cable-fo-mm-om3-50-125-12h',
 'Cable multimodo OM3 de 12 hilos. Cubierta LSZH. Para instalaciones LAN.',
 1,2,2100.00,2800.00,  7, 15,'activo','liquidacion',FALSE,0),

('HT-VFL-5MW','Identificador Visual de Fibra VFL 5mW',
 'identificador-visual-fibra-vfl-5mw',
 'Pluma VFL 5mW para identificacion visual de fibra optica activa.',
 5,6, 680.00, NULL,   19,  5,'activo','top_venta',TRUE, 19)
ON CONFLICT (sku) DO NOTHING;

-- ── ESPECIFICACIONES PRODUCTO 1 ──────────────────────────────
INSERT INTO producto_especificaciones (producto_id, clave, valor, orden)
SELECT p.id, e.clave, e.valor, e.orden
  FROM (VALUES
    ('Tipo de fibra','Monomodo SM G.652D',1),
    ('Conector','SC/UPC',2),
    ('Pulido','UPC (Ultra Physical Contact)',3),
    ('Diametro exterior','3.0 mm',4),
    ('Cubierta','LSZH Amarillo',5),
    ('Perdida de insercion','≤ 0.3 dB',6),
    ('Retorno optico (RL)','≥ 50 dB',7),
    ('Temperatura op.','-20°C a +70°C',8)
  ) AS e(clave,valor,orden)
  JOIN productos p ON p.sku = 'FO-SM-SC-001'
ON CONFLICT (producto_id, clave) DO NOTHING;

-- ── VARIANTES DE LONGITUD ────────────────────────────────────
INSERT INTO variantes_longitud (producto_id, etiqueta, precio_extra, stock)
SELECT p.id, v.etiqueta, v.precio_extra, v.stock
  FROM (VALUES
    ('1 m',      0.00,  30),
    ('2 m',     80.00,  20),
    ('3 m',    160.00,  84),
    ('5 m',    280.00,  15),
    ('10 m',   700.00,   8),
    ('Carrete',5000.00,  3)
  ) AS v(etiqueta,precio_extra,stock)
  JOIN productos p ON p.sku = 'FO-SM-SC-001'
ON CONFLICT (producto_id, etiqueta) DO NOTHING;

-- ── USUARIOS ─────────────────────────────────────────────────
-- Contraseña: Admin@MBS2025 — hash bcrypt, reemplazar en producción
INSERT INTO usuarios
  (nombre, apellidos, email, password_hash, rol, activo)
VALUES
  ('MBS','Admin','admin@mbs.mx',
   '$2b$12$REEMPLAZAR_CON_HASH_REAL_EN_PRODUCCION_xxxxxxxxxxxxxxx',
   'superadmin', TRUE)
ON CONFLICT (email) DO NOTHING;

INSERT INTO usuarios
  (nombre, apellidos, email, password_hash, telefono, rfc, razon_social, tipo, rol)
VALUES
  ('Carlos','Mendez Rojas','carlos@empresa.com',
   '$2b$12$REEMPLAZAR_CON_HASH_REAL_EN_PRODUCCION_xxxxxxxxxxxxxxx',
   '+52 (442) 000-0000','MERJ870420TY3',
   'Telecomunicaciones del Centro SA de CV','empresa','cliente')
ON CONFLICT (email) DO NOTHING;

-- ── DIRECCIÓN DEMO ───────────────────────────────────────────
INSERT INTO direcciones
  (usuario_id, alias, nombre, apellidos, calle_numero, colonia,
   ciudad, estado, cp, es_predeterminada)
SELECT u.id,'Oficina principal','Carlos','Mendez Rojas',
       'Av. Constituyentes 100','Col. Centro',
       'Santiago de Queretaro','Queretaro','76000',TRUE
  FROM usuarios u WHERE u.email = 'carlos@empresa.com'
  AND NOT EXISTS (SELECT 1 FROM direcciones d WHERE d.usuario_id = u.id);
-- ── IMÁGENES DE PRODUCTOS (placeholders) ─────────────────────
ALTER TABLE producto_imagenes ADD COLUMN IF NOT EXISTS es_principal BOOLEAN DEFAULT FALSE;

INSERT INTO producto_imagenes (producto_id, url, alt, orden, es_principal)
SELECT p.id,
       'https://placehold.co/400x400/e2e8f0/64748b?text=' || p.sku,
       p.nombre,
       1,
       TRUE
FROM productos p
WHERE p.sku IN (
  'FO-SM-SC-001','CN-LC-SM-002','PC-LCLC-SM-3M','TR-SFP10G-SR',
  'HT-FSM-60S','AD-SC-APC-DX','AC-MNG-24H','HT-OTDR-SM01',
  'FO-MM-OM3-12H','HT-VFL-5MW','FO-SM-LC-001'
)
AND NOT EXISTS (
  SELECT 1 FROM producto_imagenes pi
  WHERE pi.producto_id = p.id AND pi.es_principal = TRUE
);
