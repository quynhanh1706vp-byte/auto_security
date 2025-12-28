#!/usr/bin/env python3
from pathlib import Path
import subprocess, datetime, shutil, json, sys, os, re

root = Path("/home/test/Data/SECURITY_BUNDLE/ui")
bin_dir = root / "bin"
out_ci = root / "out_ci"
out_ci.mkdir(parents=True, exist_ok=True)

ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
log_txt = out_ci / f"p43_bin_syntax_gate_{ts}.txt"
log_json = out_ci / f"p43_bin_syntax_gate_{ts}.json"
qdir = bin_dir / f"_quarantine_P43_{ts}"

# Toggle:
#   P43_FAST=1 (default) -> scan active patterns only
#   P43_FAST=0           -> scan ALL *.sh in bin/ (excluding .bak_/.disabled_/_quarantine_)
FAST = (os.environ.get("P43_FAST", "1") == "1")

ACTIVE_PATTERNS = [
    r"^p\d{1,3}_.*\.sh$",
    r"^commercial_.*\.sh$",
    r"^(add|backfill|capitalize|clean|cleanup|clone|debug|deploy|diag|disable|e2e|enable)_.*\.sh$",
    r"^(run|vsp|kpi|pack)_.*\.sh$",
    r"^unify.*\.sh$",
    r"^aate_.*\.(sh|py)$",  # (py is ignored by .sh glob, but kept here for clarity)
]

def is_ignored(p: Path) -> bool:
    n = p.name
    if not n.endswith(".sh"):
        return True
    if ".bak_" in n or ".disabled_" in n:
        return True
    if any(part.startswith("_quarantine_") for part in p.parts):
        return True
    return False

def is_active(p: Path) -> bool:
    name = p.name
    if name == "dw":
        return True
    return any(re.search(pat, name) for pat in ACTIVE_PATTERNS)

# Build file list (IMPORTANT: define all_files BEFORE files)
all_files = sorted([x for x in bin_dir.glob("*.sh") if not is_ignored(x)])
files = [x for x in all_files if (is_active(x) if FAST else True)]

fails = []
for fp in files:
    r = subprocess.run(["bash", "-n", str(fp)], capture_output=True, text=True)
    if r.returncode != 0:
        err = (r.stderr or "").strip().splitlines()
        fails.append({"file": str(fp), "stderr": err[:120]})

moved = []
if fails:
    qdir.mkdir(parents=True, exist_ok=True)
    for x in fails:
        src = Path(x["file"])
        dst = qdir / src.name
        shutil.move(str(src), str(dst))
        moved.append({"from": str(src), "to": str(dst)})

summary = {
    "ts": ts,
    "fast": FAST,
    "scanned": len(files),
    "fail_count": len(fails),
    "quarantine_dir": str(qdir) if fails else "",
    "moved": moved,
    "fails": fails,
}

lines = []
lines.append("== [P43] bin syntax gate ==")
lines.append(f"TS={ts}")
lines.append(f"FAST={1 if FAST else 0}")
lines.append(f"SCANNED={len(files)}")
lines.append(f"FAIL={len(fails)}")
if fails:
    lines.append(f"QUARANTINE_DIR={qdir}")
lines.append("")
for x in fails:
    lines.append(f"[FAIL] {x['file']}")
    for e in x["stderr"]:
        lines.append(f"  {e}")
    lines.append("")
lines.append("== [SUMMARY] ==")
lines.append(f"FAIL={len(fails)}")
lines.append("[VERDICT] PASS" if len(fails) == 0 else "[VERDICT] FAIL")

log_txt.write_text("\n".join(lines) + "\n", encoding="utf-8")
log_json.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

print("\n".join(lines))
print(f"[P43] log: {log_txt}")
print(f"[P43] json: {log_json}")

sys.exit(0 if len(fails) == 0 else 3)
