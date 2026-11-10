#!/usr/bin/env python3
import sys


def main() -> int:
    if len(sys.argv) < 3:
        sys.stderr.write("Usage: embed_file_to_header.py <input-file> <output-header>\n")
        return 1
    in_path, out_path = sys.argv[1], sys.argv[2]
    with open(in_path, "rb") as f:
        data = f.read()
    with open(out_path, "w", encoding="utf-8") as out:
        out.write("#pragma once\n")
        out.write("#include <stddef.h>\n")
        out.write("#include <stdint.h>\n\n")
        out.write(f"static constexpr size_t kEmbeddedTipDllSize = {len(data)};\n")
        out.write("static const uint8_t kEmbeddedTipDll[] = {\n")
        for i in range(0, len(data), 16):
            chunk = data[i : i + 16]
            out.write("    " + ", ".join(f"0x{b:02X}" for b in chunk) + ",\n")
        out.write("};\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
