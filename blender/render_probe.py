"""Blender 5.2 Apple Silicon CI probe: create a scene and render with each engine."""
import argparse
import json
import math
import os
import sys
import time
import traceback

import bpy
from mathutils import Vector

def material(name, color, metal=0.0, rough=0.38):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    return mat

def smooth(obj):
    for p in obj.data.polygons:
        p.use_smooth = True

def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()

def build_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    scn = bpy.context.scene
    scn.render.resolution_x = 640
    scn.render.resolution_y = 360
    scn.render.resolution_percentage = 100
    scn.render.image_settings.file_format = "PNG"
    scn.render.film_transparent = False
    scn.render.image_settings.color_mode = "RGBA"
    scn.render.threads_mode = "FIXED"
    scn.render.threads = 3
    scn.view_settings.view_transform = "AgX"

    blue = material("Ceramic teal", (0.02, 0.65, 0.73), 0.5, 0.23)
    copper = material("Warm copper", (0.91, 0.36, 0.13), 0.73, 0.26)
    green = material("Glass-like emerald", (0.10, 0.81, 0.42), 0.38, 0.18)
    ground = material("Matte midnight", (0.025, 0.040, 0.078), 0, 0.8)

    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -0.65))
    bpy.context.object.name = "Midnight floor"
    bpy.context.object.data.materials.append(ground)

    bpy.ops.mesh.primitive_torus_add(major_segments=64, minor_segments=16,
        major_radius=0.95, minor_radius=0.23, location=(-2.35, 0, 0.55))
    torus = bpy.context.object
    torus.rotation_euler = (math.radians(22), math.radians(-25), math.radians(12))
    torus.data.materials.append(copper)
    smooth(torus)

    bpy.ops.mesh.primitive_monkey_add(location=(0, 0, 0.55))
    monkey = bpy.context.object
    monkey.name = "Suzanne"
    monkey.data.materials.append(blue)
    sub = monkey.modifiers.new("Smooth surface", "SUBSURF")
    sub.levels = 2
    sub.render_levels = 2
    smooth(monkey)
    monkey.rotation_euler.z = math.radians(15)

    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24,
        radius=1.08, location=(2.4, 0, 0.6))
    sphere = bpy.context.object
    sphere.data.materials.append(green)
    smooth(sphere)

    bpy.ops.object.camera_add(location=(6.6, -10.7, 5.35))
    scn.camera = bpy.context.object
    aim(scn.camera, (0.05, 0.0, 0.30))
    scn.camera.data.type = "ORTHO"
    scn.camera.data.ortho_scale = 9.1

    for name, loc, power, color, size in [
        ("Key", (-3.4, -4, 7), 1400, (0.8, 0.9, 1.0), 6),
        ("Rim", (3.5, 3, 5), 1700, (1.0, 0.72, 0.45), 5),
        ("Fill", (4, -5, 4), 700, (0.4, 0.7, 1.0), 4),
    ]:
        bpy.ops.object.light_add(type="AREA", location=loc)
        lamp = bpy.context.object
        lamp.name = name
        lamp.data.energy = power
        lamp.data.color = color
        lamp.data.shape = "DISK"
        lamp.data.size = size
        aim(lamp, (0, 0, 0.3))
    scn.world.color = (0.20, 0.20, 0.20)
    return scn

def setup_engine(scn, renderer, result):
    if renderer == "eevee":
        scn.render.engine = "BLENDER_EEVEE"
        result["device"] = "EEVEE backend"
    else:
        scn.render.engine = "CYCLES"
        scn.cycles.samples = 24 if renderer == "cycles_cpu" else 16
        scn.cycles.use_denoising = False
        if renderer == "cycles_cpu":
            scn.cycles.device = "CPU"
            result["device"] = "CPU"
        else:
            prefs = bpy.context.preferences.addons["cycles"].preferences
            prefs.compute_device_type = "METAL"
            prefs.get_devices()
            devices = []
            for device in prefs.devices:
                devices.append({"name": device.name, "type": device.type, "id": device.id})
                device.use = (device.type == "METAL")
            result["detected_devices"] = devices
            print("CYCLES_METAL_DEVICES=" + json.dumps(devices), flush=True)
            if not any(d["type"] == "METAL" for d in devices):
                raise RuntimeError("Cycles METAL device not exposed in hosted runner")
            scn.cycles.device = "GPU"
            result["device"] = "METAL GPU"

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--renderer", required=True, choices=("cycles_cpu", "cycles_metal", "eevee"))
    parser.add_argument("--output", required=True)
    parser.add_argument("--save-blend", default="")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    result = {
        "renderer": args.renderer,
        "blender_version": bpy.app.version_string,
        "version": list(bpy.app.version),
        "output": args.output,
        "status": "failed"
    }
    t0 = time.monotonic()
    try:
        scn = build_scene()
        if args.save_blend:
            bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(args.save_blend))
        setup_engine(scn, args.renderer, result)
        scn.render.filepath = os.path.abspath(args.output)
        print("RENDER_START " + args.renderer, flush=True)
        bpy.ops.render.render(write_still=True)
        if not os.path.isfile(args.output):
            raise RuntimeError("Blender returned but no PNG image was written")
        result["output_bytes"] = os.path.getsize(args.output)
        if result["output_bytes"] < 10000:
            raise RuntimeError("PNG output was unexpectedly small")
        img = bpy.data.images.load(os.path.abspath(args.output), check_existing=False)
        result["image_size"] = list(img.size)
        if list(img.size) != [640, 360]:
            raise RuntimeError("PNG resolution mismatch")
        result["status"] = "ok"
        print("RENDER_OK " + args.renderer, flush=True)
    except Exception as exc:
        result["error"] = repr(exc)
        result["traceback"] = traceback.format_exc()
        print(result["traceback"], flush=True)
    finally:
        result["elapsed_seconds"] = round(time.monotonic() - t0, 2)
        with open("artifacts/" + args.renderer + ".json", "w") as f:
            json.dump(result, f, indent=2)
        print("RENDER_RESULT=" + json.dumps(result), flush=True)
    if result["status"] != "ok":
        sys.exit(3)

if __name__ == "__main__":
    main()
