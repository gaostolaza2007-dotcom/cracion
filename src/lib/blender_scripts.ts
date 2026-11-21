/**
 * Scripts Python (bpy) para Blender 5.2 de proposito general.
 * Todos leen sus parametros desde CRACION_AN_PARAMS y emiten CRACION_AN_JSON:{...}.
 */

const PY_BASE = String.raw`
import bpy
import json
import math
import os
import traceback
from mathutils import Vector

PARAMS = json.loads(os.environ.get("CRACION_AN_PARAMS", "{}"))

def emitir(datos):
    print("CRACION_AN_JSON:" + json.dumps(datos, ensure_ascii=False))

def fallar(mensaje):
    emitir({"ok": False, "error": str(mensaje)})

MATERIALES_PBR = {
    "blanco_estudio": {"nombre": "Mat_Blanco_Estudio", "color": (0.85, 0.85, 0.87, 1.0), "metallic": 0.0, "roughness": 0.45, "emission": 0.0},
    "metal_cromado": {"nombre": "Mat_Metal_Cromado", "color": (0.88, 0.90, 0.92, 1.0), "metallic": 1.0, "roughness": 0.14, "emission": 0.0},
    "oro": {"nombre": "Mat_Oro", "color": (0.95, 0.75, 0.28, 1.0), "metallic": 1.0, "roughness": 0.20, "emission": 0.0},
    "cobre": {"nombre": "Mat_Cobre", "color": (0.88, 0.45, 0.28, 1.0), "metallic": 1.0, "roughness": 0.24, "emission": 0.0},
    "plastico_rojo": {"nombre": "Mat_Plastico_Rojo", "color": (0.82, 0.14, 0.14, 1.0), "metallic": 0.0, "roughness": 0.30, "emission": 0.0},
    "azul_cobalto": {"nombre": "Mat_Azul_Cobalto", "color": (0.14, 0.36, 0.86, 1.0), "metallic": 0.0, "roughness": 0.32, "emission": 0.0},
    "verde_esmeralda": {"nombre": "Mat_Verde_Esmeralda", "color": (0.12, 0.65, 0.38, 1.0), "metallic": 0.0, "roughness": 0.34, "emission": 0.0},
    "madera_calida": {"nombre": "Mat_Madera_Calida", "color": (0.48, 0.28, 0.14, 1.0), "metallic": 0.0, "roughness": 0.58, "emission": 0.0},
    "vidrio": {"nombre": "Mat_Vidrio", "color": (0.88, 0.95, 1.0, 1.0), "metallic": 0.0, "roughness": 0.06, "emission": 0.0, "transmission": 0.9},
    "emisivo_cyan": {"nombre": "Mat_Emisivo_Cyan", "color": (0.15, 0.85, 1.0, 1.0), "metallic": 0.0, "roughness": 0.25, "emission": 3.5},
}

def obtener_o_crear_material(clave):
    spec = MATERIALES_PBR.get(clave, MATERIALES_PBR["blanco_estudio"])
    mat = bpy.data.materials.get(spec["nombre"])
    if mat is None:
        mat = bpy.data.materials.new(name=spec["nombre"])
    if mat.node_tree is None:
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = spec["color"]
        bsdf.inputs["Metallic"].default_value = spec["metallic"]
        bsdf.inputs["Roughness"].default_value = spec["roughness"]
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = spec["color"]
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = spec.get("emission", 0.0)
        if "Transmission Weight" in bsdf.inputs and "transmission" in spec:
            bsdf.inputs["Transmission Weight"].default_value = spec["transmission"]
    return mat

def asignar_material(obj, clave):
    if not hasattr(obj.data, "materials"):
        return
    mat = obtener_o_crear_material(clave)
    if obj.data.materials:
        obj.data.materials[0] = mat
    else:
        obj.data.materials.append(mat)

def apuntar_objeto(obj, objetivo):
    direccion = objetivo - obj.location
    obj.rotation_euler = direccion.to_track_quat("-Z", "Y").to_euler()

def limpiar_escena():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for col in (bpy.data.meshes, bpy.data.lights, bpy.data.cameras, bpy.data.curves):
        for item in list(col):
            if item.users == 0:
                col.remove(item)

def crear_luz_area(nombre, ubicacion, energia, tamano, rotacion_deg):
    data = bpy.data.lights.new(name=nombre, type="AREA")
    data.energy = energia
    data.size = tamano
    obj = bpy.data.objects.new(nombre, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = ubicacion
    obj.rotation_euler = tuple(math.radians(a) for a in rotacion_deg)
    return obj

def configurar_estudio():
    escena = bpy.context.scene
    escena.render.engine = "BLENDER_EEVEE"
    escena.unit_settings.system = "METRIC"
    if escena.world is None:
        escena.world = bpy.data.worlds.new("Mundo_Estudio")
    if escena.world.node_tree is None:
        escena.world.use_nodes = True
    bg = escena.world.node_tree.nodes.get("Background")
    if bg is not None:
        bg.inputs["Color"].default_value = (0.055, 0.065, 0.082, 1.0)
        bg.inputs["Strength"].default_value = 0.85

    crear_luz_area("Luz_Principal", (3.8, -3.6, 4.2), 480.0, 2.5, (52, 0, 45))
    crear_luz_area("Luz_Relleno", (-4.2, -2.2, 2.4), 200.0, 3.5, (65, 0, -58))
    crear_luz_area("Luz_Contorno", (0.0, 4.4, 3.6), 280.0, 2.0, (125, 0, 0))

    cam_data = bpy.data.cameras.new("Camara_Principal")
    cam_data.lens = 50.0
    cam_obj = bpy.data.objects.new("Camara_Principal", cam_data)
    escena.collection.objects.link(cam_obj)
    cam_obj.location = (3.4, -3.8, 2.4)
    apuntar_objeto(cam_obj, Vector((0.0, 0.0, 0.4)))
    escena.camera = cam_obj

def crear_objeto_3d(tipo, nombre, material, pos, rot_deg, escala, subdivisiones, texto_contenido="cracion AN"):
    if tipo == "cubo":
        bpy.ops.mesh.primitive_cube_add(size=1.2, location=pos)
    elif tipo == "esfera":
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.65, segments=32, ring_count=16, location=pos)
    elif tipo == "cilindro":
        bpy.ops.mesh.primitive_cylinder_add(radius=0.5, depth=1.4, vertices=32, location=pos)
    elif tipo == "cono":
        bpy.ops.mesh.primitive_cone_add(radius1=0.65, depth=1.4, vertices=32, location=pos)
    elif tipo == "toroide":
        bpy.ops.mesh.primitive_torus_add(major_radius=0.65, minor_radius=0.22, major_segments=36, minor_segments=16, location=pos)
    elif tipo == "plano":
        bpy.ops.mesh.primitive_plane_add(size=4.5, location=pos)
    elif tipo == "texto_3d":
        bpy.ops.object.text_add(location=pos)
        obj_t = bpy.context.active_object
        obj_t.data.body = texto_contenido
        obj_t.data.extrude = 0.08
        obj_t.data.align_x = "CENTER"
    elif tipo == "luz_area":
        return crear_luz_area(nombre, pos, 300.0, 1.5, rot_deg)
    else:
        raise ValueError(f"Tipo de objeto desconocido: {tipo}")

    obj = bpy.context.active_object
    obj.name = nombre
    obj.rotation_euler = tuple(math.radians(a) for a in rot_deg)
    obj.scale = Vector(escala)

    if obj.type == "MESH":
        for poly in obj.data.polygons:
            poly.use_smooth = True
        if subdivisiones > 0:
            mod = obj.modifiers.new(name="Subdivision", type="SUBSURF")
            mod.levels = subdivisiones
            mod.render_levels = subdivisiones

    asignar_material(obj, material)
    return obj

def resumen_escena():
    objetos = []
    for obj in bpy.data.objects:
        info = {
            "nombre": obj.name,
            "tipo": obj.type,
            "posicion": [round(v, 3) for v in obj.location],
            "dimensiones": [round(v, 3) for v in obj.dimensions],
            "materiales": [m.name for m in obj.data.materials] if getattr(obj.data, "materials", None) else [],
        }
        if obj.type == "MESH":
            info["vertices"] = len(obj.data.vertices)
            info["caras"] = len(obj.data.polygons)
        objetos.append(info)
    return {
        "objetos": objetos,
        "total_objetos": len(objetos),
        "camara_activa": bpy.context.scene.camera.name if bpy.context.scene.camera else None,
    }

def limites_mallas():
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mins = Vector((float("inf"), float("inf"), float("inf")))
    maxs = Vector((float("-inf"), float("-inf"), float("-inf")))
    hay = False
    for obj in bpy.context.scene.objects:
        if obj.type not in ("MESH", "FONT"):
            continue
        hay = True
        ev = obj.evaluated_get(depsgraph)
        for esq in ev.bound_box:
            p = ev.matrix_world @ Vector(esq)
            mins.x = min(mins.x, p.x)
            mins.y = min(mins.y, p.y)
            mins.z = min(mins.z, p.z)
            maxs.x = max(maxs.x, p.x)
            maxs.y = max(maxs.y, p.y)
            maxs.z = max(maxs.z, p.z)
    if not hay:
        return Vector((0.0, 0.0, 0.0)), 2.2
    return (mins + maxs) * 0.5, max((maxs - mins).length * 0.5, 0.6)
`;

