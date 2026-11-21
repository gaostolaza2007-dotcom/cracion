#!/usr/bin/env node
/**
 * Demostracion automatizada (E2E) del servidor MCP cracion AN sobre Blender 5.2.
 * Ejecuta el caso real "Prototipo de Luminaria Modular de Estudio":
 *   crear escena -> agregar objetos 3D -> ajustar con Python (bpy) ->
 *   inspeccionar -> renderizar 2 vistas PNG -> exportar GLB y STL ->
 *   listar archivos -> validar proteccion confirmar:true y eliminar archivo temporal.
 *
 * Uso:
 *   node scripts/demo-examen.mjs [--guardar-evidencia]
 */
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const guardarEvidencia = process.argv.includes("--guardar-evidencia");
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "demo-cracion-an-"));

const t0 = Date.now();
const transport = new StdioClientTransport({
  command: process.execPath,
  args: [path.join(raiz, "dist", "index.js")],
  env: { ...process.env, CRACION_AN_DIR: tmpDir },
});
const client = new Client({ name: "demo-examen-cracion-an", version: "1.0.0" });

async function llamar(name, args) {
  const inicio = Date.now();
  const res = await client.callTool({ name, arguments: args });
  const ms = Date.now() - inicio;
  if (res.isError) {
    throw new Error(`${name} devolvio error: ${res.content[0]?.text ?? "desconocido"}`);
  }
  const txt = res.content[0]?.text ?? "";
  return { ms, txt, data: txt.trim().startsWith("{") ? JSON.parse(txt) : txt };
}

