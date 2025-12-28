#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BIN="bin"
OUT="out_ci"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need bash; need grep; need head; need wc

TS="$(date +%Y%m%d_%H%M%S)"
LOG_TXT="$OUT/p44_active_shrink_v2_${TS}.txt"
LOG_JSON="$OUT/p44_active_shrink_v2_${TS}.json"

ACTIVE_MD="$BIN/INDEX_ACTIVE_SCRIPTS.md"
QUAR_MD="$BIN/INDEX_QUARANTINE.md"

backup_if_exists(){
  local f="$1"
  if [ -f "$f" ]; then
    cp -f "$f" "${f}.bak_${TS}"
    echo "[BACKUP] ${f}.bak_${TS}" | tee -a "$LOG_TXT"
  fi
}

echo "== [P44v2] shrink ACTIVE by dependency graph ==" | tee "$LOG_TXT"

backup_if_exists "$ACTIVE_MD"
backup_if_exists "$QUAR_MD"

python3 - <<'PY' | tee -a "$LOG_TXT"
from pathlib import Path
import re, json, os, sys, datetime

root = Path("/home/test/Data/SECURITY_BUNDLE/ui")
bin_dir = root / "bin"
out_dir = root / "out_ci"
ts = os.environ.get("TS") or datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

ACTIVE_MD = bin_dir / "INDEX_ACTIVE_SCRIPTS.md"
QUAR_MD   = bin_dir / "INDEX_QUARANTINE.md"
LOG_JSON  = out_dir / f"p44_active_shrink_v2_{ts}.json"

def is_disabled(p: Path) -> bool:
    return ".disabled_" in p.name

def is_backup(p: Path) -> bool:
    # cover common backup styles: .bak_*, .bak-*, .bak.*, .bak<digits>
    n=p.name
    return (".bak_" in n) or (".bak-" in n) or (".bak." in n) or re.search(r"\.bak\d", n or "") is not None

def is_quarantine(p: Path) -> bool:
    n=p.name
    return n.startswith("_quarantine_") or ("quarantine" in n)

def desc_of_file(p: Path) -> str:
    try:
        lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
    except Exception:
        return "—"
    for ln in lines[:80]:
        m=re.search(r'==\s*\[([^\]]+)\]\s*(.+)?', ln)
        if m:
            out=f"{m.group(1)}: {(m.group(2) or '').strip()}".strip(": ").strip()
            return (out[:160] if out else "—")
    start = 1 if (lines and lines[0].startswith("#!")) else 0
    for ln in lines[start:start+80]:
        t=ln.strip()
        if not t: 
            continue
        if t.startswith("#"):
            t=t.lstrip("#").strip()
            return (t[:160] if t else "—")
        break
    return "—"

def run_cmd(p: Path) -> str:
    if p.suffix == ".sh":
        return f"bash bin/{p.name}"
    if p.suffix == ".py":
        return f"python3 bin/{p.name}"
    return f"bin/{p.name}"

# 1) Collect candidates
cands = []
for p in bin_dir.iterdir():
    if not p.is_file(): 
        continue
    if p.suffix not in (".sh",".py",".md"):
        continue
    if is_disabled(p) or is_backup(p):
        continue
    cands.append(p)

# 2) quarantine list (for INDEX_QUARANTINE.md) — keep like before
quar = [p for p in cands if is_quarantine(p)]
# active candidates for graph: only sh/py and not quarantine
scripts = [p for p in cands if p.suffix in (".sh",".py") and not is_quarantine(p)]
by_name = {p.name: p for p in scripts}

# 3) Seed set: “commercial entrypoints” (auto-detect if present)
seed_names = [
    "p43_bin_syntax_gate.sh",
    "commercial_ui_audit_v3b.sh",
    "p46_gate_pack_handover_v1.sh",
    "p39_pack_commercial_release_v1b.sh",
    "p2_release_pack_ui_commercial_v1.sh",
    "p1_release_proofnote_v2_fixed.sh",
    "vsp_ui_ops_safe_v3.sh",
    "commercial_ui_audit_v1.sh",
    "commercial_ui_audit_v2.sh",
    "commercial_ui_audit_v3.sh",
    "commercial_ui_audit_v3b.sh",
    "p44_index_inventory_v1.sh",
]
seeds = [by_name[n] for n in seed_names if n in by_name]

