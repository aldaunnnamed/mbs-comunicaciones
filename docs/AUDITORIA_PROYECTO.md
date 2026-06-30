# Auditoría del Proyecto MBS Comunicaciones
*Fecha: 25 de junio de 2026*

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
| `/api/pagos` | pagos.routes.js | ✅ 14 rutas OK |
| `/api/contacto` | contacto.routes.js | ✅ 1 ruta OK |
| `/api/config/publica` | app.js (inline) | ✅ OK |

---

## 🔴 Problemas Críticos

### 1. Scripts de base de datos faltantes en la documentación (CLAUDE.md)

Los siguientes scripts existen en `database/` pero **no están listados en CLAUDE.md** y probablemente no han sido aplicados:

| Script | Descripción | ¿Necesario? |
|---|---|---|
| `08_pagos_metodos.sql` | Crea tabla `metodos_pago` con registros para PayPal, Stripe, SPEI, MP | **CRÍTICO** — sin esto el checkout no muestra métodos de pago |
| `09_fix_carrito.sql` | Reescribe `fn_carrito_obtener` para fusionar carrito anónimo al hacer login | **IMPORTANTE** — sin esto el carrito se pierde al iniciar sesión |
| `10_mercadopago_metodo.sql` | Inserta Mercado Pago en `metodos_pago` | **NECESARIO** — creado en esta sesión para que aparezca la tab de MP |

**Acción requerida — ejecutar en este orden:**
```bash
psql -U postgres -d mbs_comunicaciones -f database/08_pagos_metodos.sql
psql -U postgres -d mbs_comunicaciones -f database/09_fix_carrito.sql
psql -U postgres -d mbs_comunicaciones -f database/10_mercadopago_metodo.sql
```

---

## 🟡 Problemas Moderados

### 2. `recuperar-password.html` con caracteres corruptos

**Ubicación:** `mbs_backend/public/pages/recuperar-password.html`

El archivo funciona visualmente pero `grep` lo detecta como binario debido a caracteres UTF-8 mal codificados (`Ã³`, `â€"`, etc.) en sus strings. Esto también es mencionado en las "Known issues" del CLAUDE.md.

**Impacto:** No rompe la funcionalidad pero puede causar problemas si se edita en ciertos editores.

**Acción:** Abrir el archivo, identificar strings con caracteres `Ã³`, `Ã©`, `Ã¡`, `â€"` y reemplazarlos por sus equivalentes correctos (`ó`, `é`, `á`, `—`).

---

### 3. Archivo de debug `test-login.html` en producción

**Ubicación:** `mbs_backend/public/test-login.html`

Es un archivo de prueba con herramientas de diagnóstico expuestas públicamente (peticiones a `/api/auth/login`, tokens JWT visibles, etc.).

**Acción:** Eliminar antes de cualquier despliegue a producción.
```bash
del mbs_backend\public\test-login.html
```

---

### 4. `.env.example` incompleto

El archivo `.env.example` no documenta las variables agregadas en esta sesión:

```env
# Estas variables faltan en .env.example:
APP_URL=https://underrate-silk-librarian.ngrok-free.dev
NODE_ENV=development
```

Stripe, Mercado Pago y PayPal **no van en `.env`** — sus credenciales se gestionan desde el panel admin (tabla `configuracion`). Eso está bien diseñado y no requiere cambio.

---

## 🟢 Observaciones (no son errores)

### 5. JS por página: todo es inline

Solo existen 4 archivos JS en `public/js/`:
- `global.js` — helpers globales, se carga en todas las páginas
- `catalogo.js` — lógica del catálogo
- `home.js` — lógica del home
- `admin-core.js` — panel de administración

El resto de páginas (`checkout`, `carrito`, `mis-pedidos`, `mi-cuenta`, `login`, `registro`, `producto`, `contacto`, etc.) tienen todo su JavaScript **embebido en el propio HTML** dentro de `<script>` tags. Esto es intencional en el diseño actual, no es un error.

---

### 6. `pdfkit` en uso (no es dependencia muerta)

La dependencia `pdfkit` listada en `package.json` SÍ se usa:
- `admin.controller.js` línea 429 — exportar productos como PDF
- `admin.controller.js` línea 674 — exportar clientes como PDF

---

### 7. `iniciar_con_ngrok.bat` no documentado

**Ubicación:** `mbs_backend/iniciar_con_ngrok.bat`

Archivo de lote creado en esta sesión para iniciar ngrok + servidor con un solo clic. No está documentado en CLAUDE.md.

**Para usarlo:**
```
Doble clic en mbs_backend\iniciar_con_ngrok.bat
```
Abre ngrok en una ventana y el servidor Node en la misma ventana.

---

## 📋 Inventario Completo de Archivos

