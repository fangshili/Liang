#!/usr/bin/env python3
"""为 DMG 文件设置应用图标。

通过写入 com.apple.ResourceFork 并设置 Finder 自定义图标标志实现，
不依赖 pyobjc 等第三方库。
"""

import ctypes
import os
import struct
import subprocess
import sys


def setxattr(path: bytes, name: bytes, value: bytes) -> bool:
    libc = ctypes.CDLL("libc.dylib", use_errno=True)
    libc.setxattr.argtypes = [
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.c_void_p,
        ctypes.c_size_t,
        ctypes.c_uint32,
        ctypes.c_int,
    ]
    libc.setxattr.restype = ctypes.c_int
    res = libc.setxattr(path, name, value, len(value), 0, 0)
    return res == 0


def set_icon_for_app_bundle(app_bundle_path: str, dmg_path: str) -> bool:
    icns_path = os.path.join(app_bundle_path, "Contents", "Resources", "AppIcon.icns")
    if not os.path.exists(icns_path):
        print(f"ICNS not found: {icns_path}")
        return False

    with open(icns_path, "rb") as f:
        data = f.read()

    # Resource fork 中的自定义图标格式：'icns' + 大端长度 + icns 数据
    rsrc = b"icns" + struct.pack(">I", len(data)) + data

    if not setxattr(dmg_path.encode("utf-8"), b"com.apple.ResourceFork", rsrc):
        print("Failed to write com.apple.ResourceFork")
        return False

    subprocess.run(["SetFile", "-a", "C", dmg_path], check=False)
    return True


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: set-dmg-icon.py <source-app-bundle> <target-dmg-file>")
        sys.exit(1)

    source = sys.argv[1]
    target = sys.argv[2]
    ok = set_icon_for_app_bundle(source, target)
    print(f"Set icon for {target}: {'success' if ok else 'failed'}")
    sys.exit(0 if ok else 1)
