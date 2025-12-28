#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_resolver_uireq_${TS}"
echo "[BACKUP] $F.bak_resolver_uireq_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p=Path("vsp_demo_app.py")
t=p.read_text(encoding="utf-8", errors="ignore")

TAG="# === VSP_RESOLVER_UIREQ_FALLBACK_V1 ==="
if TAG in t:
    print("[OK] already patched"); raise SystemExit(0)

# find function def vsp_run_status_v1_fs_resolver(rid):
m = re.search(r"^def\s+vsp_run_status_v1_fs_resolver\s*\(\s*rid\s*\)\s*:\s*$", t, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find def vsp_run_status_v1_fs_resolver(rid)")

start=m.end()
mnext=re.search(r"^def\s+[A-Za-z0-9_]+\s*\(", t[start:], flags=re.M)
end=start+(mnext.start() if mnext else len(t[start:]))

block=t[m.start():end].splitlines(True)

# insert near top of function body (first indented line)
out=[]
inserted=False
for ln in block:
    if (not inserted) and re.match(r"^\s{4}\S", ln):
        indent=" " * 4
        inj = textwrap.dedent(f"""\
            {indent}{TAG}
            {indent}# If resolver can't map UIREQ->RIDN but status_v1 has ci_run_dir, return rid_norm from it
            {indent}try:
            {indent}    if isinstance(rid, str) and "UIREQ" in rid:
            {indent}        st = vsp_run_status_v1().get_json(silent=True) if hasattr(vsp_run_status_v1(), "get_json") else None
            {indent}except Exception:
            {indent}    st = None
            {indent}# === END VSP_RESOLVER_UIREQ_FALLBACK_V1 ===
        """)
        # safer: do not call view; we’ll just use existing helper if present later. So just mark and continue.
        out.append(inj)
        inserted=True
    out.append(ln)

t2=t[:m.start()] + "".join(out) + t[end:]
p.write_text(t2, encoding="utf-8")
print("[OK] injected UIREQ fallback marker (next patch will replace return block safely)")
PY

# Replace the marker with a working fallback using response from /api/vsp/run_status_v1/<rid>
python3 - <<'PY'
from pathlib import Path
import re, textwrap

p=Path("vsp_demo_app.py")
t=p.read_text(encoding="utf-8", errors="ignore")

# we will add a small helper in resolver by string replace around the marker block
marker = r"# === VSP_RESOLVER_UIREQ_FALLBACK_V1 ==="
if marker not in t:
    raise SystemExit("[ERR] marker not found")

# Insert working code right after marker line
t = t.replace(marker, marker + "\n" + textwrap.dedent("""
    # WORKING: fetch status_v1 for this rid and derive rid_norm from ci_run_dir
    try:
        _st = proxy_get(f"/api/vsp/run_status_v1/{rid}")
        if isinstance(_st, dict) and _st.get("ok") and isinstance(_st.get("ci_run_dir"), str) and _st["ci_run_dir"]:
            _ridn = _st["ci_run_dir"].rstrip("/").split("/")[-1]
            return {
                "ok": True,
                "rid_norm": _ridn,
                "ci_run_dir": _st.get("ci_run_dir"),
                "status": _st.get("status"),
                "final": _st.get("final"),
            }
    except Exception:
        pass
""").rstrip() + "\n")

p.write_text(t, encoding="utf-8")
print("[OK] expanded UIREQ fallback to real logic")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== test resolver (should ok:true rid_norm!=null) =="
RID="VSP_UIREQ_20251214_140744_b1ff2a"
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v1_fs_resolver/$RID" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()))'
