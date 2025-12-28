#!/usr/bin/env bash
set +e
set -u

KICS_TIMEOUT_SEC="${KICS_TIMEOUT_SEC:-1200}"   # default 20 phút
echo "[INFO] KICS_TIMEOUT_SEC=$KICS_TIMEOUT_SEC"

ROOTS=(
  "/home/test/Data/SECURITY_BUNDLE/bin"
  "/home/test/Data/SECURITY-10-10-v4/bin"
)

python3 - <<'PY'
from pathlib import Path
import re, time

KICS_TIMEOUT_SEC = int(__import__("os").environ.get("KICS_TIMEOUT_SEC","1200"))
marker = "VSP_P1_KICS_TIMEOUT_DEGRADED_FAST_V2"

def backup(p: Path):
    ts=time.strftime("%Y%m%d_%H%M%S")
    b=p.with_name(p.name+f".bak_kics_fast_{ts}")
    b.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    return b

def patch_sh(p: Path):
    s=p.read_text(encoding="utf-8", errors="replace")
    if marker in s:
        print("[OK] already:", p)
        return False

    if "kics" not in s.lower():
        return False

    # Strategy:
    # 1) Prefer patching "run_all_tools*.sh" that calls run_kics*.sh
    # 2) Otherwise patch any line that invokes kics/docker checkmarx/kics
    lines=s.splitlines(True)

    # helper: add timeout var if not present
    ins = 1 if (lines and lines[0].startswith("#!")) else 0
    helper = (
        f"# {marker}\n"
        f'KICS_TIMEOUT_SEC="${{KICS_TIMEOUT_SEC:-{KICS_TIMEOUT_SEC}}}"\n'
        f'export KICS_TIMEOUT_SEC\n'
    )
    lines.insert(ins, helper)

    # patch patterns
    patched=False

    # A) wrap call to run_kics*.sh (best)
    call_pat = re.compile(r'^\s*(?!#).*?\b(run_kics[^ \n]*\.sh)\b.*$', re.I)
    for i,ln in enumerate(lines):
        m=call_pat.match(ln)
        if not m: 
            continue
        if "timeout" in ln:
            continue
        indent=re.match(r'^(\s*)', ln).group(1)
        cmd=ln.strip().rstrip(";")
        lines[i]=(
            f'{indent}echo "[INFO] KICS wrapper timeout=${{KICS_TIMEOUT_SEC}}s"\n'
            f'{indent}timeout -k 30s "${{KICS_TIMEOUT_SEC}}s" {cmd} || '
            f'echo "[WARN] KICS timeout/error -> degraded, continue"\n'
        )
        patched=True
        break

    # B) if not found, wrap direct docker/kics scan line
    if not patched:
        kics_pat = re.compile(r'^\s*(?!#).*(\bkics\b.*\bscan\b|checkmarx/kics|docker.*\bkics\b).*$', re.I)
        for i,ln in enumerate(lines):
            if not kics_pat.match(ln): 
                continue
            if "timeout" in ln:
                continue
            indent=re.match(r'^(\s*)', ln).group(1)
            cmd=ln.strip().rstrip(";")
            lines[i]=(
                f'{indent}echo "[INFO] KICS wrapper timeout=${{KICS_TIMEOUT_SEC}}s"\n'
                f'{indent}timeout -k 30s "${{KICS_TIMEOUT_SEC}}s" {cmd} || '
                f'echo "[WARN] KICS timeout/error -> degraded, continue"\n'
            )
            patched=True
            break

    if not patched:
        # still write marker helper to make behavior explicit
        pass

    p.write_text("".join(lines), encoding="utf-8")
    print("[PATCHED]" if patched else "[MARKED]", p)
    return True

roots = [
  Path("/home/test/Data/SECURITY_BUNDLE/bin"),
  Path("/home/test/Data/SECURITY-10-10-v4/bin"),
]

cands=[]
for r in roots:
    if not r.is_dir():
        continue
    for p in sorted(r.glob("*.sh")):
        name=p.name.lower()
        if "kics" in name or "run_all" in name or "tools" in name:
            cands.append(p)

# patch only a manageable set
for p in cands[:80]:
    try:
        s=p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if "kics" not in s.lower():
        continue
    b=backup(p)
    print("[BACKUP]", b)
    patch_sh(p)
PY

echo "[OK] done. Now start a new scan from /runs (Scan panel)."
