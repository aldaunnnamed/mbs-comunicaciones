# Fase 0 — Despliegue en Render + Neubox (dominio y correo)

Arquitectura elegida (julio 2026):

- **Render** → aplicación Node.js + base de datos PostgreSQL administrada (~$13–15 USD/mes).
- **Neubox** (hosting existente del cliente) → dominio, DNS y correo corporativo (SMTP).

El cPanel compartido de Neubox NO puede correr la app (es PHP + MySQL); solo se
usa para dominio/DNS/correo.

---

## 1. Preparación del repositorio (ya hecho / verificar)

- [x] `app.js` usa `process.env.PORT` y `trust proxy` — listo para Render.
- [x] `db.js` soporta SSL vía `DB_SSL=true` (ajuste aplicado en esta fase).
- [ ] Push del repo `mbs-backend` a GitHub con estos cambios.

## 2. Crear la base de datos en Render

1. Dashboard Render → **New → PostgreSQL**.
   - Nombre: `mbs-comunicaciones-db`, región: **Oregon (US West)** u **Ohio (US East)** (menor latencia a México: Ohio).
   - Plan: **Basic-256mb** (~$6/mes) — incluye backups diarios.
2. Anotar las credenciales (Host, Port, Database, Username, Password) de la
   sección *Connections*. Usar el **External Database URL** para cargar el esquema.
3. Cargar el esquema desde tu máquina (los 4 scripts, en orden):
   ```bash
   psql "<EXTERNAL_URL>" -f database/01_schema.sql
   psql "<EXTERNAL_URL>" -f database/02_functions.sql
   psql "<EXTERNAL_URL>" -f database/03_seed_data.sql
   psql "<EXTERNAL_URL>" -f database/05_pagos.sql
   ```
   Nota: `01_schema.sql` ejecuta `CREATE EXTENSION unaccent` — en Render está
   permitido (extensión *trusted* en PostgreSQL 14+). Si falla, correr antes:
   `CREATE EXTENSION IF NOT EXISTS unaccent;`

## 3. Crear el web service en Render

1. **New → Web Service** → conectar el repo GitHub `mbs-backend`.
2. Configuración:
   - Runtime: **Node**
   - Build command: `npm install`
   - Start command: `npm start`
   - Plan: **Starter** ($7/mes) — siempre encendido (el Free se duerme; inaceptable para webhooks de pago).
   - Región: la MISMA que la BD (para usar el hostname interno, más rápido y sin costo de egreso).
3. Variables de entorno (usar las credenciales **internas** de la BD):
   ```
   NODE_ENV=production
   APP_URL=https://www.dominiodelcliente.mx      ← sin / final
   DB_HOST=<hostname interno de Render>
   DB_PORT=5432
   DB_NAME=<database>
   DB_USER=<username>
   DB_PASSWORD=<password>
   DB_SSL=true
   JWT_SECRET=<generar nuevo: openssl rand -hex 32>   ← NO reutilizar el de desarrollo
   JWT_EXPIRES_IN=7d
   SMTP_HOST=<servidor de correo Neubox, p.ej. mail.dominiodelcliente.mx>
   SMTP_PORT=465
   SMTP_SECURE=true
   SMTP_USER=no-reply@dominiodelcliente.mx
   SMTP_PASS=<contraseña de la cuenta creada en cPanel>
   SMTP_FROM=MBS Comunicaciones <no-reply@dominiodelcliente.mx>
   PAYPAL_MODE=live
   PAYPAL_CLIENT_ID=            ← Fase 2
   PAYPAL_SECRET=               ← Fase 2
   PAYPAL_WEBHOOK_ID=           ← Fase 2
   ```
   (PORT lo inyecta Render automáticamente — no definirlo.)

## 4. Disco persistente para imágenes de producto

Multer guarda las imágenes en `public/uploads/productos`. Sin disco, se
**pierden en cada deploy**.

1. En el web service → **Disks → Add Disk**:
   - Mount path: `/opt/render/project/src/public/uploads`
   - Tamaño: 1 GB para empezar ($0.25/mes; ampliable).
2. Después del primer deploy, subir el logo desde el panel admin (o copiar
   `uploads/logo/` manualmente vía un deploy inicial, ya que el disco "tapa"
   el contenido del repo en esa ruta).

## 5. Correo en Neubox (cPanel)

1. cPanel → **Cuentas de correo electrónico** → crear `no-reply@dominiodelcliente.mx`.
2. Anotar host SMTP/puerto que indique Neubox (usualmente `mail.<dominio>` : 465 SSL).
3. Probar desde la app (formulario de contacto) una vez desplegada.

## 6. DNS en Neubox

1. Render → web service → **Settings → Custom Domains** → agregar
   `www.dominiodelcliente.mx` y el dominio raíz. Render indica los registros.
2. cPanel Neubox → **Editor de zona**:
   - `www` → CNAME → `<servicio>.onrender.com`
   - dominio raíz → registro A/ALIAS al valor que indique Render.
   - **NO tocar** los registros MX ni `mail` (el correo se queda en Neubox).
3. Esperar propagación; Render emite el certificado TLS automáticamente.

## 7. Verificación de fin de fase

- [ ] `https://www.dominiodelcliente.mx` carga el home con candado (TLS válido).
- [ ] `/admin` accesible y login admin funciona.
- [ ] Crear un producto de prueba con imagen desde el admin → re-deploy manual → la imagen sigue existiendo (disco persistente OK).
- [ ] Formulario de contacto envía correo (SMTP Neubox OK).
- [ ] El sitio local y ngrok quedan solo para desarrollo.

Con esto se cierra Fase 0 y se puede pasar a Fase 1 (seguridad: CORS, CSP,
`npm audit`) y Fase 2 (credenciales Live de pagos + webhooks apuntando al
dominio real).
