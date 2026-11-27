"""Verify the five authored models and both static exports in background Blender."""
import json
import struct
from pathlib import Path

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from pxr import Usd, UsdGeom, UsdShade

FOLDER = Path(__file__).resolve().parents[1] / "assets/model"
# Width, depth, height in mm, native pixels, ppi, number of battery cells.
MODELS = {
    "macbook-pro-14": (310.8, 216.3, 15, 3024, 1986, 254, 6),
    "macbook-pro-14-notch": (312.6, 221.2, 15.5, 3024, 1964, 254, 6),
    "macbook-pro-16-notch": (355.7, 248.1, 16.8, 3456, 2234, 254, 6),
    "macbook-air-13": (304.1, 215, 11.3, 2560, 1664, 224, 4),
    "macbook-air-15": (340.4, 237.6, 11.5, 2880, 1864, 224, 6),
}
LID = {"Shell_Lid", "Display", "Display_Bezel", "Logo"}
SHARED = LID | set("Shell_Bottom Chassis_Rail Lid_Hinge Board SoC_Package Keyboard "
                   "Keyboard_Deck Trackpad SSD_0 SSD_1 Die_GPU Die_Perf "
                   "Speaker_L Speaker_R Ports_L Ports_R".split())


def names(model, cells):
    expected = SHARED | {f"Battery_Cell_{i}" for i in range(cells)}
    cutout = "Dynamic_Island" if model == "macbook-pro-14" else "Display_Notch"
    expected.add(cutout)
    if "air" in model:
        expected.add("Heatsink")
    else:
        expected.update({"Heatpipe", "Die_Super" if cutout == "Dynamic_Island" else "Die_Eff"})
        expected.update(f"Fan_{side}_{part}" for side in "LR" for part in ["Rotor", "Housing"])
    return expected, cutout


def thermal(name):
    return name.startswith(("Die_", "SSD_", "Battery_Cell_")) or name.endswith("_Housing")


EXTERIOR = LID | {"Shell_Bottom", "Chassis_Rail", "Keyboard_Deck", "Keyboard",
                  "Display_Notch", "Dynamic_Island"}


def check_base_color(owner, material, rgb):
    # Test each binding: an exterior material shared with the board is still an interior color.
    if owner in EXTERIOR and material.replace(" ", "_") != "Machined_graphite_interior":
        return
    channels = tuple(rgb)[:3]
    assert max(channels) - min(channels) <= .01 + 1e-8, (owner, material, tuple(channels))


def dimensions(points):
    return [1000 * (max(p[i] for p in points) - min(p[i] for p in points)) for i in range(3)]


def close_dimensions(actual, expected):
    assert max(abs(a - b) for a, b in zip(actual, expected)) <= .5, (actual, expected)


def world_points(obj):
    return [obj.matrix_world @ v.co for v in obj.data.vertices]


def check_logo_center(logo, lid):
    def center_x(points):
        xs = [p[0] for p in points]
        return (min(xs) + max(xs)) / 2

    offset_mm = abs(center_x(logo) - center_x(lid)) * 1000
    assert offset_mm <= .05, f"Logo X offset from lid center: {offset_mm:.4f} mm"


def check_bottom(scene):
    meshes = [o for o in scene.objects if o.type == "MESH" and o.name != "Shell_Bottom"]
    trees = {}
    for obj in meshes:
        vertices = world_points(obj)
        trees[obj.name] = BVHTree.FromPolygons(vertices, [p.vertices[:] for p in obj.data.polygons])
    direction = Vector((0, 1, 0))
    for obj in meshes:
        if not (thermal(obj.name) or obj.name.endswith("_Rotor") or obj.name == "SoC_Package"):
            continue
        verts = world_points(obj)
        left, right = min(v.x for v in verts), max(v.x for v in verts)
        back, front = min(v.z for v in verts), max(v.z for v in verts)
        visible = covered = 0
        for ix in range(21):
            for iz in range(21):
                origin = Vector((left+(right-left)*(ix+.5)/21, -.03, back+(front-back)*(iz+.5)/21))
                distance = trees[obj.name].ray_cast(origin, direction)[3]
                if distance is None:
                    continue
                covered += 1
                visible += all(name == obj.name or tree.ray_cast(origin, direction, distance-.00002)[0] is None
                               for name, tree in trees.items())
        threshold = .20 if obj.name == "SoC_Package" else .97
        assert covered and visible / covered >= threshold, (obj.name, visible, covered)


