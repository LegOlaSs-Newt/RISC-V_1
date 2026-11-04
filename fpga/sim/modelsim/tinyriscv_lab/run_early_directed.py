# 模块说明：run_early_directed。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
"""实际执行提前查询七项检查；输入只来自提交根，不读取历史 results。"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--record", required=True, type=Path)
    parser.add_argument("--gcc-bin", default=os.environ.get("RISCV_GCC_BIN", ""))
    parser.add_argument("--modelsim-bin", default="D:/modeltech64_2020.4/win64")
    args = parser.parse_args()
    lab = Path(__file__).resolve().parent
    root = lab.parents[2]
    board = root / "pds/tinyriscv_mes50hp"
    out = args.record.resolve()
    if out.exists():
        raise ValueError("Use a new record; old evidence is never merged")
    gcc = (
        Path(args.gcc_bin)
        if args.gcc_bin
        else Path(shutil.which("riscv-none-elf-gcc.exe") or "").parent
    )
    if not (gcc / "riscv-none-elf-gcc.exe").is_file():
        raise ValueError("Specify --gcc-bin or RISCV_GCC_BIN")
    out.mkdir(parents=True)
    source = lab / "programs/early_focus.S"
    link = root / "third_party/tinyriscv/tests/isa/link.ld"
    cmd = [
        str(gcc / "riscv-none-elf-gcc.exe"),
        "-march=rv32im_zicsr",
        "-mabi=ilp32",
        "-nostdlib",
        "-mno-relax",
        "-Wl,--no-relax",
        "-T",
        str(link),
        str(source),
        "-o",
        str(out / "program.elf"),
    ]
    with (out / "gcc.log").open("w") as stream:
        subprocess.run(cmd, stdout=stream, stderr=subprocess.STDOUT, check=True)
    subprocess.run(
        [
            str(gcc / "riscv-none-elf-objcopy.exe"),
            "-O",
            "binary",
            str(out / "program.elf"),
            str(out / "program.bin"),
        ],
        check=True,
    )
    data = (out / "program.bin").read_bytes()
    data += bytes((-len(data)) % 4)
    (out / "inst.data").write_text(
        "".join(f'{int.from_bytes(data[i:i+4], "little"):08x}\n' for i in range(0, len(data), 4))
    )
    files = sorted((board / "rtl/vendor").rglob("*.v"))
    compiled = []
    for path in files:
        if path.name not in ("full_handshake_tx.v", "full_handshake_rx.v"):
            compiled.append(path)
            continue
        # 与整组回归一致的 ModelSim 声明顺序兼容，局限于本次副本。
        variable = "ack" if path.name == "full_handshake_tx.v" else "req"
        text = path.read_text(encoding="utf-8")
        pattern = rf"(?m)^[ \t]*reg[ \t]+{variable};[ \t]*\n"
        if len(re.findall(pattern, text)) != 1:
            raise ValueError("Handshake declaration changed")
        text = re.sub(pattern, "", text).replace(
            "    localparam STATE_IDLE", f"    reg {variable};\n\n    localparam STATE_IDLE"
        )
        target = out / "compat" / path.name
        target.parent.mkdir(exist_ok=True)
        target.write_text(text, encoding="utf-8")
        compiled.append(target)
    q = lambda path: "{" + str(path).replace("\\", "/") + "}"
    tcl = [
        "onerror {quit -f -code 1}",
        "cd " + q(out),
        "vmap -c",
        "vlib work",
        "vmap work work",
        "vlog -work work +define+MES50HP_BP_ENABLE=1 "
        + q("+incdir+" + (board / "rtl/vendor/core").as_posix())
        + " "
        + q("+incdir+" + (board / "rtl").as_posix())
        + " "
        + " ".join(map(q, compiled)),
        "vlog -sv -work work " + q(lab / "early_cpu_tb.sv") + " " + q(lab / "early_cache_tb.sv"),
    ]
    for fast in (0, 1):
        for host in (0, 1, 2):
            tcl += [
                "transcript file " + q(out / f"fast{fast}_host{host}.log"),
                "vsim -onfinish stop -voptargs=+acc -wlf "
                + q(out / f"fast{fast}_host{host}.wlf")
                + f" -gFAST={fast} -gHOST_LAST={host} work.early_cpu_tb "
                + q("+IMAGE=" + (out / "inst.data").as_posix()),
                "run -all",
                "set pass [examine -radix unsigned /early_cpu_tb/passed]",
                "if {$pass != 1} {quit -f -code 1}",
                "quit -sim",
            ]
    tcl += [
        "transcript file " + q(out / "cache.log"),
        "vsim -onfinish stop -voptargs=+acc -wlf " + q(out / "cache.wlf") + " work.early_cache_tb",
        "run -all",
        "set pass [examine -radix unsigned /early_cache_tb/passed]",
        "if {$pass != 1} {quit -f -code 1}",
        "quit -sim",
        "quit -f -code 0",
    ]
    (out / "run.do").write_text("\n".join(tcl) + "\n")
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest().upper()
    inputs = (
        files
        + list((board / "rtl").glob("*.vh"))
        + [
            source,
            link,
            lab / "early_cpu_tb.sv",
            lab / "early_cache_tb.sv",
            out / "run.do",
            out / "program.bin",
        ]
    )
    manifest = [dict(path=str(p), sha256=sha(p)) for p in inputs]
    (out / "input_manifest.json").write_text(json.dumps(manifest, indent=2))
    with (out / "runner.log").open("w") as stream:
        done = subprocess.run(
            [str(Path(args.modelsim_bin) / "vsim.exe"), "-c", "-do", "do run.do"],
            cwd=out,
            stdout=stream,
            stderr=subprocess.STDOUT,
        )
    unchanged = all(sha(Path(row["path"])) == row["sha256"] for row in manifest)
    passed = (
        done.returncode == 0
        and unchanged
        and all(
            "EARLY_CPU_PASS fast=" + str(fast) in (out / f"fast{fast}_host{host}.log").read_text()
            for fast in (0, 1)
            for host in (0, 1, 2)
        )
        and "EARLY_CACHE_PASS" in (out / "cache.log").read_text()
    )
    result = dict(
        Passed=passed,
        Cases=7,
        ExitCode=done.returncode,
        InputsUnchanged=unchanged,
        Scope="Simulation: early On/Off architectural/IRQ/halt/host-write and cache cancellation",
    )
    (out / "completion.json").write_text(json.dumps(result, indent=2))
    print(json.dumps(result))
    if not passed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
