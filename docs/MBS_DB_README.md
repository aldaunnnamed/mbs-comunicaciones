# MBS Comunicaciones — Base de Datos PostgreSQL

## Archivos del proyecto

```
database/
├── 00_drop_functions.sql        → Elimina funciones previas (opcional, antes de 02)
├── 01_schema.sql                → Tablas, índices, triggers (incluye lo que antes eran 06_imagenes.sql y 07_contacto.sql)
├── 02_functions.sql             → Funciones / stored procedures (incluye carrito y notas de pedido)
├── 03_seed_data.sql             → Datos iniciales y de prueba, incluye el seed de metodos_pago y la config de pasarelas (antes en 08_pagos_metodos.sql)
├── 05_pagos.sql                  → Módulo de pagos: PayPal, SPEI legacy y SPEI vía Stripe (customer_balance)
├── migrations/
│   ├── 12_remove_mercadopago.sql → Elimina referencias a MercadoPago (ya aplicado; histórico)
│   ├── 13_drop_tablas_huerfanas.sql → Elimina sesiones/recuperacion_password/tarjetas_guardadas (ya aplicado; histórico)
│   └── 14_drop_blog_cotizaciones_cupones_newsletter.sql → Elimina 9 tablas + 5 funciones de drift (blog, cotizaciones, cupones, newsletter) y cupon_id en carritos/pedidos (ya aplicado; histórico)
└── tools/
    ├── 04_examples.sql           → Guía de uso con SELECTs listos (referencia — algunas funciones citadas ya no existen, ver nota abajo)
    └── CHECK_firmas.sql          → Diagnóstico: verifica firmas de funciones almacenadas
docs/
└── MBS_DB_README.md      → Esta documentación
```

> **Motor requerido:** PostgreSQL 14 o superior
> **Extensión requerida:** `unaccent` (incluida en la instalación estándar de PG)

---

## Orden de ejecución obligatorio

Los archivos tienen dependencias entre sí. **Deben ejecutarse en este orden:**

```
01_schema.sql → 02_functions.sql → 03_seed_data.sql → 05_pagos.sql
```

Desde la unificación de julio 2026 esto son solo 4 scripts (antes eran 7): `06_imagenes.sql`, `07_contacto.sql` y `08_pagos_metodos.sql` se fusionaron en los archivos base de arriba, y ya no existen como archivos separados.

- `00_drop_functions.sql` es opcional: solo se usa para reinstalar `02_functions.sql` sin recrear el esquema.
- `tools/04_examples.sql` es solo de referencia, no se ejecuta en producción.
- `05_pagos.sql` agrega las tablas y funciones de PayPal/SPEI, incluido el flujo SPEI vía Stripe (`customer_balance`, CLABE dinámica) en paralelo al flujo SPEI casero, seleccionable con la clave de configuración `spei_motor` (`legacy` | `stripe`) — necesario para que `/api/pagos` funcione.
- `01_schema.sql` ya incluye los índices de `producto_imagenes` y las tablas `mensajes_contacto` (formulario de contacto) y `password_resets` (recuperación de contraseña).
- `03_seed_data.sql` ya incluye la configuración de pasarelas (Stripe/PayPal) además del seed de `metodos_pago`.
- `migrations/12_remove_mercadopago.sql` ya fue aplicado; se conserva solo como referencia histórica.

---

## Diagrama de tablas

```
USUARIOS
  usuarios ──────────┬── direcciones
                     ├── favoritos
                     ├── notificaciones
                     └── auditoria

CATÁLOGO
  productos ─────────┬── categorias
                     ├── marcas
                     ├── producto_imagenes
                     ├── producto_especificaciones
                     └── variantes_longitud

VENTAS
  carritos ──────────┬── carrito_items
  pedidos ───────────┬── pedido_items
                     ├── pedido_historial
                     ├── pago_referencias (SPEI)
                     └── pago_paypal

LOGÍSTICA
  metodos_envio
  metodos_pago
  inventario_movimientos

CONTENIDO
  resenas

SISTEMA
  configuracion (clave-valor)
  newsletter
  mensajes_contacto
  password_resets
  pago_webhooks_log
```

---

## Funciones disponibles

> En PostgreSQL los stored procedures que retornan datos
> son **FUNCTIONS** y se llaman con `SELECT * FROM fn_nombre(...)`.

### Módulo: Usuarios

