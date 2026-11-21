param([string]$ArchivoInicial = "")

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Web.Extensions

$ErrorActionPreference = "Stop"

function Buscar-Blender {
    $envPath = $env:BLENDER_PATH
    if ($envPath -and (Test-Path $envPath)) { return $envPath }
    $raices = @(
        "C:\Program Files\Blender Foundation",
        (Join-Path $env:LOCALAPPDATA "Programs\Blender Foundation")
    )
    foreach ($raiz in $raices) {
        if (-not (Test-Path $raiz)) { continue }
        $dirs = Get-ChildItem -Path $raiz -Directory -Filter "Blender*" | Sort-Object Name -Descending
        foreach ($d in $dirs) {
            $exe = Join-Path $d.FullName "blender.exe"
            if (Test-Path $exe) { return $exe }
        }
    }
    return "blender.exe"
}

function Obtener-CarpetaTrabajo {
    if ($env:CRACION_AN_DIR -and $env:CRACION_AN_DIR.Trim()) {
        return [System.IO.Path]::GetFullPath($env:CRACION_AN_DIR.Trim())
    }
    $homeDir = [Environment]::GetFolderPath("UserProfile")
    $candidatos = @(
        (Join-Path $homeDir "OneDrive\Escritorio"),
        (Join-Path $homeDir "OneDrive\Desktop"),
        (Join-Path $homeDir "Escritorio"),
        (Join-Path $homeDir "Desktop")
    )
    $esc = $candidatos | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $esc) { $esc = Join-Path $homeDir "Desktop" }
    $dir = Join-Path $esc "cracion-AN"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

$script:BlenderExe = Buscar-Blender
$script:CarpetaTrabajo = Obtener-CarpetaTrabajo
$script:RutaPreview = Join-Path $env:TEMP "cracion_an_preview.png"
$script:ArchivoActual = ""
$script:Objetos = @()
$script:Bloqueado = $false
$script:JsonSer = New-Object System.Web.Script.Serialization.JavaScriptSerializer

$PY_BASE = @"
import bpy, json, math, os
from mathutils import Vector

PARAMS = json.loads(os.environ.get('CRACION_AN_PARAMS', '{}'))

def emitir(d):
    print('CRACION_AN_JSON:' + json.dumps(d, ensure_ascii=False))

MATERIALES_PBR = {
    'blanco_estudio': {'nombre': 'Mat_Blanco_Estudio', 'color': (0.85, 0.85, 0.87, 1.0), 'metallic': 0.0, 'roughness': 0.45, 'emission': 0.0},
    'metal_cromado': {'nombre': 'Mat_Metal_Cromado', 'color': (0.88, 0.90, 0.92, 1.0), 'metallic': 1.0, 'roughness': 0.14, 'emission': 0.0},
    'oro': {'nombre': 'Mat_Oro', 'color': (0.95, 0.75, 0.28, 1.0), 'metallic': 1.0, 'roughness': 0.20, 'emission': 0.0},
    'cobre': {'nombre': 'Mat_Cobre', 'color': (0.88, 0.45, 0.28, 1.0), 'metallic': 1.0, 'roughness': 0.24, 'emission': 0.0},
    'plastico_rojo': {'nombre': 'Mat_Plastico_Rojo', 'color': (0.82, 0.14, 0.14, 1.0), 'metallic': 0.0, 'roughness': 0.30, 'emission': 0.0},
    'azul_cobalto': {'nombre': 'Mat_Azul_Cobalto', 'color': (0.14, 0.36, 0.86, 1.0), 'metallic': 0.0, 'roughness': 0.32, 'emission': 0.0},
    'verde_esmeralda': {'nombre': 'Mat_Verde_Esmeralda', 'color': (0.12, 0.65, 0.38, 1.0), 'metallic': 0.0, 'roughness': 0.34, 'emission': 0.0},
    'madera_calida': {'nombre': 'Mat_Madera_Calida', 'color': (0.48, 0.28, 0.14, 1.0), 'metallic': 0.0, 'roughness': 0.58, 'emission': 0.0},
    'vidrio': {'nombre': 'Mat_Vidrio', 'color': (0.88, 0.95, 1.0, 1.0), 'metallic': 0.0, 'roughness': 0.06, 'emission': 0.0},
    'emisivo_cyan': {'nombre': 'Mat_Emisivo_Cyan', 'color': (0.15, 0.85, 1.0, 1.0), 'metallic': 0.0, 'roughness': 0.25, 'emission': 3.5},
}

def asignar_material(obj, clave):
    if not hasattr(obj.data, 'materials'): return
    spec = MATERIALES_PBR.get(clave, MATERIALES_PBR['blanco_estudio'])
    mat = bpy.data.materials.get(spec['nombre']) or bpy.data.materials.new(name=spec['nombre'])
    if mat.node_tree is None: mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    if bsdf:
        bsdf.inputs['Base Color'].default_value = spec['color']
        bsdf.inputs['Metallic'].default_value = spec['metallic']
        bsdf.inputs['Roughness'].default_value = spec['roughness']
        if 'Emission Color' in bsdf.inputs: bsdf.inputs['Emission Color'].default_value = spec['color']
        if 'Emission Strength' in bsdf.inputs: bsdf.inputs['Emission Strength'].default_value = spec['emission']
    if obj.data.materials: obj.data.materials[0] = mat
    else: obj.data.materials.append(mat)

