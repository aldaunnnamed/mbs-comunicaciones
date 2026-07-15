# Auditoría del Proyecto MBS Comunicaciones
*Fecha original: 25 de junio de 2026 · Última actualización: 2 de julio de 2026*

---

## ✅ Estado General del Backend

**Todas las rutas y controladores están correctamente conectados.** No hay handlers faltantes ni exports rotos. La tabla completa:

| Prefijo | Archivo de rutas | Estado |
|---|---|---|
| `/api/auth` | auth.routes.js | ✅ 7 rutas OK |
| `/api/productos` | productos.routes.js | ✅ 5 rutas OK |
| `/api/carrito` | carrito.routes.js | ✅ 6 rutas OK |
| `/api/pedidos` | pedidos.routes.js | ✅ 8 rutas OK |
| `/api/usuarios` | usuarios.routes.js | ✅ 8 rutas OK |
| `/api/admin` | admin.routes.js | ✅ ~30 rutas OK |
| `/api/pagos` | pagos.routes.js | ✅ 14 rutas OK — webhooks con rate limiting |
| `/api/contacto` | contacto.routes.js | ✅ 1 ruta OK |
| `/api/config/publica` | app.js (inline) | ✅ OK |

Ver también el reporte técnico más reciente: `docs/Reporte_Auditoria_MBS_2026-07-01.pdf` (mapeo de dependencias, bugs corregidos, deuda técnica).

---

## ✅ Resuelto (originalmente crítico/moderado en esta auditoría)

### 1. Scripts de base de datos — ejecutados

| Script | Descripción | Estado |
|---|---|---|
| `08_pagos_metodos.sql` | Tabla `metodos_pago` (PayPal, Stripe, SPEI) | ✅ Ejecutado — checkout muestra métodos de pago |
| `09_fix_carrito.sql` | Fusión de carrito anónimo al hacer login | ✅ Ejecutado y verificado end-to-end (carrito ya no se pierde al iniciar sesión) |

`10_mercadopago_metodo.sql` mencionado en la versión anterior de este documento quedó **obsoleto**: Mercado Pago fue removido por completo del proyecto (`database/12_remove_mercadopago.sql`, ya aplicado). No debe crearse ni ejecutarse.

También se desactivó (no se eliminó, por integridad referencial con 21 pedidos históricos) el método de pago duplicado `contado`, dejando solo `entrega` activo.

### 2. `recuperar-password.html` — encoding verificado

Se revisó el archivo completo (contenido y escaneo de bytes) y **no presenta caracteres corruptos** (`Ã³`, `â€"`, etc.). El problema mencionado en la versión original de esta auditoría ya no aplica — probablemente corregido en un commit posterior no reflejado en este documento.

### 3. `test-login.html` — ya no existe

No se encontró el archivo en `public/` ni rastro en el historial de git de `mbs_backend`. Ya fue eliminado antes de esta revisión.

### 4. `mp-retorno.html` y otros huérfanos de Mercado Pago

El archivo no existe en el árbol de trabajo actual (eliminado en el commit `8bfa8cc`). Se hizo una búsqueda exhaustiva (nombres de archivo y contenido en todo el repo) y **no quedan referencias a Mercado Pago** en código. Sí queda una fila histórica `mercadopago` en `metodos_pago` (id 84, `activo=false`, referenciada por 35 pedidos) — no se puede eliminar sin romper integridad referencial, pero no afecta nada al estar desactivada.

### 5. Rate limiting en webhooks de pago (oportunidad futura del reporte de julio)

Implementado `express-rate-limit` (30 solicitudes/IP/minuto) en `/api/pagos/spei/webhook`, `/api/pagos/paypal/webhook` y `/api/pagos/stripe/webhook`. Verificado en vivo: la solicitud #31 en un minuto recibe `429`. No reemplaza la verificación de firma/token existente en cada webhook, es una capa adicional.

### 6. Limpieza de avatares al subir uno nuevo

`POST /api/usuarios/foto` ahora borra el archivo del avatar anterior en `public/uploads/avatares/` antes de guardar el nuevo (antes se acumulaban indefinidamente). Verificado subiendo dos avatares consecutivos: solo queda el más reciente en disco.

### 7. Limpieza de datos de prueba en la base de datos

La suite de Jest corre contra la BD real (no hay BD de test separada — ver sección de Tests en `CLAUDE.md`), por lo que meses de ejecuciones habían dejado **266 usuarios**, **21 productos** (`TEST-ADMIN-*`) y **26 mensajes de contacto** de prueba mezclados con datos reales. Se identificaron por patrón (`_[0-9]{9,}@mbs\.mx` para usuarios generados por Jest, `TEST-ADMIN-*` para productos, emails `test@test.com`/`qa@test.com`/`contacto_test@mbs.mx` para mensajes) y se eliminaron en una transacción única, respetando el orden que exigen las foreign keys `NO ACTION` (pedidos → items/historial/pagos antes que usuarios; inventario antes que productos). Se conservó un respaldo completo (`pg_dump`) antes de borrar.

