# CLAUDE.md
Responde siempre en español

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

All backend commands must be run from `mbs_backend/`:

```bash
# Install dependencies
npm install

# Start production server
npm start          # node src/app.js

# Start dev server (auto-restart on change)
npm run dev        # nodemon src/app.js
```

### Tests

```bash
npm test           # jest --runInBand
```

Tests live in `mbs_backend/tests/` (Jest + Supertest) and run against the real Express app (`require('../src/app')`, which only calls `app.listen` when run directly — see `if (require.main === module)` in `app.js`) and the configured PostgreSQL database from `.env`. There is no separate test database; tests create their own throwaway users (`test_<timestamp>@mbs.mx`) and rely on existing seed data (e.g. `admin@mbs.mx` / `Admin@MBS2025`, the `cable-fo-monomodo-sc-upc-3mm` product) from `03_seed_data.sql`. Run `--runInBand` to avoid concurrent connections racing on shared rows.

**Current state: 93/93 tests passing** (9 suites: auth, admin, productos, carrito, pedidos, usuarios, resenas, contacto, pagos.paypal).

Test isolation notes:
- Product tests (`admin.test.js`) use `TEST-ADMIN-${Date.now()}` for both SKU and name to avoid slug collisions across runs — the DB is not cleaned between runs.
- `fn_confirmar_pago_paypal` idempotency check requires `05_pagos.sql` to be applied (the function in the DB must be up to date). Re-run `05_pagos.sql` if this test fails after a DB reset.
- Jest reports an open-handles warning after the suite — benign, caused by the pg pool not being closed between test files.

### Database setup (PostgreSQL 14+, extension `unaccent` required)

Run scripts in this exact order — they have dependencies:

```bash
psql -U postgres -d mbs_comunicaciones -f database/01_schema.sql
psql -U postgres -d mbs_comunicaciones -f database/02_functions.sql
psql -U postgres -d mbs_comunicaciones -f database/03_seed_data.sql
psql -U postgres -d mbs_comunicaciones -f database/05_pagos.sql
psql -U postgres -d mbs_comunicaciones -f database/06_imagenes.sql
psql -U postgres -d mbs_comunicaciones -f database/07_contacto.sql
psql -U postgres -d mbs_comunicaciones -f database/08_pagos_metodos.sql
# database/04_examples.sql is reference only — do not run in production
```

- `05_pagos.sql` adds the PayPal/SPEI payment tables, the parallel Stripe `customer_balance` SPEI flow (dynamic CLABE, selectable via the `spei_motor` config key: `legacy` | `stripe`), and manual payment confirmation (`fn_marcar_pedido_pagado_manual`) — required for `/api/pagos`.
- `06_imagenes.sql` is optional: only adds indexes on `producto_imagenes` (the table already exists in `01_schema.sql`).
- `07_contacto.sql` creates `mensajes_contacto` and `password_resets` — **required** for password recovery, the contact form, and the admin "Mensajes" panel.
- `08_pagos_metodos.sql` seeds only the payment-gateway configuration (Stripe/PayPal keys in `configuracion`) — the `metodos_pago` rows themselves are seeded once, in `03_seed_data.sql`, to avoid duplicate rows for the same payment method under two different `clave`s.

Other SQL files (not part of the setup sequence):
- `database/migrations/13_drop_tablas_huerfanas.sql` — already applied; dropped the unused `sesiones`, `recuperacion_password`, `tarjetas_guardadas` tables. Kept for historical reference only.
- `database/migrations/14_drop_blog_cotizaciones_cupones_newsletter.sql` — already applied; dropped 9 tables and 5 functions (blog/CMS, cotizaciones, cupones, newsletter) plus the `cupon_id` columns on `carritos`/`pedidos` — all schema drift never defined in any versioned script. Kept for historical reference only.
- `database/tools/CHECK_firmas.sql` — diagnostic: verifies stored function signatures
- `database/12_remove_mercadopago.sql` — removes MercadoPago references (already applied; kept for historical reference only)

To reset functions without dropping schema:

```bash
psql -U postgres -d mbs_comunicaciones -f database/00_drop_functions.sql
psql -U postgres -d mbs_comunicaciones -f database/02_functions.sql
```

### Environment

Copy `mbs_backend/.env.example` to `mbs_backend/.env` and fill in values. Required keys: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `JWT_SECRET`, `JWT_EXPIRES_IN`. PayPal keys can remain empty until needed.

---

## Project structure