try {
  await client.connect(transport);

  const r1 = await llamar("crear_escena_blend", { nombre: "prototipo_luminaria", plantilla: "vacia" });
  console.log(`1. crear_escena_blend (${r1.ms} ms) -> ${r1.data.total_objetos} objetos base (camara + 3 luces)`);

  const r2 = await llamar("agregar_objeto_3d", {
    archivo: "prototipo_luminaria",
    tipo: "cilindro",
    nombre: "Base_Madera",
    material: "madera_calida",
    posicion: [0, 0, -0.55],
    escala: [1.1, 1.1, 0.14],
    subdivisiones: 0,
  });
  const r3 = await llamar("agregar_objeto_3d", {
    archivo: "prototipo_luminaria",
    tipo: "cilindro",
    nombre: "Columna_Cromada",
    material: "metal_cromado",
    posicion: [0, 0, 0.05],
    escala: [0.14, 0.14, 0.85],
    subdivisiones: 0,
  });
  const r4 = await llamar("agregar_objeto_3d", {
    archivo: "prototipo_luminaria",
    tipo: "toroide",
    nombre: "Aro_Dorado",
    material: "oro",
    posicion: [0, 0, 0.72],
    rotacion: [25, 0, 15],
    escala: [0.78, 0.78, 0.78],
    subdivisiones: 1,
  });
  const r5 = await llamar("agregar_objeto_3d", {
    archivo: "prototipo_luminaria",
    tipo: "esfera",
    nombre: "Difusor_Luz",
    material: "emisivo_cyan",
    posicion: [0, 0, 0.72],
    escala: [0.52, 0.52, 0.52],
    subdivisiones: 1,
  });
  console.log(`2-5. agregar_objeto_3d -> Base_Madera (${r2.ms} ms), Columna_Cromada (${r3.ms} ms), Aro_Dorado (${r4.ms} ms), Difusor_Luz (${r5.ms} ms)`);

  const codigoPy = [
    "bpy.ops.mesh.primitive_plane_add(size=7.0, location=(0, 0, -0.65))",
    "suelo = bpy.context.active_object",
    "suelo.name = 'Suelo_Presentacion'",
    "asignar_material(suelo, 'blanco_estudio')",
    "base = bpy.data.objects.get('Base_Madera')",
    "if base:",
    "    bev = base.modifiers.new('Bisel', 'BEVEL')",
    "    bev.width = 0.03",
    "    bev.segments = 3",
  ].join("\n");

  const r6 = await llamar("ejecutar_python_blender", {
    archivo: "prototipo_luminaria",
    codigo_python: codigoPy,
  });
  console.log(`6. ejecutar_python_blender (${r6.ms} ms) -> ${r6.data.total_objetos} objetos totales`);

  const r7 = await llamar("inspeccionar_escena_blend", { archivo: "prototipo_luminaria" });
  const mallas = r7.data.objetos.filter((o) => o.tipo === "MESH");
  const totalV = mallas.reduce((acc, o) => acc + (o.vertices ?? 0), 0);
  const totalC = mallas.reduce((acc, o) => acc + (o.caras ?? 0), 0);
  console.log(`7. inspeccionar_escena_blend (${r7.ms} ms) -> Blender ${r7.data.blender_version}, ${r7.data.total_objetos} objetos (${mallas.length} mallas, ${totalV} vertices, ${totalC} caras)`);
  console.log("   Detalle objetos:", JSON.stringify(mallas));

  const r8 = await llamar("renderizar_vista_blend", {
    archivo: "prototipo_luminaria",
    vista: "perspectiva",
    resolucion: 1024,
  });
  const r9 = await llamar("renderizar_vista_blend", {
    archivo: "prototipo_luminaria",
    vista: "frontal",
    resolucion: 1024,
  });
  const sizePersp = fs.statSync(r8.data.imagen).size;
  const sizeFront = fs.statSync(r9.data.imagen).size;
  console.log(`8-9. renderizar_vista_blend -> perspectiva (${r8.ms} ms, ${(sizePersp / 1024).toFixed(1)} KB), frontal (${r9.ms} ms, ${(sizeFront / 1024).toFixed(1)} KB)`);

  if (guardarEvidencia) {
    const evDir = path.join(raiz, "docs", "evidencia");
    fs.mkdirSync(evDir, { recursive: true });
    fs.copyFileSync(r8.data.imagen, path.join(evDir, "demo_perspectiva.png"));
    fs.copyFileSync(r9.data.imagen, path.join(evDir, "demo_frontal.png"));
    console.log("   Evidencia guardada en docs/evidencia/");
  }

  const r10 = await llamar("exportar_modelo_3d", { archivo: "prototipo_luminaria", formato: "glb" });
  const r11 = await llamar("exportar_modelo_3d", { archivo: "prototipo_luminaria", formato: "stl" });
  const glbKb = (fs.statSync(r10.data.archivo_exportado).size / 1024).toFixed(1);
  const stlKb = (fs.statSync(r11.data.archivo_exportado).size / 1024).toFixed(1);
  console.log(`10-11. exportar_modelo_3d -> GLB (${r10.ms} ms, ${glbKb} KB), STL (${r11.ms} ms, ${stlKb} KB)`);

  const r12 = await llamar("listar_proyectos_blend", {});
  console.log(
    `12. listar_proyectos_blend (${r12.ms} ms) -> ${r12.data.total} archivos:`,
    r12.data.archivos.map((a) => `${a.nombre} (${a.tamano_kb} KB)`).join(", "),
  );

  // Verificar proteccion de borrado (sin confirmar: true debe rechazarse)
  let bloqueado = false;
  try {
    const resSinConfirmar = await client.callTool({
      name: "eliminar_archivo_blend",
      arguments: { archivo: "prototipo_luminaria.glb" },
    });
    if (resSinConfirmar.isError) bloqueado = true;
  } catch {
    bloqueado = true;
  }
  if (!bloqueado) throw new Error("Fallo de seguridad: eliminar_archivo_blend permitio borrar sin confirmar=true");
  console.log("13. proteccion confirmar=true -> OK (rechazado sin confirmacion)");

  const r14 = await llamar("eliminar_archivo_blend", { archivo: "prototipo_luminaria.stl", confirmar: true });
  console.log(`14. eliminar_archivo_blend (${r14.ms} ms) -> ${r14.txt}`);

  await client.close();
  console.log(`DEMO_E2E_OK en ${((Date.now() - t0) / 1000).toFixed(1)} s`);
} finally {
  fs.rmSync(tmpDir, { recursive: true, force: true });
}
