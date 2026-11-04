# 模块说明：check_rom_init。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
"""Check this Port's 4096x32 ROM INIT data in PDS synthesis/post-route netlists.

This checks generated netlist parameters, not RAM readback on the physical board.
Only the explicit GTP_RAM32X1SP and V_RAM32X1 forms emitted by this PDS are accepted.
"""

import argparse
import hashlib
import json
import re
from pathlib import Path


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def check(netlist, boot):
    tokens = boot.read_text(encoding="utf-8-sig").split()
    if len(tokens) != 4096 or any(not re.fullmatch(r"[0-9a-fA-F]{8}", t) for t in tokens):
        raise ValueError("Expected exactly 4096 hexadecimal 32-bit boot words")
    expected = [int(t, 16) for t in tokens]
    pattern = re.compile(
        r"(?:GTP_RAM32X1SP|V_RAM32X1)\s*/\*\s*"
        r"(?:u_soc/u_rom/)?_rom_(\d+)_(\d+)(?:/[^*]*)?\s*\*/\s*"
        r"#\(\s*\.INIT\(\s*32'b([01_]+)\s*\)"
    )
    cells = pattern.findall(netlist.read_text(encoding="utf-8-sig"))
    words = [0] * 4096
    seen = set()
    for bank_text, bit_text, data_text in cells:
        bank, bit = int(bank_text), int(bit_text)
        data_text = data_text.replace("_", "")
        if not (0 <= bank < 128 and 0 <= bit < 32) or len(data_text) != 32:
            raise ValueError("Unexpected ROM cell dimensions")
        if (bank, bit) in seen:
            raise ValueError("Duplicate ROM cell")
        seen.add((bank, bit))
        value = int(data_text, 2)
        for offset in range(32):
            words[bank * 32 + offset] |= ((value >> offset) & 1) << bit
    if len(seen) != 4096:
        raise ValueError(f"ROM cell coverage incomplete: {len(seen)}/4096")
    bad = [i for i, (actual, wanted) in enumerate(zip(words, expected)) if actual != wanted]
    return {
        "Cells": len(seen),
        "Words": len(words),
        "MismatchWords": len(bad),
        "FirstMismatches": [
            {
                "Address": f"0x{i * 4:08X}",
                "Actual": f"{words[i]:08X}",
                "Expected": f"{expected[i]:08X}",
            }
            for i in bad[:16]
        ],
        "AllEqual": not bad,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--netlist", type=Path, required=True)
    parser.add_argument("--boot", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Output already exists; preserve it and choose a new record")
    result = {
        "Netlist": str(args.netlist.resolve()),
        "Boot": str(args.boot.resolve()),
        "Scope": "Netlist INIT values only; not physical board RAM readback",
        "AllEqual": False,
    }
    try:
        result.update(NetlistSHA256=sha256(args.netlist), BootSHA256=sha256(args.boot))
        result.update(check(args.netlist, args.boot))
    except (OSError, ValueError) as error:
        result["Error"] = str(error)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"ROM_INIT_{'PASS' if result['AllEqual'] else 'FAIL'} {args.output}")
    return 0 if result["AllEqual"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
