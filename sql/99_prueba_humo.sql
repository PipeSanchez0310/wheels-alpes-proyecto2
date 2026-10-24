-- Wheels Alpes -- Entrega 2 -- 99_prueba_humo.sql
-- Prueba rapida de que 01_ddl.sql y 02_triggers.sql quedaron bien.
-- Crea datos minimos, intenta cada regla y deshace todo al final (ROLLBACK).
-- En SQL Workshop > SQL Commands: pegarlo, Run, y leer la salida.
-- Cada linea debe decir OK. Si alguna dice FALLA, la regla no esta funcionando.

DECLARE
    v_conductor NUMBER;
    v_pasajero  NUMBER;
    v_pasajero2 NUMBER;
    v_viaje     NUMBER;
    v_viaje_hoy NUMBER;
    v_sol       NUMBER;
    v_sol2      NUMBER;

    PROCEDURE ok ( p_caso VARCHAR2 ) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('OK     ' || p_caso);
    END;

    -- Corre p_sql y verifica que falle con el codigo p_codigo.
    PROCEDURE debe_fallar ( p_caso VARCHAR2, p_sql VARCHAR2, p_codigo NUMBER ) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
        DBMS_OUTPUT.PUT_LINE('FALLA  ' || p_caso || ' (la base lo acepto)');
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = p_codigo THEN
                ok(p_caso || ' -> ' || SQLCODE);
            ELSE
                DBMS_OUTPUT.PUT_LINE('FALLA  ' || p_caso || ' (esperaba ' || p_codigo
                                     || ', salio ' || SQLERRM || ')');
            END IF;
    END;
