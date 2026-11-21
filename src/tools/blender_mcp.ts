/**
 * Herramientas MCP de cracion AN para crear y manipular escenas 3D en Blender 5.2
 * y lanzar la aplicacion nativa de escritorio CracionAN.exe.
 */
import { existsSync } from "node:fs";
import { readdir, stat, unlink } from "node:fs/promises";
import path from "node:path";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import {
  abrirAppNativaWindows,
  asegurarDirectorioTrabajo,
  ejecutarScriptBlender,
  obtenerDirectorioTrabajo,
  resolverRutaEnProyecto,
} from "../lib/blender.js";
import {
  scriptAgregarObjeto,
  scriptCrearEscena,
  scriptEjecutarPython,
  scriptExportarModelo,
  scriptInspeccionarEscena,
  scriptRenderizarVista,
} from "../lib/blender_scripts.js";
import { error, json, texto } from "../lib/respuestas.js";

const VEC3 = z.tuple([z.number(), z.number(), z.number()]);

const OBJETOS_3D = [
  "cubo",
  "esfera",
  "cilindro",
  "cono",
  "toroide",
  "plano",
  "texto_3d",
  "luz_area",
] as const;

const MATERIALES = [
  "blanco_estudio",
  "metal_cromado",
  "oro",
  "cobre",
  "plastico_rojo",
  "azul_cobalto",
  "verde_esmeralda",
  "madera_calida",
  "vidrio",
  "emisivo_cyan",
] as const;

