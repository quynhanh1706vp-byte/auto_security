#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls; need cp; need systemctl; need curl

TS="$(date +%Y%m%d_%H%M%S)"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

echo "== [1] snapshot current =="
cp -f "$W" "${W}.bak_snapshot_fix_${TS}"
echo "[SNAPSHOT] ${W}.bak_snapshot_fix_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, shutil

w = Path("wsgi_vsp_ui_gateway.py")

def comp(path: Path) -> bool:
    try:
        py_compile.compile(str(path), doraise=True)
        return True
    except Exception as e:
        print("[DBG] compile fail:", path.name, "=>", type(e).__name__, e)
        return False

# If current file doesn't compile, restore newest compiling backup.
if not comp(w):
    baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)
    restored = False
    for b in baks:
        tmp = Path("/tmp/_wsgi_try_restore.py")
        try:
            tmp.write_text(b.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        except Exception:
            continue
        if comp(tmp):
            shutil.copy2(b, w)
            print("[OK] restored wsgi from compiling backup:", b.name)
            restored = True
            break
    if not restored:
        raise SystemExit("[ERR] cannot find any compiling backup to restore")

# Fix the known unterminated string literal for gate story script include.
s = w.read_text(encoding="utf-8", errors="replace")
target_prefix = "script = '<script src=\"/static/js/vsp_dashboard_gate_story_v1.js?v="
if target_prefix in s:
    # replace any broken/partial assignment line (even if it accidentally spans lines)
    import re
    s2, n = re.subn(
        r"script\s*=\s*'<script\s+src=\"/static/js/vsp_dashboard_gate_story_v1\.js\?v=\{?\s*asset_v\s*\}?\"></script>\s*",
        "script = '<script src=\"/static/js/vsp_dashboard_gate_story_v1.js?v={{ asset_v }}\"></script>'\n",
        s,
        flags=re.M
    )
    # if pattern above didn't match (because it broke across lines), do a more robust fix:
    if n == 0:
        s2, n = re.subn(
            r"script\s*=\s*'<script\s+src=\"/static/js/vsp_dashboard_gate_story_v1\.js\?v=.*?</script>\s*",
            "script = '<script src=\"/static/js/vsp_dashboard_gate_story_v1.js?v={{ asset_v }}\"></script>'\n",
            s,
            flags=re.S
        )
    if n > 0:
        s = s2
        print(f"[OK] fixed gate_story script assignment (n={n})")
    else:
        print("[WARN] gate_story script assignment prefix found but pattern not replaced; continuing")

# Ensure allowlist includes reports/run_gate_summary.json and reports/run_gate.json
need = ["reports/run_gate_summary.json", "reports/run_gate.json"]
if all(x in s for x in need):
    print("[OK] allowlist already contains reports gate files")
else:
    import re
    cand = None
    for m in re.finditer(r'(?s)(\[[^\]]*?"run_gate_summary\.json"[^\]]*?\])', s):
        cand = m
        break
    if not cand:
        for m in re.finditer(r'(?s)(set\(\s*\[[^\]]*?"run_gate_summary\.json"[^\]]*?\]\s*\))', s):
            cand = m
            break
    if not cand:
        print("[WARN] cannot locate allowlist block containing run_gate_summary.json; skip allowlist injection")
    else:
        block = cand.group(1)
        out = block
        for item in need:
            if item in out:
                continue
            out = re.sub(r'("run_gate_summary\.json"\s*,?)', r'\1\n  "'+item+'",', out, count=1)
        out = re.sub(r',\s*,', ',', out)
        s = s.replace(block, out, 1)
        print("[OK] injected allowlist items:", ", ".join([x for x in need if x in s]))

w.write_text(s, encoding="utf-8")
print("[OK] wrote patched wsgi")
PY

echo "== [2] compile check =="
python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== [3] restart service =="
systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.8

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== [4] sanity =="
echo "-- / (head) --"
curl -sS -I "$BASE/" | sed -n '1,6p' || true
echo "-- KPI v2 --"
curl -sS "$BASE/api/ui/runs_kpi_v2?days=30" | head -c 220; echo
echo "-- run_file_allow reports gate summary (should be ok or at least NOT 403) --"
RID="RUN_20251120_130310"
curl -sS "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -c 260; echo

echo "[DONE] Now hard-reload /runs (Ctrl+Shift+R)."