def apuntar(obj, target):
    obj.rotation_euler = (target - obj.location).to_track_quat('-Z', 'Y').to_euler()
# ---
"@

$SCRIPT_CREAR = $PY_BASE + "`n" + @"
try:
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    esc = bpy.context.scene
    esc.render.engine = 'BLENDER_EEVEE'
    if esc.world is None: esc.world = bpy.data.worlds.new('Mundo')
    if esc.world.node_tree is None: esc.world.use_nodes = True
    bg = esc.world.node_tree.nodes.get('Background')
    if bg:
        bg.inputs['Color'].default_value = (0.055, 0.065, 0.082, 1.0)
        bg.inputs['Strength'].default_value = 0.85
    for nom, loc, eng, sz, rot in [
        ('Luz_Principal', (3.8, -3.6, 4.2), 480.0, 2.5, (52, 0, 45)),
        ('Luz_Relleno', (-4.2, -2.2, 2.4), 200.0, 3.5, (65, 0, -58)),
        ('Luz_Contorno', (0.0, 4.4, 3.6), 280.0, 2.0, (125, 0, 0)),
    ]:
        ld = bpy.data.lights.new(nom, 'AREA'); ld.energy = eng; ld.size = sz
        lo = bpy.data.objects.new(nom, ld); esc.collection.objects.link(lo)
        lo.location = loc; lo.rotation_euler = tuple(math.radians(a) for a in rot)
    cd = bpy.data.cameras.new('Camara_Principal'); cd.lens = 50.0
    co = bpy.data.objects.new('Camara_Principal', cd); esc.collection.objects.link(co)
    co.location = (3.4, -3.8, 2.4); apuntar(co, Vector((0, 0, 0.4))); esc.camera = co
    pl = PARAMS.get('plantilla', 'composicion_base')
    if pl in ('estudio_producto', 'composicion_base'):
        bpy.ops.mesh.primitive_plane_add(size=6.0, location=(0, 0, -0.65))
        s = bpy.context.active_object; s.name = 'Suelo_Estudio'; asignar_material(s, 'blanco_estudio')
    if pl == 'estudio_producto':
        bpy.ops.mesh.primitive_cube_add(size=1.2, location=(0, 0, 0))
        c = bpy.context.active_object; c.name = 'Cubo_Principal'; c.rotation_euler = (0, 0, math.radians(20)); asignar_material(c, 'azul_cobalto')
    elif pl == 'composicion_base':
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.65, segments=32, ring_count=16, location=(-1.1, 0.2, 0))
        e = bpy.context.active_object; e.name = 'Esfera_Oro'; asignar_material(e, 'oro')
        for p in e.data.polygons: p.use_smooth = True
        bpy.ops.mesh.primitive_cube_add(size=1.1, location=(0.2, -0.1, 0))
        c = bpy.context.active_object; c.name = 'Cubo_Azul'; c.rotation_euler = (0, 0, math.radians(25)); asignar_material(c, 'azul_cobalto')
        bpy.ops.mesh.primitive_torus_add(major_radius=0.65, minor_radius=0.22, location=(1.35, 0.15, 0.1))
        t = bpy.context.active_object; t.name = 'Aro_Cromado'; t.rotation_euler = (math.radians(55), math.radians(15), 0); asignar_material(t, 'metal_cromado')
        for p in t.data.polygons: p.use_smooth = True
    bpy.ops.wm.save_as_mainfile(filepath=PARAMS['ruta'])
    emitir({'ok': True})
except Exception as ex:
    emitir({'ok': False, 'error': str(ex)})
"@

$SCRIPT_INSPECCIONAR = $PY_BASE + "`n" + @"
try:
    bpy.ops.wm.open_mainfile(filepath=PARAMS['ruta'])
    objs = []
    for o in bpy.data.objects:
        d = {
            'nombre': o.name, 'tipo': o.type,
            'posicion': [round(v, 3) for v in o.location],
            'rotacion': [round(math.degrees(v), 1) for v in o.rotation_euler],
            'escala': [round(v, 3) for v in o.scale],
            'vertices': len(o.data.vertices) if o.type == 'MESH' else 0,
            'caras': len(o.data.polygons) if o.type == 'MESH' else 0,
        }
        objs.append(d)
    emitir({'ok': True, 'objetos': objs})
except Exception as ex:
    emitir({'ok': False, 'error': str(ex)})
"@

