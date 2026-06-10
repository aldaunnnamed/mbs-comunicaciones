-- ================================================================
--  MBS — VERIFICAR FIRMAS REALES DE FUNCIONES EN LA BD
--  Ejecuta esto en pgAdmin para ver qué firmas tiene tu BD
-- ================================================================

SELECT
  p.proname AS funcion,
  pg_get_function_arguments(p.oid) AS argumentos
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'fn_carrito_obtener',
    'fn_listar_productos',
    'fn_carrito_agregar_item',
    'fn_obtener_perfil_cliente',
    'fn_listar_pedidos_cliente',
    'fn_detalle_pedido',
    'fn_producto_detalle',
    'fn_registrar_usuario',
    'fn_actualizar_datos_personales',
    'fn_listar_favoritos',
    'fn_toggle_favorito',
    'fn_guardar_producto',
    'fn_ajustar_stock',
    'fn_alertas_inventario',
    'fn_dashboard_resumen',
    'fn_ventas_semana',
    'fn_admin_listar_clientes',
    'fn_toggle_bloqueo_cliente',
    'fn_actualizar_estado_pedido',
    'fn_crear_pedido'
  )
ORDER BY p.proname;
