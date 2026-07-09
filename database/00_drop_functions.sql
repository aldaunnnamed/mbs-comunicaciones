-- ================================================================
--  MBS COMUNICACIONES — DROP FUNCTIONS
--  Ejecutar ANTES de 02_functions.sql cuando ya existen funciones
--  con firmas anteriores en la base de datos
-- ================================================================

DROP FUNCTION IF EXISTS fn_generar_numero_pedido() CASCADE;

-- NOTA: fn_set_updated_at(), fn_crear_trigger_updated_at() y fn_productos_fts()
-- se definen en 01_schema.sql (no en 02_functions.sql). NO incluirlas aquí:
-- el DROP en CASCADE elimina los triggers updated_at de 8 tablas y el trigger
-- de búsqueda full-text de "productos", y este script solo va seguido de
-- 02_functions.sql, que no los vuelve a crear.

DROP FUNCTION IF EXISTS fn_registrar_usuario(VARCHAR,VARCHAR,VARCHAR,VARCHAR,VARCHAR,VARCHAR) CASCADE;
DROP FUNCTION IF EXISTS fn_obtener_perfil_cliente(INT) CASCADE;
DROP FUNCTION IF EXISTS fn_actualizar_datos_personales(INT,VARCHAR,VARCHAR,VARCHAR,VARCHAR,VARCHAR) CASCADE;
DROP FUNCTION IF EXISTS fn_toggle_bloqueo_cliente(INT,BOOLEAN,VARCHAR,INT) CASCADE;

DROP FUNCTION IF EXISTS fn_listar_productos(INT,INT,NUMERIC,NUMERIC,BOOLEAN,VARCHAR,VARCHAR,INT,INT) CASCADE;
DROP FUNCTION IF EXISTS fn_listar_productos(INT[],INT,NUMERIC,NUMERIC,BOOLEAN,VARCHAR,VARCHAR,INT,INT) CASCADE;
DROP FUNCTION IF EXISTS fn_producto_detalle(VARCHAR) CASCADE;

DROP FUNCTION IF EXISTS fn_carrito_agregar_item(INT,VARCHAR,INT,INT,INT) CASCADE;
DROP FUNCTION IF EXISTS fn_carrito_obtener(INT,VARCHAR) CASCADE;

DROP FUNCTION IF EXISTS fn_crear_pedido(INT,INT,INT,INT,INT,TEXT,BOOLEAN) CASCADE;
DROP FUNCTION IF EXISTS fn_actualizar_estado_pedido(INT,VARCHAR,VARCHAR,VARCHAR,TEXT,INT) CASCADE;
DROP FUNCTION IF EXISTS fn_listar_pedidos_cliente(INT,VARCHAR,INT) CASCADE;
DROP FUNCTION IF EXISTS fn_detalle_pedido(INT,INT) CASCADE;

DROP FUNCTION IF EXISTS fn_ajustar_stock(INT,INT,VARCHAR,INT) CASCADE;
DROP FUNCTION IF EXISTS fn_alertas_inventario() CASCADE;

DROP FUNCTION IF EXISTS fn_dashboard_resumen() CASCADE;
DROP FUNCTION IF EXISTS fn_ventas_semana() CASCADE;

DROP FUNCTION IF EXISTS fn_obtener_configuracion(VARCHAR) CASCADE;
DROP FUNCTION IF EXISTS fn_guardar_configuracion(VARCHAR,TEXT,INT) CASCADE;

DROP FUNCTION IF EXISTS fn_toggle_favorito(INT,INT) CASCADE;
DROP FUNCTION IF EXISTS fn_listar_favoritos(INT) CASCADE;

-- NOTA: las funciones de 05_pagos.sql (fn_crear_referencia_spei,
-- fn_confirmar_pago_spei, fn_crear_orden_paypal, fn_confirmar_pago_paypal,
-- fn_vencer_referencias_spei, fn_estado_pago_pedido, fn_pago_*_updated_at)
-- NO se incluyen aquí por la misma razón: este script solo va seguido de
-- 02_functions.sql, que no las recrearía. Si necesitas reiniciarlas, vuelve
-- a ejecutar 05_pagos.sql directamente (usa CREATE OR REPLACE).

SELECT 'Todas las funciones eliminadas correctamente' AS resultado;
