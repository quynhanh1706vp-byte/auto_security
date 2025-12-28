#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID1="${1:-VSP_CI_20251215_173713}"

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

patch_file(){
  local f="$1"
  [ -f "$f" ] || return 0

  python3 - <<PY
from pathlib import Path
import re, py_compile, time

p=Path("$f")
s=p.read_text(encoding="utf-8", errors="ignore")
MARK="VSP_P0_DASH_KPIS_RESPECT_RID_CONTRACT_V1"
if MARK in s:
    print("[OK] already patched:", p)
    raise SystemExit(0)

if "dash_kpis" not in s:
    print("[SKIP] no dash_kpis token in", p)
    raise SystemExit(0)

# Heuristic patch: when handler builds JSON j for dash_kpis, enforce rid_used and echo rid_used.
# We patch common patterns:
# - request.args.get("rid")
# - args.get("rid")
# - rid = ...
# - return jsonify(j) or return j

# 1) Ensure we capture rid_req and rid_used near the top of handler.
# Try to find a function/route block containing "dash_kpis" and insert a rid normalization snippet.
m = re.search(r"(def\s+[^\\n]*dash_kpis[^\\n]*\\n)([\\s\\S]{0,800}?)\\n\\s*(return\\s+)", s)
if not m:
    # fallback: search for a route decorator then def
    m = re.search(r"(route\\([^\\)]*dash_kpis[^\\)]*\\)[\\s\\S]{0,120}?(def\\s+[^\\n]+\\n))([\\s\\S]{0,800}?)\\n\\s*(return\\s+)", s)

if not m:
    print("[WARN] could not locate dash_kpis handler block in", p, "- leaving unchanged")
    raise SystemExit(0)

start = m.start()
# Insert after function signature line (group1)
sig = m.group(1) if m.lastindex and m.lastindex >= 1 else None
if sig is None:
    print("[WARN] unexpected matcher; skip")
    raise SystemExit(0)

insert_after = start + len(sig)

snippet = """
    # --- VSP_P0_DASH_KPIS_RESPECT_RID_CONTRACT_V1 ---
    try:
        _rid_req = (request.args.get("rid") or "").strip()
    except Exception:
        _rid_req = ""
    # IMPORTANT: rid_used must follow query rid if provided; otherwise fall back to existing logic.
    # We don't force-pick latest here; we only ensure we do NOT overwrite user rid.
    # --- /VSP_P0_DASH_KPIS_RESPECT_RID_CONTRACT_V1 ---
"""

# Avoid double insert if request.args already used right after
if "VSP_P0_DASH_KPIS_RESPECT_RID_CONTRACT_V1" not in s:
    s = s[:insert_after] + snippet + s[insert_after:]

# 2) Patch places where rid is chosen/overwritten: replace patterns like `rid = RID_LATEST` ONLY IF rid_req exists.
# This is best-effort: we add a guard block before first assignment to 'rid' that uses rid_req.
s = re.sub(
    r"(\n\s*)(rid\s*=\s*)([^\n#]+)(\n)",
    lambda m: (m.group(0) if "_rid_req" in m.group(0) else
               m.group(1) + "rid = (_rid_req or (" + m.group(3).strip() + "))" + m.group(4)),
    s,
    count=1
)

# 3) Ensure response includes rid_used; patch common `return jsonify(j)` or `return j`
# Insert `j["rid_used"]=rid` just before first return inside handler vicinity.
# (We do a broad but safe insertion: right before the first `return` after the marker snippet.)
pos = s.find("VSP_P0_DASH_KPIS_RESPECT_RID_CONTRACT_V1")
if pos != -1:
    # search forward for first "\n    return"
    r = re.search(r"\n(\s+)return\b", s[pos:])
    if r:
        rpos = pos + r.start()
        indent = r.group(1)
        add = f"\n{indent}# {MARK}\n{indent}try:\n{indent}    j['rid_used'] = rid\n{indent}    j['rid_req'] = _rid_req\n{indent}except Exception:\n{indent}    pass\n"
        if MARK not in s:
            s = s[:rpos] + add + s[rpos:]

# 4) If there is a cache dict key 'dash_kpis' without rid, make it include rid (best-effort).
s = re.sub(r"(['\"]dash_kpis['\"]\s*\+\s*)([^\\n]+)", r"\1(str(rid)+':'+(\2))", s, count=1)
s = s + f"\n# {MARK}\n"

p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched:", p)
PY
}

TS="$(date +%Y%m%d_%H%M%S)"
for f in vsp_demo_app.py wsgi_vsp_ui_gateway.py; do
  if [ -f "$f" ]; then
    cp -f "$f" "${f}.bak_dashkpis_${TS}"
    ok "backup: ${f}.bak_dashkpis_${TS}"
    patch_file "$f" || true
  fi
done

# restart
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || err "restart failed"
  sleep 0.6
fi

echo "== [VERIFY] dash_kpis rid_used field =="
RID2="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); r=(j.get("runs") or [{}])[0].get("rid",""); print(r)')"
echo "RID1=$RID1"
echo "RID2=$RID2"
curl -fsS "$BASE/api/vsp/dash_kpis?rid=$RID1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("RID1 rid_used=",j.get("rid_used"),"total=",j.get("total_findings"))'
curl -fsS "$BASE/api/vsp/dash_kpis?rid=$RID2" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("RID2 rid_used=",j.get("rid_used"),"total=",j.get("total_findings"))'

ok "DONE"
