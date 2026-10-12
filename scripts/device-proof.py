#!/usr/bin/env python3
"""Read local Apple tool results; never print private journey or photo contents."""
import json
import sys

UDID = "00008150-00180C3A0A40401C"
BUNDLE = "com.wanderlog.travel"

def result(path):
    with open(path) as f:
        return json.load(f)["result"]

def photos(path):
    return {
        f["relativePath"]: (f["metadata"]["size"], f["metadata"].get("lastModDate"))
        for f in result(path)["files"]
        if not f.get("resources", {}).get("isDirectory")
        and f["relativePath"].startswith("Documents/")
        and f["relativePath"].lower().endswith((".jpg", ".jpeg", ".png", ".heic", ".webp"))
    }

mode = sys.argv[1]
if mode == "device":
    devices = result(sys.argv[2])["devices"]
    target = next((d for d in devices if d.get("properties", {}).get("hardware", d.get("hardwareProperties", {})).get("udid") == UDID), None)
    if not target:
        sys.exit("指定 iPhone 未找到；未安装。")
    hardware = target.get("properties", {}).get("hardware", target.get("hardwareProperties", {}))
    connection = target.get("properties", {}).get("connection", {})
    state = connection.get("state", target.get("connectionProperties", {}).get("tunnelState"))
    if hardware.get("reality") != "physical" or hardware.get("productType") != "iPhone18,1" or state not in ("connected", "available"):
        sys.exit("指定实体 iPhone 17 Pro 不可用；请连接并解锁，未安装。")
    print("已核对指定实体 iPhone 17 Pro。")
elif mode == "storage-files":
    prefixes = ("Library/Application Support/" + BUNDLE + "/RCTAsyncLocalStorage_V1/", "Documents/RCTAsyncLocalStorage_V1/", "Documents/RCTAsyncLocalStorage/", "Documents/RCTAsyncLocalStorage_V0/", "Library/Application Support/" + BUNDLE + "/WanderlogNative/")
    import hashlib
    filenames = {"manifest.json", hashlib.md5(b"wanderlog.custom-trips.v1").hexdigest(), "trips.json", "legacy-import.json", "trips.previous.json", "pending-deletion.json"}
    for f in result(sys.argv[2])["files"]:
        path = f["relativePath"]
        if path.startswith(prefixes) and path.rsplit("/", 1)[-1] in filenames and not f.get("resources", {}).get("isDirectory"):
            if ".." in path.split("/") or "\n" in path:
                sys.exit("存储路径异常；未安装。")
            print(path)
elif mode == "photos":
    before, after = photos(sys.argv[2]), photos(sys.argv[3])
    if before != after:
        sys.exit("照片文件元数据发生变化，需要核查。")
    print(f"覆盖前后 {len(before)} 个照片文件的路径、大小和修改时间一致。")
elif mode == "version":
    app = next((a for a in result(sys.argv[2])["apps"] if a.get("bundleIdentifier") == BUNDLE), None)
    if not app or app.get("version") != sys.argv[3] or str(app.get("bundleVersion")) != sys.argv[4]:
        sys.exit("设备侧版本未匹配；安装状态尚未确认。")
    print(f"设备侧已确认 {BUNDLE}，版本 {app['version']}，构建 {app['bundleVersion']}。")
else:
    sys.exit("未知检查方式。")
