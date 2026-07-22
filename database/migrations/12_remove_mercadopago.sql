-- ================================================================
--  MBS COMUNICACIONES — Script 12: Eliminar Mercado Pago
--  Ejecutar: psql -U postgres -d mbs_comunicaciones -f database/12_remove_mercadopago.sql
-- ================================================================

-- Eliminar método de pago Mercado Pago
DELETE FROM metodos_pago WHERE clave = 'mercadopago';

-- Eliminar claves de configuración de Mercado Pago
DELETE FROM configuracion WHERE clave IN ('mp_mode', 'mp_pk_test', 'mp_at_test', 'mp_pk_live', 'mp_at_live');
