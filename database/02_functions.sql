-- ================================================================
--  MBS COMUNICACIONES — FUNCIONES / STORED PROCEDURES PostgreSQL
--  Archivo 02 — Toda la lógica de negocio en plpgsql
--  En PostgreSQL los SP que retornan datos son FUNCTIONS.
-- ================================================================

-- ================================================================
-- ► UTILS INTERNOS
-- ================================================================

-- Genera número de pedido: MBS-YYYY-NNNNNN
CREATE OR REPLACE FUNCTION fn_generar_numero_pedido()
RETURNS VARCHAR LANGUAGE plpgsql AS $$
DECLARE
  v_anio  TEXT := TO_CHAR(NOW(), 'YYYY');
  v_max   INT;
BEGIN
  SELECT COALESCE(MAX(SPLIT_PART(numero, '-', 3)::INT), 0)
    INTO v_max FROM pedidos
   WHERE numero LIKE 'MBS-' || v_anio || '-%';
  RETURN 'MBS-' || v_anio || '-' || LPAD((v_max + 1)::TEXT, 6, '0');
END;
$$;


-- ================================================================
-- ► MÓDULO: USUARIOS
-- ================================================================

-- Registrar cliente
CREATE OR REPLACE FUNCTION fn_registrar_usuario(
  p_nombre        VARCHAR,
  p_apellidos     VARCHAR,
  p_email         VARCHAR,
  p_password_hash VARCHAR,
  p_telefono      VARCHAR,
  p_tipo          VARCHAR
)
RETURNS TABLE(
  r_usuario_id INT,
  r_mensaje VARCHAR
) LANGUAGE plpgsql AS $$
DECLARE v_id INT;
BEGIN
  IF EXISTS (SELECT 1 FROM usuarios WHERE email = p_email) THEN
    RETURN QUERY SELECT 0::INT, 'El correo electronico ya esta registrado.'::VARCHAR;
    RETURN;
  END IF;

  INSERT INTO usuarios (nombre, apellidos, email, password_hash, telefono, tipo)
  VALUES (p_nombre, p_apellidos, p_email, p_password_hash, p_telefono, p_tipo)
  RETURNING id INTO v_id;

  INSERT INTO auditoria (usuario_id, accion, tabla, registro_id)
  VALUES (v_id, 'registro_usuario', 'usuarios', v_id);

  RETURN QUERY SELECT v_id, 'OK'::VARCHAR;
END;
$$;

-- Perfil completo del cliente
CREATE OR REPLACE FUNCTION fn_obtener_perfil_cliente(p_usuario_id INT)
RETURNS TABLE(
  r_id INT,
  r_nombre VARCHAR,
  r_apellidos VARCHAR,
  r_email VARCHAR,
  r_telefono VARCHAR,
  r_rfc VARCHAR,
  r_razon_social VARCHAR,
  r_tipo VARCHAR,
  r_activo BOOLEAN,
  r_avatar_url VARCHAR,
  r_miembro_desde TIMESTAMPTZ,
  r_total_pedidos BIGINT,
  r_total_gastado NUMERIC,
  r_total_favoritos BIGINT
) LANGUAGE plpgsql AS $$
BEGIN
  RETURN QUERY
  SELECT u.id, u.nombre, u.apellidos, u.email, u.telefono,
         u.rfc, u.razon_social, u.tipo, u.activo, u.avatar_url,
         u.created_at,
         (SELECT COUNT(*) FROM pedidos WHERE usuario_id = u.id AND estado != 'cancelado'),
         (SELECT COALESCE(SUM(total),0) FROM pedidos
           WHERE usuario_id = u.id AND estatus_pago = 'pagado'),
         (SELECT COUNT(*) FROM favoritos WHERE usuario_id = u.id)
    FROM usuarios u WHERE u.id = p_usuario_id;
END;
$$;

-- Actualizar datos personales
CREATE OR REPLACE FUNCTION fn_actualizar_datos_personales(
  p_usuario_id  INT,
  p_nombre      VARCHAR,
  p_apellidos   VARCHAR,
  p_telefono    VARCHAR,
  p_rfc         VARCHAR,
  p_razon_social VARCHAR
) RETURNS VARCHAR LANGUAGE plpgsql AS $$
BEGIN
  UPDATE usuarios
     SET nombre = p_nombre, apellidos = p_apellidos,
         telefono = p_telefono, rfc = p_rfc, razon_social = p_razon_social
   WHERE id = p_usuario_id;

  INSERT INTO auditoria (usuario_id, accion, tabla, registro_id)
  VALUES (p_usuario_id, 'actualizar_perfil', 'usuarios', p_usuario_id);

  RETURN 'OK';
END;
$$;

-- Bloquear / desbloquear cliente
CREATE OR REPLACE FUNCTION fn_toggle_bloqueo_cliente(
  p_usuario_id INT, p_bloqueado BOOLEAN,
  p_motivo VARCHAR, p_admin_id INT
) RETURNS VARCHAR LANGUAGE plpgsql AS $$
BEGIN
  UPDATE usuarios SET bloqueado = p_bloqueado, motivo_bloqueo = p_motivo
   WHERE id = p_usuario_id;

  INSERT INTO auditoria (usuario_id, accion, tabla, registro_id, detalle)
  VALUES (p_admin_id,
          CASE WHEN p_bloqueado THEN 'bloquear_cliente' ELSE 'desbloquear_cliente' END,
          'usuarios', p_usuario_id,
          jsonb_build_object('motivo', p_motivo));

  RETURN 'OK';
END;
$$;