def check_source(base, expected, cutout, spec):
    bpy.ops.wm.open_mainfile(filepath=str(base.with_suffix(".blend")))
    scene = bpy.context.scene
    objects = {o.name: o for o in scene.objects}
    assert set(objects) == expected, set(objects) ^ expected
    hinge = objects["Lid_Hinge"]
    assert abs(hinge.rotation_euler.x) < 1e-6 and hinge.location.z < -spec[1]*.00045
    assert all(objects[n].parent == hinge for n in LID | {cutout})
    meshes = [o for o in objects.values() if o.type == "MESH"]
    assert len(meshes) == len(expected)-1 and hinge.type == "EMPTY"
    pts = [p for o in meshes for p in world_points(o)]
    close_dimensions(dimensions(pts), [spec[0], spec[2], spec[1]])
    assert abs(min(p.y for p in pts)) < .00001
    screen = dimensions(world_points(objects["Display"]))
    close_dimensions([screen[0], screen[2]], [v*25.4/spec[5] for v in spec[3:5]])
    if cutout == "Display_Notch":
        assert max(p.z for p in world_points(objects[cutout])) >= max(p.z for p in world_points(objects["Display"]))
    for obj in meshes:
        for mat in obj.data.materials:
            shader = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
            check_base_color(obj.name, mat.name, shader.inputs["Base Color"].default_value)
        assert all(abs(scale - 1) < 1e-5 for scale in obj.scale)
        if obj.name.endswith("_Rotor"):
            low, high = map(Vector, (obj.bound_box[0], obj.bound_box[6]))
            assert ((low + high) / 2).length < .00001
            assert obj.location.y > 0 and obj.rotation_euler.to_matrix() == Matrix.Identity(3)
    check_logo_center(world_points(objects["Logo"]), world_points(objects["Shell_Lid"]))
    check_bottom(scene)


