#!/usr/bin/env bash
# =============================================================================
# ASUS T100TAS CPU Mitigations Benchmark (mitigations=off vs default)
# Measures syscall latency, zstd memory compression, Python/GTK startup, & boot time
# =============================================================================
set -euo pipefail

echo "=================================================================="
echo "TransformerOS T100TAS Benchmark — $(date -Is)"
echo "Kernel:  $(uname -r)"
echo "Cmdline: $(cat /proc/cmdline)"
echo "CPU:     $(awk -F: '/model name/{print $2; exit}' /proc/cpuinfo | xargs)"
echo "=================================================================="

echo ""
echo "[1/4] Systemd Boot Time Analysis:"
systemd-analyze time || true

echo ""
echo "[2/4] Syscall & Context-Switch Microbenchmark (200,000 getppid+pipe loops in Python):"
python3 - << 'PYEOF'
import os, time
t0 = time.perf_counter()
for _ in range(200_000):
    os.getppid()
t1 = time.perf_counter()
r, w = os.pipe()
for _ in range(100_000):
    os.write(w, b"x")
    os.read(r, 1)
os.close(r)
os.close(w)
t2 = time.perf_counter()
print(f"  200k getppid() syscalls : {(t1 - t0)*1000:.1f} ms")
print(f"  100k pipe read/write    : {(t2 - t1)*1000:.1f} ms")
PYEOF

echo ""
echo "[3/4] Memory & ZRAM Compression Throughput (64 MiB buffer):"
python3 - << 'PYEOF'
import hashlib, time, zlib
buf = (b"TransformerOS-BayTrail-Z3775-" * (64 * 1024 * 1024 // 29))[:64 * 1024 * 1024]
t0 = time.perf_counter()
for _ in range(5):
    hashlib.sha256(buf).digest()
t1 = time.perf_counter()
c = zlib.compress(buf, 1)
t2 = time.perf_counter()
print(f"  320 MiB SHA-256         : {(t1 - t0)*1000:.1f} ms ({320.0/(t1-t0):.1f} MiB/s)")
print(f"  64 MiB zlib-1 compress  : {(t2 - t1)*1000:.1f} ms ({64.0/(t2-t1):.1f} MiB/s)")
PYEOF

echo ""
echo "[4/4] Live Memory Footprint:"
free -h
swapon --show
