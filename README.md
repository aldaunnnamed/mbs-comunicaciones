# MBS Comunicaciones

E-commerce de insumos de fibra óptica. Este repositorio contiene el **esquema de base de datos PostgreSQL**, la documentación del proyecto y los mockups de las interfaces. El código del backend (API + frontend estático) vive en un repositorio aparte: **[mbs-backend](https://github.com/aldaunnnamed/mbs-backend)**.

## Contenido de este repositorio

```
00_drop_functions.sql           → Elimina funciones previas (opcional, antes de 02)
01_schema.sql                   → Tablas, índices, triggers
02_functions.sql                → Funciones / stored procedures (fn_*)
03_seed_data.sql                → Datos iniciales y de prueba
04_examples.sql                 → SELECTs de ejemplo (solo referencia)
05_pagos.sql                    → Módulo de pagos: PayPal y SPEI
06_imagenes.sql                 → Índices de producto_imagenes (opcional)
07_contacto.sql                 → Tablas de contacto y recuperación de contraseña
migracion_fix_duplicados_seed.sql → Migración puntual sobre datos sembrados
CHECK_firmas.sql                → Consultas para verificar firmas de funciones
MBS_DB_README.md                → Documentación completa del esquema y funciones
mbs_interfaces_admin/           → Mockups (PDF) del panel de administración
mbs_interfaces_cliente/         → Mockups (PDF) de las vistas de cliente
```

## Orden de ejecución de los scripts SQL

> Requiere **PostgreSQL 14+** con la extensión `unaccent`.

```bash
psql -U postgres -d mbs_comunicaciones -f 01_schema.sql
psql -U postgres -d mbs_comunicaciones -f 02_functions.sql
psql -U postgres -d mbs_comunicaciones -f 03_seed_data.sql
psql -U postgres -d mbs_comunicaciones -f 05_pagos.sql
psql -U postgres -d mbs_comunicaciones -f 06_imagenes.sql
psql -U postgres -d mbs_comunicaciones -f 07_contacto.sql
```

- `00_drop_functions.sql` solo se usa para reinstalar `02_functions.sql` sin recrear el esquema.
- `04_examples.sql` es de referencia, no se ejecuta en producción.

Ver **[MBS_DB_README.md](./MBS_DB_README.md)** para el diagrama de tablas, el catálogo completo de funciones `fn_*` y el flujo de compra.

## Documentación

- [MBS_DB_README.md](./MBS_DB_README.md) — esquema, funciones y flujo de negocio.
- [CLAUDE.md](./CLAUDE.md) — guía de desarrollo (comandos, arquitectura, convenciones).
- [mbs_interfaces_admin/](./mbs_interfaces_admin) y [mbs_interfaces_cliente/](./mbs_interfaces_cliente) — mockups de diseño.