| Función | Descripción | Ejemplo |
|---|---|---|
| `fn_registrar_usuario(nombre, apellidos, email, hash, tel, tipo)` | Registrar cliente con validación de email único | `SELECT * FROM fn_registrar_usuario('Carlos','Mendez','c@mx.com','$2b$...','442xxx','empresa');` |
| `fn_obtener_perfil_cliente(usuario_id)` | Perfil completo con stats de pedidos, gastado, favoritos | `SELECT * FROM fn_obtener_perfil_cliente(2);` |
| `fn_actualizar_datos_personales(id, nombre, apellidos, tel, rfc, razon)` | Editar perfil personal | `SELECT fn_actualizar_datos_personales(2,'Carlos','M.','+52...','RFC','Empresa SA');` |
| `fn_toggle_bloqueo_cliente(usuario_id, bloqueado, motivo, admin_id)` | Bloquear o desbloquear cliente con auditoría | `SELECT fn_toggle_bloqueo_cliente(5, TRUE, 'Fraude detectado', 1);` |

> El listado de clientes del panel admin (búsqueda y paginación) no usa una función almacenada — es SQL inline en `admin.controller.js`. `fn_admin_listar_clientes` no existe en el esquema actual.

### Módulo: Catálogo

| Función | Descripción | Ejemplo |
|---|---|---|
| `fn_listar_productos(cat_id, marca_id, precio_min, precio_max, solo_stock, busqueda, orden, pagina, por_pagina)` | Listado con todos los filtros del catálogo, full-text con acentos | `SELECT * FROM fn_listar_productos(1,NULL,0,5000,TRUE,'SC','precio_asc',1,9);` |
| `fn_producto_detalle(slug)` | Datos completos del producto por slug, incluye `r_categoria_id` y `r_categoria_nombre` (usados para cargar productos relacionados) | `SELECT * FROM fn_producto_detalle('cable-fo-monomodo-sc-upc-3mm');` |
| `fn_listar_resenas_producto(p_producto_id, p_pagina=1)` | Reseñas aprobadas de un producto, paginadas (10 por página) | `SELECT * FROM fn_listar_resenas_producto(1,1);` |

> Crear/editar producto desde el panel admin no usa una función almacenada — es SQL inline (`INSERT`/`UPDATE` sobre `productos`) en `admin.controller.js`. `fn_guardar_producto` no existe en el esquema actual.

### Módulo: Carrito

| Función | Descripción | Ejemplo |
|---|---|---|
| `fn_carrito_agregar_item(usuario_id, session_key, producto_id, variante_id, cantidad)` | Agregar ítem validando stock. Soporta sesiones anónimas | `SELECT * FROM fn_carrito_agregar_item(2,NULL,1,3,2);` |
| `fn_carrito_obtener(usuario_id, session_key)` | Items del carrito con totales e imagen | `SELECT * FROM fn_carrito_obtener(2,NULL);` |

> No hay sistema de cupones/descuentos: ni tablas (`cupones`, `cupon_usos`), ni `fn_carrito_aplicar_cupon`, ni lógica en el backend o frontend. Nunca se implementó — quedó documentado en versiones anteriores de este archivo como si existiera.

### Módulo: Pedidos

| Función | Descripción | Ejemplo |
|---|---|---|
| `fn_crear_pedido(usuario_id, carrito_id, direccion_id, envio_id, pago_id, notas, requiere_factura)` | Flujo completo: valida stock → snapshot precios → descuenta inventario → registra movimientos → limpia carrito → notifica | `SELECT * FROM fn_crear_pedido(2,1,1,1,1,'Entregar en recepcion.',TRUE);` |
| `fn_actualizar_estado_pedido(pedido_id, estado, paqueteria, guia, notas, admin_id)` | Cambiar estado con historial y notificación automática al cliente | `SELECT fn_actualizar_estado_pedido(1,'enviado','FedEx','749...',NULL,1);` |
| `fn_listar_pedidos_cliente(usuario_id, estado, pagina)` | Pedidos del cliente filtrados por estado, paginados | `SELECT * FROM fn_listar_pedidos_cliente(2,'enviado',1);` |
| `fn_detalle_pedido(pedido_id, usuario_id)` | Detalle completo: items, historial, dirección, métodos | `SELECT * FROM fn_detalle_pedido(1,2);` |
| `fn_guardar_notas_pedido(pedido_id, notas, admin_id)` | Guarda notas internas del pedido sin disparar la notificación de "cambio de estado" al cliente | `SELECT fn_guardar_notas_pedido(1,'Cliente pidió factura después.',1);` |