$SCRIPT_RENDER = $PY_BASE + "`n" + @"
try:
    bpy.ops.wm.open_mainfile(filepath=PARAMS['ruta'])
    esc = bpy.context.scene
    esc.render.engine = 'BLENDER_EEVEE'
    esc.render.resolution_x = 960; esc.render.resolution_y = 640
    esc.render.resolution_percentage = 100
    esc.render.image_settings.file_format = 'PNG'
    esc.render.filepath = PARAMS['salida']
    vista = PARAMS.get('vista', 'perspectiva')
    if vista != 'camara_escena':
        dg = bpy.context.evaluated_depsgraph_get()
        mins = Vector((1e9, 1e9, 1e9)); maxs = Vector((-1e9, -1e9, -1e9)); hay = False
        for o in esc.objects:
            if o.type not in ('MESH', 'FONT'): continue
            hay = True; ev = o.evaluated_get(dg)
            for esq in ev.bound_box:
                p = ev.matrix_world @ Vector(esq)
                mins.x = min(mins.x, p.x); mins.y = min(mins.y, p.y); mins.z = min(mins.z, p.z)
                maxs.x = max(maxs.x, p.x); maxs.y = max(maxs.y, p.y); maxs.z = max(maxs.z, p.z)
        centro = (mins + maxs) * 0.5 if hay else Vector((0, 0, 0))
        radio = max((maxs - mins).length * 0.5, 0.8) if hay else 2.2
        dirs = {
            'frontal': Vector((0, -1, 0.14)), 'posterior': Vector((0, 1, 0.14)),
            'lateral_derecha': Vector((1, 0, 0.14)), 'lateral_izquierda': Vector((-1, 0, 0.14)),
            'superior': Vector((0, -0.05, 1)), 'perspectiva': Vector((0.75, -0.88, 0.50))
        }
        vec = dirs.get(vista, dirs['perspectiva']).normalized()
        cd = bpy.data.cameras.new('Cam_Preview'); cd.lens = 50.0
        co = bpy.data.objects.new('Cam_Preview', cd); esc.collection.objects.link(co)
        co.location = centro + vec * (radio * 2.5); apuntar(co, centro); esc.camera = co
    bpy.ops.render.render(write_still=True)
    emitir({'ok': True})
except Exception as ex:
    emitir({'ok': False, 'error': str(ex)})
"@

$SCRIPT_AGREGAR = $PY_BASE + "`n" + @"
try:
    bpy.ops.wm.open_mainfile(filepath=PARAMS['ruta'])
    t = PARAMS['tipo']
    if t == 'cubo': bpy.ops.mesh.primitive_cube_add(size=1.2)
    elif t == 'esfera': bpy.ops.mesh.primitive_uv_sphere_add(radius=0.65, segments=32, ring_count=16)
    elif t == 'cilindro': bpy.ops.mesh.primitive_cylinder_add(radius=0.5, depth=1.4, vertices=32)
    elif t == 'cono': bpy.ops.mesh.primitive_cone_add(radius1=0.65, depth=1.4, vertices=32)
    elif t == 'toroide': bpy.ops.mesh.primitive_torus_add(major_radius=0.65, minor_radius=0.22)
    elif t == 'plano': bpy.ops.mesh.primitive_plane_add(size=4.5)
    elif t == 'texto_3d':
        bpy.ops.object.text_add(); bpy.context.active_object.data.body = 'cracion AN'; bpy.context.active_object.data.extrude = 0.08
    elif t == 'luz_area':
        ld = bpy.data.lights.new(PARAMS['nombre'], 'AREA'); ld.energy = 300.0
        lo = bpy.data.objects.new(PARAMS['nombre'], ld); bpy.context.scene.collection.objects.link(lo)
        lo.location = (0, -2, 2.5); bpy.ops.wm.save_as_mainfile(filepath=PARAMS['ruta']); emitir({'ok': True}); raise SystemExit(0)
    o = bpy.context.active_object; o.name = PARAMS['nombre']
    if o.type == 'MESH':
        for p in o.data.polygons: p.use_smooth = True
    asignar_material(o, PARAMS.get('material', 'blanco_estudio'))
    bpy.ops.wm.save_as_mainfile(filepath=PARAMS['ruta'])
    emitir({'ok': True})
except SystemExit:
    pass
except Exception as ex:
    emitir({'ok': False, 'error': str(ex)})
"@

$SCRIPT_MODIFICAR = $PY_BASE + "`n" + @"
try:
    bpy.ops.wm.open_mainfile(filepath=PARAMS['ruta'])
    o = bpy.data.objects.get(PARAMS['nombre'])
    if o is None: raise ValueError('Objeto no encontrado')
    o.location = PARAMS['posicion']
    o.rotation_euler = tuple(math.radians(a) for a in PARAMS['rotacion'])
    o.scale = PARAMS['escala']
    asignar_material(o, PARAMS['material'])
    sub = int(PARAMS.get('subdivisiones', -1))
    if sub >= 0 and o.type == 'MESH':
        mod = o.modifiers.get('Subdivision') or o.modifiers.new('Subdivision', 'SUBSURF')
        mod.levels = sub; mod.render_levels = sub
    bpy.ops.wm.save_as_mainfile(filepath=PARAMS['ruta'])
    emitir({'ok': True})
except Exception as ex:
    emitir({'ok': False, 'error': str(ex)})
"@

$SCRIPT_ELIMINAR = $PY_BASE + "`n" + @"
try:
    bpy.ops.wm.open_mainfile(filepath=PARAMS['ruta'])
    o = bpy.data.objects.get(PARAMS['nombre'])
    if o: bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.wm.save_as_mainfile(filepath=PARAMS['ruta'])
    emitir({'ok': True})
except Exception as ex:
    emitir({'ok': False, 'error': str(ex)})
"@