```
MBS_COMUNICACIONES/
├── CLAUDE.md / README.md / .gitignore
├── iniciar_con_ngrok.bat        — starts ngrok + Node server together
├── iniciar_servidor.bat         — starts Node server only
├── database/
│   ├── 00_drop_functions.sql … 08_pagos_metodos.sql, 12_remove_mercadopago.sql
│   ├── migrations/              — one-off scripts, already applied (run manually if reverting)
│   └── tools/                   — diagnostic queries (CHECK_firmas.sql)
├── docs/
│   ├── MBS_DB_README.md         — full stored-function reference
│   ├── MBS_Documentacion_BD_v2.docx
│   ├── AUDITORIA_PROYECTO.md
│   ├── Manual_Usuario_Admin_MBS_v2.0.docx   — current admin manual
│   ├── Manual_Usuario_Cliente_MBS_v1.0.docx — current client-portal manual
│   ├── archivo/                 — superseded docs, kept for history (old admin v1.0 Beta + old combined v2.0 manual)
│   ├── qa/                      — user stories, use cases, test cases (xlsx)
│   └── interfaces/
│       ├── admin/               — wireframe PDFs for admin panel
│       └── cliente/             — wireframe PDFs for storefront
└── mbs_backend/                 — Node.js app (has its own git repo)
    ├── src/                     — live application code
    ├── public/                  — static frontend
    ├── tests/                   — Jest + Supertest
    ├── scripts/                 — utility scripts (fix-imagenes-principal.js)
    └── logs/                    — runtime logs (gitignored)
```

---

## Architecture

### Overview

This is a full-stack e-commerce for fiber optic products. Express serves both the REST API (`/api/*`) and the static HTML frontend from `mbs_backend/public/`. Business logic is split between thin Node.js controllers and PostgreSQL stored functions.

### Backend (`mbs_backend/src/`)

```
app.js               — Entry point: middleware, static files, route mounting, error handler
config/db.js         — pg Pool; exports query(text, params) helper used everywhere
middlewares/auth.js  — verificarToken, soloAdmin, tokenOpcional
middlewares/upload.js — multer: uploadImage (product photos → public/uploads/productos), uploadCsv (memory)
controllers/         — One file per domain; each function maps to one route
routes/              — Router files; wire HTTP verbs to controller functions
services/            — factura.service.js: generates printable HTML invoice
```

**Controller pattern:** All controllers call `query()` directly — there is no service layer between controllers and the database. Most complex operations delegate to a stored function via `SELECT * FROM fn_nombre(...)`. Inline SQL (not stored functions) is used only for simple direct queries.

**Auth flow:** JWT stored in `localStorage` (client) and sent as `Authorization: Bearer <token>`. The token payload is `{ id, email, rol }`. Anonymous cart sessions use `x-session-key` from `sessionStorage`.

**API response shape:** All endpoints return `{ ok: boolean, mensaje?: string, ...data }`.

### Route → Controller → DB mapping

| Prefix | Routes file | Controller | Notes |
|---|---|---|---|
| `/api/auth` | auth.routes.js | auth.controller.js | registro, login, perfil |
| `/api/productos` | productos.routes.js | productos.controller.js | catalog, categories, brands |
| `/api/carrito` | carrito.routes.js | carrito.controller.js | anonymous + authenticated carts |
| `/api/pedidos` | pedidos.routes.js | pedidos.controller.js | some routes inline in router file |
| `/api/usuarios` | usuarios.routes.js | — | all logic inline in router file |
| `/api/admin` | admin.routes.js | admin.controller.js | requires `verificarToken + soloAdmin` |
| `/api/pagos` | pagos.routes.js | pagos.controller.js | SPEI, PayPal (Orders v2), Stripe (PaymentIntents) |
| `/api/contacto` | contacto.routes.js | — | all logic inline, like usuarios.routes.js — inserts into `mensajes_contacto` |

### Database (`database/01_schema.sql`, `database/02_functions.sql`)

The schema owns most business logic through stored functions prefixed `fn_`. Controllers call them with explicit `CAST($N AS TYPE)` to avoid type coercion issues.

Key stored functions:
- `fn_crear_pedido(...)` — transactional checkout: stock validation, price snapshot, inventory movement, coupon consumption, cart cleanup, notification
- `fn_listar_productos(...)` — full-text search via `tsvector` field (`fts`) with `unaccent` support
- `fn_carrito_agregar_item(usuario_id, session_key, ...)` — supports both auth and anonymous sessions

Full function reference is in `docs/MBS_DB_README.md`.

### Frontend (`mbs_backend/public/`)

Static HTML pages, no build step. `public/js/global.js` is loaded on every page and provides: `apiFetch()` wrapper, JWT/session helpers, cart badge updater, navbar auth state, and toast notifications. Each page has its own JS file in `public/js/`.

MXN/USD dual-currency display fetches a public exchange rate API on page load.

### Known issues to be aware of

- **Malformed directories:** `mbs_backend/{src` and `mbs_backend/src/{config,controllers,...}` are filesystem artifacts from a failed shell expansion — ignore them.
- **Encoding:** Some source files contain garbled UTF-8 characters (`Ã³`, `â€"`, etc.) in string literals. Fix the file encoding before editing those strings.
- **Payment credentials:** All payment credentials (PayPal, Stripe) are stored in the `configuracion` DB table and managed from the admin panel (Configuración > Pagos). They are NOT read from `.env`. Only SMTP and DB credentials go in `.env`.
- **ngrok:** use `iniciar_con_ngrok.bat` (repo root) to start both ngrok (static domain `underrate-silk-librarian.ngrok-free.dev`) and the Node server together. `APP_URL` in `.env` must match the public domain for payment return URLs.