BEGIN
    -- Datos base ------------------------------------------------------------
    INSERT INTO zonas VALUES (110111, 'Prueba Chapinero');

    INSERT INTO estudiantes (nombre, apellidos, universidad, programa, correo,
                             celular, tipo_documento, numero_documento)
    VALUES ('Cata', 'Conductora', 'Uniandes', 'Sistemas', 'cata.humo@uniandes.edu.co',
            '3000000001', 'CC', 'HUMO-1')
    RETURNING id_estudiante INTO v_conductor;

    INSERT INTO estudiantes (nombre, apellidos, correo, celular, tipo_documento, numero_documento)
    VALUES ('Pao', 'Pasajera', 'pao.humo@uniandes.edu.co', '3000000002', 'CC', 'HUMO-2')
    RETURNING id_estudiante INTO v_pasajero;

    INSERT INTO estudiantes (nombre, apellidos, correo, celular, tipo_documento, numero_documento)
    VALUES ('Pepe', 'Pasajero', 'pepe.humo@uniandes.edu.co', '3000000003', 'CC', 'HUMO-3')
    RETURNING id_estudiante INTO v_pasajero2;

    INSERT INTO vehiculos VALUES ('HUM001', 'Mazda', '3', 2020, 'Gris', 3, v_conductor);

    -- Viaje en 2 dias, 1 cupo, para probar cupos y cancelaciones.
    INSERT INTO viajes (placa_vehiculo, fecha_hora_salida, punto_origen, ruta_general, cupos, tarifa)
    VALUES ('HUM001', SYSDATE + 2, 'Calle 85', 'Calle 85 - Uniandes', 1, 6000)
    RETURNING id_viaje INTO v_viaje;
    INSERT INTO paradas VALUES (v_viaje, 1, 'Cra 7 # 72', 110111);
    ok('datos base insertados');

    -- CHECK (ORA-02290) -----------------------------------------------------
    debe_fallar('CK tarifa negativa',
        q'[INSERT INTO viajes (placa_vehiculo, fecha_hora_salida, punto_origen, ruta_general, cupos, tarifa)
           VALUES ('HUM001', SYSDATE+1, 'x', 'x', 1, -1)]', -2290);
    debe_fallar('CK cupos del viaje = 0',
        q'[INSERT INTO viajes (placa_vehiculo, fecha_hora_salida, punto_origen, ruta_general, cupos, tarifa)
           VALUES ('HUM001', SYSDATE+1, 'x', 'x', 0, 1000)]', -2290);
    debe_fallar('CK estado de viaje invalido',
        q'[INSERT INTO viajes (placa_vehiculo, fecha_hora_salida, punto_origen, ruta_general, cupos, tarifa, estado)
           VALUES ('HUM001', SYSDATE+1, 'x', 'x', 1, 1000, 'pausado')]', -2290);
    -- Los triggers BEFORE corren antes que las CHECK; con la regla RF10 activa
    -- saldria -20012 en vez de -2290. Se apaga solo para ver la CHECK.
    wa_ctx.g_carga_historica := TRUE;
    debe_fallar('CK estado de solicitud invalido',
        q'[INSERT INTO solicitudes (id_viaje, numero_parada, id_estudiante, estado_solicitud)
           VALUES (]' || v_viaje || ', 1, ' || v_pasajero || q'[, 'confirmada')]', -2290);
    wa_ctx.g_carga_historica := FALSE;
    debe_fallar('CK correo en mayusculas',
        q'[INSERT INTO estudiantes (nombre, apellidos, correo, celular, tipo_documento, numero_documento)
           VALUES ('a','b','Mayus@uniandes.edu.co','1','CC','HUMO-9')]', -2290);

    -- UNIQUE (ORA-00001) y FK (ORA-02291) -----------------------------------
    debe_fallar('UN correo repetido',
        q'[INSERT INTO estudiantes (nombre, apellidos, correo, celular, tipo_documento, numero_documento)
           VALUES ('a','b','pao.humo@uniandes.edu.co','1','CC','HUMO-8')]', -1);
    debe_fallar('FK vehiculo con dueno inexistente',
        q'[INSERT INTO vehiculos VALUES ('HUM999','Kia','Rio',2019,'Rojo',3,-1)]', -2291);
    debe_fallar('FK solicitud a parada que no existe',
        q'[INSERT INTO solicitudes (id_viaje, numero_parada, id_estudiante)
           VALUES (]' || v_viaje || ', 9, ' || v_pasajero || ')', -2291);

    -- Triggers --------------------------------------------------------------
    debe_fallar('C6 cupos del viaje > cupos del vehiculo',
        q'[UPDATE viajes SET cupos = 4 WHERE id_viaje = ]' || v_viaje, -20001);
    debe_fallar('D4 conductor pide cupo en su viaje',
        q'[INSERT INTO solicitudes (id_viaje, numero_parada, id_estudiante)
           VALUES (]' || v_viaje || ', 1, ' || v_conductor || ')', -20011);
    debe_fallar('RF10 solicitud nueva ya aceptada',
        q'[INSERT INTO solicitudes (id_viaje, numero_parada, id_estudiante, estado_solicitud)
           VALUES (]' || v_viaje || ', 1, ' || v_pasajero || q'[, 'aceptada')]', -20012);

    INSERT INTO solicitudes (id_viaje, numero_parada, id_estudiante)
    VALUES (v_viaje, 1, v_pasajero) RETURNING id_solicitud INTO v_sol;
    INSERT INTO solicitudes (id_viaje, numero_parada, id_estudiante)
    VALUES (v_viaje, 1, v_pasajero2) RETURNING id_solicitud INTO v_sol2;
    ok('RF10 dos solicitudes pendientes creadas');

    debe_fallar('C14 segunda solicitud viva del mismo pasajero',
        q'[INSERT INTO solicitudes (id_viaje, numero_parada, id_estudiante)
           VALUES (]' || v_viaje || ', 1, ' || v_pasajero || ')', -1);

    UPDATE solicitudes SET estado_solicitud = 'aceptada' WHERE id_solicitud = v_sol;
    ok('RF4 primera solicitud aceptada');
    debe_fallar('RF4 aceptar con el viaje lleno (1 cupo)',
        q'[UPDATE solicitudes SET estado_solicitud = 'aceptada' WHERE id_solicitud = ]' || v_sol2, -20016);
    debe_fallar('C11 aceptada -> pendiente no vale',
        q'[UPDATE solicitudes SET estado_solicitud = 'pendiente' WHERE id_solicitud = ]' || v_sol, -20013);

    UPDATE solicitudes SET estado_solicitud = 'cancelada' WHERE id_solicitud = v_sol;
    ok('RF11 cancelar solicitud con 2 dias de anticipacion');

    debe_fallar('RF5 programado -> completado salta en curso',
        q'[UPDATE viajes SET estado = 'completado', tiempo_viaje_minutos = 30, distancia = 10
           WHERE id_viaje = ]' || v_viaje, -20003);

    -- Cancelacion del viaje con cascada sobre la solicitud pendiente.
    UPDATE viajes SET estado = 'cancelado' WHERE id_viaje = v_viaje;
    FOR r IN (SELECT estado_solicitud FROM solicitudes WHERE id_solicitud = v_sol2) LOOP
        IF r.estado_solicitud = 'cancelada' THEN
            ok('RF5 cancelar viaje cancela sus solicitudes vivas');
        ELSE
            DBMS_OUTPUT.PUT_LINE('FALLA  cascada: la solicitud quedo ' || r.estado_solicitud);
        END IF;
    END LOOP;
    debe_fallar('RF5 viaje cancelado no cambia mas',
        q'[UPDATE viajes SET estado = 'programado' WHERE id_viaje = ]' || v_viaje, -20002);

    -- Regla de las 2 horas: viaje que sale en 1 hora.
    INSERT INTO viajes (placa_vehiculo, fecha_hora_salida, punto_origen, ruta_general, cupos, tarifa)
    VALUES ('HUM001', SYSDATE + 1/24, 'Calle 85', 'Calle 85 - Uniandes', 2, 6000)
    RETURNING id_viaje INTO v_viaje_hoy;
    INSERT INTO paradas VALUES (v_viaje_hoy, 1, 'Cra 7 # 72', 110111);
    INSERT INTO solicitudes (id_viaje, numero_parada, id_estudiante)
    VALUES (v_viaje_hoy, 1, v_pasajero) RETURNING id_solicitud INTO v_sol;
    UPDATE solicitudes SET estado_solicitud = 'aceptada' WHERE id_solicitud = v_sol;

    debe_fallar('RF11 cancelar solicitud a 1 hora de la salida',
        q'[UPDATE solicitudes SET estado_solicitud = 'cancelada' WHERE id_solicitud = ]' || v_sol, -20014);
    debe_fallar('RF5 cancelar viaje a 1 hora de la salida',
        q'[UPDATE viajes SET estado = 'cancelado' WHERE id_viaje = ]' || v_viaje_hoy, -20004);

    UPDATE viajes SET estado = 'en curso' WHERE id_viaje = v_viaje_hoy;
    ok('RF5 programado -> en curso');
    debe_fallar('CK completar sin tiempo ni distancia',
        q'[UPDATE viajes SET estado = 'completado' WHERE id_viaje = ]' || v_viaje_hoy, -2290);
    UPDATE viajes SET estado = 'completado', tiempo_viaje_minutos = 35, distancia = 12.5
     WHERE id_viaje = v_viaje_hoy;
    ok('RF5 en curso -> completado');
    debe_fallar('RF10 solicitar en un viaje completado',
        q'[INSERT INTO solicitudes (id_viaje, numero_parada, id_estudiante)
           VALUES (]' || v_viaje_hoy || ', 1, ' || v_pasajero2 || ')', -20010);

    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('-- fin: todo deshecho con ROLLBACK');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        wa_ctx.g_carga_historica := FALSE;
        DBMS_OUTPUT.PUT_LINE('ERROR INESPERADO: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
END;
/
