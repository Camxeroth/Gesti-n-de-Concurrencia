#  Gestión de Concurrencia y Consistencia en un Sistema de Matriculación Universitaria

Proyecto de **Administración de Bases de Datos** (Unidad 1, Tema 1: *Programación avanzada en SQL – Transacciones*) de la carrera de **Ciencia de Datos e IA**, Universidad Nacional de Chimborazo (UNACH).

Se diseña una base de datos en **SQL Server** que gestiona la disponibilidad de cupos por asignatura, y se demuestra con pruebas prácticas cómo las **transacciones ACID**, los **bloqueos** y los **niveles de aislamiento** protegen la integridad de los datos cuando varios estudiantes se matriculan al mismo tiempo.

---

##  Contenido

- [Objetivo](#-objetivo)
- [Tecnologías](#-tecnologías)
- [Esquema de la base de datos](#-esquema-de-la-base-de-datos)
- [Transacciones ACID](#-transacciones-acid)
- [Niveles de aislamiento y concurrencia](#-niveles-de-aislamiento-y-concurrencia)
- [Valor agregado: `sp_Matricular`](#-valor-agregado-sp_matricular)
- [Cómo ejecutar el proyecto](#-cómo-ejecutar-el-proyecto)
- [Conclusiones](#-conclusiones)
- [Autor](#-autor)

---

##  Objetivo

Aplicar de forma progresiva los conceptos de administración de bases de datos: transacciones con propiedades ACID (`COMMIT` / `ROLLBACK`), control de bloqueos y niveles de aislamiento, garantizando la integridad de la información en un escenario real de matriculación universitaria.

## Tecnologías

- **Motor:** SQL Server Express 17.0
- **Cliente:** SQL Server Management Studio / editor T-SQL
- **Lenguaje:** T-SQL

---

## 🗄️ Esquema de la base de datos

Base de datos: `MatriculaUniversitaria`

| Tabla | Descripción | Columnas principales |
|---|---|---|
| `Estudiantes` | Personas que pueden matricularse | `estudiante_id` (PK), `cedula`, `nombre`, `correo` |
| `Asignaturas` | Oferta académica y cupos | `asignatura_id` (PK), `codigo`, `nombre`, `cupos_disponibles` |
| `Registros_Matricula` | Relaciona estudiantes con asignaturas | `registro_id` (PK), `estudiante_id` (FK), `asignatura_id` (FK), `fecha_matricula`, `estado` |

### Decisiones de diseño

- **PK con `INT IDENTITY(1,1)`** en las tres tablas.
- **`cedula CHAR(10)`** con `CHECK (cedula NOT LIKE '%[^0-9]%')` para aceptar solo dígitos, además de `UNIQUE`.
- **`cupos_disponibles SMALLINT`** con `CHECK (cupos_disponibles >= 0)`: es un candado a nivel de base de datos que impide cupos negativos.
- **Llaves foráneas** desde `Registros_Matricula`, que evitan matricular estudiantes o asignaturas inexistentes.
- **`UNIQUE (estudiante_id, asignatura_id)`** para que un estudiante no se matricule dos veces en la misma materia.
- **`estado`** restringido a `CONFIRMADA` o `PENDIENTE`.
- **Índice no agrupado** `IX_Registros_asignatura` sobre `asignatura_id` para acelerar consultas por materia.
- `READ_COMMITTED_SNAPSHOT OFF`, para que las pruebas de bloqueo se comporten con bloqueos reales.

### Datos de prueba

- **Estudiantes:** Ana Pérez, Luis Gómez, Carla Ruiz, Diego Mora.
- **Asignaturas:** Base de Datos (5 cupos), Programación Avanzada (4), Machine Learning 1 (3), Metaheurísticas (0), Redes de Computadores (5).

>  Al final del script de esquema hay un `UPDATE` que intenta dejar `cupos_disponibles = -1`. Es una prueba intencional: el motor lo rechaza por la restricción `CHECK`.

---

##  Transacciones ACID

| Transacción | Escenario | Acción | Resultado observado |
|---|---|---|---|
| **A – COMMIT** | Matrícula de Ana Pérez en *Base de Datos*: `INSERT` en `Registros_Matricula` + `UPDATE` que resta 1 cupo | `COMMIT` | Ambos cambios se guardan de forma permanente. El cupo pasa de 5 a 4 y existe 1 matrícula. |
| **B – ROLLBACK** | Se inserta la matrícula de Luis Gómez y se simula un fallo antes de actualizar el cupo | `ROLLBACK` | Dentro de la transacción había 2 filas; tras el `ROLLBACK` vuelve a haber 1 y el cupo sigue en 4. |
| **C – Multimateria** | Carla Ruiz se matricula en 3 materias; las dos primeras son válidas y la tercera tiene un ID inexistente | Error `50001` → `ROLLBACK` (con `TRY/CATCH`) | Las tablas quedan sin cambios, aunque los dos primeros `UPDATE` habían funcionado. |

**Hallazgo en la Transacción B:** el `ROLLBACK` deshace los datos, pero **no revierte el contador `IDENTITY`**. Se genera un "hueco" en los IDs (`MAX(registro_id)` = 10, `IDENT_CURRENT` = 11). Esto no afecta la integridad, porque los IDs solo deben ser únicos, no consecutivos.

---

##  Niveles de aislamiento y concurrencia

Pruebas realizadas con **dos sesiones simultáneas** (S1 y S2) que simulan a dos estudiantes sobre la misma materia (*Redes de Computadores*).

| Nivel | Qué se probó | Qué se observó |
|---|---|---|
| **READ COMMITTED** (por defecto) | S1 modifica el cupo sin hacer `COMMIT`; S2 intenta leer | S2 queda **bloqueada** esperando. Con `sys.dm_exec_requests` se confirma que S1 la bloquea. El motor prefiere hacer esperar al lector antes que mostrarle un dato sin confirmar. |
| **REPEATABLE READ** | S2 cuenta las matrículas (0); S1 inserta una nueva; S2 vuelve a contar | S2 ve ahora **1** matrícula: ocurre una **lectura fantasma**. Este nivel protege las filas ya leídas, pero no impide inserciones nuevas. |
| **SERIALIZABLE** | S2 cuenta las matrículas (0); S1 intenta insertar | S1 queda **bloqueada**. Con `sys.dm_tran_locks` se observa un **bloqueo de rango (`RangeS-S`)** que impide cualquier inserción hasta que S2 termine. Es la mayor protección de integridad, a costa de concurrencia. |

>  **READ UNCOMMITTED** es el único nivel que permite *lecturas sucias* (ver un cupo modificado y aún sin confirmar). Se contrasta con `READ COMMITTED` ejecutando `SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;` en S2.

### Resumen de anomalías

| Nivel | Lectura sucia | Lectura no repetible | Lectura fantasma |
|---|:---:|:---:|:---:|
| READ UNCOMMITTED |  Posible |  Posible | Posible |
| READ COMMITTED |  Evitada |  Posible |  Posible |
| REPEATABLE READ |  Evitada |  Evitada |  Posible |
| SERIALIZABLE |  Evitada |  Evitada |  Evitada |

---

## Valor agregado: `sp_Matricular`

Para llevar la práctica a un escenario real se creó el procedimiento almacenado **`sp_Matricular`**, que ejecuta todo el proceso de matrícula como una sola unidad:

- Hace el `INSERT` y el `UPDATE` de cupos **dentro del mismo procedimiento**, en lugar de dejarlos separados en la aplicación.
- Usa la sugerencia **`UPDLOCK`** al leer el cupo, de modo que dos estudiantes no puedan leer "5 cupos" al mismo tiempo y causar **sobreventa** de la materia.
- Valida errores (estudiante inexistente, materia inexistente, sin cupos), los reporta con `THROW` y ejecuta un **`ROLLBACK` automático** para no dejar datos a medias.

```sql
EXEC sp_Matricular 4, 2;     -- Matrícula exitosa (Diego en Programación Avanzada)
EXEC sp_Matricular 4, 999;   -- Error: Materia inexistente
EXEC sp_Matricular 999, 2;   -- Error: Estudiante inexistente
```

---

## ▶️ Cómo ejecutar el proyecto

1. Instala **SQL Server** (Express es suficiente) y **SSMS** o un cliente T-SQL compatible.
2. Clona el repositorio:
```bash
   git clone https://github.com/<tu-usuario>/<tu-repositorio>.git
```
3. Abre el script de esquema en tu cliente y ejecútalo completo. **Atención:** si la base `MatriculaUniversitaria` ya existe, el script la elimina y la vuelve a crear.
4. Ejecuta los scripts de transacciones (A, B y C) y verifica con los `SELECT` incluidos.
5. Para los niveles de aislamiento, **abre dos pestañas de consulta (S1 y S2)** conectadas a la misma base de datos y ejecuta los pasos de cada prueba alternando entre sesiones.

---

## Conclusiones

- La **atomicidad** queda demostrada: ante un error, el `ROLLBACK` deja la base como si nada hubiera pasado.
- Las restricciones (`CHECK`, `FK`, `UNIQUE`) actúan como **segunda línea de defensa** de la integridad, incluso si la aplicación falla.
- No existe un nivel de aislamiento "perfecto": **a mayor protección, menor concurrencia**. En una matrícula real conviene combinar un nivel adecuado con bloqueos puntuales (`UPDLOCK`) dentro de procedimientos almacenados.

---

## Autor

**Camilo Morocho**
Carrera: Ciencia de Datos e IA · Cuarto semestre "A"
Universidad Nacional de Chimborazo (UNACH) — Facultad de Ingeniería
Octubre de 2026