# fallback: if no seeds found, pick a few most-recent p4*/commercial* in bin
if not seeds:
    recent = sorted(scripts, key=lambda p: p.stat().st_mtime, reverse=True)
    seeds = [p for p in recent if (p.name.startswith("p4") or "commercial" in p.name)][:12]

# 4) Parse dependencies (bash bin/X, sh bin/X, python3 bin/X, ./bin/X)
call_re = re.compile(
    r'''(?mx)
    (?:\b(?:bash|sh)\s+bin/([A-Za-z0-9._-]+\.sh)\b)|
    (?:\bpython3\s+bin/([A-Za-z0-9._-]+\.py)\b)|
    (?:\b\./bin/([A-Za-z0-9._-]+\.(?:sh|py))\b)
    '''
)

def deps_of(p: Path):
    try:
        s=p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return set()
    found=set()
    for m in call_re.finditer(s):
        for g in m.groups():
            if g:
                found.add(g)
    # keep only those that exist in by_name
    return {name for name in found if name in by_name}

# BFS
reachable = set([p.name for p in seeds])
queue = list(seeds)
while queue:
    cur = queue.pop(0)
    for d in deps_of(cur):
        if d not in reachable:
            reachable.add(d)
            queue.append(by_name[d])

reachable_paths = [by_name[n] for n in sorted(reachable)]
seed_paths = seeds

# 5) Write INDEX_ACTIVE_SCRIPTS.md (small + CIO-friendly)
lines=[]
lines.append("# INDEX_ACTIVE_SCRIPTS (Commercial Reachable)")
lines.append("")
lines.append(f"- Generated: {ts}")
lines.append(f"- Root: {root}")
lines.append(f"- Seeds: {len(seed_paths)} | Reachable scripts: {len(reachable_paths)}")
lines.append("")
lines.append("## A) Commercial entrypoints (seeds)")
lines.append("")
lines.append("| Script | Purpose | Run |")
lines.append("|---|---|---|")
for p in seed_paths:
    lines.append(f"| `{p.name}` | {desc_of_file(p)} | `{run_cmd(p)}` |")
lines.append("")
lines.append("## B) Reachable dependencies (called by seeds)")
lines.append("")
lines.append("| Script | Purpose | Run |")
lines.append("|---|---|---|")
for p in reachable_paths:
    if p in seed_paths:
        continue
    lines.append(f"| `{p.name}` | {desc_of_file(p)} | `{run_cmd(p)}` |")
lines.append("")
lines.append("## C) Not listed")
lines.append("- Legacy/one-off/patch scripts are intentionally not listed here to keep this file readable.")
lines.append("- To browse all scripts: `ls -1 bin/*.sh bin/*.py | wc -l`")

ACTIVE_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")

# 6) Write/refresh INDEX_QUARANTINE.md (same spirit)
q=[]
q.append("# INDEX_QUARANTINE")
q.append("")
q.append(f"- Generated: {ts}")
q.append(f"- Root: {root}")
q.append("")
q.append("## Summary")
q.append(f"- Quarantine files in bin/: **{len(quar)}**")
q.append("")
q.append("| File | Note |")
q.append("|---|---|")
for p in quar:
    q.append(f"| `{p.name}` | quarantine file (do not call from release gate) |")
q.append("")
QUAR_MD.write_text("\n".join(q) + "\n", encoding="utf-8")

# 7) Emit json
LOG_JSON.write_text(json.dumps({
    "ok": True,
    "ts": ts,
    "seeds": [p.name for p in seed_paths],
    "reachable_count": len(reachable_paths),
    "reachable": [p.name for p in reachable_paths],
    "quarantine_count": len(quar),
    "files": {
        "INDEX_ACTIVE_SCRIPTS": str(ACTIVE_MD),
        "INDEX_QUARANTINE": str(QUAR_MD),
    }
}, indent=2), encoding="utf-8")

print(f"[OK] wrote {ACTIVE_MD} (reachable={len(reachable_paths)})")
print(f"[OK] wrote {QUAR_MD} (quarantine={len(quar)})")
print(f"[OK] json  {LOG_JSON}")
PY

echo "[OK] done (see $LOG_TXT)"