def read_gltf(base, expected, cutout):
    blob = base.with_suffix(".glb").read_bytes()
    assert blob[:4] == b"glTF" and len(blob) == struct.unpack_from("<I", blob, 8)[0]
    g = json.loads(blob[20:20+struct.unpack_from("<I", blob, 12)[0]])
    nodes = {n["name"]: n for n in g["nodes"]}
    assert set(nodes) == expected and not any(g.get(key) for key in ("animations", "skins", "cameras", "images", "textures"))
    assert {g["nodes"][i]["name"] for i in nodes["Lid_Hinge"]["children"]} == LID | {cutout}
    material_sets, total = {}, 0
    for name, node in nodes.items():
        if "mesh" not in node:
            continue
        primitives = g["meshes"][node["mesh"]]["primitives"]
        material_sets[name] = {g["materials"][p["material"]]["name"] for p in primitives}
        for primitive in primitives:
            mat = g["materials"][primitive["material"]]
            rgb = mat["pbrMetallicRoughness"].get("baseColorFactor", [1, 1, 1, 1])
            check_base_color(name, mat["name"], rgb)
        assert all(p.get("mode", 4) == 4 for p in primitives)
        count = sum(g["accessors"][p["indices"]]["count"]//3 for p in primitives)
        assert count > 0 and (not name.endswith("_Rotor") or count <= 3000)
        if name == "Logo":
            assert count <= 1500, count
        total += count
    assert total <= 80000 and len(g["materials"]) <= 32
    check_materials(material_sets)
    lid = next(m for m in g["materials"] if m["name"] == "Smoked titanium")
    assert .2 <= lid["pbrMetallicRoughness"]["baseColorFactor"][3] <= .3
    logo, = material_sets["Logo"]
    material = next(m for m in g["materials"] if m["name"] == logo)
    if cutout == "Display_Notch":
        pbr = material["pbrMetallicRoughness"]
        assert pbr.get("metallicFactor", 1) == 1 and abs(pbr["roughnessFactor"]-.1) < .02
        assert not any(material.get("emissiveFactor", []))
    else:
        assert min(material["emissiveFactor"]) > 0
    return total, len(g["materials"])


def check_materials(sets):
    assert "Bottom_case_opacity" in sets["Shell_Bottom"]
    assert "Laser_etch" in set.union(*sets.values())
    for name, own in sets.items():
        if not (thermal(name) or name == "Logo"):
            continue
        assert len(own) == 1 and all(not own.intersection(other) for key, other in sets.items() if key != name), name


def check_usdz(base, expected, cutout, spec):
    stage = Usd.Stage.Open(str(base.with_suffix(".usdz")))
    assert UsdGeom.GetStageUpAxis(stage) == "Y" and abs(UsdGeom.GetStageMetersPerUnit(stage)-1) < 1e-6
    prims = list(stage.Traverse())
    assert all(not attr.GetNumTimeSamples() for p in prims for attr in p.GetAttributes())
    assert not any(p.GetTypeName() in {"Camera", "Skeleton", "SkelAnimation"} or "Light" in p.GetTypeName() for p in prims)
    meshes = {p.GetName(): p for p in prims if p.IsA(UsdGeom.Mesh)}
    assert set(meshes) == expected - {"Lid_Hinge"}, set(meshes) ^ (expected - {"Lid_Hinge"})
    sets, points, lid_parts = {}, [], {}
    xf = UsdGeom.XformCache()
    for name, mesh in meshes.items():
        group = mesh.GetParent()
        assert group.GetName() == name
        if name in LID | {cutout}:
            assert group.GetParent().GetName() == "Lid_Hinge"
        bindings = [UsdShade.MaterialBindingAPI(p).ComputeBoundMaterial()[0] for p in [mesh, *mesh.GetChildren()]]
        sets[name] = {m.GetPrim().GetName() for m in bindings if m}
        for mat in filter(bool, bindings):
            color = mat.ComputeSurfaceSource()[0].GetInput("diffuseColor")
            check_base_color(name, mat.GetPrim().GetName(), color.Get())
        transform = xf.GetLocalToWorldTransform(mesh)
        vertices = [transform.Transform(p) for p in UsdGeom.Mesh(mesh).GetPointsAttr().Get()]
        points.extend(vertices)
        if name in {"Logo", "Shell_Lid"}:
            lid_parts[name] = vertices
    check_logo_center(lid_parts["Logo"], lid_parts["Shell_Lid"])
    check_materials(sets)
    close_dimensions(dimensions(points), [spec[0], spec[2], spec[1]])


def verify(model, spec):
    base = FOLDER / model
    expected, cutout = names(model, spec[-1])
    check_source(base, expected, cutout, spec)
    tris, materials = read_gltf(base, expected, cutout)
    check_usdz(base, expected, cutout, spec)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(base.with_suffix(".glb")))
    imported = bpy.context.scene.objects
    assert {o.name for o in imported} == expected
    check_logo_center(world_points(imported["Logo"]), world_points(imported["Shell_Lid"]))
    close_dimensions(dimensions([p for o in imported if o.type == "MESH" for p in world_points(o)]), spec[:3])
    for view in ("top", "bottom", "open"):
        data = (FOLDER / f"{model}-{view}.png").read_bytes()
        assert data[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack_from(">II", data, 16) == (1600, 1000)
    print(f"VERIFIED {model}: {tris:,} triangles, {materials} materials", flush=True)


for model, spec in MODELS.items():
    verify(model, spec)
