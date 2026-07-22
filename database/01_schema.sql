-- ================================================================
--  MBS COMUNICACIONES — SCHEMA PostgreSQL 14+
--  Archivo 01 — Tablas, índices, triggers de updated_at y FTS
--  Incluye lo que antes eran los archivos 06_imagenes.sql y
--  07_contacto.sql (fusionados aquí para reducir la cantidad de
--  scripts de instalación).
-- ================================================================


-- ================================================================
-- FUNCIÓN GLOBAL updated_at
-- ================================================================
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- Macro para crear el trigger en cualquier tabla
CREATE OR REPLACE FUNCTION fn_crear_trigger_updated_at(p_tabla TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE format(
    'CREATE TRIGGER trg_%I_updated_at
     BEFORE UPDATE ON %I
     FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at()',
    p_tabla, p_tabla
  );
END;
$$;

-- ================================================================
-- 1. USUARIOS Y AUTENTICACIÓN
-- ================================================================

CREATE TABLE IF NOT EXISTS usuarios (
  id              SERIAL          PRIMARY KEY,
  nombre          VARCHAR(100)    NOT NULL,
  apellidos       VARCHAR(100)    NOT NULL,
  email           VARCHAR(180)    NOT NULL UNIQUE,
  password_hash   VARCHAR(255)    NOT NULL,
  telefono        VARCHAR(20),
  rfc             VARCHAR(13),
  razon_social    VARCHAR(200),
  tipo            VARCHAR(20)     NOT NULL DEFAULT 'particular'
                  CHECK (tipo IN ('particular','empresa')),
  rol             VARCHAR(20)     NOT NULL DEFAULT 'cliente'
                  CHECK (rol IN ('cliente','admin','superadmin')),
  activo          BOOLEAN         NOT NULL DEFAULT TRUE,
  bloqueado       BOOLEAN         NOT NULL DEFAULT FALSE,
  motivo_bloqueo  VARCHAR(255),
  avatar_url      VARCHAR(500),
  notas_internas  TEXT,
  ultimo_login    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_usuarios_email ON usuarios(email);
CREATE INDEX idx_usuarios_rol   ON usuarios(rol);
CREATE INDEX idx_usuarios_tipo  ON usuarios(tipo);
SELECT fn_crear_trigger_updated_at('usuarios');

-- Nota: no hay tabla de sesiones — la autenticación es JWT stateless.
-- La recuperación de contraseña usa password_resets (ver sección 11, más abajo).

-- ================================================================
-- 2. CATÁLOGO
-- ================================================================

CREATE TABLE IF NOT EXISTS categorias (
  id          SERIAL          PRIMARY KEY,
  nombre      VARCHAR(100)    NOT NULL,
  slug        VARCHAR(120)    NOT NULL UNIQUE,
  descripcion TEXT,
  icono       VARCHAR(100),
  imagen_url  VARCHAR(500),
  orden       INT             NOT NULL DEFAULT 0,
  activa      BOOLEAN         NOT NULL DEFAULT TRUE,
  parent_id   INT             REFERENCES categorias(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_categorias_slug   ON categorias(slug);
CREATE INDEX idx_categorias_activa ON categorias(activa);
SELECT fn_crear_trigger_updated_at('categorias');

CREATE TABLE IF NOT EXISTS marcas (
  id          SERIAL          PRIMARY KEY,
  nombre      VARCHAR(100)    NOT NULL UNIQUE,
  logo_url    VARCHAR(500),
  activa      BOOLEAN         NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS productos (
  id                  SERIAL          PRIMARY KEY,
  sku                 VARCHAR(60)     NOT NULL UNIQUE,
  nombre              VARCHAR(300)    NOT NULL,
  slug                VARCHAR(320)    NOT NULL UNIQUE,
  descripcion_corta   VARCHAR(500),
  descripcion_larga   TEXT,
  categoria_id        INT             NOT NULL REFERENCES categorias(id),
  marca_id            INT             REFERENCES marcas(id) ON DELETE SET NULL,
  precio_venta        NUMERIC(12,2)   NOT NULL,
  precio_antes        NUMERIC(12,2),
  stock_actual        INT             NOT NULL DEFAULT 0,
  stock_minimo        INT             NOT NULL DEFAULT 5,
  estado              VARCHAR(20)     NOT NULL DEFAULT 'activo'
                      CHECK (estado IN ('activo','inactivo','borrador')),
  badge               VARCHAR(20)
                      CHECK (badge IN ('nuevo','oferta','top_venta','liquidacion')),
  destacado           BOOLEAN         NOT NULL DEFAULT FALSE,
  peso_kg             NUMERIC(8,3),
  meta_titulo         VARCHAR(200),
  meta_descripcion    VARCHAR(300),
  visitas             INT             NOT NULL DEFAULT 0,
  ventas_totales      INT             NOT NULL DEFAULT 0,
  fts                 TSVECTOR,          -- columna de búsqueda full-text
  created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_productos_sku    ON productos(sku);
CREATE INDEX idx_productos_slug   ON productos(slug);
CREATE INDEX idx_productos_estado ON productos(estado);
CREATE INDEX idx_productos_stock  ON productos(stock_actual);
CREATE INDEX idx_productos_cat    ON productos(categoria_id);
CREATE INDEX idx_productos_fts    ON productos USING GIN(fts);
SELECT fn_crear_trigger_updated_at('productos');

-- Trigger para mantener el tsvector actualizado
CREATE OR REPLACE FUNCTION fn_productos_fts()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.fts = to_tsvector('simple',
    COALESCE(NEW.nombre,'') || ' ' ||
    COALESCE(NEW.sku,'')   || ' ' ||
    COALESCE(NEW.descripcion_corta,'')
  );
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_productos_fts
  BEFORE INSERT OR UPDATE ON productos
  FOR EACH ROW EXECUTE FUNCTION fn_productos_fts();

CREATE TABLE IF NOT EXISTS producto_imagenes (
  id           SERIAL        PRIMARY KEY,
  producto_id  INT           NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
  url          VARCHAR(500)  NOT NULL,
  alt          VARCHAR(200),
  orden        INT           NOT NULL DEFAULT 0,
  es_principal BOOLEAN       NOT NULL DEFAULT FALSE,
  created_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_prod_imagenes_prod ON producto_imagenes(producto_id);
CREATE INDEX idx_prod_imagenes_principal ON producto_imagenes(producto_id, es_principal)
  WHERE es_principal = TRUE;

CREATE TABLE IF NOT EXISTS producto_especificaciones (
  id          SERIAL        PRIMARY KEY,
  producto_id INT           NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
  clave       VARCHAR(100)  NOT NULL,
  valor       VARCHAR(300)  NOT NULL,
  orden       INT           NOT NULL DEFAULT 0,
  UNIQUE (producto_id, clave)
);

CREATE TABLE IF NOT EXISTS variantes_longitud (
  id          SERIAL        PRIMARY KEY,
  producto_id INT           NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
  etiqueta    VARCHAR(50)   NOT NULL,
  precio_extra NUMERIC(10,2) NOT NULL DEFAULT 0,
  stock       INT           NOT NULL DEFAULT 0,
  activa      BOOLEAN       NOT NULL DEFAULT TRUE,
  UNIQUE (producto_id, etiqueta)
);

-- ================================================================
-- 3. MOVIMIENTOS DE INVENTARIO
-- ================================================================

CREATE TABLE IF NOT EXISTS inventario_movimientos (
  id            SERIAL        PRIMARY KEY,
  producto_id   INT           NOT NULL REFERENCES productos(id),
  tipo          VARCHAR(20)   NOT NULL
                CHECK (tipo IN ('entrada','salida','ajuste','devolucion','reserva')),
  cantidad      INT           NOT NULL,
  stock_antes   INT           NOT NULL,
  stock_despues INT           NOT NULL,
  motivo        VARCHAR(200),
  referencia    VARCHAR(100),
  usuario_id    INT           REFERENCES usuarios(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_inv_mov_prod    ON inventario_movimientos(producto_id);
CREATE INDEX idx_inv_mov_created ON inventario_movimientos(created_at);

-- ================================================================
-- 4. RESEÑAS
-- ================================================================

CREATE TABLE IF NOT EXISTS resenas (
  id           SERIAL        PRIMARY KEY,
  producto_id  INT           NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
  usuario_id   INT           NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  calificacion SMALLINT      NOT NULL CHECK (calificacion BETWEEN 1 AND 5),
  titulo       VARCHAR(200),
  comentario   TEXT,
  verificado   BOOLEAN       NOT NULL DEFAULT FALSE,
  aprobado     BOOLEAN       NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (usuario_id, producto_id)
);

-- ================================================================
-- 5. FAVORITOS
-- ================================================================

CREATE TABLE IF NOT EXISTS favoritos (
  id          SERIAL        PRIMARY KEY,
  usuario_id  INT           NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  producto_id INT           NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (usuario_id, producto_id)
);

-- ================================================================
-- 6. DIRECCIONES
-- ================================================================

CREATE TABLE IF NOT EXISTS direcciones (
  id                SERIAL        PRIMARY KEY,
  usuario_id        INT           NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  alias             VARCHAR(80),
  nombre            VARCHAR(100)  NOT NULL,
  apellidos         VARCHAR(100)  NOT NULL,
  calle_numero      VARCHAR(200)  NOT NULL,
  colonia           VARCHAR(100)  NOT NULL,
  ciudad            VARCHAR(100)  NOT NULL,
  estado            VARCHAR(100)  NOT NULL,
  cp                VARCHAR(10)   NOT NULL,
  pais              VARCHAR(60)   NOT NULL DEFAULT 'México',
  telefono          VARCHAR(20),
  referencias       VARCHAR(300),
  es_predeterminada BOOLEAN       NOT NULL DEFAULT FALSE,
  created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_dir_usuario ON direcciones(usuario_id);
SELECT fn_crear_trigger_updated_at('direcciones');


-- ================================================================
-- 7. MÉTODOS DE ENVÍO Y PAGO
-- ================================================================

CREATE TABLE IF NOT EXISTS metodos_envio (
  id          SERIAL        PRIMARY KEY,
  nombre      VARCHAR(100)  NOT NULL UNIQUE,
  descripcion VARCHAR(300),
  precio      NUMERIC(10,2) NOT NULL DEFAULT 0,
  precio_tipo VARCHAR(20)   NOT NULL DEFAULT 'fijo'
              CHECK (precio_tipo IN ('fijo','gratis','cotizar')),
  dias_min    SMALLINT,
  dias_max    SMALLINT,
  activo      BOOLEAN       NOT NULL DEFAULT TRUE,
  orden       INT           NOT NULL DEFAULT 0,
  monto_gratis NUMERIC(12,2),
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS metodos_pago (
  id            SERIAL        PRIMARY KEY,
  clave         VARCHAR(50)   NOT NULL UNIQUE,
  nombre        VARCHAR(100)  NOT NULL,
  descripcion   VARCHAR(300),
  comision      NUMERIC(5,4),
  comision_fija NUMERIC(10,2),
  activo        BOOLEAN       NOT NULL DEFAULT TRUE,
  config_json   JSONB
);

-- Nota: no hay tabla de tarjetas guardadas — los pagos con tarjeta van
-- directo a Stripe/PayPal, que tokenizan y almacenan del lado del gateway.

-- ================================================================
-- 8. CARRITO
-- ================================================================

CREATE TABLE IF NOT EXISTS carritos (
  id          SERIAL        PRIMARY KEY,
  usuario_id  INT           REFERENCES usuarios(id) ON DELETE CASCADE,
  session_key VARCHAR(100),
  notas       TEXT,
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_carrito_usuario ON carritos(usuario_id);
CREATE INDEX idx_carrito_session ON carritos(session_key);
SELECT fn_crear_trigger_updated_at('carritos');

CREATE TABLE IF NOT EXISTS carrito_items (
  id              SERIAL        PRIMARY KEY,
  carrito_id      INT           NOT NULL REFERENCES carritos(id) ON DELETE CASCADE,
  producto_id     INT           NOT NULL REFERENCES productos(id),
  variante_id     INT           REFERENCES variantes_longitud(id) ON DELETE SET NULL,
  cantidad        INT           NOT NULL DEFAULT 1,
  precio_unitario NUMERIC(12,2) NOT NULL,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (carrito_id, producto_id, variante_id)
);
SELECT fn_crear_trigger_updated_at('carrito_items');

-- ================================================================
-- 9. PEDIDOS
-- ================================================================

CREATE TABLE IF NOT EXISTS pedidos (
  id                  SERIAL        PRIMARY KEY,
  numero              VARCHAR(30)   NOT NULL UNIQUE,
  usuario_id          INT           NOT NULL REFERENCES usuarios(id),
  estado              VARCHAR(25)   NOT NULL DEFAULT 'nuevo'
                      CHECK (estado IN ('nuevo','en_preparacion','enviado',
                                        'en_camino','entregado','cancelado','devolucion')),
  -- Snapshot dirección
  dir_nombre          VARCHAR(100)  NOT NULL,
  dir_apellidos       VARCHAR(100)  NOT NULL,
  dir_calle           VARCHAR(200)  NOT NULL,
  dir_colonia         VARCHAR(100)  NOT NULL,
  dir_ciudad          VARCHAR(100)  NOT NULL,
  dir_estado_geo      VARCHAR(100)  NOT NULL,
  dir_cp              VARCHAR(10)   NOT NULL,
  dir_telefono        VARCHAR(20),
  -- Totales
  subtotal            NUMERIC(12,2) NOT NULL,
  costo_envio         NUMERIC(12,2) NOT NULL DEFAULT 0,
  iva                 NUMERIC(12,2) NOT NULL DEFAULT 0,
  total               NUMERIC(12,2) NOT NULL,
  -- Pago
  metodo_pago_id      INT           NOT NULL REFERENCES metodos_pago(id),
  estatus_pago        VARCHAR(20)   NOT NULL DEFAULT 'pendiente'
                      CHECK (estatus_pago IN ('pendiente','pagado','fallido','reembolsado')),
  referencia_pago     VARCHAR(200),
  -- Envío
  metodo_envio_id     INT           REFERENCES metodos_envio(id) ON DELETE SET NULL,
  paqueteria          VARCHAR(80),
  numero_guia         VARCHAR(100),
  -- Notas y factura
  notas_cliente       TEXT,
  notas_internas      TEXT,
  requiere_factura    BOOLEAN       NOT NULL DEFAULT FALSE,
  rfc_factura         VARCHAR(13),
  -- Timestamps de flujo
  fecha_pago          TIMESTAMPTZ,
  fecha_envio         TIMESTAMPTZ,
  fecha_entrega       TIMESTAMPTZ,
  fecha_cancelacion   TIMESTAMPTZ,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_pedidos_numero   ON pedidos(numero);
CREATE INDEX idx_pedidos_usuario  ON pedidos(usuario_id);
CREATE INDEX idx_pedidos_estado   ON pedidos(estado);
CREATE INDEX idx_pedidos_created  ON pedidos(created_at);
SELECT fn_crear_trigger_updated_at('pedidos');

CREATE TABLE IF NOT EXISTS pedido_items (
  id              SERIAL        PRIMARY KEY,
  pedido_id       INT           NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
  producto_id     INT           NOT NULL REFERENCES productos(id),
  variante_id     INT           REFERENCES variantes_longitud(id) ON DELETE SET NULL,
  sku             VARCHAR(60)   NOT NULL,
  nombre          VARCHAR(300)  NOT NULL,
  variante_nombre VARCHAR(50),
  cantidad        INT           NOT NULL,
  precio_unitario NUMERIC(12,2) NOT NULL,
  subtotal        NUMERIC(12,2) NOT NULL
);
CREATE INDEX idx_pedido_items_pedido ON pedido_items(pedido_id);

CREATE TABLE IF NOT EXISTS pedido_historial (
  id          SERIAL        PRIMARY KEY,
  pedido_id   INT           NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
  estado      VARCHAR(50)   NOT NULL,
  nota        TEXT,
  usuario_id  INT           REFERENCES usuarios(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_ped_hist_pedido ON pedido_historial(pedido_id);


-- ================================================================
-- 10. SISTEMA
-- ================================================================

CREATE TABLE IF NOT EXISTS configuracion (
  clave       VARCHAR(100)  PRIMARY KEY,
  valor       TEXT,
  tipo        VARCHAR(20)   NOT NULL DEFAULT 'texto'
              CHECK (tipo IN ('texto','numero','booleano','json','imagen')),
  descripcion VARCHAR(300),
  seccion     VARCHAR(60),
  updated_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
SELECT fn_crear_trigger_updated_at('configuracion');

CREATE TABLE IF NOT EXISTS notificaciones (
  id          SERIAL        PRIMARY KEY,
  usuario_id  INT           NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  tipo        VARCHAR(60)   NOT NULL,
  titulo      VARCHAR(200)  NOT NULL,
  mensaje     TEXT,
  leida       BOOLEAN       NOT NULL DEFAULT FALSE,
  url         VARCHAR(500),
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_notif_usuario_leida ON notificaciones(usuario_id, leida);


CREATE TABLE IF NOT EXISTS auditoria (
  id          SERIAL        PRIMARY KEY,
  usuario_id  INT           REFERENCES usuarios(id) ON DELETE SET NULL,
  accion      VARCHAR(100)  NOT NULL,
  tabla       VARCHAR(80),
  registro_id INT,
  detalle     JSONB,
  ip          VARCHAR(45),
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_audit_tabla   ON auditoria(tabla, registro_id);
CREATE INDEX idx_audit_usuario ON auditoria(usuario_id);
CREATE INDEX idx_audit_created ON auditoria(created_at);

-- ================================================================
-- 11. CONTACTO Y RECUPERACIÓN DE CONTRASEÑA
-- ================================================================

CREATE TABLE IF NOT EXISTS mensajes_contacto (
  id          SERIAL        PRIMARY KEY,
  nombre      VARCHAR(120)  NOT NULL,
  empresa     VARCHAR(120),
  email       VARCHAR(200)  NOT NULL,
  telefono    VARCHAR(30),
  asunto      VARCHAR(60)   NOT NULL,
  mensaje     TEXT          NOT NULL,
  leido       BOOLEAN       NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS password_resets (
  id          SERIAL        PRIMARY KEY,
  usuario_id  INT           NOT NULL UNIQUE REFERENCES usuarios(id) ON DELETE CASCADE,
  token       VARCHAR(64)   NOT NULL,
  expira_at   TIMESTAMPTZ   NOT NULL,
  usado       BOOLEAN       NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);