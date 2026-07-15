# MBS Comunicaciones

E-commerce de insumos de fibra óptica. Este repositorio contiene el **esquema de base de datos PostgreSQL**, la documentación del proyecto y los mockups de las interfaces. El código del backend (API + frontend estático) vive en un repositorio aparte: **[mbs-backend](https://github.com/aldaunnnamed/mbs-backend)**.

## Contenido de este repositorio

```
database/
├── 00_drop_functions.sql           → Elimina funciones previas (opcional, antes de 02)
├── 01_schema.sql                   → Tablas, índices, triggers
├── 02_functions.sql                → Funciones / stored procedures (fn_*)
├── 03_seed_data.sql                → Datos iniciales y de prueba, incluye el seed único de metodos_pago
├── 04_examples.sql                 → SELECTs de ejemplo (solo referencia)
├── 05_pagos.sql                    → Módulo de pagos: PayPal, SPEI legacy y SPEI vía Stripe
├── 06_imagenes.sql                 → Índices de producto_imagenes (opcional)
├── 07_contacto.sql                 → Tablas de contacto y recuperación de contraseña
├── 08_pagos_metodos.sql            → Siembra solo la configuración de pasarelas (Stripe/PayPal)
├── migrations/                     → Migraciones puntuales ya aplicadas (histórico)
└── tools/CHECK_firmas.sql          → Consultas para verificar firmas de funciones
docs/
├── MBS_DB_README.md                → Documentación completa del esquema y funciones
└── MBS_Documentacion_BD_v2.docx    → Documentación del esquema (Word)
mbs_interfaces_admin/                → Mockups (PDF) del panel de administración
mbs_interfaces_cliente/              → Mockups (PDF) de las vistas de cliente
CLAUDE.md                            → Guía de desarrollo para Claude Code
```

## Orden de ejecución de los scripts SQL

> Requiere **PostgreSQL 14+** con la extensión `unaccent`.

```bash
psql -U postgres -d mbs_comunicaciones -f database/01_schema.sql
psql -U postgres -d mbs_comunicaciones -f database/02_functions.sql
psql -U postgres -d mbs_comunicaciones -f database/03_seed_data.sql
psql -U postgres -d mbs_comunicaciones -f database/05_pagos.sql
psql -U postgres -d mbs_comunicaciones -f database/06_imagenes.sql
psql -U postgres -d mbs_comunicaciones -f database/07_contacto.sql
psql -U postgres -d mbs_comunicaciones -f database/08_pagos_metodos.sql
```

- `database/00_drop_functions.sql` solo se usa para reinstalar `02_functions.sql` sin recrear el esquema.
- `database/04_examples.sql` es de referencia, no se ejecuta en producción.

Ver **[docs/MBS_DB_README.md](./docs/MBS_DB_README.md)** para el diagrama de tablas, el catálogo completo de funciones `fn_*` y el flujo de compra.

## Documentación

- [docs/MBS_DB_README.md](./docs/MBS_DB_README.md) — esquema, funciones y flujo de negocio.
- [CLAUDE.md](./CLAUDE.md) — guía de desarrollo (comandos, arquitectura, convenciones).
- [mbs_interfaces_admin/](./mbs_interfaces_admin) y [mbs_interfaces_cliente/](./mbs_interfaces_cliente) — mockups de diseño.