$SCRIPT_PYTHON = $PY_BASE + "`n" + @"
try:
    bpy.ops.wm.open_mainfile(filepath=PARAMS['ruta'])
    exec(compile(PARAMS['codigo'], '<script>', 'exec'), {'bpy': bpy, 'math': math, 'Vector': Vector, 'asignar_material': asignar_material})
    bpy.ops.wm.save_as_mainfile(filepath=PARAMS['ruta'])
    emitir({'ok': True})
except Exception as ex:
    emitir({'ok': False, 'error': str(ex)})
"@

$SCRIPT_EXPORTAR = $PY_BASE + "`n" + @"
try:
    bpy.ops.wm.open_mainfile(filepath=PARAMS['ruta'])
    fmt = PARAMS['formato']; sal = PARAMS['salida']
    if fmt == 'glb': bpy.ops.export_scene.gltf(filepath=sal, export_format='GLB')
    elif fmt == 'obj': bpy.ops.wm.obj_export(filepath=sal)
    elif fmt == 'fbx': bpy.ops.export_scene.fbx(filepath=sal)
    elif fmt == 'stl': bpy.ops.wm.stl_export(filepath=sal)
    emitir({'ok': True})
except Exception as ex:
    emitir({'ok': False, 'error': str(ex)})
"@

