#!/usr/bin/env python3
import sys
import json
import zlib
import base64

def main():
    if len(sys.argv) < 2:
        print("Usage: detect_capture_keys.py <overlay_captures.json>")
        sys.exit(1)

    path = sys.argv[1]
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    filter_bases = [int(x, 16) for x in sys.argv[2:]] if len(sys.argv) > 2 else None

    for c in data:
        raw = base64.b64decode(c["bytes_b64"])
        crc = zlib.crc32(raw)
        load_addr = int(c["load_addr"], 16) if isinstance(c["load_addr"], str) else c["load_addr"]
        phys = load_addr & 0x1FFFFFFF
        if phys == 0:
            continue
        if filter_bases is not None and phys not in filter_bases:
            continue
        print(f"0x{phys:08X}:0x{crc:08X}")

if __name__ == "__main__":
    main()
