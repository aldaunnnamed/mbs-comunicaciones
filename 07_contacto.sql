-- Tabla para mensajes de contacto del formulario web
CREATE TABLE IF NOT EXISTS mensajes_contacto (
  id          SERIAL        PRIMARY KEY,
  nombre      VARCHAR(120)  NOT NULL,
  empresa     VARCHAR(120),
  email       VARCHAR(200)  NOT NULL,
  telefono    VARCHAR(30),
  asunto      VARCHAR(60)   NOT NULL,
  mensaje     TEXT          NOT NULL,
  leido       BOOLEAN       NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- Tabla para tokens de recuperación de contraseña
CREATE TABLE IF NOT EXISTS password_resets (
  id          SERIAL        PRIMARY KEY,
  usuario_id  INT           NOT NULL UNIQUE REFERENCES usuarios(id) ON DELETE CASCADE,
  token       VARCHAR(64)   NOT NULL,
  expira_at   TIMESTAMPTZ   NOT NULL,
  usado       BOOLEAN       NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
