#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_topfind_v4_${TS}"
echo "[BACKUP] ${APP}.bak_topfind_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# sanity: we patch only if V3 marker exists (so we don't break unknown layouts)
if "VSP_P0_TOPFIND_ROUTE_V3" not in s:
    raise SystemExit("[ERR] missing marker VSP_P0_TOPFIND_ROUTE_V3 (did you apply v3?)")

# ensure helper to pick RID with actual unified exists (idempotent)
helper_marker = "VSP_P0_TOPFIND_PICK_RID_WITH_UNIFIED_V1"
if helper_marker not in s:
    helper_block = f"""
# {helper_marker}
def _vsp__pick_latest_rid_with_unified() -> str:
    best = ("", -1.0)
    for root in _vsp__candidate_run_roots():
        try:
            if not os.path.isdir(root):
                continue
            for d in glob.glob(os.path.join(root, "VSP_*")):
                if not os.path.isdir(d):
                    continue
                # require at least one usable source
                cand = [
                    os.path.join(d, "reports", "findings_unified.json"),
                    os.path.join(d, "findings_unified.json"),
                    os.path.join(d, "report", "findings_unified.json"),
                    os.path.join(d, "reports", "findings_unified.csv"),
                ]
                ok = False
                for fp in cand:
                    try:
                        if os.path.isfile(fp) and os.path.getsize(fp) > 20:
                            ok = True
                            break
                    except Exception:
                        pass
                if not ok:
                    continue
                mt = os.path.getmtime(d)
                name = os.path.basename(d)
                if mt > best[1]:
                    best = (name, mt)
        except Exception:
            continue
    return best[0] or ""
"""
    # place helper near existing helpers block if possible
    ins = s.find("VSP_P0_TOPFIND_HELPERS_V3")
    if ins >= 0:
        # insert after the helpers marker line
        m = re.search(r'^\s*#\s*VSP_P0_TOPFIND_HELPERS_V3\s*$', s, flags=re.M)
        if m:
            # insert after end of that helper section (heuristic: before '# END VSP_P0_TOPFIND_HELPERS_V3' if present)
            mend = re.search(r'^\s*#\s*END\s+VSP_P0_TOPFIND_HELPERS_V3\s*$', s, flags=re.M)
            if mend:
                s = s[:mend.start()] + helper_block + "\n" + s[mend.start():]
            else:
                s = s[:m.end()] + "\n" + helper_block + "\n" + s[m.end():]
        else:
            s = helper_block + "\n" + s
    else:
        s = helper_block + "\n" + s

# Replace the V3 topfind route body with a V4 contract+fallback version.
# We replace from '# VSP_P0_TOPFIND_ROUTE_V3' up to just before the diag route decorator.
start = s.find("# VSP_P0_TOPFIND_ROUTE_V3")
if start < 0:
    raise SystemExit("[ERR] cannot locate start marker")

m_diag = re.search(r'^\s*@app\.route\(\"/api/vsp/_diag_topfind_routes_v1\"', s, flags=re.M)
if not m_diag:
    raise SystemExit("[ERR] cannot locate diag route anchor for safe replacement")

end = start
# end at the diag decorator line
end = m_diag.start()

new_route = r'''
# VSP_P0_TOPFIND_ROUTE_V4 (contract+fallback)
@app.route("/api/vsp/top_findings_v1", methods=["GET"], endpoint="vsp_top_findings_v1_p0")
def vsp_top_findings_v1_p0():
    try:
        rid_req = (request.args.get("rid") or "").strip()
        rid = rid_req
        limit = int(request.args.get("limit") or "5")
        limit = 1 if limit < 1 else (50 if limit > 50 else limit)

        if not rid:
            rid = _vsp__pick_latest_rid_with_unified() or _vsp__pick_latest_rid()

        if not rid:
            return jsonify({"ok": False, "rid": "", "rid_requested": rid_req, "rid_used": "", "total": 0, "items": [], "reason": "NO_RUNS"}), 200

        findings, reason = _vsp__load_unified_findings_anywhere(rid)

        # fallback: requested RID has no usable sources -> use latest RID that actually has unified/csv
        if findings is None:
            rid2 = _vsp__pick_latest_rid_with_unified()
            if rid2 and rid2 != rid:
                findings2, reason2 = _vsp__load_unified_findings_anywhere(rid2)
                if findings2 is not None:
                    rid = rid2
                    findings = findings2
                    reason = ""

        if findings is None:
            return jsonify({"ok": False, "rid": rid, "rid_requested": rid_req, "rid_used": "", "total": 0, "items": [], "reason": reason}), 200

        items = []
        for f in (findings or []):
            if not isinstance(f, dict):
                continue
            items.append({
                "tool": f.get("tool"),
                "severity": (f.get("severity") or "").upper(),
                "title": f.get("title"),
                "cwe": f.get("cwe"),
                "rule_id": f.get("rule_id") or f.get("check_id") or f.get("id"),
                "file": _vsp__sanitize_path(f.get("file") or f.get("path") or ""),
                "line": f.get("line") or f.get("start_line") or f.get("line_start"),
            })
        items.sort(key=lambda x: (_vsp__sev_weight(x.get("severity")), str(x.get("title") or "")), reverse=True)

        return jsonify({
            "ok": True,
            "rid": rid,
            "rid_requested": rid_req,
            "rid_used": rid,
            "total": len(items),
            "items": items[:limit],
            "ts": datetime.utcnow().isoformat() + "Z",
        }), 200
    except Exception:
        return jsonify({"ok": False, "rid": (request.args.get("rid") or ""), "rid_requested": (request.args.get("rid") or ""), "rid_used": "", "total": 0, "items": [], "reason": "EXCEPTION"}), 200
'''

s = s[:start] + new_route + "\n" + s[end:]
p.write_text(s, encoding="utf-8")
print("[OK] replaced route block with V4 fallback contract")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service
sudo systemctl is-active --quiet vsp-ui-8910.service && echo "[OK] service active"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${1:-VSP_CI_20251218_114312}"

echo "== [TEST] top_findings_v1 headers+body =="
curl -sS -D /tmp/top.h -o /tmp/top.b "$BASE/api/vsp/top_findings_v1?rid=$RID&limit=5" || true
sed -n '1,20p' /tmp/top.h
head -c 260 /tmp/top.b; echo

echo "== [TEST] top_findings_v1 parse (must have total/items) =="
python3 - <<'PY'
import json
b=open("/tmp/top.b","rb").read().strip()
j=json.loads(b.decode("utf-8","replace")) if b else {}
print("ok=",j.get("ok"),"rid_requested=",j.get("rid_requested"),"rid_used=",j.get("rid_used"),"total=",j.get("total"))
items=j.get("items") or []
print("items=",len(items))
if items:
    print("first_sev=",items[0].get("severity"),"title=",(items[0].get("title") or "")[:120])
PY

echo "[DONE]"