function Invocar-Blender([string]$CodigoPy, [hashtable]$Parametros) {
    $tempPy = Join-Path $env:TEMP ("cracion_an_" + [Guid]::NewGuid().ToString("N") + ".py")
    [System.IO.File]::WriteAllText($tempPy, $CodigoPy, [System.Text.Encoding]::UTF8)
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $script:BlenderExe
        $psi.Arguments = "--background --factory-startup --python `"$tempPy`""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.EnvironmentVariables["CRACION_AN_PARAMS"] = ($Parametros | ConvertTo-Json -Compress -Depth 5)

        $proc = [System.Diagnostics.Process]::Start($psi)
        $out = $proc.StandardOutput.ReadToEnd()
        $err = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()

        $lineas = $out -split "`r?`n"
        $lineaJson = $lineas | Where-Object { $_ -like "CRACION_AN_JSON:*" } | Select-Object -Last 1
        if (-not $lineaJson) {
            throw "Blender no devolvio respuesta JSON. $err"
        }
        $data = $script:JsonSer.DeserializeObject($lineaJson.Substring("CRACION_AN_JSON:".Length))
        if ($data["ok"] -eq $false) {
            throw [string]$data["error"]
        }
        return $data
    } finally {
        if (Test-Path $tempPy) { Remove-Item $tempPy -Force -ErrorAction SilentlyContinue }
    }
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="cracion AN - Estudio 3D para Blender 5.2"
        Width="1320" Height="840" MinWidth="1040" MinHeight="660"
        WindowStartupLocation="CenterScreen" Background="#0F131A" Foreground="#E6EDF3">
  <DockPanel LastChildFill="True">
    <Border DockPanel.Dock="Top" Background="#161B24" BorderBrush="#2A3444" BorderThickness="0,0,0,1" Padding="12,8">
      <WrapPanel Orientation="Horizontal" VerticalAlignment="Center">
        <Border Background="#2563EB" CornerRadius="5" Padding="8,4" Margin="0,0,10,0">
          <TextBlock Text="cracion AN" FontWeight="Bold" Foreground="White" FontSize="13"/>
        </Border>
        <ComboBox x:Name="CmbProyectos" Width="210" Margin="0,0,8,0" VerticalContentAlignment="Center"/>
        <Button x:Name="BtnNuevo" Content="+ Nuevo .blend" Background="#2563EB" Foreground="White" BorderBrush="#374151" Padding="9,5" Margin="0,0,6,0"/>
        <Button x:Name="BtnExpGlb" Content="Exportar GLB" Background="#1F2937" Foreground="White" BorderBrush="#374151" Padding="9,5" Margin="0,0,6,0"/>
        <Button x:Name="BtnExpObj" Content="Exportar OBJ" Background="#1F2937" Foreground="White" BorderBrush="#374151" Padding="9,5" Margin="0,0,6,0"/>
        <Button x:Name="BtnExpFbx" Content="Exportar FBX" Background="#1F2937" Foreground="White" BorderBrush="#374151" Padding="9,5" Margin="0,0,6,0"/>
        <Button x:Name="BtnExpStl" Content="Exportar STL" Background="#1F2937" Foreground="White" BorderBrush="#374151" Padding="9,5" Margin="0,0,6,0"/>
        <Button x:Name="BtnAbrirBlender" Content="Abrir en Blender 5.2" Background="#059669" Foreground="White" BorderBrush="#374151" Padding="9,5" Margin="0,0,6,0"/>
        <Button x:Name="BtnCarpeta" Content="Carpeta" Background="#1F2937" Foreground="White" BorderBrush="#374151" Padding="9,5"/>
      </WrapPanel>
    </Border>

    <Border DockPanel.Dock="Bottom" Background="#161B24" BorderBrush="#2A3444" BorderThickness="0,1,0,0" Padding="12,6">
      <TextBlock x:Name="TxtEstado" Text="Iniciando Blender 5.2..." Foreground="#9CA3AF" FontSize="12"/>
    </Border>

    <Grid>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="255"/>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="290"/>
      </Grid.ColumnDefinitions>

      <Border Grid.Column="0" Background="#151A22" BorderBrush="#2A3444" BorderThickness="0,0,1,0" Padding="10">
        <DockPanel LastChildFill="True">
          <TextBlock DockPanel.Dock="Top" Text="AGREGAR OBJETO 3D" FontSize="11" FontWeight="Bold" Foreground="#8B9BB0" Margin="0,0,0,8"/>
          <UniformGrid DockPanel.Dock="Top" Columns="2" Margin="0,0,0,14">
            <Button x:Name="BtnAddCubo" Content="Cubo" Background="#1E2633" Foreground="White" BorderBrush="#374151" Margin="2" Padding="6"/>
            <Button x:Name="BtnAddEsfera" Content="Esfera" Background="#1E2633" Foreground="White" BorderBrush="#374151" Margin="2" Padding="6"/>
            <Button x:Name="BtnAddCilindro" Content="Cilindro" Background="#1E2633" Foreground="White" BorderBrush="#374151" Margin="2" Padding="6"/>
            <Button x:Name="BtnAddCono" Content="Cono" Background="#1E2633" Foreground="White" BorderBrush="#374151" Margin="2" Padding="6"/>
            <Button x:Name="BtnAddToroide" Content="Toroide" Background="#1E2633" Foreground="White" BorderBrush="#374151" Margin="2" Padding="6"/>
            <Button x:Name="BtnAddPlano" Content="Plano" Background="#1E2633" Foreground="White" BorderBrush="#374151" Margin="2" Padding="6"/>
            <Button x:Name="BtnAddTexto" Content="Texto 3D" Background="#1E2633" Foreground="White" BorderBrush="#374151" Margin="2" Padding="6"/>
            <Button x:Name="BtnAddLuz" Content="Luz Area" Background="#1E2633" Foreground="White" BorderBrush="#374151" Margin="2" Padding="6"/>
          </UniformGrid>
          <TextBlock DockPanel.Dock="Top" Text="OBJETOS EN ESCENA" FontSize="11" FontWeight="Bold" Foreground="#8B9BB0" Margin="0,0,0,6"/>
          <Button x:Name="BtnEliminarObj" DockPanel.Dock="Bottom" Content="Eliminar Objeto Seleccionado" Background="#7F1D1D" Foreground="White" BorderBrush="#374151" Padding="6" Margin="0,8,0,0"/>
          <ListBox x:Name="LstObjetos" Background="#0F131A" Foreground="#E6EDF3" BorderBrush="#2A3444"/>
        </DockPanel>
      </Border>

      <DockPanel Grid.Column="1" Background="#0B0E14" LastChildFill="True">
        <Border DockPanel.Dock="Top" Background="#131820" BorderBrush="#2A3444" BorderThickness="0,0,0,1" Padding="10,6">
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="Vista Blender 5.2: " VerticalAlignment="Center" Foreground="#9CA3AF" Margin="0,0,6,0"/>
            <ComboBox x:Name="CmbVista" Width="160" Margin="0,0,8,0">
              <ComboBoxItem Content="perspectiva" IsSelected="True"/>
              <ComboBoxItem Content="frontal"/>
              <ComboBoxItem Content="posterior"/>
              <ComboBoxItem Content="lateral_derecha"/>
              <ComboBoxItem Content="lateral_izquierda"/>
              <ComboBoxItem Content="superior"/>
              <ComboBoxItem Content="camara_escena"/>
            </ComboBox>
            <Button x:Name="BtnRender" Content="Renderizar Vista" Background="#2563EB" Foreground="White" BorderBrush="#374151" Padding="9,4"/>
          </StackPanel>
        </Border>
        <Grid>
          <TextBlock x:Name="TxtVacio" Text="Renderizando vista previa con Blender 5.2..." HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="#6B7280" FontSize="14"/>
          <Image x:Name="ImgPreview" Stretch="Uniform" Margin="12"/>
        </Grid>
      </DockPanel>

      <Border Grid.Column="2" Background="#151A22" BorderBrush="#2A3444" BorderThickness="1,0,0,0" Padding="10">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel>
            <TextBlock Text="PROPIEDADES DEL OBJETO" FontSize="11" FontWeight="Bold" Foreground="#8B9BB0" Margin="0,0,0,8"/>
            <TextBlock Text="Posicion (X, Y, Z)" FontSize="11" Foreground="#9CA3AF" Margin="0,0,0,3"/>
            <UniformGrid Columns="3" Margin="0,0,0,6">
              <TextBox x:Name="TxtPosX" Text="0" Background="#0B0E14" Foreground="#E6EDF3" BorderBrush="#2A3444" Margin="2,0" Padding="4" TextAlignment="Center"/>
              <TextBox x:Name="TxtPosY" Text="0" Background="#0B0E14" Foreground="#E6EDF3" BorderBrush="#2A3444" Margin="2,0" Padding="4" TextAlignment="Center"/>
              <TextBox x:Name="TxtPosZ" Text="0" Background="#0B0E14" Foreground="#E6EDF3" BorderBrush="#2A3444" Margin="2,0" Padding="4" TextAlignment="Center"/>
            </UniformGrid>
            <TextBlock Text="Rotacion grados (X, Y, Z)" FontSize="11" Foreground="#9CA3AF" Margin="0,0,0,3"/>
            <UniformGrid Columns="3" Margin="0,0,0,6">
              <TextBox x:Name="TxtRotX" Text="0" Background="#0B0E14" Foreground="#E6EDF3" BorderBrush="#2A3444" Margin="2,0" Padding="4" TextAlignment="Center"/>
              <TextBox x:Name="TxtRotY" Text="0" Background="#0B0E14" Foreground="#E6EDF3" BorderBrush="#2A3444" Margin="2,0" Padding="4" TextAlignment="Center"/>
              <TextBox x:Name="TxtRotZ" Text="0" Background="#0B0E14" Foreground="#E6EDF3" BorderBrush="#2A3444" Margin="2,0" Padding="4" TextAlignment="Center"/>
            </UniformGrid>
            <TextBlock Text="Escala (X, Y, Z)" FontSize="11" Foreground="#9CA3AF" Margin="0,0,0,3"/>
            <UniformGrid Columns="3" Margin="0,0,0,8">
              <TextBox x:Name="TxtEscX" Text="1" Background="#0B0E14" Foreground="#E6EDF3" BorderBrush="#2A3444" Margin="2,0" Padding="4" TextAlignment="Center"/>
              <TextBox x:Name="TxtEscY" Text="1" Background="#0B0E14" Foreground="#E6EDF3" BorderBrush="#2A3444" Margin="2,0" Padding="4" TextAlignment="Center"/>
              <TextBox x:Name="TxtEscZ" Text="1" Background="#0B0E14" Foreground="#E6EDF3" BorderBrush="#2A3444" Margin="2,0" Padding="4" TextAlignment="Center"/>
            </UniformGrid>

            <TextBlock Text="Material PBR" FontSize="11" Foreground="#9CA3AF" Margin="0,2,0,3"/>
            <ComboBox x:Name="CmbMaterial" Margin="0,0,0,8">
              <ComboBoxItem Content="blanco_estudio" IsSelected="True"/>
              <ComboBoxItem Content="metal_cromado"/>
              <ComboBoxItem Content="oro"/>
              <ComboBoxItem Content="cobre"/>
              <ComboBoxItem Content="plastico_rojo"/>
              <ComboBoxItem Content="azul_cobalto"/>
              <ComboBoxItem Content="verde_esmeralda"/>
              <ComboBoxItem Content="madera_calida"/>
              <ComboBoxItem Content="vidrio"/>
              <ComboBoxItem Content="emisivo_cyan"/>
            </ComboBox>

            <TextBlock Text="Subdivision suave" FontSize="11" Foreground="#9CA3AF" Margin="0,2,0,3"/>
            <ComboBox x:Name="CmbSubdiv" Margin="0,0,0,10">
              <ComboBoxItem Content="Sin cambio" IsSelected="True"/>
              <ComboBoxItem Content="0"/>
              <ComboBoxItem Content="1"/>
              <ComboBoxItem Content="2"/>
              <ComboBoxItem Content="3"/>
            </ComboBox>

            <Button x:Name="BtnAplicar" Content="Aplicar Cambios al Objeto" Background="#2563EB" Foreground="White" BorderBrush="#374151" Padding="7"/>

            <TextBlock Text="SCRIPT PYTHON (bpy) EN BLENDER" FontSize="11" FontWeight="Bold" Foreground="#8B9BB0" Margin="0,18,0,6"/>
            <TextBox x:Name="TxtPython" Height="130" AcceptsReturn="True" TextWrapping="NoWrap"
                     VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                     Background="#0B0E14" Foreground="#D1D5DB" BorderBrush="#2A3444" FontFamily="Consolas" FontSize="11.5"/>
            <Button x:Name="BtnEjecutarPy" Content="Ejecutar Script en Escena" Background="#0F766E" Foreground="White" BorderBrush="#374151" Padding="7" Margin="0,6,0,0"/>
          </StackPanel>
        </ScrollViewer>
      </Border>
    </Grid>
  </DockPanel>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$win = [Windows.Markup.XamlReader]::Load($reader)

$ctrl = @{}
foreach ($n in @(
    "CmbProyectos", "BtnNuevo", "BtnExpGlb", "BtnExpObj", "BtnExpFbx", "BtnExpStl", "BtnAbrirBlender", "BtnCarpeta",
    "TxtEstado", "LstObjetos", "BtnEliminarObj", "CmbVista", "BtnRender", "TxtVacio", "ImgPreview",
    "BtnAddCubo", "BtnAddEsfera", "BtnAddCilindro", "BtnAddCono", "BtnAddToroide", "BtnAddPlano", "BtnAddTexto", "BtnAddLuz",
    "TxtPosX", "TxtPosY", "TxtPosZ", "TxtRotX", "TxtRotY", "TxtRotZ", "TxtEscX", "TxtEscY", "TxtEscZ",
    "CmbMaterial", "CmbSubdiv", "BtnAplicar", "TxtPython", "BtnEjecutarPy"
)) {
    $ctrl[$n] = $win.FindName($n)
}
$ctrl["TxtPython"].Text = "# Ejemplo: agregar un toroide`nbpy.ops.mesh.primitive_torus_add(location=(0, 0, 1.2))`n"

function Refrescar-Proyectos([string]$preferido = "") {
    $script:Bloqueado = $true
    $ctrl["CmbProyectos"].Items.Clear()
    $blends = Get-ChildItem -Path $script:CarpetaTrabajo -Filter "*.blend" | Sort-Object LastWriteTime -Descending
    foreach ($b in $blends) { [void]$ctrl["CmbProyectos"].Items.Add($b.Name) }
    if ($preferido -and (Test-Path $preferido)) { $script:ArchivoActual = $preferido }
    elseif (-not $script:ArchivoActual -or -not (Test-Path $script:ArchivoActual)) {
        $script:ArchivoActual = ($blends | Select-Object -First 1).FullName
    }
    if ($script:ArchivoActual) {
        $ctrl["CmbProyectos"].SelectedItem = [System.IO.Path]::GetFileName($script:ArchivoActual)
    }
    $script:Bloqueado = $false
}

function Inspeccionar-Actual {
    if (-not $script:ArchivoActual) { return }
    $res = Invocar-Blender $SCRIPT_INSPECCIONAR @{ ruta = $script:ArchivoActual }
    $ctrl["LstObjetos"].Items.Clear()
    $script:Objetos = @()
    foreach ($o in $res["objetos"]) {
        $script:Objetos += $o
        $etq = if ($o["tipo"] -eq "MESH") { "$($o['nombre'])  [$($o['tipo']) | $($o['vertices'])v]" } else { "$($o['nombre'])  [$($o['tipo'])]" }
        [void]$ctrl["LstObjetos"].Items.Add($etq)
    }
    if ($ctrl["LstObjetos"].Items.Count -gt 0) { $ctrl["LstObjetos"].SelectedIndex = 0 }
}

function Renderizar-Actual {
    if (-not $script:ArchivoActual) { return }
    $vista = $ctrl["CmbVista"].SelectedItem.Content.ToString()
    $ctrl["TxtEstado"].Text = "Renderizando vista '$vista' con Blender 5.2..."
    $win.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
    $null = Invocar-Blender $SCRIPT_RENDER @{ ruta = $script:ArchivoActual; salida = $script:RutaPreview; vista = $vista }
    if (Test-Path $script:RutaPreview) {
        $bytes = [System.IO.File]::ReadAllBytes($script:RutaPreview)
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $ms = New-Object System.IO.MemoryStream(, $bytes)
        $bmp.BeginInit()
        $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmp.StreamSource = $ms
        $bmp.EndInit()
        $bmp.Freeze()
        $ms.Dispose()
        $ctrl["ImgPreview"].Source = $bmp
        $ctrl["TxtVacio"].Visibility = [System.Windows.Visibility]::Collapsed
        $ctrl["TxtEstado"].Text = "Listo · $([System.IO.Path]::GetFileName($script:ArchivoActual)) · Vista $vista"
    }
}

function Cargar-Todo {
    try {
        Inspeccionar-Actual
        Renderizar-Actual
    } catch {
        $ctrl["TxtEstado"].Text = "Error: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show($_.Exception.Message, "cracion AN", "OK", "Error") | Out-Null
    }
}

$ctrl["LstObjetos"].Add_SelectionChanged({
    $idx = $ctrl["LstObjetos"].SelectedIndex
    if ($idx -lt 0 -or $idx -ge $script:Objetos.Count) { return }
    $o = $script:Objetos[$idx]
    $ctrl["TxtPosX"].Text = [string]$o["posicion"][0]
    $ctrl["TxtPosY"].Text = [string]$o["posicion"][1]
    $ctrl["TxtPosZ"].Text = [string]$o["posicion"][2]
    $ctrl["TxtRotX"].Text = [string]$o["rotacion"][0]
    $ctrl["TxtRotY"].Text = [string]$o["rotacion"][1]
    $ctrl["TxtRotZ"].Text = [string]$o["rotacion"][2]
    $ctrl["TxtEscX"].Text = [string]$o["escala"][0]
    $ctrl["TxtEscY"].Text = [string]$o["escala"][1]
    $ctrl["TxtEscZ"].Text = [string]$o["escala"][2]
})

$ctrl["CmbProyectos"].Add_SelectionChanged({
    if ($script:Bloqueado -or -not $ctrl["CmbProyectos"].SelectedItem) { return }
    $ruta = Join-Path $script:CarpetaTrabajo $ctrl["CmbProyectos"].SelectedItem.ToString()
    if ($ruta -ne $script:ArchivoActual -and (Test-Path $ruta)) {
        $script:ArchivoActual = $ruta
        Cargar-Todo
    }
})

$ctrl["BtnRender"].Add_Click({ try { Renderizar-Actual } catch { [System.Windows.MessageBox]::Show($_.Exception.Message, "cracion AN", "OK", "Error") | Out-Null } })

$mapaAgregar = @{
    "BtnAddCubo" = @("cubo", "Cubo")
    "BtnAddEsfera" = @("esfera", "Esfera")
    "BtnAddCilindro" = @("cilindro", "Cilindro")
    "BtnAddCono" = @("cono", "Cono")
    "BtnAddToroide" = @("toroide", "Toroide")
    "BtnAddPlano" = @("plano", "Plano")
    "BtnAddTexto" = @("texto_3d", "Texto")
    "BtnAddLuz" = @("luz_area", "Luz")
}
foreach ($k in $mapaAgregar.Keys) {
    $tipo = $mapaAgregar[$k][0]
    $label = $mapaAgregar[$k][1]
    $ctrl[$k].Add_Click({
        if (-not $script:ArchivoActual) { return }
        $nom = "$label`_$($script:Objetos.Count + 1)"
        $mat = $ctrl["CmbMaterial"].SelectedItem.Content.ToString()
        $ctrl["TxtEstado"].Text = "Agregando $label en Blender 5.2..."
        $win.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
        $null = Invocar-Blender $SCRIPT_AGREGAR @{ ruta = $script:ArchivoActual; tipo = $tipo; nombre = $nom; material = $mat }
        Cargar-Todo
    }.GetNewClosure())
}

