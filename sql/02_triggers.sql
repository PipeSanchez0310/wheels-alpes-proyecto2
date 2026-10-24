-- Wheels Alpes -- Entrega 2 -- 02_triggers.sql
-- Reglas de negocio que una CHECK no alcanza porque comparan filas de varias
-- tablas o dependen de la hora actual. Correr despues de 01_ddl.sql.
--
-- Codigos de error (RAISE_APPLICATION_ERROR). La app APEX muestra el mensaje.
--   -20001  C6   los cupos del viaje superan los del vehiculo
--   -20002  RF5  el viaje ya esta completado o cancelado
--   -20003  RF5  transicion de estado del viaje no valida
--   -20004  RF5  cancelacion del viaje con menos de 2 horas
--   -20010  RF10 el viaje no esta programado
--   -20011  D4   el conductor solicita cupo en su propio viaje
--   -20012  RF10 una solicitud nueva debe nacer pendiente
--   -20013  RF4  transicion de estado de la solicitud no valida
--   -20014  RF11 cancelacion de la solicitud con menos de 2 horas
--   -20015  RF4  aceptar una solicitud de un viaje que no esta programado
--   -20016  RF4  las solicitudes aceptadas superan los cupos del viaje

-- ---------------------------------------------------------------------------
-- Paquete de contexto
--   g_cascada         lo prende el trigger de viajes mientras cancela las
--                     solicitudes del viaje. Evita ORA-04091 (tabla mutante):
--                     los triggers de solicitudes no deben leer viajes en ese
--                     momento.
--   g_carga_historica lo prende el script de poblacion (03_poblacion.sql) para
--                     poder insertar viajes y solicitudes del pasado ya en su
--                     estado final. Solo apaga las reglas de tiempo y de
--                     secuencia de estados; D4, cupos, CHECK y FK siguen
--                     activos.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE wa_ctx AS
    g_cascada         BOOLEAN := FALSE;
    g_carga_historica BOOLEAN := FALSE;
END wa_ctx;
/

-- ---------------------------------------------------------------------------
-- C6: viaje.cupos <= vehiculo.cupos
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER viajes_cupos_TRG
    BEFORE INSERT OR UPDATE OF cupos, placa_vehiculo ON viajes
    FOR EACH ROW
DECLARE
    v_cupos_vehiculo vehiculos.cupos%TYPE;
BEGIN
    SELECT cupos INTO v_cupos_vehiculo
      FROM vehiculos
     WHERE placa = :NEW.placa_vehiculo;

    IF :NEW.cupos > v_cupos_vehiculo THEN
        RAISE_APPLICATION_ERROR(-20001,
            'El viaje ofrece ' || :NEW.cupos || ' cupos y el vehiculo solo tiene '
            || v_cupos_vehiculo || '.');
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        NULL;  -- placa inexistente: la FK viajes_vehiculos_FK da el ORA-02291
END;
/

-- ---------------------------------------------------------------------------
-- RF5: secuencia de estados del viaje
--   programado -> en curso -> completado
--   programado | en curso -> cancelado, con al menos 2 horas de anticipacion
--   completado y cancelado son finales
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER viajes_estado_TRG
    BEFORE UPDATE OF estado ON viajes
    FOR EACH ROW
    WHEN ( NEW.estado <> OLD.estado )
BEGIN
    IF wa_ctx.g_carga_historica THEN
        RETURN;
    END IF;

    IF :OLD.estado IN ('completado','cancelado') THEN
        RAISE_APPLICATION_ERROR(-20002,
            'El viaje ya esta ' || :OLD.estado || ' y no puede cambiar de estado.');
    END IF;

    IF NOT (   (:OLD.estado = 'programado' AND :NEW.estado IN ('en curso','cancelado'))
            OR (:OLD.estado = 'en curso'   AND :NEW.estado IN ('completado','cancelado')) ) THEN
        RAISE_APPLICATION_ERROR(-20003,
            'No se puede pasar un viaje de ' || :OLD.estado || ' a ' || :NEW.estado || '.');
    END IF;

    IF :NEW.estado = 'cancelado' AND :OLD.fecha_hora_salida - SYSDATE < 2/24 THEN
        RAISE_APPLICATION_ERROR(-20004,
            'Un viaje solo se puede cancelar con al menos dos horas de anticipacion.');
    END IF;
END;
/

-- ---------------------------------------------------------------------------
-- RF5: al cancelar un viaje, sus solicitudes vivas quedan canceladas
-- ("En ese caso, las reservas de los pasajeros quedan canceladas").
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER viajes_cancelacion_TRG
    AFTER UPDATE OF estado ON viajes
    FOR EACH ROW
    WHEN ( NEW.estado = 'cancelado' AND OLD.estado <> 'cancelado' )
BEGIN
    wa_ctx.g_cascada := TRUE;
    UPDATE solicitudes
       SET estado_solicitud = 'cancelada'
     WHERE id_viaje = :NEW.id_viaje
       AND estado_solicitud IN ('pendiente','aceptada');
    wa_ctx.g_cascada := FALSE;