> Definida en `02_functions.sql`.

### Módulo: Pagos

> Definidas en `05_pagos.sql`. Cubren las formas de pago activas: PayPal, SPEI/referencia bancaria (legacy) y SPEI vía Stripe `customer_balance` (CLABE dinámica), seleccionable con la clave de configuración `spei_motor` (`legacy` | `stripe`, controlado desde `pagos.controller.js`).

| Función | Descripción | Ejemplo |
|---|---|---|
| `fn_crear_referencia_spei(pedido_id, clabe, banco, beneficiario, horas_vence=48)` | Genera una referencia SPEI (motor legacy) única con monto y fecha límite, y marca el pedido como `pago_proveedor='spei'` | `SELECT * FROM fn_crear_referencia_spei(1,'646180111800000001','STP','MBS Comunicaciones',48);` |
| `fn_confirmar_pago_spei(referencia, monto, clave_rastreo, banco_emisor, webhook_json)` | Llamada desde el webhook bancario (motor legacy): marca la referencia y el pedido como pagados, notifica al cliente y registra auditoría | `SELECT fn_confirmar_pago_spei('25000001234','349.00','MX12345...','BBVA','{}'::JSONB);` |
| `fn_crear_referencia_spei_stripe(pedido_id, clabe, banco, beneficiario, referencia, stripe_customer_id, stripe_payment_intent_id, horas_vence=48)` | Igual que `fn_crear_referencia_spei` pero para el motor Stripe: persiste la CLABE dinámica ya generada por la API de Stripe | `SELECT * FROM fn_crear_referencia_spei_stripe(1,'646180...','STP','MBS Comunicaciones','25000001234','cus_...','pi_...',48);` |
| `fn_confirmar_pago_spei_stripe(stripe_payment_intent_id, estado, monto, webhook_json)` | Llamada desde el webhook de Stripe (`payment_intent.processing` / `.succeeded` / `.payment_failed`); `estado` es `procesando`, `pagado`, `fallido` o `vencido` | `SELECT fn_confirmar_pago_spei_stripe('pi_123','pagado',349.00,'{}'::JSONB);` |
| `fn_crear_orden_paypal(pedido_id, order_id, url_aprobacion)` | Guarda la orden creada en PayPal (estado `CREATED`) y marca el pedido como `pago_proveedor='paypal'` | `SELECT fn_crear_orden_paypal(1,'8RA97X14K8765432L','https://www.paypal.com/checkoutnow?token=...');` |
| `fn_confirmar_pago_paypal(order_id, capture_id, estado, monto, comision, email_pagador, webhook_json)` | Llamada desde la captura síncrona y desde el webhook de PayPal: actualiza `pago_paypal`, y si `estado='COMPLETED'` marca el pedido como pagado, notifica y audita. Es idempotente: si la orden ya estaba `COMPLETED`, una segunda llamada con `estado='COMPLETED'` no repite la notificación/auditoría | `SELECT fn_confirmar_pago_paypal('8RA97X14K8765432L','3C679366YS',...);` |
| `fn_marcar_pedido_pagado_manual(pedido_id, admin_id, nota)` | Marca un pedido como pagado manualmente desde el panel admin (pedidos legacy sin webhook, o cualquier caso fuera de banda); también cierra referencias SPEI pendientes/procesando | `SELECT fn_marcar_pedido_pagado_manual(1,1,'Confirmado por telefono con el cliente.');` |
| `fn_estado_pago_pedido(pedido_id)` | Resume el estado de pago de un pedido: estatus general + datos de SPEI y PayPal en una sola fila | `SELECT * FROM fn_estado_pago_pedido(1);` |

> `fn_vencer_referencias_spei()` está documentada en `tools/04_examples.sql` pero no existe como función almacenada en el esquema actual — no invocarla.

### Módulo: Inventario

| Función | Descripción | Ejemplo |
|---|---|---|
| `fn_ajustar_stock(producto_id, nuevo_stock, motivo, admin_id)` | Ajustar stock manualmente con movimiento registrado | `SELECT fn_ajustar_stock(2,50,'Recepcion mercancia',1);` |
| `fn_alertas_inventario()` | Productos con stock = 0 (Sin stock), ≤ mínimo/2 (Crítico) o ≤ mínimo (Bajo) | `SELECT * FROM fn_alertas_inventario();` |

