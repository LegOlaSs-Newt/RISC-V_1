# 模块说明：check_drm_rom_init。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
"""Verify the 4096x32 boot image in this PDS's synthesized 4Kx4 DRM cells.

This is a netlist-parameter check, never physical RAM readback. Pango's local
GTP_DRM18K model initializes 2048 9-bit entries and selects one of two data
nibbles per entry in x4 mode. Unsupported netlist forms fail closed.
"""

import argparse
import hashlib
import json
import re
from pathlib import Path


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def reconstruct(text):
    module = re.search(r"\bmodule\s+rom\b(.*?)\bendmodule\b", text, re.S)
    if not module:
        raise ValueError("Expected a synthesized module named rom")
    pattern = re.compile(r"GTP_DRM18K\s*/\*\s*([^*]+)\*/\s*#\((.*?)\)\s*(\w+)\s*\((.*?)\);", re.S)
    cells = list(pattern.finditer(module[1]))
    if len(cells) != 8:
        raise ValueError(f"Expected eight 4096x4 ROM cells, got {len(cells)}")
    words = [0] * 4096
    covered = set()
    details = []
    for cell in cells:
        comment, parameters, instance, ports = cell.groups()
        for name, value in (("DATA_WIDTH_A", "4"), ("DATA_WIDTH_B", "4")):
            if not re.search(r"\." + name + r"\(\s*" + value + r"\s*\)", parameters):
                raise ValueError("Unsupported DRM width")
        if (
            '.RAM_MODE("SIMPLE_DUAL_PORT")' not in parameters
            or '.INIT_FILE("NONE")' not in parameters
        ):
            raise ValueError("Unsupported DRM configuration")
        output = re.search(r"\.DOB\s*\(\s*\{([^{}]+)\}\s*\)", ports)
        input_ = re.search(r"\.DIA\s*\(\s*\{([^{}]+)\}\s*\)", ports)
        address = re.search(r"\.ADDRB\s*\(\s*\{([^{}]+)\}\s*\)", ports)
        if not output or not input_ or not address:
            raise ValueError("Unsupported ROM port concatenation")
        output_bits = [int(v) for v in re.findall(r"\bdata_o\[(\d+)\]", output[1])]
        input_bits = [int(v) for v in re.findall(r"\bdata_i\[(\d+)\]", input_[1])]
        address_bits = [int(v) for v in re.findall(r"\baddr_i\[(\d+)\]", address[1])]
        if (
            len(output_bits) != 4
            or output_bits != input_bits
            or address_bits != list(range(13, 1, -1))
        ):
            raise ValueError("Unexpected ROM data/address wiring")
        base = min(output_bits)
        if output_bits != list(range(base + 3, base - 1, -1)) or base % 4 or base in covered:
            raise ValueError("Duplicate or permuted ROM nibble")
        covered.add(base)
        values = {}
        for match in re.finditer(r"\.INIT_([0-9A-Fa-f]{2})\(\s*288'b([01_]+)\s*\)", parameters):
            number = int(match[1], 16)
            bits = match[2].replace("_", "")
            if number in values or len(bits) != 288:
                raise ValueError("Malformed/duplicate DRM initialization")
            values[number] = int(bits, 2)
        if set(values) != set(range(64)):
            raise ValueError("Incomplete DRM initialization")
        packed = sum(value << (288 * number) for number, value in values.items())
        for index in range(4096):
            position = (index // 2) * 9 + (index % 2) * 4
            words[index] |= ((packed >> position) & 15) << base
        details.append({"Instance": instance, "OutputBits": output_bits, "INITBlocks": len(values)})
    if covered != set(range(0, 32, 4)):
        raise ValueError("ROM nibble coverage incomplete")
    return words, details


def check(netlist, boot):
    tokens = boot.read_text(encoding="utf-8-sig").split()
    if len(tokens) != 4096 or any(not re.fullmatch(r"[0-9a-fA-F]{8}", token) for token in tokens):
        raise ValueError("Expected 4096 initialized 32-bit words")
    expected = [int(token, 16) for token in tokens]
    text = netlist.read_text(encoding="utf-8-sig")
    actual, cells = reconstruct(text)
    mismatches = [n for n, pair in enumerate(zip(actual, expected)) if pair[0] != pair[1]]
    # Mutate one data INIT bit in memory. The checker must see one bad word.
    rom_match = re.search(r"\bmodule\s+rom\b(.*?)\bendmodule\b", text, re.S)
    init_match = re.search(r"\.INIT_00\(288'b([01]+)\)", rom_match[1])
    if not init_match:
        raise ValueError("Cannot construct INIT negative control")
    bits = init_match[1]
    changed = bits[:-1] + ("0" if bits[-1] == "1" else "1")
    start = rom_match.start(1) + init_match.start(1)
    tampered = text[:start] + changed + text[start + len(bits) :]
    bad_words, _ = reconstruct(tampered)
    changed_words = [n for n, pair in enumerate(zip(actual, bad_words)) if pair[0] != pair[1]]
    if changed_words != [0]:
        raise ValueError("INIT negative control was not detected exactly")
    return {
        "AllEqual": not mismatches,
        "Words": len(actual),
        "Cells": cells,
        "MismatchWords": len(mismatches),
        "FirstMismatches": mismatches[:16],
        "NegativeControl": "One INIT data bit changed in memory; exactly word 0 changed",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--netlist", type=Path, required=True)
    parser.add_argument("--boot", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Use a new output")
    result = {
        "Scope": "Synthesized DRM INIT parameters and wiring; no physical readback or execution",
        "Netlist": str(args.netlist.resolve()),
        "Boot": str(args.boot.resolve()),
        "AllEqual": False,
    }
    try:
        result.update(NetlistSHA256=sha(args.netlist), BootSHA256=sha(args.boot))
        result.update(check(args.netlist, args.boot))
    except (ValueError, OSError) as error:
        result["Error"] = str(error)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"DRM_ROM_INIT_{'PASS' if result['AllEqual'] else 'FAIL'} {args.output}")
    return 0 if result["AllEqual"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
