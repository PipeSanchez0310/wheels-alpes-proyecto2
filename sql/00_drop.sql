-- Wheels Alpes -- Entrega 2 -- 00_drop.sql
-- Borra todo lo del proyecto para poder correr 01 y 02 desde cero.
-- Si un objeto no existe, lo salta sin error.

BEGIN
    FOR o IN (
        SELECT 'TABLE' tipo, 'SOLICITUDES' nombre FROM dual UNION ALL
        SELECT 'TABLE', 'PARADAS'     FROM dual UNION ALL
        SELECT 'TABLE', 'VIAJES'      FROM dual UNION ALL
        SELECT 'TABLE', 'VEHICULOS'   FROM dual UNION ALL
        SELECT 'TABLE', 'ZONAS'       FROM dual UNION ALL
        SELECT 'TABLE', 'ESTUDIANTES' FROM dual UNION ALL
        SELECT 'PACKAGE', 'WA_SEGURIDAD' FROM dual UNION ALL
        SELECT 'PACKAGE', 'WA_CTX'    FROM dual
    ) LOOP
        BEGIN
            IF o.tipo = 'TABLE' THEN
                EXECUTE IMMEDIATE 'DROP TABLE ' || o.nombre || ' CASCADE CONSTRAINTS PURGE';
            ELSE
                EXECUTE IMMEDIATE 'DROP PACKAGE ' || o.nombre;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                IF SQLCODE NOT IN (-942, -4043) THEN RAISE; END IF;
        END;
    END LOOP;
END;
/