Cuentas ambiguas que no seguían el patrón automatizado (correos personales usados para pruebas manuales, incluida la cuenta del desarrollador actual) se conservaron a propósito, por decisión explícita.

**Nota operativa:** cada corrida futura de `npm test` volverá a insertar un puñado de filas de prueba (comportamiento esperado, no un bug). Repetir la misma limpieza si se requiere un estado "limpio" de nuevo.

Estado final verificado: 10 usuarios reales · 12 productos reales · pedidos/mensajes reales intactos · 93/93 tests siguen pasando · checkout end-to-end probado tras la limpieza.

---

## 🟡 Pendientes (heredados del Reporte_Auditoria_MBS_2026-07-01.pdf, sección "Deuda técnica" / "Oportunidades futuras")

| Pendiente | Prioridad | Motivo |
|---|---|---|
| Webhook secrets vacíos (`stripe_webhook_secret_test/live`, `paypal_webhook_id_test/live`) | Alta | Requiere credenciales reales de los dashboards de Stripe/PayPal — configuración externa, no código |
| CSP desactivado (`helmet({ contentSecurityPolicy: false })` en `app.js`) | Media | Requiere listar explícitamente los dominios de PayPal/Stripe antes de activarlo |
| Cotizaciones sin capa Express (tablas y funciones SQL existen, faltan rutas/controlador) | Media | Requiere decisión de producto sobre implementar la feature |
| 37 filas sin `seccion` en tabla `configuracion` | Baja | Basura de una versión anterior, no causa errores |
| Tablas huérfanas (`blog_articulos`, `newsletter`, `tarjetas_guardadas`) | Baja | Sin rutas ni controladores, requieren decisión de producto |
| `fn_admin_listar_clientes` nunca invocada desde Node | Baja | Función muerta en BD, no rompe nada |

---

## 📋 Inventario Completo de Archivos

### Backend (`mbs_backend/src/`)
```
app.js                          ✅
config/db.js                    ✅
middlewares/auth.js             ✅ (verificarToken, soloAdmin, tokenOpcional)
middlewares/upload.js           ✅ (uploadImage, uploadCsv, uploadLogo, uploadAvatar)
controllers/auth.controller.js      ✅
controllers/pedidos.controller.js   ✅
controllers/productos.controller.js ✅
controllers/carrito.controller.js   ✅
controllers/admin.controller.js     ✅
controllers/pagos.controller.js     ✅ (Stripe, PayPal, SPEI — sin Mercado Pago)
routes/auth.routes.js           ✅
routes/productos.routes.js      ✅
routes/carrito.routes.js        ✅
routes/pedidos.routes.js        ✅
routes/usuarios.routes.js       ✅ (limpieza de avatar al reemplazar foto)
routes/admin.routes.js          ✅
routes/pagos.routes.js          ✅ (rate limiting en los 3 webhooks)
routes/contacto.routes.js       ✅
services/email.service.js       ✅
services/factura.service.js     ✅
services/paypal.service.js      ✅
services/stripe.service.js      ✅
```

### Base de datos (`database/`)
```
01_schema.sql                   ✅ Documentado en CLAUDE.md
02_functions.sql                ✅ Documentado
03_seed_data.sql                ✅ Documentado
04_examples.sql                 ✅ Solo referencia
05_pagos.sql                    ✅ Documentado
06_imagenes.sql                 ✅ Documentado
07_contacto.sql                 ✅ Documentado
08_pagos_metodos.sql            ✅ Documentado y ejecutado
09_fix_carrito.sql              ✅ Documentado y ejecutado
12_remove_mercadopago.sql       ✅ Documentado y aplicado
```

---

## 🚧 Estado de Integraciones de Pago

| Pasarela | Backend | Frontend | Webhook | Rate limiting |
|---|---|---|---|---|
| PayPal | ✅ Funciona (lee de DB) | ✅ Flujo completo | ⚠️ Sin verificar firma (webhook_id vacío) | ✅ |
| Stripe | ✅ Funciona (lee de DB) | ✅ CardElement | ⚠️ Rechaza 400 (secret vacío) | ✅ |
| SPEI | ✅ Referencia + webhook (token compartido) | ✅ Instrucciones | ✅ Verificado | ✅ |
| Mercado Pago | Removido del proyecto | — | — | — |

---

## ✅ Lista de Acciones Restantes

Ordenadas por prioridad:

1. **Configurar webhook secrets de Stripe y PayPal** desde sus dashboards y cargarlos en Admin → Configuración → Pagos.
2. **Definir política CSP** que permita los dominios de PayPal/Stripe y activarla en `app.js`.
3. ~~Decidir sobre `cotizaciones`, `blog_articulos`, `newsletter`~~ — resuelto, ver addendum: se eliminaron (`tarjetas_guardadas` también, en una pasada anterior del addendum).
4. **Limpiar las 37 filas sin `seccion`** en `configuracion` (verificar primero que ningún código las lea).

---

## Addendum — 15 de julio de 2026

