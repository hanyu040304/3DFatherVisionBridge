bl_info = {
    "name": "Fusion Spatial Blender Connector",
    "author": "Fusion Spatial",
    "version": (1, 0, 0),
    "blender": (4, 0, 0),
    "location": "Background",
    "description": "Exports the active Blender scene for Apple Vision Pro Spatial Preview",
    "category": "Import-Export",
}

import json
import os
from pathlib import Path
import subprocess
import time
import uuid

import bpy
from bpy.app.handlers import persistent

BRIDGE = Path.home() / "Library" / "Application Support" / "FusionSpatialBridge" / "Bridge" / "Blender"
HANDLED_REQUEST = None
LAST_HEARTBEAT = 0.0
SCENE_DIRTY = False
LAST_CHANGE = 0.0


def atomic_json(name, payload):
    BRIDGE.mkdir(parents=True, exist_ok=True)
    temporary = BRIDGE / (name + ".tmp")
    temporary.write_text(json.dumps(payload), encoding="utf-8")
    os.replace(temporary, BRIDGE / name)


def respond(request_id, status, message="", timings=None):
    atomic_json("export-response.json", {
        "id": request_id, "status": status, "message": message, "timings": timings or {}
    })


def export_scene(request):
    request_id = request["id"]
    started = time.perf_counter()
    source = BRIDGE / "current_tmp.usd"
    package = BRIDGE / "current_tmp.usdz"
    final = BRIDGE / "current.usdz"
    try:
        respond(request_id, "exporting")
        source.unlink(missing_ok=True)
        package.unlink(missing_ok=True)
        print("[FusionSpatial Blender] Exporting...")
        result = bpy.ops.wm.usd_export(filepath=str(source))
        if "FINISHED" not in result or not source.is_file():
            raise RuntimeError("Blender USD export failed")
        export_seconds = time.perf_counter() - started
        file_started = time.perf_counter()
        process = subprocess.run(
            ["/usr/bin/usdzip", str(package), "--asset", str(source)],
            capture_output=True, text=True, timeout=120
        )
        if process.returncode != 0 or not package.is_file():
            raise RuntimeError(process.stderr.strip() or "USDZ packaging failed")
        os.replace(package, final)
        source.unlink(missing_ok=True)
        timings = {
            "detectionSeconds": max(0, time.time() - request.get("requestedAt", time.time())),
            "queueSeconds": 0,
            "exportSeconds": export_seconds,
            "fileSeconds": time.perf_counter() - file_started,
            "bytes": final.stat().st_size,
        }
        respond(request_id, "complete", timings=timings)
        print("[FusionSpatial Blender] Export completed")
    except Exception as error:
        print("[FusionSpatial Blender] Export failed: " + str(error))
        respond(request_id, "error", str(error))


def poll_bridge():
    global HANDLED_REQUEST, LAST_HEARTBEAT, SCENE_DIRTY, LAST_CHANGE
    try:
        now = time.time()
        if now - LAST_HEARTBEAT >= 2:
            atomic_json("connector-status.json", {"version": "1.0.0", "timestamp": now, "pid": os.getpid()})
            LAST_HEARTBEAT = now
        request = json.loads((BRIDGE / "export-request.json").read_text(encoding="utf-8"))
        if request.get("id") != HANDLED_REQUEST and request.get("expiresAt", 0) >= now:
            HANDLED_REQUEST = request["id"]
            export_scene(request)
        if SCENE_DIRTY and now - LAST_CHANGE >= 0.5:
            atomic_json("model-change.json", {"id": uuid.uuid4().hex, "timestamp": now})
            SCENE_DIRTY = False
    except (OSError, ValueError, KeyError, TypeError):
        pass
    except Exception as error:
        print("[FusionSpatial Blender] Poll failed: " + str(error))
    return 0.1


@persistent
def scene_changed(_scene, _depsgraph):
    global SCENE_DIRTY, LAST_CHANGE
    SCENE_DIRTY = True
    LAST_CHANGE = time.time()


def register():
    BRIDGE.mkdir(parents=True, exist_ok=True)
    if scene_changed not in bpy.app.handlers.depsgraph_update_post:
        bpy.app.handlers.depsgraph_update_post.append(scene_changed)
    if not bpy.app.timers.is_registered(poll_bridge):
        bpy.app.timers.register(poll_bridge, first_interval=0.1, persistent=True)
    print("[FusionSpatial Blender] Connector started")


def unregister():
    if scene_changed in bpy.app.handlers.depsgraph_update_post:
        bpy.app.handlers.depsgraph_update_post.remove(scene_changed)
    if bpy.app.timers.is_registered(poll_bridge):
        bpy.app.timers.unregister(poll_bridge)
    print("[FusionSpatial Blender] Connector stopped")