$ctrl["BtnAplicar"].Add_Click({
    $idx = $ctrl["LstObjetos"].SelectedIndex
    if ($idx -lt 0) { return }
    $nom = $script:Objetos[$idx]["nombre"]
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $subTxt = $ctrl["CmbSubdiv"].SelectedItem.Content.ToString()
    $sub = if ($subTxt -eq "Sin cambio") { -1 } else { [int]$subTxt }
    $null = Invocar-Blender $SCRIPT_MODIFICAR @{
        ruta = $script:ArchivoActual; nombre = $nom
        posicion = @([double]::Parse($ctrl["TxtPosX"].Text, $inv), [double]::Parse($ctrl["TxtPosY"].Text, $inv), [double]::Parse($ctrl["TxtPosZ"].Text, $inv))
        rotacion = @([double]::Parse($ctrl["TxtRotX"].Text, $inv), [double]::Parse($ctrl["TxtRotY"].Text, $inv), [double]::Parse($ctrl["TxtRotZ"].Text, $inv))
        escala = @([double]::Parse($ctrl["TxtEscX"].Text, $inv), [double]::Parse($ctrl["TxtEscY"].Text, $inv), [double]::Parse($ctrl["TxtEscZ"].Text, $inv))
        material = $ctrl["CmbMaterial"].SelectedItem.Content.ToString()
        subdivisiones = $sub
    }
    Cargar-Todo
})

