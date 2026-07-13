-- Fix fn_carrito_obtener: cuando el usuario está logueado, también busca
-- el carrito de sesión anónima (por si agregó productos sin iniciar sesión)
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
  -- Prioridad: carrito del usuario. Si no existe, carrito de sesión anónima.
  SELECT c.id INTO v_carrito_pk
    FROM carritos c
   WHERE (p_usuario_id IS NOT NULL AND c.usuario_id = p_usuario_id)
      OR (p_session_key IS NOT NULL AND c.session_key = p_session_key
          AND c.usuario_id IS NULL)
   ORDER BY CASE WHEN p_usuario_id IS NOT NULL AND c.usuario_id = p_usuario_id THEN 0 ELSE 1 END
   LIMIT 1;

  RETURN QUERY
  SELECT ci.id,
         ci.cantidad,
         ci.precio_unitario,
         ci.cantidad * ci.precio_unitario,
         prod.id,
         prod.nombre,
         prod.sku,
         -- El stock disponible real es el de la variante (si el ítem tiene una),
         -- no el del producto padre — igual que en fn_carrito_agregar_item y
         -- en el controlador actualizarCantidad. Antes siempre se devolvía
         -- prod.stock_actual, mostrando un límite incorrecto en el carrito
         -- para productos con variantes de longitud.
         COALESCE(vl.stock, prod.stock_actual),
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

-- Función para fusionar carrito anónimo al carrito del usuario al hacer login
CREATE OR REPLACE FUNCTION fn_carrito_fusionar(
  p_usuario_id  INT,
  p_session_key VARCHAR
) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
  v_carrito_sesion INT;
  v_carrito_usuario INT;
BEGIN
  -- Buscar carrito de sesión anónima
  SELECT id INTO v_carrito_sesion FROM carritos
   WHERE session_key = p_session_key AND usuario_id IS NULL LIMIT 1;

  IF v_carrito_sesion IS NULL THEN RETURN; END IF;

  -- Buscar o crear carrito del usuario
  SELECT id INTO v_carrito_usuario FROM carritos
   WHERE usuario_id = p_usuario_id LIMIT 1;

  IF v_carrito_usuario IS NULL THEN
    -- Reasignar el carrito de sesión al usuario
    UPDATE carritos SET usuario_id = p_usuario_id, session_key = NULL
     WHERE id = v_carrito_sesion;
    RETURN;
  END IF;

  -- Fusionar items: mover items del carrito de sesión al del usuario
  -- Si ya existe el mismo producto, sumar cantidades
  INSERT INTO carrito_items (carrito_id, producto_id, variante_id, cantidad, precio_unitario)
  SELECT v_carrito_usuario, ci.producto_id, ci.variante_id,
         ci.cantidad, ci.precio_unitario
    FROM carrito_items ci
   WHERE ci.carrito_id = v_carrito_sesion
  ON CONFLICT (carrito_id, producto_id, variante_id) DO UPDATE
     SET cantidad = carrito_items.cantidad + EXCLUDED.cantidad;

  -- Eliminar carrito de sesión
  DELETE FROM carrito_items WHERE carrito_id = v_carrito_sesion;
  DELETE FROM carritos WHERE id = v_carrito_sesion;
END;
$$;