export function scriptCrearEscena(): string {
  return `${PY_BASE}
try:
    ruta = PARAMS["ruta"]
    plantilla = PARAMS.get("plantilla", "estudio_producto")
    limpiar_escena()
    configurar_estudio()

    if plantilla == "estudio_producto":
        crear_objeto_3d("plano", "Suelo_Estudio", "blanco_estudio", (0, 0, -0.6), (0, 0, 0), (1.8, 1.8, 1), 0)
        crear_objeto_3d("cubo", "Cubo_Principal", "azul_cobalto", (0, 0, 0), (0, 0, 20), (1, 1, 1), 1)
    elif plantilla == "composicion_base":
        crear_objeto_3d("plano", "Suelo_Estudio", "blanco_estudio", (0, 0, -0.65), (0, 0, 0), (2.2, 2.2, 1), 0)
        crear_objeto_3d("esfera", "Esfera_Metalica", "oro", (-1.1, 0.2, 0.0), (0, 0, 0), (1, 1, 1), 1)
        crear_objeto_3d("cubo", "Bloque_Central", "azul_cobalto", (0.2, -0.1, 0.0), (0, 0, 25), (1, 1, 1), 1)
        crear_objeto_3d("toroide", "Aro_Cromado", "metal_cromado", (1.35, 0.15, 0.1), (55, 15, 0), (0.9, 0.9, 0.9), 1)

    bpy.ops.wm.save_as_mainfile(filepath=ruta)
    emitir({"ok": True, "ruta": ruta, "plantilla": plantilla, **resumen_escena()})
except Exception as exc:
    fallar(f"{exc}\\n{traceback.format_exc()}")
`;
}

