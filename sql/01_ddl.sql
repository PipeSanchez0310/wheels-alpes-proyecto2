CREATE TABLE estudiantes (
    id_estudiante    NUMBER(10)      NOT NULL,
    nombre           VARCHAR2(80)    NOT NULL,
    apellidos        VARCHAR2(80)    NOT NULL,
    universidad      VARCHAR2(120),
    programa         VARCHAR2(120),
    correo           VARCHAR2(120)   NOT NULL,
    celular          VARCHAR2(20)    NOT NULL,
    tipo_documento   VARCHAR2(4)     NOT NULL,
    numero_documento VARCHAR2(20)    NOT NULL,
    clave_hash       VARCHAR2(64),
    CONSTRAINT estudiantes_pk PRIMARY KEY (id_estudiante)
);

CREATE TABLE vehiculos (
    placa         VARCHAR2(10)  NOT NULL,
    marca         VARCHAR2(60)  NOT NULL,
    modelo        VARCHAR2(60)  NOT NULL,
    anio          NUMBER(4)     NOT NULL,
    color         VARCHAR2(40)  NOT NULL,
    cupos         NUMBER(2)     NOT NULL,
    id_estudiante NUMBER(10)    NOT NULL,
    CONSTRAINT vehiculos_pk PRIMARY KEY (placa),
    CONSTRAINT vehiculos_estudiantes_fk FOREIGN KEY (id_estudiante)
        REFERENCES estudiantes (id_estudiante)
);

CREATE TABLE zonas (
    codigo_postal NUMBER(10)    NOT NULL,
    nombre        VARCHAR2(80)  NOT NULL,
    CONSTRAINT zonas_pk PRIMARY KEY (codigo_postal)
);

CREATE TABLE viajes (
    id_viaje             NUMBER(10)      NOT NULL,
    placa_vehiculo       VARCHAR2(10)    NOT NULL,
    fecha_hora_salida    DATE            NOT NULL,
    punto_origen         VARCHAR2(200)   NOT NULL,
    ruta_general         VARCHAR2(400)   NOT NULL,
    cupos                NUMBER(2)       NOT NULL,
    tarifa               NUMBER(10,2)    NOT NULL,
    estado               VARCHAR2(20)    NOT NULL,
    tiempo_viaje_minutos NUMBER(5),
    distancia            NUMBER(8,2),
    CONSTRAINT viajes_pk PRIMARY KEY (id_viaje),
    CONSTRAINT viajes_vehiculos_fk FOREIGN KEY (placa_vehiculo)
        REFERENCES vehiculos (placa)
);

CREATE TABLE paradas (
    id_viaje           NUMBER(10)      NOT NULL,
    numero_parada      NUMBER(3)       NOT NULL,
    direccion          VARCHAR2(200)   NOT NULL,
    codigo_postal_zona NUMBER(10)      NOT NULL,
    CONSTRAINT paradas_pk PRIMARY KEY (id_viaje, numero_parada),
    CONSTRAINT paradas_viajes_fk FOREIGN KEY (id_viaje)
        REFERENCES viajes (id_viaje),
    CONSTRAINT paradas_zonas_fk FOREIGN KEY (codigo_postal_zona)
        REFERENCES zonas (codigo_postal)
);

CREATE TABLE solicitudes (
    id_solicitud     NUMBER(10)      NOT NULL,
    id_viaje         NUMBER(10)      NOT NULL,
    numero_parada    NUMBER(3)       NOT NULL,
    id_estudiante    NUMBER(10)      NOT NULL,
    estado_solicitud VARCHAR2(20)    NOT NULL,
    fecha_solicitud  DATE            NOT NULL,
    CONSTRAINT solicitudes_pk PRIMARY KEY (id_solicitud),
    CONSTRAINT solicitudes_paradas_fk FOREIGN KEY (id_viaje, numero_parada)
        REFERENCES paradas (id_viaje, numero_parada),
    CONSTRAINT solicitudes_estudiantes_fk FOREIGN KEY (id_estudiante)
        REFERENCES estudiantes (id_estudiante)
);