### Módulo: Dashboard Admin

| Función | Descripción | Ejemplo |
|---|---|---|
| `fn_dashboard_resumen()` | Todos los KPIs en una sola fila: pedidos hoy, sin atender, clientes, stock bajo, ventas del día | `SELECT * FROM fn_dashboard_resumen();` |
| `fn_ventas_semana()` | Gráfica de ventas de los últimos 7 días con totales por día | `SELECT * FROM fn_ventas_semana();` |

### Módulo: Configuración

| Función | Descripción | Ejemplo |
|---|---|---|
| `fn_obtener_configuracion(seccion)` | Leer configuración por sección o toda | `SELECT * FROM fn_obtener_configuracion('general');` |
| `fn_guardar_configuracion(clave, valor, admin_id)` | Guardar o actualizar clave-valor con auditoría | `SELECT fn_guardar_configuracion('site_telefono','+52 442...',1);` |

### Módulo: Favoritos

| Función | Descripción | Ejemplo |
|---|---|---|
| `fn_toggle_favorito(usuario_id, producto_id)` | Agrega si no existe, elimina si existe | `SELECT fn_toggle_favorito(2,1);` |
| `fn_listar_favoritos(usuario_id)` | Lista completa de favoritos con imagen y precio | `SELECT * FROM fn_listar_favoritos(2);` |

### Funciones internas (usadas por otras funciones)

| Función | Descripción |
|---|---|
| `fn_generar_numero_pedido()` | Genera `MBS-YYYY-NNNNNN` secuencial por año |
| `fn_set_updated_at()` | Trigger que actualiza `updated_at` automáticamente |
| `fn_crear_trigger_updated_at(tabla)` | Crea el trigger de `updated_at` en cualquier tabla |
| `fn_productos_fts()` | Mantiene el `tsvector` de búsqueda de productos actualizado |

---

## Flujo principal de compra

```
1. fn_registrar_usuario()       → Crear cuenta del cliente
2. fn_listar_productos()        → Navegar el catálogo con filtros
3. fn_producto_detalle()        → Ver detalle de un producto
4. fn_carrito_agregar_item()    → Agregar al carrito
5. fn_crear_pedido()            → Checkout — realiza todo en una transacción:
      ├── Valida stock ítem por ítem ANTES de insertar
      ├── Genera número MBS-2025-XXXXXX
      ├── Hace snapshot de dirección y precios (protege contra cambios futuros)
      ├── Descuenta stock de cada producto
      ├── Registra movimiento en inventario_movimientos
      ├── Elimina el carrito limpiamente
      └── Inserta notificación para el cliente
6. fn_actualizar_estado_pedido() → Admin gestiona: en preparación → enviado → entregado
```

---

## Variables de entorno recomendadas

Ver `mbs_backend/.env.example` para la lista completa y actualizada. Resumen:

```env
PORT=3000
NODE_ENV=development
DB_HOST=localhost
DB_PORT=5432
DB_NAME=mbs_comunicaciones
DB_USER=postgres
DB_PASSWORD=<password_seguro>
JWT_SECRET=<clave_larga_y_segura>
JWT_EXPIRES_IN=7d
PAYPAL_MODE=sandbox
PAYPAL_CLIENT_ID=
PAYPAL_SECRET=
```

> Los datos bancarios para SPEI (`spei_clabe`, `spei_banco`, `spei_beneficiario`) **no** se configuran por variables de entorno: se guardan en la tabla `configuracion` y se editan desde el panel de administración ("Configuración"). Ver `fn_obtener_configuracion` / `fn_guardar_configuracion`.

---

## Notas de seguridad

- Los `password_hash` se generan con **bcrypt factor 12** en el backend. Nunca se almacenan contraseñas en texto plano.
- Los pagos con tarjeta se procesan directo con **Stripe**; no hay tabla de tarjetas guardadas — la tokenización vive del lado del gateway y el número completo **nunca se almacena** en la base de datos.
- La tabla `auditoria` registra con timestamp e IP todas las acciones administrativas sensibles.
- La extensión `unaccent` permite búsquedas con y sin acentos (buscar "fibra" encuentra "fibra óptica").
- El campo `fts` (tsvector) en `productos` se actualiza automáticamente por trigger cada vez que se inserta o edita un registro.