-- Listar clientes (admin)
CREATE OR REPLACE FUNCTION fn_admin_listar_clientes(
  p_busqueda  VARCHAR,
  p_tipo      VARCHAR,
  p_pagina    INT
)
RETURNS TABLE(
  r_id INT,
  r_nombre VARCHAR,
  r_apellidos VARCHAR,
  r_email VARCHAR,
  r_telefono VARCHAR,
  r_rfc VARCHAR,
  r_tipo VARCHAR,
  r_activo BOOLEAN,
  r_bloqueado BOOLEAN,
  r_created_at TIMESTAMPTZ,
  r_num_pedidos BIGINT,
  r_total_gastado NUMERIC,
  r_total_registros BIGINT
) LANGUAGE plpgsql AS $$
DECLARE
  v_limite INT := 15;
  v_offset INT := (p_pagina - 1) * v_limite;
  v_total  BIGINT;
BEGIN
  SELECT COUNT(*) INTO v_total FROM usuarios u
   WHERE u.rol = 'cliente'
     AND (p_busqueda IS NULL
          OR u.nombre    ILIKE '%' || p_busqueda || '%'
          OR u.email     ILIKE '%' || p_busqueda || '%'
          OR u.rfc       ILIKE '%' || p_busqueda || '%')
     AND (p_tipo IS NULL OR u.tipo = p_tipo);

  RETURN QUERY
  SELECT u.id, u.nombre, u.apellidos, u.email, u.telefono, u.rfc,
         u.tipo, u.activo, u.bloqueado, u.created_at,
         COUNT(DISTINCT pe.id),
         COALESCE(SUM(pe.total), 0),
         v_total
    FROM usuarios u
    LEFT JOIN pedidos pe ON pe.usuario_id = u.id AND pe.estatus_pago = 'pagado'
   WHERE u.rol = 'cliente'
     AND (p_busqueda IS NULL
          OR u.nombre ILIKE '%' || p_busqueda || '%'
          OR u.email  ILIKE '%' || p_busqueda || '%'
          OR u.rfc    ILIKE '%' || p_busqueda || '%')
     AND (p_tipo IS NULL OR u.tipo = p_tipo)
   GROUP BY u.id
   ORDER BY COALESCE(SUM(pe.total), 0) DESC, u.created_at DESC
   LIMIT v_limite OFFSET v_offset;
END;
$$;

-- ================================================================
-- ► MÓDULO: CATÁLOGO
-- ================================================================

-- Listar productos con filtros y paginación
CREATE OR REPLACE FUNCTION fn_listar_productos(
  p_categoria_id  INT[],
  p_marca_id      INT,
  p_precio_min    NUMERIC,
  p_precio_max    NUMERIC,
  p_solo_stock    BOOLEAN,
  p_busqueda      VARCHAR,
  p_orden         VARCHAR,
  p_pagina        INT,
  p_por_pagina    INT
)
RETURNS TABLE(
  r_id INT,
  r_sku VARCHAR,
  r_nombre VARCHAR,
  r_slug VARCHAR,
  r_precio_venta NUMERIC,
  r_precio_antes NUMERIC,
  r_stock_actual INT,
  r_badge VARCHAR,
  r_destacado BOOLEAN,
  r_categoria VARCHAR,
  r_marca VARCHAR,
  r_imagen_principal VARCHAR,
  r_calificacion_promedio NUMERIC,
  r_total_resenas BIGINT,
  r_total_registros BIGINT
) LANGUAGE plpgsql AS $$
DECLARE
  v_offset   INT := (p_pagina - 1) * p_por_pagina;
  v_tsquery  TSQUERY;
  v_total    BIGINT;
BEGIN
  IF p_busqueda IS NOT NULL THEN
    v_tsquery := plainto_tsquery('simple', p_busqueda);
  END IF;

  SELECT COUNT(*) INTO v_total
    FROM productos pr
   WHERE pr.estado = 'activo'
     AND (p_categoria_id IS NULL OR pr.categoria_id = ANY(p_categoria_id))
     AND (p_marca_id     IS NULL OR pr.marca_id     = p_marca_id)
     AND (p_precio_min   IS NULL OR pr.precio_venta >= p_precio_min)
     AND (p_precio_max   IS NULL OR pr.precio_venta <= p_precio_max)
     AND (NOT p_solo_stock        OR pr.stock_actual  > 0)
     AND (v_tsquery      IS NULL  OR pr.fts @@ v_tsquery);

  RETURN QUERY
  SELECT pr.id, pr.sku, pr.nombre, pr.slug,
         pr.precio_venta, pr.precio_antes,
         pr.stock_actual, pr.badge, pr.destacado,
         cat.nombre, mar.nombre,
         pim.url,
         ROUND(COALESCE(AVG(res.calificacion),0)::NUMERIC, 1),
         COUNT(DISTINCT res.id),
         v_total
    FROM productos pr
    JOIN categorias cat ON cat.id = pr.categoria_id
    LEFT JOIN marcas mar ON mar.id = pr.marca_id
    LEFT JOIN producto_imagenes pim
           ON pim.producto_id = pr.id AND pim.es_principal = TRUE
    LEFT JOIN resenas res ON res.producto_id = pr.id AND res.aprobado = TRUE
   WHERE pr.estado = 'activo'
     AND (p_categoria_id IS NULL OR pr.categoria_id = ANY(p_categoria_id))
     AND (p_marca_id     IS NULL OR pr.marca_id     = p_marca_id)
     AND (p_precio_min   IS NULL OR pr.precio_venta >= p_precio_min)
     AND (p_precio_max   IS NULL OR pr.precio_venta <= p_precio_max)
     AND (NOT p_solo_stock        OR pr.stock_actual  > 0)
     AND (v_tsquery      IS NULL  OR pr.fts @@ v_tsquery)
   GROUP BY pr.id, cat.nombre, mar.nombre, pim.url
   ORDER BY
     CASE WHEN p_orden = 'precio_asc'  THEN pr.precio_venta::TEXT END ASC  NULLS LAST,
     CASE WHEN p_orden = 'precio_desc' THEN pr.precio_venta::TEXT END DESC NULLS LAST,
     CASE WHEN p_orden = 'nombre'      THEN pr.nombre             END ASC  NULLS LAST,
     CASE WHEN p_orden = 'nuevo'       THEN pr.created_at::TEXT   END DESC NULLS LAST,
     pr.ventas_totales DESC
   LIMIT p_por_pagina OFFSET v_offset;