Los apartados anteriores (fechados 25 jun / 2 jul) describen un estado de la base de datos que **ya no corresponde a la BD local actual**: la sección 7 de este documento reporta "10 usuarios reales · 12 productos reales" tras la limpieza de datos de prueba, y la línea 49 registra la fila `mercadopago` como "referenciada por 35 pedidos" y la de `contado` como referenciada por 21. Al revisar hoy la misma base de datos local, se encontraron solo 1–2 productos de prueba, 0 pedidos ligados a `mercadopago`/`entrega`/`contado`, y un total de 4 pedidos en toda la tabla — consistente con un reseteo/resiembra ocurrido después del 2 de julio, no con las cifras que documenta esta auditoría. Si en algún momento vuelve a existir una base de datos de producción separada con historial real, **revalidar contra ella** antes de asumir que lo siguiente sigue vigente ahí.

Cambios aplicados hoy sobre esta base (detalle completo en `CLAUDE.md` y `docs/MBS_DB_README.md`):

- **Tablas huérfanas eliminadas** (0 filas, 0 referencias en código, verificado antes de borrar): `sesiones`, `recuperacion_password` y `tarjetas_guardadas` — esta última ya estaba señalada como pendiente en la sección "🟡 Pendientes" de este documento (línea 79) y en la lista de acciones restantes. Migración: `database/migrations/13_drop_tablas_huerfanas.sql`. `01_schema.sql` actualizado para no volver a crearlas.
- **Duplicado de `metodos_pago` corregido**: `08_pagos_metodos.sql` insertaba `entrega` con `ON CONFLICT DO NOTHING` mientras `03_seed_data.sql` ya insertaba `contado` con el mismo nombre ("Pago contra entrega") — ambas claves coexistían como filas separadas. Se dejó `03_seed_data.sql` como única fuente del seed de `metodos_pago`; `08_pagos_metodos.sql` ahora solo siembra configuración de pasarelas. En esta BD (0 pedidos en cualquiera de las dos filas) se eliminó `entrega` y la fila residual `mercadopago` (también 0 pedidos aquí, a diferencia de los 35 que reporta este documento para un estado anterior).
- **Scripts fusionados a los archivos base** (eliminados tras la fusión): `09_fix_carrito.sql` → `02_functions.sql`; `migrations/10_spei_stripe.sql` → `05_pagos.sql`; `migrations/11_notas_pedido.sql` → `02_functions.sql`. El orden de instalación limpio quedó en 7 scripts: `01→02→03→05→06→07→08`.
- **Scripts de un solo uso eliminados** (ya inservibles): `migrations/run_reg.sql`, `migrations/migracion_fix_duplicados_seed.sql`.
- **Documentación de cupones corregida**: `docs/MBS_DB_README.md` documentaba `cupones`/`cupon_usos`/`fn_carrito_aplicar_cupon` como si fueran parte del esquema vigente. Corrección a esta misma nota (ver punto siguiente): sí existían, pero solo como *drift* — nunca en los scripts versionados.

### Corrección al punto anterior + hallazgo mayor: 9 tablas y 5 funciones de drift

Al revisar el pendiente "decidir sobre `cotizaciones`, `blog_articulos`, `newsletter`" (línea 79 / lista de acciones restantes), se encontró que estas tablas **sí existen físicamente en la BD local**, a pesar de no estar en `01_schema.sql` — igual que `cupones`/`cupon_usos`, que se había afirmado arriba que "nunca existieron en el esquema" (impreciso: no existían en los *scripts*, pero sí como residuo vivo en la BD, incluida la función `fn_carrito_aplicar_cupon`).

Inventario completo de drift encontrado y eliminado (0 filas en las 9 tablas, 0 referencias en `mbs_backend/src`, verificado antes de borrar):

| Módulo | Tablas | Funciones |
|---|---|---|
| Blog/CMS | `blog_articulos`, `blog_categorias`, `blog_etiquetas`, `blog_articulo_etiquetas` | `fn_guardar_articulo` |
| Cotizaciones | `cotizaciones`, `cotizacion_items` | `fn_generar_numero_cotizacion`, `fn_crear_cotizacion`, `fn_responder_cotizacion` |
| Cupones | `cupones`, `cupon_usos` | `fn_carrito_aplicar_cupon` |
| Newsletter | `newsletter` | — |

También se encontraron y eliminaron las columnas `cupon_id` en `carritos` y `pedidos` (tablas reales y en uso) — tampoco estaban en `01_schema.sql`, apuntaban a `cupones` vía FK, y tenían 0 valores no nulos en ambas. Migración: `database/migrations/14_drop_blog_cotizaciones_cupones_newsletter.sql` (incluye chequeo de seguridad que aborta si alguna tabla tiene filas o esas columnas tienen valores).

Todas estas tablas/funciones fueron removidas de los scripts versionados en el commit `b6413f7` (ver auditoría original, sección "Cotizaciones sin capa Express" línea 77 y "Tablas huérfanas" línea 79) pero nunca se eliminaron de las bases de datos ya aprovisionadas — una instalación nueva desde `01_schema.sql`/`02_functions.sql` jamás las crea.

Verificado: instalación limpia end-to-end en una base de datos temporal (creada y eliminada), y 93/93 tests del backend pasando tras todos los cambios (incluida esta segunda tanda).