$ctrl["BtnEliminarObj"].Add_Click({
    $idx = $ctrl["LstObjetos"].SelectedIndex
    if ($idx -lt 0) { return }
    $nom = $script:Objetos[$idx]["nombre"]
    $null = Invocar-Blender $SCRIPT_ELIMINAR @{ ruta = $script:ArchivoActual; nombre = $nom }
    Cargar-Todo
})

$ctrl["BtnEjecutarPy"].Add_Click({
    if (-not $script:ArchivoActual) { return }
    $null = Invocar-Blender $SCRIPT_PYTHON @{ ruta = $script:ArchivoActual; codigo = $ctrl["TxtPython"].Text }
    Cargar-Todo
})

foreach ($par in @(@("BtnExpGlb", "glb"), @("BtnExpObj", "obj"), @("BtnExpFbx", "fbx"), @("BtnExpStl", "stl"))) {
    $fmt = $par[1]
    $ctrl[$par[0]].Add_Click({
        if (-not $script:ArchivoActual) { return }
        $base = [System.IO.Path]::GetFileNameWithoutExtension($script:ArchivoActual)
        $sal = Join-Path $script:CarpetaTrabajo "$base.$fmt"
        $null = Invocar-Blender $SCRIPT_EXPORTAR @{ ruta = $script:ArchivoActual; salida = $sal; formato = $fmt }
        $ctrl["TxtEstado"].Text = "Exportado: $sal"
        [System.Windows.MessageBox]::Show("Modelo exportado en:`n$sal", "cracion AN", "OK", "Information") | Out-Null
    }.GetNewClosure())
}