EXCEPTION
    WHEN OTHERS THEN
        wa_ctx.g_cascada := FALSE;
        RAISE;
END;
/

-- ---------------------------------------------------------------------------
-- Solicitudes: reglas por fila (RF10, D4, RF4, RF11)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER solicitudes_reglas_TRG
    BEFORE INSERT OR UPDATE OF estado_solicitud ON solicitudes
    FOR EACH ROW
DECLARE
    v_estado_viaje viajes.estado%TYPE;
    v_salida       viajes.fecha_hora_salida%TYPE;
    v_conductor    vehiculos.id_estudiante%TYPE;
BEGIN
    -- Cancelacion en cascada desde viajes: no leer viajes (tabla mutante).
    IF wa_ctx.g_cascada THEN
        RETURN;
    END IF;

    SELECT vi.estado, vi.fecha_hora_salida, ve.id_estudiante
      INTO v_estado_viaje, v_salida, v_conductor
      FROM viajes vi
      JOIN vehiculos ve ON ve.placa = vi.placa_vehiculo
     WHERE vi.id_viaje = :NEW.id_viaje;

    IF INSERTING THEN
        -- D4: aplica siempre, tambien en la carga historica.
        IF :NEW.id_estudiante = v_conductor THEN
            RAISE_APPLICATION_ERROR(-20011,
                'El conductor no puede solicitar cupo en su propio viaje.');
        END IF;

        IF NOT wa_ctx.g_carga_historica THEN
            IF v_estado_viaje <> 'programado' THEN
                RAISE_APPLICATION_ERROR(-20010,
                    'Solo se puede solicitar cupo en viajes programados.');
            END IF;
            IF :NEW.estado_solicitud <> 'pendiente' THEN
                RAISE_APPLICATION_ERROR(-20012,
                    'Una solicitud nueva debe quedar en estado pendiente.');
            END IF;
        END IF;

    ELSIF UPDATING AND :NEW.estado_solicitud <> :OLD.estado_solicitud
          AND NOT wa_ctx.g_carga_historica THEN
        -- C11: pendiente -> aceptada | rechazada ; aceptada -> cancelada
        IF NOT (   (:OLD.estado_solicitud = 'pendiente'
                    AND :NEW.estado_solicitud IN ('aceptada','rechazada'))
                OR (:OLD.estado_solicitud = 'aceptada'
                    AND :NEW.estado_solicitud = 'cancelada') ) THEN
            RAISE_APPLICATION_ERROR(-20013,
                'No se puede pasar una solicitud de ' || :OLD.estado_solicitud
                || ' a ' || :NEW.estado_solicitud || '.');
        END IF;

        IF :NEW.estado_solicitud = 'aceptada' AND v_estado_viaje <> 'programado' THEN
            RAISE_APPLICATION_ERROR(-20015,
                'Solo se aceptan solicitudes de viajes programados.');
        END IF;

        IF :NEW.estado_solicitud = 'cancelada' AND v_salida - SYSDATE < 2/24 THEN
            RAISE_APPLICATION_ERROR(-20014,
                'Una solicitud solo se puede cancelar con al menos dos horas de anticipacion.');
        END IF;
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        NULL;  -- viaje inexistente: la FK solicitudes_paradas_FK da el ORA-02291
END;
/

-- ---------------------------------------------------------------------------
-- RF4: aceptadas de un viaje <= viaje.cupos
-- Contar solicitudes desde un trigger de fila de solicitudes da ORA-04091, por
-- eso es compound: cada fila anota su viaje y el conteo se hace al final de la
-- sentencia, cuando la tabla ya no esta mutando.
-- Aplica siempre, tambien en la carga historica.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER solicitudes_cupos_TRG
    FOR INSERT OR UPDATE OF estado_solicitud ON solicitudes
    COMPOUND TRIGGER

    TYPE t_ids IS TABLE OF BOOLEAN INDEX BY PLS_INTEGER;
    g_viajes t_ids;

    AFTER EACH ROW IS
    BEGIN
        IF :NEW.estado_solicitud = 'aceptada' THEN
            g_viajes(:NEW.id_viaje) := TRUE;
        END IF;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
        v_id        PLS_INTEGER;
        v_cupos     viajes.cupos%TYPE;
        v_aceptadas NUMBER;
    BEGIN
        v_id := g_viajes.FIRST;
        WHILE v_id IS NOT NULL LOOP
            SELECT cupos INTO v_cupos FROM viajes WHERE id_viaje = v_id;
            SELECT COUNT(*) INTO v_aceptadas
              FROM solicitudes
             WHERE id_viaje = v_id AND estado_solicitud = 'aceptada';
            IF v_aceptadas > v_cupos THEN
                g_viajes.DELETE;
                RAISE_APPLICATION_ERROR(-20016,
                    'El viaje ' || v_id || ' ya tiene sus ' || v_cupos
                    || ' cupos ocupados.');
            END IF;
            v_id := g_viajes.NEXT(v_id);
        END LOOP;
        g_viajes.DELETE;
    END AFTER STATEMENT;

END solicitudes_cupos_TRG;
/
