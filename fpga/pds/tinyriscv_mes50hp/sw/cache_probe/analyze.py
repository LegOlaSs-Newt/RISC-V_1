# 模块说明：analyze。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
"""Check real probe UART records without treating simulation as board evidence."""

import argparse
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--off", type=Path, required=True)
parser.add_argument("--on", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--scope", choices=("simulation", "board"), required=True)
args = parser.parse_args()
if args.output.exists():
    raise ValueError("Use a new analysis output")


def read(path, enabled):
    text = path.read_text(encoding="ascii")
    if (
        text.count("V3_CACHE_PROBE_BEGIN v1") != 1
        or text.count("V3_CACHE_PROBE_PASS") != 1
        or "_FAIL" in text
    ):
        raise ValueError("Incomplete/failed UART record: " + str(path))
    rows = re.findall(
        r"^WORK ([0-9A-F]{8}) cycles=([0-9A-F]{8}) dh=([0-9A-F]{8}) dm=([0-9A-F]{8}) checksum=([0-9A-F]{8}) expected=([0-9A-F]{8})\r?$",
        text,
        re.M,
    )
    if len(rows) != 4:
        raise ValueError("Expected four workload records")
    expected_counts = ((992, 32), (62, 2), (0, 96), (2, 1))
    work = []
    for index, row in enumerate(rows):
        n, cycles, hits, misses, checksum, expected = (int(x, 16) for x in row)
        if n != index or not cycles or checksum != expected:
            raise ValueError("Invalid workload result")
        if (hits, misses) != (expected_counts[index] if enabled else (0, 0)):
            raise ValueError(f"Unexpected cache behavior at workload {index}: {hits}/{misses}")
        work.append(
            dict(
                Index=n,
                Cycles=cycles,
                DReadHits=hits,
                DReadMisses=misses,
                Checksum=f"{checksum:08X}",
            )
        )
    if "SMC before_after=00070009" not in text:
        raise ValueError("FENCE.I self-modification failed")
    pairs = re.findall(r"^STAT ([0-9A-F]{8}) delta=([0-9A-F]{16})\r?$", text, re.M)
    if len(pairs) != 15 or [int(x, 16) for x, _ in pairs] != list(range(15)):
        raise ValueError("Full 64-bit telemetry missing")
    counters = [int(value, 16) for _, value in pairs]
    if enabled and (not counters[0] or not counters[1] or not counters[11]):
        raise ValueError("Cache/refill activity not observed")
    if not enabled and any(counters[n] for n in (0, 1, 2, 3, 11, 12, 13)):
        raise ValueError("Cache-off counters should be inactive")
    return dict(UART=str(path.resolve()), Workloads=work, TelemetryDelta=counters)


off = read(args.off, False)
on = read(args.on, True)
if [x["Checksum"] for x in off["Workloads"]] != [x["Checksum"] for x in on["Workloads"]]:
    raise ValueError("Cache On/Off produced different data")
report = dict(
    Passed=True,
    Scope=args.scope,
    CacheOff=off,
    CacheOn=on,
    WorkloadSpeedup=[a["Cycles"] / b["Cycles"] for a, b in zip(off["Workloads"], on["Workloads"])],
    Limitations=[
        "WORK cycles include call-body measurement instructions, identical in both images",
        "WORK D hit/miss intervals contain only explicit workload cacheable loads",
        "STAT counters are sampled individually high-low-high; deltas include observation/stack/SMC",
        "Telemetry is not a pure burst-efficiency measurement",
        "A board report still requires matching configuration/download identity",
    ],
)
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(dict(Passed=True, Scope=args.scope, WorkloadSpeedup=report["WorkloadSpeedup"])))