export function register(server: McpServer): void {
  server.registerTool(
    "abrir_programa_cracion_an",
    {
      title: "Abrir aplicacion CracionAN.exe",
      description:
        "Abre la aplicacion nativa de escritorio de Windows CracionAN.exe conectada a Blender 5.2.",
      inputSchema: {
        archivo: z.string().optional().describe("Archivo .blend opcional a abrir al iniciar"),
      },
      annotations: { readOnlyHint: false },
    },
    async ({ archivo }) => {
      try {
        const ruta = archivo ? resolverRutaEnProyecto(archivo, ".blend") : undefined;
        const exe = abrirAppNativaWindows(ruta);
        return texto(`Aplicacion nativa iniciada: ${exe}`);
      } catch (e) {
        return error(e instanceof Error ? e.message : String(e));
      }
    },
  );

  server.registerTool(
    "listar_proyectos_blend",
    {
      title: "Listar proyectos .blend",
      description:
        "Lista los archivos .blend, renders .png y modelos exportados dentro de la carpeta cracion-AN.",
      inputSchema: {
        filtro: z.string().optional().describe("Texto opcional para filtrar por nombre o extension"),
      },
      annotations: { readOnlyHint: true },
    },
    async ({ filtro }) => {
      try {
        const dir = await asegurarDirectorioTrabajo();
        const entradas = await readdir(dir, { withFileTypes: true });
        const archivos = [];

        for (const entrada of entradas) {
          if (!entrada.isFile()) continue;
          if (filtro && !entrada.name.toLowerCase().includes(filtro.toLowerCase())) continue;
          const info = await stat(path.join(dir, entrada.name));
          archivos.push({
            nombre: entrada.name,
            extension: path.extname(entrada.name).toLowerCase(),
            tamano_kb: Math.round((info.size / 1024) * 10) / 10,
            modificado: info.mtime.toISOString(),
          });
        }

        archivos.sort((a, b) => b.modificado.localeCompare(a.modificado));
        return json({ carpeta: dir, total: archivos.length, archivos });
      } catch (e) {
        return error(e instanceof Error ? e.message : String(e));
      }
    },
  );

  server.registerTool(
    "inspeccionar_escena_blend",
    {
      title: "Inspeccionar escena .blend",
      description:
        "Abre un archivo .blend con Blender 5.2 en segundo plano y devuelve sus objetos, dimensiones, vertices y materiales.",
      inputSchema: {
        archivo: z.string().min(1).describe("Nombre del archivo .blend dentro de cracion-AN"),
      },
      annotations: { readOnlyHint: true },
    },
    async ({ archivo }) => {
      try {
        const ruta = resolverRutaEnProyecto(archivo, ".blend");
        if (!existsSync(ruta)) {
          return error(`No existe el archivo ${path.basename(ruta)} en ${obtenerDirectorioTrabajo()}.`);
        }
        return json(await ejecutarScriptBlender(scriptInspeccionarEscena(), { ruta }));
      } catch (e) {
        return error(e instanceof Error ? e.message : String(e));
      }
    },
  );

  server.registerTool(
    "crear_escena_blend",
    {
      title: "Crear escena .blend",
      description:
        "Crea un proyecto .blend nuevo en cracion-AN con iluminacion de estudio y camara. No sobrescribe existentes.",
      inputSchema: {
        nombre: z.string().min(1).describe("Nombre del proyecto sin ruta (ej: mi_escena)"),
        plantilla: z
          .enum(["vacia", "estudio_producto", "composicion_base"])
          .default("estudio_producto")
          .describe("Plantilla inicial de la escena"),
      },
      annotations: { readOnlyHint: false },
    },
    async ({ nombre, plantilla }) => {
      try {
        await asegurarDirectorioTrabajo();
        const ruta = resolverRutaEnProyecto(nombre, ".blend");
        if (existsSync(ruta)) {
          return error(`El archivo ${path.basename(ruta)} ya existe. Elige otro nombre.`);
        }
        return json(await ejecutarScriptBlender(scriptCrearEscena(), { ruta, plantilla }));
      } catch (e) {
        return error(e instanceof Error ? e.message : String(e));
      }
    },
  );

  server.registerTool(
    "agregar_objeto_3d",
    {
      title: "Agregar objeto 3D en Blender",
      description:
        "Agrega un objeto 3D (cubo, esfera, cilindro, cono, toroide, plano, texto_3d o luz_area) a un .blend existente.",
      inputSchema: {
        archivo: z.string().min(1).describe("Archivo .blend destino"),
        tipo: z.enum(OBJETOS_3D).describe("Tipo de objeto 3D"),
        nombre: z.string().min(1).describe("Nombre del objeto en la escena"),
        material: z.enum(MATERIALES).default("blanco_estudio").describe("Material PBR"),
        posicion: VEC3.default([0, 0, 0]).describe("Posicion [X, Y, Z]"),
        rotacion: VEC3.default([0, 0, 0]).describe("Rotacion [X, Y, Z] en grados"),
        escala: VEC3.default([1, 1, 1]).describe("Escala [X, Y, Z]"),
        subdivisiones: z.number().int().min(0).max(3).default(0).describe("Nivel de subdivision suave (0 a 3)"),
        texto: z.string().optional().describe("Contenido si el tipo es texto_3d"),
      },
      annotations: { readOnlyHint: false },
    },
    async ({ archivo, tipo, nombre, material, posicion, rotacion, escala, subdivisiones, texto: txt }) => {
      try {
        const ruta = resolverRutaEnProyecto(archivo, ".blend");
        if (!existsSync(ruta)) return error(`No existe ${path.basename(ruta)}.`);
        return json(
          await ejecutarScriptBlender(scriptAgregarObjeto(), {
            ruta,
            tipo,
            nombre,
            material,
            posicion,
            rotacion,
            escala,
            subdivisiones,
            texto: txt ?? "cracion AN",
          }),
        );
      } catch (e) {
        return error(e instanceof Error ? e.message : String(e));
      }
    },
  );

  server.registerTool(
    "ejecutar_python_blender",
    {
      title: "Ejecutar script Python en Blender",
      description:
        "Ejecuta codigo Python (bpy) personalizado sobre un archivo .blend existente y guarda los cambios.",
      inputSchema: {
        archivo: z.string().min(1).describe("Archivo .blend existente"),
        codigo_python: z.string().min(5).describe("Codigo Python usando bpy"),
      },
      annotations: { readOnlyHint: false },
    },
    async ({ archivo, codigo_python }) => {
      try {
        const ruta = resolverRutaEnProyecto(archivo, ".blend");
        if (!existsSync(ruta)) return error(`No existe ${path.basename(ruta)}.`);
        return json(await ejecutarScriptBlender(scriptEjecutarPython(), { ruta, codigo: codigo_python }));
      } catch (e) {
        return error(e instanceof Error ? e.message : String(e));
      }
    },
  );

  server.registerTool(
    "renderizar_vista_blend",
    {
      title: "Renderizar vista .png",
      description:
        "Renderiza una imagen PNG de un archivo .blend usando Blender 5.2 (BLENDER_EEVEE).",
      inputSchema: {
        archivo: z.string().min(1).describe("Archivo .blend existente"),
        vista: z
          .enum(["perspectiva", "frontal", "posterior", "lateral_derecha", "lateral_izquierda", "superior", "camara_escena"])
          .default("perspectiva")
          .describe("Angulo de camara"),
        resolucion: z.number().int().min(256).max(2048).default(1024).describe("Ancho en pixeles"),
      },
      annotations: { readOnlyHint: false },
    },
    async ({ archivo, vista, resolucion }) => {
      try {
        const ruta = resolverRutaEnProyecto(archivo, ".blend");
        if (!existsSync(ruta)) return error(`No existe ${path.basename(ruta)}.`);
        const base = path.basename(ruta, ".blend");
        const salida = resolverRutaEnProyecto(`${base}_${vista}.png`, ".png");
        return json(
          await ejecutarScriptBlender(scriptRenderizarVista(), {
            ruta,
            salida,
            vista,
            ancho: resolucion,
            alto: Math.round(resolucion * 0.75),
          }),
        );
      } catch (e) {
        return error(e instanceof Error ? e.message : String(e));
      }
    },
  );

  server.registerTool(
    "exportar_modelo_3d",
    {
      title: "Exportar modelo 3D",
      description: "Exporta un proyecto .blend a GLB, OBJ, FBX o STL desde Blender 5.2.",
      inputSchema: {
        archivo: z.string().min(1).describe("Archivo .blend origen"),
        formato: z.enum(["glb", "obj", "fbx", "stl"]).default("glb").describe("Formato destino"),
      },
      annotations: { readOnlyHint: false },
    },
    async ({ archivo, formato }) => {
      try {
        const ruta = resolverRutaEnProyecto(archivo, ".blend");
        if (!existsSync(ruta)) return error(`No existe ${path.basename(ruta)}.`);
        const base = path.basename(ruta, ".blend");
        const salida = resolverRutaEnProyecto(`${base}.${formato}`, `.${formato}`);
        return json(await ejecutarScriptBlender(scriptExportarModelo(), { ruta, salida, formato }));
      } catch (e) {
        return error(e instanceof Error ? e.message : String(e));
      }
    },
  );

  server.registerTool(
    "eliminar_archivo_blend",
    {
      title: "Eliminar archivo",
      description: "Elimina permanentemente un archivo de cracion-AN. Exige confirmar: true.",
      inputSchema: {
        archivo: z.string().min(1).describe("Nombre exacto del archivo con extension"),
        confirmar: z.literal(true).describe("Debe ser true para confirmar la eliminacion"),
      },
      annotations: { readOnlyHint: false, destructiveHint: true },
    },
    async ({ archivo }) => {
      try {
        const ruta = resolverRutaEnProyecto(archivo);
        if (!existsSync(ruta)) return error(`No se encontro ${path.basename(ruta)}.`);
        await unlink(ruta);
        return texto(`Archivo eliminado: ${ruta}`);
      } catch (e) {
        return error(e instanceof Error ? e.message : String(e));
      }
    },
  );
}
