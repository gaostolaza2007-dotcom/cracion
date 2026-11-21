# Declaración de Uso de IA, Límites Conocidos y Consideraciones de Seguridad

## 1. Uso de aplicaciones propias o autorizadas

- **Blender 5.2 LTS**: software libre y de código abierto (licencia GNU GPL), instalado legítimamente en el computador local del estudiante. No se intervienen servicios privados, cuentas de terceros ni aplicaciones sin autorización.
- **cracion AN (servidor MCP + aplicación de escritorio `CracionAN.ps1`)**: desarrollado a partir de la plantilla oficial del curso (`mcp-starter-kit`, rama `main`), usando TypeScript (`@modelcontextprotocol/sdk`, `zod`) y la API nativa WPF de Windows.

---

## 2. Permisos acotados y consideraciones de seguridad

El proyecto implementa controles concretos en el código fuente para minimizar riesgos al conectar un modelo de IA con un programa local:

1. **Ejecución sin shell (`execFile` / `spawn`)**: todas las invocaciones a Blender ([`src/lib/exec.ts`](../src/lib/exec.ts) y [`src/lib/blender.ts`](../src/lib/blender.ts)) pasan argumentos como arreglos explícitos sin invocar `cmd.exe` ni shell de comandos, eliminando vectores de inyección de comandos del sistema operativo.
2. **Aislamiento de parámetros hacia Python**: los datos ingresados por el modelo se serializan como JSON en la variable de entorno `CRACION_AN_PARAMS` y son leídos por el script de Blender mediante `json.loads(...)`, evitando interpolación directa de cadenas dentro del código Python.
3. **Confinamiento de archivos (*sandboxing* de rutas)**: la función `resolverRutaEnProyecto()` valida cada nombre de archivo con expresión regular, rechaza caracteres de control, rutas absolutas externas y secuencias de *path traversal* (`..`), y verifica que la ruta final permanezca estrictamente dentro de la carpeta `<Escritorio>/cracion-AN` (o `CRACION_AN_DIR`).
4. **Validación estricta de entradas y anotaciones MCP**: todas las herramientas en [`src/tools/blender_mcp.ts`](../src/tools/blender_mcp.ts) validan parámetros y rangos con `zod` y declaran `annotations` (`readOnlyHint`, `destructiveHint`) para que el cliente MCP pueda informar o solicitar aprobación al usuario.
5. **Protección contra acciones destructivas**:
   - `crear_escena_blend` nunca sobrescribe un archivo `.blend` existente.
   - `eliminar_archivo_blend` exige explícitamente el parámetro `confirmar: z.literal(true)` (verificado en la prueba E2E de `npm run demo`).
6. **Cero credenciales ni datos personales**: el MCP opera 100% de forma local sobre Blender, no requiere claves API, no sube archivos `.env` (ignorado en `.gitignore`) y no almacena rutas ni nombres de usuario personales en el repositorio.

---

## 3. Límites conocidos

- **Dependencia de instalación local de Blender**: requiere tener Blender 5.2 (o una versión 4.x/5.x compatible con `BLENDER_EEVEE`, `wm.obj_export` y `wm.stl_export`) instalado en el computador.
- **Alcance de `ejecutar_python_blender`**: esta herramienta ejecuta código Python (`bpy`) dentro del proceso local de Blender para habilitar modelado avanzado. Al poder ejecutar código Python arbitrario, está concebida **exclusivamente para uso individual local de confianza** y nunca debe exponerse a usuarios externos ni en red.
- **Aplicación de escritorio solo en Windows**: la interfaz gráfica nativa [`app-windows/CracionAN.ps1`](../app-windows/CracionAN.ps1) usa WPF sobre Windows PowerShell (se eligió script WPF firmado por el intérprete de Windows en lugar de un `.exe` compilado localmente sin firma, ya que el Control de Aplicaciones de Windows bloquea ejecutables locales sin firma digital). En macOS y Linux, el servidor MCP funciona normalmente vía CLI con Blender, excepto la herramienta `abrir_programa_cracion_an`.
- **Rendimiento de renderizado**: cada operación lanza Blender en modo `--background --factory-startup`; el tiempo de respuesta depende del hardware del equipo (entre 5 y 20 segundos por operación/render en `1024×768`).
- **Archivos de respaldo de Blender**: al guardar modificaciones sobre un `.blend`, Blender puede crear automáticamente archivos `.blend1` en la misma carpeta de trabajo.

---

## 4. Declaración transparente de uso de IA

Para el desarrollo de este examen se utilizó un asistente de inteligencia artificial (**Google Antigravity**) como apoyo en las siguientes tareas:

- **Diseño y arquitectura**: evaluación de las vías de integración con Blender 5.2 (elección del CLI headless + `bpy`) y definición de las 9 herramientas MCP siguiendo las reglas de `AGENTS.md`.
- **Implementación**: escritura y depuración del servidor MCP en TypeScript (`src/lib/blender.ts`, `src/lib/blender_scripts.ts`, `src/tools/blender_mcp.ts`), de la aplicación nativa de escritorio en Windows (`app-windows/CracionAN.ps1`) y del script de demostración automatizada (`scripts/demo-examen.mjs`).
- **Verificación y documentación**: ejecución de pruebas de compilación (`npm run build`), prueba de humo (`npm test`) y prueba integral real sobre Blender 5.2.1 LTS (`npm run demo`), así como estructuración y redacción inicial de la documentación (`README.md` y `docs/`).

**Rol, decisiones y validación del estudiante:** el estudiante definió el alcance del proyecto (`cracion AN`), seleccionó Blender 5.2 como aplicación objetivo, solicitó iteraciones para contar con una aplicación nativa de escritorio en Windows (descartando enfoques web y especializaciones que no correspondían a su objetivo), revisó los archivos resultantes y validó su ejecución real en su computador.
