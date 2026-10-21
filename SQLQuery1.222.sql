/* ============ ESQUEMA  ============ */
USE master;

--  Si la base de datos existe, la borra
IF DB_ID('MatriculaUniversitaria') IS NOT NULL
BEGIN
    ALTER DATABASE MatriculaUniversitaria SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE MatriculaUniversitaria;
END


-- Creamos la base de datos
CREATE DATABASE MatriculaUniversitaria;
--  Nos metemos en la base de datos
USE MatriculaUniversitaria;

PRINT 'Base de datos creada y seleccionada correctamente.';


--  para las pruebas de bloqueo
ALTER DATABASE MatriculaUniversitaria SET READ_COMMITTED_SNAPSHOT OFF WITH ROLLBACK IMMEDIATE;

-- Creamos las  tablas
CREATE TABLE Estudiantes (
    estudiante_id INT IDENTITY(1,1) PRIMARY KEY,
    cedula CHAR(10) NOT NULL UNIQUE
        CHECK (cedula NOT LIKE '%[^0-9]%'),
    nombre VARCHAR(100) NOT NULL,
    correo VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE Asignaturas (
    asignatura_id INT IDENTITY(1,1) PRIMARY KEY,
    codigo VARCHAR(10) NOT NULL UNIQUE,
    nombre VARCHAR(100) NOT NULL,
    cupos_disponibles SMALLINT NOT NULL
        CHECK (cupos_disponibles >= 0)
);

CREATE TABLE Registros_Matricula (
    registro_id INT IDENTITY(1,1) PRIMARY KEY,
    estudiante_id INT NOT NULL,
    asignatura_id INT NOT NULL,
    fecha_matricula DATETIME NOT NULL DEFAULT GETDATE(),
    estado VARCHAR(10) NOT NULL
        CHECK (estado IN ('CONFIRMADA','PENDIENTE')),
    CONSTRAINT FK_Reg_Est FOREIGN KEY (estudiante_id)
        REFERENCES Estudiantes(estudiante_id),
    CONSTRAINT FK_Reg_Asig FOREIGN KEY (asignatura_id)
        REFERENCES Asignaturas(asignatura_id),
    CONSTRAINT UQ_Est_Asig UNIQUE (estudiante_id, asignatura_id)
);

CREATE NONCLUSTERED INDEX IX_Registros_asignatura
    ON Registros_Matricula(asignatura_id);

-- insertamos datox
INSERT INTO Estudiantes (cedula, nombre, correo) VALUES
('0102030405','Ana Pérez','ana@uni.edu'),
('0102030406','Luis Gómez','luis@uni.edu'),
('0102030407','Carla Ruiz','carla@uni.edu'),
('0102030408','Diego Mora','diego@uni.edu');

INSERT INTO Asignaturas (codigo, nombre, cupos_disponibles) VALUES
('BD101','Base de Datos',5),
('PRG201','Programación Avanzada',4),
('ML301','Machine Learning 1',3),
('META401','Metaheurísticas',0),
('RED501','Redes de Computadores',5);

-- verificacion inicial
SELECT * FROM Estudiantes;
SELECT * FROM Asignaturas;
SELECT * FROM Registros_Matricula;
UPDATE Asignaturas SET cupos_disponibles = -1 WHERE codigo = 'BD101';