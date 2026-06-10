-- ================================================================
--  MBS COMUNICACIONES — EJEMPLOS DE USO (PostgreSQL)
--  Archivo 04 — En PG las funciones se llaman con SELECT
-- ================================================================

-- ── USUARIOS ─────────────────────────────────────────────────

-- Registrar nuevo cliente
SELECT * FROM fn_registrar_usuario(
  'Laura', 'Gonzalez', 'laura@empresa.mx',
  '$2b$12$hash...', '+52 (442) 111-2222', 'empresa'
);

-- Perfil completo
SELECT * FROM fn_obtener_perfil_cliente(2);

-- Actualizar datos personales
SELECT fn_actualizar_datos_personales(2,'Carlos','Mendez R.',
  '+52 (442) 000-0000','MERJ870420TY3','TelCo SA de CV');

-- Bloquear cliente
SELECT fn_toggle_bloqueo_cliente(2, TRUE, 'Pedidos sospechosos', 1);

-- Listar clientes (admin) — búsqueda + paginación
SELECT * FROM fn_admin_listar_clientes('TelCo', NULL, 1);

-- ── CATÁLOGO ─────────────────────────────────────────────────

-- Buscar productos con filtros
SELECT * FROM fn_listar_productos(
  1,         -- categoria_id (Cables de fibra)
  NULL,      -- marca_id
  0,         -- precio_min
  5000,      -- precio_max
  TRUE,      -- solo_stock
  'SC',      -- busqueda full-text
  'precio_asc',
  1,         -- pagina
  9          -- por pagina
);

-- Detalle de producto por slug
SELECT * FROM fn_producto_detalle('cable-fo-monomodo-sc-upc-3mm');

-- Imágenes del producto
SELECT * FROM producto_imagenes
 WHERE producto_id = (SELECT id FROM productos WHERE slug='cable-fo-monomodo-sc-upc-3mm');

-- Especificaciones
SELECT * FROM producto_especificaciones
 WHERE producto_id = (SELECT id FROM productos WHERE slug='cable-fo-monomodo-sc-upc-3mm')
 ORDER BY orden;

-- Crear producto nuevo
SELECT * FROM fn_guardar_producto(
  0,'FO-SM-LC-001','Cable FO SM LC/UPC 2mm Drop',
  'Cable drop LC monomodo','<p>Descripcion larga...</p>',
  1,1, 299.00, 380.00, 50, 10,'activo','nuevo', 1
);

-- ── CARRITO ──────────────────────────────────────────────────

-- Agregar ítem (usuario logueado)
SELECT * FROM fn_carrito_agregar_item(2, NULL, 1, 3, 2);
-- usuario_id=2, session=NULL, producto=1, variante=3(3m), cantidad=2

-- Agregar ítem (sesión anónima)
SELECT * FROM fn_carrito_agregar_item(NULL, 'sess_abc123', 2, NULL, 5);

-- Ver carrito
SELECT * FROM fn_carrito_obtener(2, NULL);

-- Aplicar cupón MBS10 — devuelve descuento y mensaje
SELECT * FROM fn_carrito_aplicar_cupon(1, 2, 'MBS10');

-- ── PEDIDOS ──────────────────────────────────────────────────

-- Crear pedido completo
SELECT * FROM fn_crear_pedido(
  2,   -- usuario_id
  1,   -- carrito_id
  1,   -- direccion_id
  1,   -- metodo_envio_id (FedEx Express)
  1,   -- metodo_pago_id (Tarjeta)
  'Entregar en recepcion. Llamar antes.',
  TRUE -- requiere_factura
);

-- Detalle del pedido (cliente)
SELECT * FROM fn_detalle_pedido(1, 2);

-- Listar pedidos con filtro de estado
SELECT * FROM fn_listar_pedidos_cliente(2, 'en_preparacion', 1);

-- Actualizar estado — admin marca como enviado con guía
SELECT fn_actualizar_estado_pedido(
  1, 'enviado', 'FedEx Express', '7489201934',
  'Paquete despachado el 15 Mayo.', 1
);

-- ── INVENTARIO ────────────────────────────────────────────────

-- Ver alertas de stock
SELECT * FROM fn_alertas_inventario();

-- Ajustar stock manualmente
SELECT fn_ajustar_stock(2, 50, 'Recepcion mercancia Corning Mayo 2025', 1);

-- Historial de movimientos de un producto
SELECT * FROM inventario_movimientos WHERE producto_id = 2 ORDER BY created_at DESC;


-- ── DASHBOARD ────────────────────────────────────────────────

-- KPIs en una sola fila
SELECT * FROM fn_dashboard_resumen();

-- Gráfica ventas últimos 7 días
SELECT * FROM fn_ventas_semana();

-- Listar artículos publicados
SELECT id, titulo, estado, visitas, publicado_en
  FROM blog_articulos
 WHERE estado = 'publicado'
 ORDER BY publicado_en DESC;

-- ── FAVORITOS ────────────────────────────────────────────────

-- Toggle favorito (agrega si no existe, elimina si existe)
SELECT fn_toggle_favorito(2, 1);

-- Ver favoritos del usuario
SELECT * FROM fn_listar_favoritos(2);

-- ── CONFIGURACIÓN ────────────────────────────────────────────

-- Leer toda la config de una sección
SELECT * FROM fn_obtener_configuracion('general');

-- Guardar un valor
SELECT fn_guardar_configuracion('site_telefono', '+52 (442) 345-5929', 1);

-- ── CONSULTAS ADMIN ÚTILES ───────────────────────────────────

-- Top 5 productos más vendidos
SELECT sku, nombre, ventas_totales, precio_venta,
       ventas_totales * precio_venta AS revenue_estimado
  FROM productos ORDER BY ventas_totales DESC LIMIT 5;

-- Pedidos del día con totales
SELECT numero, estado, total, estatus_pago, created_at
  FROM pedidos WHERE created_at::DATE = CURRENT_DATE
 ORDER BY created_at DESC;

-- Clientes con mayor gasto total
SELECT u.nombre, u.apellidos, u.email, u.tipo,
       COUNT(p.id) AS pedidos,
       SUM(p.total) AS total_gastado
  FROM usuarios u
  JOIN pedidos p ON p.usuario_id = u.id AND p.estatus_pago = 'pagado'
 WHERE u.rol = 'cliente'
 GROUP BY u.id
 ORDER BY total_gastado DESC LIMIT 10;



