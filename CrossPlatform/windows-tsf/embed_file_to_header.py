#!/usr/bin/env python3
import sys


def write_byte_array(out, name: str, data: bytes) -> None:
    out.write(f"static constexpr size_t {name}Size = {len(data)};\n")
    out.write(f"static const uint8_t {name}[] = {{\n")
    for i in range(0, len(data), 16):
        chunk = data[i : i + 16]
        out.write("    " + ", ".join(f"0x{b:02X}" for b in chunk) + ",\n")
    out.write("};\n\n")


def main() -> int:
    if len(sys.argv) == 6 and sys.argv[1] == "--x64" and sys.argv[3] == "--arm64":
        x64_path, arm64_path, out_path = sys.argv[2], sys.argv[4], sys.argv[5]
        with open(x64_path, "rb") as f:
            x64_data = f.read()
        with open(arm64_path, "rb") as f:
            arm64_data = f.read()
        with open(out_path, "w", encoding="utf-8") as out:
            out.write("#pragma once\n")
            out.write("#include <windows.h>\n")
            out.write("#include <stddef.h>\n")
            out.write("#include <stdint.h>\n\n")
            write_byte_array(out, "kEmbeddedTipDllX64", x64_data)
            write_byte_array(out, "kEmbeddedTipDllArm64", arm64_data)
            out.write("#if defined(_M_ARM64) || defined(__aarch64__)\n")
            out.write("static constexpr size_t kEmbeddedTipDllSize = kEmbeddedTipDllArm64Size;\n")
            out.write("static const uint8_t * const kEmbeddedTipDll = kEmbeddedTipDllArm64;\n")
            out.write("#else\n")
            out.write("static constexpr size_t kEmbeddedTipDllSize = kEmbeddedTipDllX64Size;\n")
            out.write("static const uint8_t * const kEmbeddedTipDll = kEmbeddedTipDllX64;\n")
            out.write("#endif\n\n")
            out.write("static inline bool IsHostWindowsArm64ForTip() {\n")
            out.write("#if defined(_M_ARM64) || defined(__aarch64__)\n")
            out.write("    return true;\n")
            out.write("#else\n")
            out.write("    typedef BOOL(WINAPI *PFN_IsWow64Process2)(HANDLE, USHORT *, USHORT *);\n")
            out.write("    HMODULE hK32 = GetModuleHandleW(L\"kernel32.dll\");\n")
            out.write("    if (hK32) {\n")
            out.write("        PFN_IsWow64Process2 pfn = reinterpret_cast<PFN_IsWow64Process2>(GetProcAddress(hK32, \"IsWow64Process2\"));\n")
            out.write("        if (pfn) {\n")
            out.write("            USHORT procMach = 0, nativeMach = 0;\n")
            out.write("            if (pfn(GetCurrentProcess(), &procMach, &nativeMach) && nativeMach == 0xAA64) {\n")
            out.write("                return true;\n")
            out.write("            }\n")
            out.write("        }\n")
            out.write("    }\n")
            out.write("    SYSTEM_INFO si{};\n")
            out.write("    GetNativeSystemInfo(&si);\n")
            out.write("    return si.wProcessorArchitecture == 12;\n")
            out.write("#endif\n")
            out.write("}\n\n")
            out.write("static inline void GetEmbeddedTipDllForHostOs(const uint8_t *&outData, size_t &outSize) {\n")
            out.write("    if (IsHostWindowsArm64ForTip()) {\n")
            out.write("        outData = kEmbeddedTipDllArm64;\n")
            out.write("        outSize = kEmbeddedTipDllArm64Size;\n")
            out.write("    } else {\n")
            out.write("        outData = kEmbeddedTipDllX64;\n")
            out.write("        outSize = kEmbeddedTipDllX64Size;\n")
            out.write("    }\n")
            out.write("}\n")
        return 0

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
        write_byte_array(out, "kEmbeddedTipDll", data)
        out.write("static inline void GetEmbeddedTipDllForHostOs(const uint8_t *&outData, size_t &outSize) {\n")
        out.write("    outData = kEmbeddedTipDll;\n")
        out.write("    outSize = kEmbeddedTipDllSize;\n")
        out.write("}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
