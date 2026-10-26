-- Ejecutar UNA vez como superusuario (lo hace docker-compose automáticamente).
-- En Neon/Supabase/RDS crea estos roles desde la consola con sus propias contraseñas.
--
-- percha_owner  : dueño de las tablas. Corre migraciones.
-- percha_app    : lo usa la API para todo lo de negocio. RLS se le aplica siempre.
-- percha_system : miembro de percha_owner -> omite RLS. Solo para login, registro,
--                 refresh e invitaciones (búsquedas que cruzan tiendas).
CREATE ROLE percha_owner LOGIN PASSWORD 'owner_dev_pass';
CREATE ROLE percha_app LOGIN PASSWORD 'app_dev_pass' NOBYPASSRLS;
CREATE ROLE percha_system LOGIN PASSWORD 'system_dev_pass' IN ROLE percha_owner;
CREATE DATABASE percha OWNER percha_owner;