### Backend (`mbs_backend/src/`)
```
app.js                          ✅
config/db.js                    ✅
middlewares/auth.js             ✅ (verificarToken, soloAdmin, tokenOpcional)
middlewares/upload.js           ✅ (uploadImage, uploadCsv, uploadLogo)
controllers/auth.controller.js      ✅
controllers/pedidos.controller.js   ✅
controllers/productos.controller.js ✅
controllers/carrito.controller.js   ✅
controllers/admin.controller.js     ✅
controllers/pagos.controller.js     ✅ (incluye Stripe, PayPal, MP Bricks, SPEI)
routes/auth.routes.js           ✅
routes/productos.routes.js      ✅
routes/carrito.routes.js        ✅
routes/pedidos.routes.js        ✅
routes/usuarios.routes.js       ✅
routes/admin.routes.js          ✅
routes/pagos.routes.js          ✅
routes/contacto.routes.js       ✅
services/email.service.js       ✅
services/factura.service.js     ✅
services/mercadopago.service.js ✅ (crearPreferencia, crearPago, getPublicKey)
services/paypal.service.js      ✅
services/stripe.service.js      ✅
```

### Frontend — Páginas HTML (`public/pages/`)
```
catalogo.html           ✅
producto.html           ✅
carrito.html            ✅
checkout.html           ✅ (PayPal + Stripe + MP Bricks)
mi-cuenta.html          ✅
mis-pedidos.html        ✅
login.html              ✅
registro.html           ✅
contacto.html           ✅
recuperar-password.html ⚠️  (encoding corrupto en algunos strings)
reset-password.html     ✅
paypal-retorno.html     ✅
mp-retorno.html         ✅
checkout-ok.html        ✅ (creado esta sesión)
checkout-error.html     ✅ (creado esta sesión)
checkout-pendiente.html ✅ (creado esta sesión)
sobre-nosotros.html     ✅
faq.html                ✅
politica-envios.html    ✅
garantia.html           ✅
privacidad.html         ✅
terminos.html           ✅
```

### Frontend — Admin (`public/admin/`)
```
index.html          ✅
login.html          ✅
productos.html      ✅
pedidos.html        ✅
clientes.html       ✅
inventario.html     ✅
mensajes.html       ✅
configuracion.html  ✅
```

### CSS (`public/css/`)
```
global.css      ✅
navbar.css      ✅
pages.css       ✅
catalogo.css    ✅
home.css        ✅
admin.css       ✅
```

### JavaScript (`public/js/`)
```
global.js       ✅
catalogo.js     ✅
home.js         ✅
admin-core.js   ✅
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
08_pagos_metodos.sql            ❌ NO documentado — EJECUTAR
09_fix_carrito.sql              ❌ NO documentado — EJECUTAR
10_mercadopago_metodo.sql       ❌ NO documentado — EJECUTAR
```

---

## 🚧 Estado de Integraciones de Pago

| Pasarela | Backend | Frontend | Prueba end-to-end |
|---|---|---|---|
| PayPal | ✅ Funciona (lee de DB) | ✅ Flujo completo | ✅ Completado con sandbox |
| Stripe | ✅ Funciona (lee de DB) | ✅ CardElement | ✅ Probado con 4242... |
| Mercado Pago Bricks | ✅ Backend completo | ✅ Brick renderiza | ⚠️ onSubmit bloqueado por Edge Tracking Prevention |
| SPEI | ✅ Referencia + webhook | ✅ Instrucciones | — Manual por naturaleza |

**Pendiente MP:** El brick de Mercado Pago se muestra correctamente pero Edge bloquea el submit. Para resolverlo:
1. En Edge: `edge://settings/privacy` → "Excepciones" → agregar `*.mlstatic.com` y `https://underrate-silk-librarian.ngrok-free.dev`
2. O instalar Google Chrome y probar ahí (no instalado en la máquina actual)

---

## ✅ Lista de Acciones Inmediatas

Ordenadas por prioridad:

1. **Ejecutar scripts de BD faltantes** (crítico para que funcionen los métodos de pago):
   ```bash
   cd mbs_backend
   psql -U postgres -d mbs_comunicaciones -f ../database/08_pagos_metodos.sql
   psql -U postgres -d mbs_comunicaciones -f ../database/09_fix_carrito.sql
   psql -U postgres -d mbs_comunicaciones -f ../database/10_mercadopago_metodo.sql
   ```

2. **Eliminar `test-login.html`** antes de producción.

3. **Corregir encoding de `recuperar-password.html`** (abrir en VS Code, buscar caracteres `Ã` y reemplazar).

4. **Agregar scripts 08, 09, 10 al CLAUDE.md** para que estén documentados.

5. **Resolver MP en Edge** — agregar excepciones de Tracking Prevention o instalar Chrome.