export function scriptInspeccionarEscena(): string {
  return `${PY_BASE}
try:
    ruta = PARAMS["ruta"]
    bpy.ops.wm.open_mainfile(filepath=ruta)
    emitir({
        "ok": True,
        "ruta": ruta,
        "blender_version": bpy.app.version_string,
        "frame_inicio": bpy.context.scene.frame_start,
        "frame_fin": bpy.context.scene.frame_end,
        **resumen_escena(),
    })
except Exception as exc:
    fallar(str(exc))
`;
}

export function scriptAgregarObjeto(): string {
  return `${PY_BASE}
try:
    ruta = PARAMS["ruta"]
    bpy.ops.wm.open_mainfile(filepath=ruta)
    obj = crear_objeto_3d(
        PARAMS["tipo"],
        PARAMS["nombre"],
        PARAMS.get("material", "blanco_estudio"),
        PARAMS.get("posicion", [0, 0, 0]),
        PARAMS.get("rotacion", [0, 0, 0]),
        PARAMS.get("escala", [1, 1, 1]),
        int(PARAMS.get("subdivisiones", 0)),
        PARAMS.get("texto", "cracion AN"),
    )
    bpy.ops.wm.save_as_mainfile(filepath=ruta)
    emitir({
        "ok": True,
        "ruta": ruta,
        "objeto_agregado": obj.name,
        **resumen_escena(),
    })
except Exception as exc:
    fallar(f"{exc}\\n{traceback.format_exc()}")
`;
}

