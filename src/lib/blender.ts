/**
 * Integracion de cracion AN con Blender 5.2 via CLI (--background) y
 * lanzamiento de la aplicacion nativa de escritorio CracionAN.exe.
 */
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, readdir, unlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { run } from "./exec.js";

const MARCADOR_JSON = "CRACION_AN_JSON:";
const NOMBRE_ARCHIVO_VALIDO = /^[\p{L}\p{N}._\- /\\]+$/u;

let blenderCache: string | null = null;

export function obtenerDirectorioTrabajo(): string {
  const custom = process.env.CRACION_AN_DIR?.trim();
  if (custom) return path.resolve(custom);

  const home = os.homedir();
  const candidatosEscritorio = [
    path.join(home, "OneDrive", "Escritorio"),
    path.join(home, "OneDrive", "Desktop"),
    path.join(home, "Escritorio"),
    path.join(home, "Desktop"),
  ];

  const escritorio = candidatosEscritorio.find((dir) => existsSync(dir)) ?? path.join(home, "Desktop");
  return path.join(escritorio, "cracion-AN");
}

export async function asegurarDirectorioTrabajo(): Promise<string> {
  const dir = obtenerDirectorioTrabajo();
  await mkdir(dir, { recursive: true });
  return dir;
}

export function resolverRutaEnProyecto(nombreArchivo: string, extensionPorDefecto?: string): string {
  const limpio = nombreArchivo.trim();
  if (!limpio || /[\u0000-\u001f\u007f]/.test(limpio)) {
    throw new Error("Nombre de archivo invalido o vacio.");
  }
  if (!NOMBRE_ARCHIVO_VALIDO.test(limpio)) {
    throw new Error("El nombre de archivo contiene caracteres no permitidos.");
  }
  if (path.isAbsolute(limpio)) {
    throw new Error("Usa un nombre relativo dentro de la carpeta cracion-AN.");
  }

  let conExtension = limpio;
  if (extensionPorDefecto && !conExtension.toLowerCase().endsWith(extensionPorDefecto.toLowerCase())) {
    conExtension += extensionPorDefecto;
  }

  const baseDir = obtenerDirectorioTrabajo();
  const destino = path.resolve(baseDir, conExtension);
  const baseConSep = baseDir.endsWith(path.sep) ? baseDir : baseDir + path.sep;

  if (!destino.startsWith(baseConSep)) {
    throw new Error("La ruta sale fuera de la carpeta de trabajo cracion-AN.");
  }
  return destino;
}

async function buscarBlenderEnCarpeta(raiz: string): Promise<string | null> {
  if (!existsSync(raiz)) return null;
  try {
    const entradas = await readdir(raiz, { withFileTypes: true });
    const carpetas = entradas
      .filter((e) => e.isDirectory() && e.name.toLowerCase().startsWith("blender"))
      .map((e) => e.name)
      .sort()
      .reverse();

    for (const carpeta of carpetas) {
      const exe = path.join(raiz, carpeta, "blender.exe");
      if (existsSync(exe)) return exe;
    }
  } catch {
    return null;
  }
  return null;
}

export async function encontrarBlender(): Promise<string> {
  if (blenderCache && existsSync(blenderCache)) return blenderCache;

  const envPath = process.env.BLENDER_PATH?.trim();
  if (envPath && existsSync(envPath)) {
    blenderCache = envPath;
    return envPath;
  }

  if (process.platform === "win32") {
    const raices = [
      "C:\\Program Files\\Blender Foundation",
      path.join(process.env.LOCALAPPDATA ?? "", "Programs", "Blender Foundation"),
    ];
    for (const raiz of raices) {
      const encontrado = await buscarBlenderEnCarpeta(raiz);
      if (encontrado) {
        blenderCache = encontrado;
        return encontrado;
      }
    }

    const where = await run("where.exe", ["blender"]);
    const primera = where.stdout.split(/\r?\n/).find((l) => l.trim().endsWith(".exe"));
    if (where.code === 0 && primera) {
      blenderCache = primera.trim();
      return blenderCache;
    }
  } else {
    const which = await run("which", ["blender"]);
    const ruta = which.stdout.trim();
    if (which.code === 0 && ruta) {
      blenderCache = ruta;
      return ruta;
    }
  }

  throw new Error("No se encontro Blender 5.2 en el equipo. Define BLENDER_PATH si esta en otra ruta.");
}

export async function ejecutarScriptBlender<T = Record<string, unknown>>(
  codigoPython: string,
  params: Record<string, unknown> = {},
  timeoutMs = 120_000,
): Promise<T> {
  const blenderExe = await encontrarBlender();
  await asegurarDirectorioTrabajo();

  const tempPy = path.join(os.tmpdir(), `cracion-an-${randomUUID()}.py`);
  await writeFile(tempPy, codigoPython, "utf8");

  try {
    const resultado = await run(
      blenderExe,
      ["--background", "--factory-startup", "--python", tempPy],
      {
        timeoutMs,
        env: { CRACION_AN_PARAMS: JSON.stringify(params) },
      },
    );

    const lineas = resultado.stdout.split(/\r?\n/);
    const lineaJson = [...lineas].reverse().find((l) => l.startsWith(MARCADOR_JSON));

    if (lineaJson) {
      const payload = JSON.parse(lineaJson.slice(MARCADOR_JSON.length)) as T & { ok?: boolean; error?: string };
      if (payload.ok === false) {
        throw new Error(payload.error || "Blender devolvio un error controlado.");
      }
      return payload;
    }

    if (resultado.code !== 0) {
      const detalle = (resultado.stderr || resultado.stdout).trim().slice(-1200);
      throw new Error(`Blender termino con codigo ${resultado.code}: ${detalle}`);
    }

    throw new Error("Blender finalizo sin devolver la respuesta JSON esperada.");
  } finally {
    await unlink(tempPy).catch(() => {});
  }
}

export function abrirAppNativaWindows(archivoBlend?: string): string {
  const aqui = path.dirname(fileURLToPath(import.meta.url));
  const raiz = path.resolve(aqui, "..", "..");
  const scriptPs1 = path.join(raiz, "app-windows", "CracionAN.ps1");
  if (!existsSync(scriptPs1)) {
    throw new Error(`No se encontro la aplicacion nativa en ${scriptPs1}.`);
  }
  const args = [
    "-NoProfile",
    "-STA",
    "-WindowStyle",
    "Hidden",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    scriptPs1,
  ];
  if (archivoBlend) args.push("-ArchivoInicial", archivoBlend);
  const child = spawn("powershell.exe", args, {
    detached: true,
    stdio: "ignore",
    windowsHide: true,
  });
  child.unref();
  return scriptPs1;
}
