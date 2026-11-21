# Utilidad Académica de cracion AN (MCP para Blender 5.2)

## 1. Qué problema resuelve

En asignaturas que requieren modelado, prototipado o visualización tridimensional, **Blender** es el estándar libre más completo, pero presenta una barrera operativa alta para estudiantes que aún están aprendiendo o que necesitan producir maquetas rápidamente: configurar desde cero una iluminación de estudio consistente, asignar materiales PBR físicos (`Principled BSDF`), encuadrar cámaras en vistas ortogonales o en perspectiva, auditar la cantidad de vértices/caras antes de imprimir en 3D y exportar correctamente a múltiples formatos (`.glb`, `.obj`, `.fbx`, `.stl`) implica decenas de clics repetitivos y memorización de menús que cambian entre versiones.

**cracion AN** elimina esa fricción mecánica conectando un asistente de IA directamente con la instalación local de **Blender 5.2 LTS** mediante el protocolo **MCP**, y complementándolo con una aplicación nativa de escritorio en Windows (`CracionAN.ps1`) para previsualizar, ajustar parámetros y abrir el proyecto en Blender cuando se requiere esculpido o edición fina manual.

## 2. Para quién está pensado

Está diseñado para **estudiantes universitarios y de educación técnica** de disciplinas que utilizan representación 3D como medio de estudio o entrega —como diseño industrial, arquitectura, ingeniería, animación digital, videojuegos, comunicación visual o ciencias aplicadas—, así como para **docentes** que preparan material visual 3D, demostraciones geométricas o prototipos base reproducibles para sus clases.

## 3. En qué dimensión del aprendizaje y del trabajo académico aporta

El aporte principal se refleja en cuatro dimensiones concretas:

- **Reducción de la carga cognitiva extrínseca**: al delegar en el MCP la preparación repetitiva de escenas (estudio de 3 luces, cámara, materiales, renders en múltiples vistas y exportaciones), el estudiante dedica su tiempo cognitivo a lo sustantivo de su disciplina: evaluar proporciones, composición espacial, legibilidad visual y criterios de diseño.
- **Iteración rápida y aprendizaje por experimentación**: probar una variación de escala, ángulo, material o modificador (`Bevel`, `Subdivision Surface`) y obtener un render `BLENDER_EEVEE` verificable toma segundos en lugar de repetir configuraciones manuales, favoreciendo ciclos cortos de hipótesis → prueba visual → corrección.
- **Verificación técnica antes de entregas e impresión 3D**: la herramienta `inspeccionar_escena_blend` permite auditar dimensiones reales, número de vértices/caras y materiales asignados, reduciendo errores frecuentes al entregar mallas o exportar `.stl` y `.glb`.
- **Puente hacia el modelado programático (`bpy`)**: al incluir `ejecutar_python_blender` y guardar todo en archivos `.blend` estándar y editables, el estudiante no queda encerrado en una "caja negra": puede aprender cómo se traducen conceptos geométricos a código Python real de Blender y continuar editando el mismo archivo en Blender 5.2 sin pérdida de compatibilidad.