$ctrl["BtnAbrirBlender"].Add_Click({
    if ($script:ArchivoActual -and (Test-Path $script:ArchivoActual)) {
        Start-Process -FilePath $script:BlenderExe -ArgumentList "`"$($script:ArchivoActual)`""
    }
})
$ctrl["BtnCarpeta"].Add_Click({ Start-Process "explorer.exe" $script:CarpetaTrabajo })

$ctrl["BtnNuevo"].Add_Click({
    $nombre = "escena_" + (Get-Date -Format "HHmmss") + ".blend"
    $ruta = Join-Path $script:CarpetaTrabajo $nombre
    $null = Invocar-Blender $SCRIPT_CREAR @{ ruta = $ruta; plantilla = "composicion_base" }
    Refrescar-Proyectos $ruta
    Cargar-Todo
})

$win.Add_ContentRendered({
    $blends = Get-ChildItem -Path $script:CarpetaTrabajo -Filter "*.blend"
    if ($blends.Count -eq 0) {
        $inicial = Join-Path $script:CarpetaTrabajo "escena_inicial.blend"
        $null = Invocar-Blender $SCRIPT_CREAR @{ ruta = $inicial; plantilla = "composicion_base" }
    }
    Refrescar-Proyectos $ArchivoInicial
    Cargar-Todo
})

$win.ShowDialog() | Out-Null