export function scriptEjecutarPython(): string {
  return `${PY_BASE}
try:
    ruta = PARAMS["ruta"]
    codigo = PARAMS["codigo"]
    bpy.ops.wm.open_mainfile(filepath=ruta)
    entorno = {
        "bpy": bpy,
        "math": math,
        "Vector": Vector,
        "obtener_o_crear_material": obtener_o_crear_material,
        "asignar_material": asignar_material,
        "crear_objeto_3d": crear_objeto_3d,
    }
    exec(compile(codigo, "<cracion_an_script>", "exec"), entorno, entorno)
    bpy.ops.wm.save_as_mainfile(filepath=ruta)
    emitir({"ok": True, "ruta": ruta, **resumen_escena()})
except Exception as exc:
    fallar(f"{exc}\\n{traceback.format_exc()}")
`;
}

export function scriptRenderizarVista(): string {
  return `${PY_BASE}
try:
    ruta = PARAMS["ruta"]
    salida = PARAMS["salida"]
    vista = PARAMS.get("vista", "perspectiva")
    ancho = int(PARAMS.get("ancho", 1024))
    alto = int(PARAMS.get("alto", 768))

    bpy.ops.wm.open_mainfile(filepath=ruta)
    escena = bpy.context.scene
    escena.render.engine = "BLENDER_EEVEE"
    escena.render.resolution_x = ancho
    escena.render.resolution_y = alto
    escena.render.resolution_percentage = 100
    escena.render.image_settings.file_format = "PNG"
    escena.render.filepath = salida

    if vista != "camara_escena":
        centro, radio = limites_mallas()
        dist = radio * 2.8
        direcciones = {
            "frontal": Vector((0.0, -1.0, 0.14)),
            "posterior": Vector((0.0, 1.0, 0.14)),
            "lateral_derecha": Vector((1.0, 0.0, 0.14)),
            "lateral_izquierda": Vector((-1.0, 0.0, 0.14)),
            "superior": Vector((0.0, -0.05, 1.0)),
            "perspectiva": Vector((0.75, -0.88, 0.50)),
        }
        vec = direcciones.get(vista, direcciones["perspectiva"]).normalized()
        cam_data = bpy.data.cameras.new("Camara_Render_Temp")
        cam_data.lens = 50.0
        cam_obj = bpy.data.objects.new("Camara_Render_Temp", cam_data)
        escena.collection.objects.link(cam_obj)
        cam_obj.location = centro + vec * dist
        apuntar_objeto(cam_obj, centro)
        escena.camera = cam_obj

    bpy.ops.render.render(write_still=True)
    emitir({"ok": True, "imagen": salida, "vista": vista, "resolucion": [ancho, alto]})
except Exception as exc:
    fallar(f"{exc}\\n{traceback.format_exc()}")
`;
}

export function scriptExportarModelo(): string {
  return `${PY_BASE}
try:
    ruta = PARAMS["ruta"]
    salida = PARAMS["salida"]
    formato = PARAMS["formato"]
    bpy.ops.wm.open_mainfile(filepath=ruta)

    if formato == "glb":
        bpy.ops.export_scene.gltf(filepath=salida, export_format="GLB")
    elif formato == "obj":
        bpy.ops.wm.obj_export(filepath=salida)
    elif formato == "fbx":
        bpy.ops.export_scene.fbx(filepath=salida)
    elif formato == "stl":
        bpy.ops.wm.stl_export(filepath=salida)
    else:
        raise ValueError(f"Formato no soportado: {formato}")

    emitir({"ok": True, "archivo_exportado": salida, "formato": formato})
except Exception as exc:
    fallar(str(exc))
`;
}