END;
$$;

-- Detalle completo de producto por slug
CREATE OR REPLACE FUNCTION fn_producto_datos(p_slug VARCHAR, p_usuario_id INT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_prod_id INT;
BEGIN
  SELECT id INTO v_prod_id FROM productos WHERE slug = p_slug AND estado = 'activo';
  IF v_prod_id IS NULL THEN RETURN; END IF;

  -- Actualizar visitas
  UPDATE productos SET visitas = visitas + 1 WHERE id = v_prod_id;
END;
$$;

-- Función separada por tipo de resultado — datos del producto
CREATE OR REPLACE FUNCTION fn_producto_detalle(p_slug VARCHAR)
RETURNS TABLE(
  r_id INT,
  r_sku VARCHAR,
  r_nombre VARCHAR,
  r_slug VARCHAR,
  r_descripcion_corta VARCHAR,
  r_descripcion_larga TEXT,
  r_precio_venta NUMERIC,
  r_precio_antes NUMERIC,
  r_stock_actual INT,
  r_badge VARCHAR,
  r_destacado BOOLEAN,
  r_categoria_id INT,
  r_categoria_nombre VARCHAR,
  r_marca_nombre VARCHAR,
  r_calificacion_promedio NUMERIC,
  r_total_resenas BIGINT
) LANGUAGE sql AS $$
  SELECT p.id, p.sku, p.nombre, p.slug,
         p.descripcion_corta, p.descripcion_larga,
         p.precio_venta, p.precio_antes,
         p.stock_actual, p.badge, p.destacado,
         c.id, c.nombre, m.nombre,
         ROUND(COALESCE(AVG(r.calificacion),0)::NUMERIC,1),
         COUNT(DISTINCT r.id)
    FROM productos p
    JOIN categorias c ON c.id = p.categoria_id
    LEFT JOIN marcas m ON m.id = p.marca_id
    LEFT JOIN resenas r ON r.producto_id = p.id AND r.aprobado = TRUE
   WHERE p.slug = p_slug AND p.estado = 'activo'
   GROUP BY p.id, c.id, c.nombre, m.nombre;
$$;

-- Listar reseñas aprobadas de un producto, paginadas
CREATE OR REPLACE FUNCTION fn_listar_resenas_producto(
  p_producto_id INT,
  p_pagina      INT DEFAULT 1
)
RETURNS TABLE(
  r_id              INT,
  r_usuario_nombre  VARCHAR,
  r_calificacion    SMALLINT,
  r_titulo          VARCHAR,
  r_comentario      TEXT,
  r_verificado      BOOLEAN,
  r_created_at      TIMESTAMPTZ,
  r_total_registros BIGINT
) LANGUAGE plpgsql AS $$
DECLARE
  v_limite INT := 10;
  v_offset INT := (p_pagina - 1) * v_limite;
  v_total  BIGINT;
BEGIN
  SELECT COUNT(*) INTO v_total
    FROM resenas
   WHERE producto_id = p_producto_id AND aprobado = TRUE;

  RETURN QUERY
  SELECT res.id,
         (u.nombre || ' ' || LEFT(u.apellidos, 1) || '.')::VARCHAR,
         res.calificacion,
         res.titulo,
         res.comentario,
         res.verificado,
         res.created_at,
         v_total
    FROM resenas res
    JOIN usuarios u ON u.id = res.usuario_id
   WHERE res.producto_id = p_producto_id AND res.aprobado = TRUE
   ORDER BY res.created_at DESC
   LIMIT v_limite OFFSET v_offset;
END;
$$;

-- Listado de productos para administración (incluye inactivos/borradores)
CREATE OR REPLACE FUNCTION fn_admin_listar_productos(
  p_busqueda      VARCHAR DEFAULT NULL,
  p_categoria_id  INT     DEFAULT NULL,
  p_estado        VARCHAR DEFAULT NULL,
  p_pagina        INT     DEFAULT 1,
  p_por_pagina    INT     DEFAULT 10
)
RETURNS TABLE(
  r_id INT,
  r_sku VARCHAR,
  r_nombre VARCHAR,
  r_descripcion_corta VARCHAR,
  r_descripcion_larga TEXT,
  r_categoria_id INT,
  r_categoria VARCHAR,
  r_marca_id INT,
  r_marca VARCHAR,
  r_precio_venta NUMERIC,
  r_precio_antes NUMERIC,
  r_stock_actual INT,
  r_stock_minimo INT,
  r_estado VARCHAR,
  r_badge VARCHAR,
  r_destacado BOOLEAN,
  r_total_registros BIGINT
) LANGUAGE plpgsql AS $$
DECLARE
  v_offset  INT := (p_pagina - 1) * p_por_pagina;
  v_tsquery TSQUERY;
  v_total   BIGINT;
BEGIN
  IF p_busqueda IS NOT NULL THEN
    v_tsquery := plainto_tsquery('simple', p_busqueda);
  END IF;

  SELECT COUNT(*) INTO v_total
    FROM productos p
   WHERE (p_categoria_id IS NULL OR p.categoria_id = p_categoria_id)
     AND (p_estado       IS NULL OR p.estado = p_estado)
     AND (v_tsquery      IS NULL OR p.fts @@ v_tsquery OR p.sku ILIKE '%'||p_busqueda||'%');

  RETURN QUERY
  SELECT p.id, p.sku, p.nombre, p.descripcion_corta, p.descripcion_larga,
         p.categoria_id, c.nombre, p.marca_id, m.nombre,
         p.precio_venta, p.precio_antes,
         p.stock_actual, p.stock_minimo,
         p.estado, p.badge, p.destacado,
         v_total
    FROM productos p
    JOIN categorias c ON c.id = p.categoria_id
    LEFT JOIN marcas m ON m.id = p.marca_id
   WHERE (p_categoria_id IS NULL OR p.categoria_id = p_categoria_id)
     AND (p_estado       IS NULL OR p.estado = p_estado)
     AND (v_tsquery      IS NULL OR p.fts @@ v_tsquery OR p.sku ILIKE '%'||p_busqueda||'%')
   ORDER BY p.created_at DESC
   LIMIT p_por_pagina OFFSET v_offset;
END;
$$;

-- Crear / Editar producto (admin)
CREATE OR REPLACE FUNCTION fn_guardar_producto(
  p_id                INT,
  p_sku               VARCHAR,
  p_nombre            VARCHAR,
  p_descripcion_corta VARCHAR,
  p_descripcion_larga TEXT,
  p_categoria_id      INT,
  p_marca_id          INT,
  p_precio_venta      NUMERIC,
  p_precio_antes      NUMERIC,
  p_stock_actual      INT,
  p_stock_minimo      INT,
  p_estado            VARCHAR,
  p_badge             VARCHAR,
  p_admin_id          INT
)
RETURNS TABLE(
  r_producto_id INT,
  r_mensaje VARCHAR
) LANGUAGE plpgsql AS $$
DECLARE
  v_id          INT;
  v_slug        VARCHAR;
  v_stock_antes INT := 0;
BEGIN
  v_slug := LOWER(REGEXP_REPLACE(REPLACE(p_nombre, ' ', '-'), '[^a-z0-9\-]', '', 'g'));

  IF p_id = 0 THEN
    INSERT INTO productos (sku, nombre, slug, descripcion_corta, descripcion_larga,
      categoria_id, marca_id, precio_venta, precio_antes,
      stock_actual, stock_minimo, estado, badge)
    VALUES (p_sku, p_nombre, v_slug, p_descripcion_corta, p_descripcion_larga,
      p_categoria_id, p_marca_id, p_precio_venta, p_precio_antes,
      p_stock_actual, p_stock_minimo, p_estado, p_badge)
    RETURNING id INTO v_id;

    IF p_stock_actual > 0 THEN
      INSERT INTO inventario_movimientos
        (producto_id, tipo, cantidad, stock_antes, stock_despues, motivo, usuario_id)
      VALUES (v_id, 'entrada', p_stock_actual, 0, p_stock_actual,
              'Stock inicial al crear producto', p_admin_id);
    END IF;

    INSERT INTO auditoria (usuario_id, accion, tabla, registro_id)
    VALUES (p_admin_id, 'crear_producto', 'productos', v_id);

    RETURN QUERY SELECT v_id, 'Producto creado exitosamente.'::VARCHAR;
  ELSE
    SELECT stock_actual INTO v_stock_antes FROM productos WHERE id = p_id;

    UPDATE productos
       SET sku = p_sku, nombre = p_nombre, slug = v_slug,
           descripcion_corta = p_descripcion_corta,
           descripcion_larga = p_descripcion_larga,
           categoria_id = p_categoria_id, marca_id = p_marca_id,
           precio_venta = p_precio_venta, precio_antes = p_precio_antes,
           stock_actual = p_stock_actual, stock_minimo = p_stock_minimo,
           estado = p_estado, badge = p_badge
     WHERE id = p_id;

    IF p_stock_actual != v_stock_antes THEN
      INSERT INTO inventario_movimientos
        (producto_id, tipo, cantidad, stock_antes, stock_despues, motivo, usuario_id)
      VALUES (p_id, 'ajuste', p_stock_actual - v_stock_antes,
              v_stock_antes, p_stock_actual, 'Ajuste manual desde admin', p_admin_id);
    END IF;

    INSERT INTO auditoria (usuario_id, accion, tabla, registro_id)
    VALUES (p_admin_id, 'editar_producto', 'productos', p_id);

    RETURN QUERY SELECT p_id, 'Producto actualizado exitosamente.'::VARCHAR;
  END IF;
END;
$$;

-- ================================================================
-- ► MÓDULO: CARRITO
-- ================================================================

CREATE OR REPLACE FUNCTION fn_carrito_agregar_item(
  p_usuario_id  INT,
  p_session_key VARCHAR,
  p_producto_id INT,
  p_variante_id INT,
  p_cantidad    INT
)
RETURNS TABLE(resultado_carrito_id INT, resultado_mensaje VARCHAR)
LANGUAGE plpgsql AS $$
DECLARE
  v_precio       NUMERIC;
  v_stock        INT;
  v_carrito_pk   INT;
  v_cant_actual  INT := 0;
BEGIN
  -- Validar que el producto existe y está activo
  SELECT precio_venta, stock_actual
    INTO v_precio, v_stock
    FROM productos
   WHERE id = p_producto_id AND estado = 'activo';

  IF v_precio IS NULL THEN
    RETURN QUERY SELECT 0::INT, 'Producto no disponible.'::VARCHAR;
    RETURN;
  END IF;

  -- Buscar carrito existente del usuario o sesión
  SELECT c.id INTO v_carrito_pk
    FROM carritos c
   WHERE (p_usuario_id IS NOT NULL AND c.usuario_id = p_usuario_id)
      OR (p_usuario_id IS NULL     AND c.session_key = p_session_key)
   LIMIT 1;

  -- Si no existe, crear uno nuevo
  IF v_carrito_pk IS NULL THEN
    INSERT INTO carritos (usuario_id, session_key)
    VALUES (p_usuario_id, p_session_key)
    RETURNING id INTO v_carrito_pk;
  END IF;

  -- Ver cuánto hay ya en el carrito de ese producto/variante
  SELECT COALESCE(ci.cantidad, 0)
    INTO v_cant_actual
    FROM carrito_items ci
   WHERE ci.carrito_id = v_carrito_pk
     AND ci.producto_id = p_producto_id
     AND (ci.variante_id = p_variante_id
          OR (ci.variante_id IS NULL AND p_variante_id IS NULL));

  -- Validar stock suficiente
  IF (v_cant_actual + p_cantidad) > v_stock THEN
    RETURN QUERY SELECT 0::INT,
      ('Stock insuficiente. Disponible: ' || v_stock || ' uds.')::VARCHAR;
    RETURN;
  END IF;

  -- Insertar o sumar cantidad si ya existe
  INSERT INTO carrito_items
    (carrito_id, producto_id, variante_id, cantidad, precio_unitario)
  VALUES
    (v_carrito_pk, p_producto_id, p_variante_id, p_cantidad, v_precio)
  ON CONFLICT (carrito_id, producto_id, variante_id)
  DO UPDATE SET
    cantidad        = carrito_items.cantidad + p_cantidad,
    precio_unitario = v_precio;

  RETURN QUERY SELECT v_carrito_pk, 'OK'::VARCHAR;
END;
$$;

-- Obtener carrito con totales
CREATE OR REPLACE FUNCTION fn_carrito_obtener(
  p_usuario_id  INT,
  p_session_key VARCHAR
)
RETURNS TABLE(
  r_item_id        INT,
  r_cantidad       INT,
  r_precio_unit    NUMERIC,
  r_subtotal       NUMERIC,
  r_producto_id    INT,
  r_nombre         VARCHAR,
  r_sku            VARCHAR,
  r_stock_actual   INT,
  r_badge          VARCHAR,
  r_variante       VARCHAR,
  r_imagen         VARCHAR
) LANGUAGE plpgsql AS $$
DECLARE v_carrito_pk INT;
BEGIN
  SELECT c.id INTO v_carrito_pk
    FROM carritos c
   WHERE (p_usuario_id IS NOT NULL AND c.usuario_id = p_usuario_id)
      OR (p_usuario_id IS NULL     AND c.session_key = p_session_key)
   LIMIT 1;

  RETURN QUERY
  SELECT ci.id,
         ci.cantidad,
         ci.precio_unitario,
         ci.cantidad * ci.precio_unitario,
         prod.id,
         prod.nombre,
         prod.sku,
         prod.stock_actual,
         prod.badge,
         vl.etiqueta,
         pimg.url
    FROM carrito_items ci
    JOIN productos prod ON prod.id = ci.producto_id
    LEFT JOIN variantes_longitud vl   ON vl.id = ci.variante_id
    LEFT JOIN producto_imagenes pimg  ON pimg.producto_id = prod.id
                                     AND pimg.es_principal = TRUE
   WHERE ci.carrito_id = v_carrito_pk;
END;
$$;


-- ================================================================
-- ► MÓDULO: PEDIDOS
-- ================================================================

CREATE OR REPLACE FUNCTION fn_crear_pedido(
  p_usuario_id       INT,
  p_carrito_id       INT,
  p_direccion_id     INT,
  p_metodo_envio_id  INT,
  p_metodo_pago_id   INT,
  p_notas_cliente    TEXT,
  p_requiere_factura BOOLEAN
)
RETURNS TABLE(
  r_pedido_id INT,
  r_numero_pedido VARCHAR,
  r_mensaje VARCHAR
)
LANGUAGE plpgsql AS $$
DECLARE
  v_subtotal      NUMERIC := 0;
  v_envio         NUMERIC := 0;
  v_monto_gratis  NUMERIC;
  v_iva           NUMERIC;
  v_total         NUMERIC;
  v_numero        VARCHAR;
  v_pedido_id     INT;
  v_dir           RECORD;
  v_item          RECORD;
  v_stock_actual  INT;
BEGIN
  -- Validar carrito no vacío
  IF (SELECT COUNT(*) FROM carrito_items WHERE carrito_id = p_carrito_id) = 0 THEN
    RETURN QUERY SELECT 0, ''::VARCHAR, 'El carrito esta vacio.'::VARCHAR; RETURN;
  END IF;

  -- Costo de envío y monto gratis
  SELECT precio, monto_gratis INTO v_envio, v_monto_gratis
    FROM metodos_envio WHERE id = p_metodo_envio_id;

  -- Subtotal del carrito
  SELECT COALESCE(SUM(cantidad * precio_unitario), 0) INTO v_subtotal
    FROM carrito_items WHERE carrito_id = p_carrito_id;

  -- Envío gratuito por monto
  IF v_monto_gratis IS NOT NULL AND v_subtotal >= v_monto_gratis THEN
    v_envio := 0;
  END IF;

  v_iva   := ROUND((v_subtotal + v_envio) * 0.16, 2);
  v_total := v_subtotal + v_envio + v_iva;

  -- Número de pedido
  v_numero := fn_generar_numero_pedido();

  -- Snapshot de dirección
  SELECT * INTO v_dir FROM direcciones WHERE id = p_direccion_id;

  -- Validar stock ítem por ítem ANTES de insertar
  FOR v_item IN
    SELECT ci.producto_id, ci.cantidad, p.nombre
      FROM carrito_items ci JOIN productos p ON p.id = ci.producto_id
     WHERE ci.carrito_id = p_carrito_id
  LOOP
    SELECT stock_actual INTO v_stock_actual
      FROM productos WHERE id = v_item.producto_id;

    IF v_stock_actual < v_item.cantidad THEN
      RETURN QUERY SELECT 0, ''::VARCHAR,
        ('Stock insuficiente: ' || v_item.nombre)::VARCHAR;
      RETURN;
    END IF;
  END LOOP;

  -- Insertar pedido
  INSERT INTO pedidos (
    numero, usuario_id,
    dir_nombre, dir_apellidos, dir_calle, dir_colonia,
    dir_ciudad, dir_estado_geo, dir_cp, dir_telefono,
    subtotal, costo_envio, iva, total,
    metodo_pago_id, metodo_envio_id,
    notas_cliente, requiere_factura
  ) VALUES (
    v_numero, p_usuario_id,
    v_dir.nombre, v_dir.apellidos, v_dir.calle_numero, v_dir.colonia,
    v_dir.ciudad, v_dir.estado, v_dir.cp, v_dir.telefono,
    v_subtotal, v_envio, v_iva, v_total,
    p_metodo_pago_id, p_metodo_envio_id,
    p_notas_cliente, p_requiere_factura
  ) RETURNING id INTO v_pedido_id;

  -- Copiar ítems y descontar stock
  FOR v_item IN
    SELECT ci.producto_id, ci.variante_id, ci.cantidad, ci.precio_unitario,
           p.nombre, p.sku, vl.etiqueta AS variante_nombre,
           p.stock_actual AS stock_antes
      FROM carrito_items ci
      JOIN productos p ON p.id = ci.producto_id
      LEFT JOIN variantes_longitud vl ON vl.id = ci.variante_id
     WHERE ci.carrito_id = p_carrito_id
  LOOP
    INSERT INTO pedido_items
      (pedido_id, producto_id, variante_id, sku, nombre,
       variante_nombre, cantidad, precio_unitario, subtotal)
    VALUES (v_pedido_id, v_item.producto_id, v_item.variante_id,
            v_item.sku, v_item.nombre, v_item.variante_nombre,
            v_item.cantidad, v_item.precio_unitario,
            v_item.precio_unitario * v_item.cantidad);

    UPDATE productos
       SET stock_actual    = stock_actual - v_item.cantidad,
           ventas_totales  = ventas_totales + v_item.cantidad
     WHERE id = v_item.producto_id;

    INSERT INTO inventario_movimientos
      (producto_id, tipo, cantidad, stock_antes, stock_despues,
       motivo, referencia, usuario_id)
    VALUES (v_item.producto_id, 'salida', v_item.cantidad,
            v_item.stock_antes, v_item.stock_antes - v_item.cantidad,
            'Venta confirmada', v_numero, p_usuario_id);
  END LOOP;

  -- Historial del pedido
  INSERT INTO pedido_historial (pedido_id, estado, nota, usuario_id)
  VALUES (v_pedido_id, 'nuevo', 'Pedido creado', p_usuario_id);


  -- Limpiar carrito
  DELETE FROM carrito_items WHERE carrito_id = p_carrito_id;
  DELETE FROM carritos        WHERE id = p_carrito_id;

  -- Notificación al cliente
  INSERT INTO notificaciones (usuario_id, tipo, titulo, mensaje, url)
  VALUES (p_usuario_id, 'pedido_confirmado',
          'Pedido ' || v_numero || ' confirmado',
          'Tu pedido por $' || v_total || ' MXN fue recibido.',
          '/mi-cuenta/pedidos/' || v_numero);

  RETURN QUERY SELECT v_pedido_id, v_numero, 'OK'::VARCHAR;
END;
$$;

-- Actualizar estado de pedido (admin)
CREATE OR REPLACE FUNCTION fn_actualizar_estado_pedido(
  p_pedido_id  INT,
  p_estado     VARCHAR,
  p_paqueteria VARCHAR,
  p_guia       VARCHAR,
  p_notas      TEXT,
  p_admin_id   INT
) RETURNS VARCHAR LANGUAGE plpgsql AS $$
DECLARE
  v_usuario_id INT;
  v_numero     VARCHAR;
BEGIN
  SELECT usuario_id, numero INTO v_usuario_id, v_numero
    FROM pedidos WHERE id = p_pedido_id;

  UPDATE pedidos
     SET estado           = p_estado,
         paqueteria       = COALESCE(p_paqueteria, paqueteria),
         numero_guia      = COALESCE(p_guia, numero_guia),
         notas_internas   = COALESCE(p_notas, notas_internas),
         fecha_envio      = CASE WHEN p_estado = 'enviado'    THEN NOW() ELSE fecha_envio     END,
         fecha_entrega    = CASE WHEN p_estado = 'entregado'  THEN NOW() ELSE fecha_entrega   END,
         fecha_cancelacion= CASE WHEN p_estado = 'cancelado'  THEN NOW() ELSE fecha_cancelacion END
   WHERE id = p_pedido_id;

  INSERT INTO pedido_historial (pedido_id, estado, nota, usuario_id)
  VALUES (p_pedido_id, p_estado, p_notas, p_admin_id);

  INSERT INTO notificaciones (usuario_id, tipo, titulo, url)
  VALUES (v_usuario_id,
          'pedido_' || p_estado,
          'Tu pedido ' || v_numero || ' cambio a: ' || UPPER(REPLACE(p_estado,'_',' ')),
          '/mi-cuenta/pedidos/' || v_numero);

  INSERT INTO auditoria (usuario_id, accion, tabla, registro_id, detalle)
  VALUES (p_admin_id, 'actualizar_estado_pedido', 'pedidos', p_pedido_id,
          jsonb_build_object('estado', p_estado, 'guia', p_guia));

  RETURN 'OK';
END;
$$;

-- Listar pedidos del cliente
CREATE OR REPLACE FUNCTION fn_listar_pedidos_cliente(
  p_usuario_id INT,
  p_estado     VARCHAR,
  p_pagina     INT
)
RETURNS TABLE(
  r_id INT,
  r_numero VARCHAR,
  r_estado VARCHAR,
  r_total NUMERIC,
  r_estatus_pago VARCHAR,
  r_created_at TIMESTAMPTZ,
  r_paqueteria VARCHAR,
  r_numero_guia VARCHAR,
  r_total_registros BIGINT
) LANGUAGE plpgsql AS $$
DECLARE
  v_limite INT := 10;
  v_offset INT := (p_pagina - 1) * v_limite;
  v_total  BIGINT;
BEGIN
  SELECT COUNT(*) INTO v_total FROM pedidos
   WHERE usuario_id = p_usuario_id
     AND (p_estado IS NULL OR estado = p_estado);

  RETURN QUERY
  SELECT ped.id, ped.numero, ped.estado, ped.total, ped.estatus_pago, ped.created_at,
         ped.paqueteria, ped.numero_guia, v_total
    FROM pedidos ped
   WHERE ped.usuario_id = p_usuario_id
     AND (p_estado IS NULL OR ped.estado = p_estado)
   ORDER BY ped.created_at DESC
   LIMIT v_limite OFFSET v_offset;
END;
$$;

-- Detalle completo de un pedido
DROP FUNCTION IF EXISTS fn_detalle_pedido(INT, INT);
CREATE FUNCTION fn_detalle_pedido(p_pedido_id INT, p_usuario_id INT DEFAULT NULL)
RETURNS TABLE(
  r_pedido_numero VARCHAR,
  r_estado VARCHAR,
  r_subtotal NUMERIC,
  r_costo_envio NUMERIC,
  r_iva NUMERIC,
  r_total NUMERIC,
  r_metodo_envio_nombre VARCHAR,
  r_metodo_pago_nombre VARCHAR,
  r_dir_nombre VARCHAR,
  r_dir_apellidos VARCHAR,
  r_dir_calle VARCHAR,
  r_dir_colonia VARCHAR,
  r_dir_ciudad VARCHAR,
  r_dir_estado_geo VARCHAR,
  r_item_producto_id INT,
  r_item_nombre VARCHAR,
  r_item_sku VARCHAR,
  r_item_cantidad INT,
  r_item_subtotal NUMERIC,
  r_hist_estado VARCHAR,
  r_hist_nota TEXT,
  r_hist_fecha TIMESTAMPTZ
) LANGUAGE sql AS $$
  SELECT p.numero, p.estado, p.subtotal, p.costo_envio, p.iva, p.total,
         me.nombre, mp.nombre,
         p.dir_nombre, p.dir_apellidos, p.dir_calle, p.dir_colonia, p.dir_ciudad, p.dir_estado_geo,
         pi.producto_id, pi.nombre, pi.sku, pi.cantidad, pi.subtotal,
         ph.estado, ph.nota, ph.created_at
    FROM pedidos p
    JOIN metodos_envio me ON me.id = p.metodo_envio_id
    JOIN metodos_pago  mp ON mp.id = p.metodo_pago_id
    JOIN pedido_items  pi ON pi.pedido_id = p.id
    JOIN pedido_historial ph ON ph.pedido_id = p.id
   WHERE p.id = p_pedido_id
     AND (p_usuario_id IS NULL OR p.usuario_id = p_usuario_id)
   ORDER BY ph.created_at;
$$;

-- ================================================================
-- ► MÓDULO: COTIZACIONES
-- ================================================================


-- ================================================================
-- ► MÓDULO: INVENTARIO
-- ================================================================

CREATE OR REPLACE FUNCTION fn_ajustar_stock(
  p_producto_id INT, p_nuevo_stock INT,
  p_motivo VARCHAR, p_admin_id INT
) RETURNS VARCHAR LANGUAGE plpgsql AS $$
DECLARE v_antes INT;
BEGIN
  SELECT stock_actual INTO v_antes FROM productos WHERE id = p_producto_id;
  IF v_antes IS NULL THEN RETURN 'Producto no encontrado.'; END IF;

  UPDATE productos SET stock_actual = p_nuevo_stock WHERE id = p_producto_id;

  INSERT INTO inventario_movimientos
    (producto_id, tipo, cantidad, stock_antes, stock_despues, motivo, usuario_id)
  VALUES (p_producto_id, 'ajuste', p_nuevo_stock - v_antes,
          v_antes, p_nuevo_stock, p_motivo, p_admin_id);

  INSERT INTO auditoria (usuario_id, accion, tabla, registro_id, detalle)
  VALUES (p_admin_id, 'ajustar_stock', 'productos', p_producto_id,
          jsonb_build_object('antes', v_antes, 'despues', p_nuevo_stock, 'motivo', p_motivo));

  RETURN 'OK';
END;
$$;

CREATE OR REPLACE FUNCTION fn_alertas_inventario()
RETURNS TABLE(
  r_id INT,
  r_sku VARCHAR,
  r_nombre VARCHAR,
  r_stock_actual INT,
  r_stock_minimo INT,
  r_categoria VARCHAR,
  r_nivel_alerta VARCHAR
) LANGUAGE sql AS $$
  SELECT p.id, p.sku, p.nombre, p.stock_actual, p.stock_minimo,
         c.nombre,
         CASE
           WHEN p.stock_actual = 0                   THEN 'sin_stock'
           WHEN p.stock_actual <= p.stock_minimo / 2 THEN 'critico'
           ELSE 'bajo'
         END
    FROM productos p
    JOIN categorias c ON c.id = p.categoria_id
   WHERE p.estado = 'activo' AND p.stock_actual <= p.stock_minimo
   ORDER BY p.stock_actual ASC;
$$;

-- ================================================================
-- ► MÓDULO: DASHBOARD
-- ================================================================

CREATE OR REPLACE FUNCTION fn_dashboard_resumen()
RETURNS TABLE(
  pedidos_hoy BIGINT, pedidos_sin_atender BIGINT,
  clientes_activos BIGINT, clientes_nuevos_mes BIGINT,
  productos_activos BIGINT, productos_stock_bajo BIGINT,
  ventas_hoy NUMERIC
) LANGUAGE sql AS $$
  SELECT
    (SELECT COUNT(*) FROM pedidos WHERE created_at::DATE = CURRENT_DATE),
    (SELECT COUNT(*) FROM pedidos WHERE estado = 'nuevo'),
    (SELECT COUNT(*) FROM usuarios WHERE rol = 'cliente' AND activo = TRUE),
    (SELECT COUNT(*) FROM usuarios WHERE rol = 'cliente'
       AND DATE_TRUNC('month', created_at) = DATE_TRUNC('month', NOW())),
    (SELECT COUNT(*) FROM productos WHERE estado = 'activo'),
    (SELECT COUNT(*) FROM productos WHERE estado = 'activo'
       AND stock_actual <= stock_minimo),
    (SELECT COALESCE(SUM(total),0) FROM pedidos
      WHERE created_at::DATE = CURRENT_DATE AND estatus_pago = 'pagado');
$$;

CREATE OR REPLACE FUNCTION fn_ventas_semana()
RETURNS TABLE(
  dia DATE, dia_nombre TEXT,
  num_pedidos BIGINT, total_ventas NUMERIC
) LANGUAGE sql AS $$
  SELECT created_at::DATE,
         TO_CHAR(created_at::DATE, 'Day'),
         COUNT(*),
         COALESCE(SUM(total), 0)
    FROM pedidos
   WHERE created_at >= CURRENT_DATE - INTERVAL '6 days'
     AND estatus_pago = 'pagado'
   GROUP BY created_at::DATE
   ORDER BY created_at::DATE;
$$;

-- ================================================================
-- ► MÓDULO: BLOG / CMS
-- ================================================================


-- ================================================================
-- ► MÓDULO: CONFIGURACIÓN
-- ================================================================

CREATE OR REPLACE FUNCTION fn_obtener_configuracion(p_seccion VARCHAR DEFAULT NULL)
RETURNS TABLE(
  r_clave VARCHAR,
  r_valor TEXT,
  r_tipo VARCHAR
) LANGUAGE sql AS $$
  SELECT clave, valor, tipo FROM configuracion
   WHERE (p_seccion IS NULL OR seccion = p_seccion);
$$;

CREATE OR REPLACE FUNCTION fn_guardar_configuracion(
  p_clave VARCHAR, p_valor TEXT, p_admin_id INT
) RETURNS VARCHAR LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO configuracion (clave, valor)
  VALUES (p_clave, p_valor)
  ON CONFLICT (clave) DO UPDATE SET valor = p_valor;

  INSERT INTO auditoria (usuario_id, accion, detalle)
  VALUES (p_admin_id, 'cambiar_configuracion',
          jsonb_build_object('clave', p_clave, 'valor', p_valor));

  RETURN 'OK';
END;
$$;

-- ================================================================
-- ► MÓDULO: FAVORITOS
-- ================================================================

CREATE OR REPLACE FUNCTION fn_toggle_favorito(p_usuario_id INT, p_producto_id INT)
RETURNS VARCHAR LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM favoritos
              WHERE usuario_id = p_usuario_id AND producto_id = p_producto_id) THEN
    DELETE FROM favoritos WHERE usuario_id = p_usuario_id AND producto_id = p_producto_id;
    RETURN 'eliminado';
  ELSE
    INSERT INTO favoritos (usuario_id, producto_id) VALUES (p_usuario_id, p_producto_id);
    RETURN 'agregado';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_listar_favoritos(p_usuario_id INT)
RETURNS TABLE(
  r_id INT,
  r_sku VARCHAR,
  r_nombre VARCHAR,
  r_slug VARCHAR,
  r_precio_venta NUMERIC,
  r_badge VARCHAR,
  r_stock_actual INT,
  r_imagen VARCHAR,
  r_agregado_en TIMESTAMPTZ
) LANGUAGE sql AS $$
  SELECT p.id, p.sku, p.nombre, p.slug,
         p.precio_venta, p.badge, p.stock_actual,
         pi.url, f.created_at
    FROM favoritos f
    JOIN productos p ON p.id = f.producto_id
    LEFT JOIN producto_imagenes pi
           ON pi.producto_id = p.id AND pi.es_principal = TRUE
   WHERE f.usuario_id = p_usuario_id
   ORDER BY f.created_at DESC;
$$;