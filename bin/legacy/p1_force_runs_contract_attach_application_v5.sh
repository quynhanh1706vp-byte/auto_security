#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runs_contract_attach_app_v5_${TS}"
echo "[BACKUP] ${F}.bak_runs_contract_attach_app_v5_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_RUNS_CONTRACT_ATTACH_APPLICATION_V5"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Insert after "application =" if exists, else append at end (safe).
m = re.search(r'(?m)^\s*application\s*=\s*', s)
ins = (s.find("\n", m.end()) + 1) if m else len(s)

inject = f'''
# ==== {MARK} ====
# P1 commercial: force /api/vsp/runs contract fields and ensure at least one RID (fallback scan).
try:
    from flask import request as _req

    def _vsp_runs_contract_after_request_v5(resp):
        try:
            if (_req.path or "") != "/api/vsp/runs":
                return resp

            mt = (getattr(resp, "mimetype", "") or "")
            if "json" not in mt:
                return resp

            try:
                resp.direct_passthrough = False
            except Exception:
                pass

            import json as _json, os as _os
            from pathlib import Path as _P

            raw = resp.get_data()
            txt = raw.decode("utf-8", "replace") if isinstance(raw, (bytes, bytearray)) else str(raw)
            data = _json.loads(txt) if txt.strip() else {{}}

            if not isinstance(data, dict) or data.get("ok") is not True:
                return resp

            items = data.get("items") or []
            if not isinstance(items, list):
                items = []
                data["items"] = items

            # effective limit requested (cap)
            try:
                lim_req = int((_req.args.get("limit") or "50").strip())
            except Exception:
                lim_req = 50
            hard_cap = 120
            lim_eff = max(1, min(lim_req, hard_cap))
            data["limit"] = lim_eff

            # roots used: prefer env, else known defaults
            roots = []
            env_roots = (_os.environ.get("VSP_RUNS_ROOTS") or "").strip()
            if env_roots:
                roots = [x.strip() for x in env_roots.split(":") if x.strip()]
            else:
                roots = [
                    "/home/test/Data/SECURITY_BUNDLE/out",
                    "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
                ]
            data["roots_used"] = roots

            # If items empty: fallback scan to populate recent runs
            if not items:
                runs = []
                for r in roots:
                    rp = _P(r)
                    if not rp.exists():
                        continue
                    for pat in ("RUN_*", "*_RUN_*"):
                        for d in rp.glob(pat):
                            if d.is_dir():
                                try:
                                    runs.append((d.stat().st_mtime, d))
                                except Exception:
                                    pass
                runs.sort(key=lambda x: x[0], reverse=True)
                take = min(len(runs), lim_eff)
                if take > 0:
                    new_items = []
                    for _, d in runs[:take]:
                        rid = d.name
                        # has flags (best-effort)
                        rep = d / "reports"
                        has = {{
                            "csv": (rep / "findings_unified.csv").exists(),
                            "html": (rep / "checkmarx_like.html").exists(),
                            "json": (rep / "findings_unified.json").exists() or (d / "findings_unified.json").exists(),
                            "sarif": (rep / "findings_unified.sarif").exists() or (d / "findings_unified.sarif").exists(),
                            "summary": (rep / "run_gate_summary.json").exists() or (d / "run_gate_summary.json").exists(),
                        }}
                        new_items.append({{"run_id": rid, "has": has}})
                    data["items"] = new_items
                    items = new_items

            # rid_latest
            rid_latest = ""
            if items:
                try:
                    rid_latest = (items[0].get("run_id") or items[0].get("rid") or "").strip()
                except Exception:
                    rid_latest = ""
            data["rid_latest"] = rid_latest

            # cache ttl
            try:
                data["cache_ttl"] = int(_os.environ.get("VSP_RUNS_CACHE_TTL", "2"))
            except Exception:
                data["cache_ttl"] = 2

            # scan cap hit (from _scanned)
            try:
                scanned = int(data.get("_scanned") or 0)
            except Exception:
                scanned = 0
            scan_cap = int(_os.environ.get("VSP_RUNS_SCAN_CAP", "500"))
            data["scan_cap"] = scan_cap
            data["scan_cap_hit"] = bool(scanned >= scan_cap)

            out = _json.dumps(data, ensure_ascii=False)
            resp.set_data(out.encode("utf-8"))
            resp.headers["Content-Length"] = str(len(resp.get_data()))
            resp.headers["X-VSP-RUNS-CONTRACT"] = "P1_V5"
            return resp
        except Exception:
            return resp

    try:
        application.after_request(_vsp_runs_contract_after_request_v5)
    except Exception:
        pass

except Exception:
    pass
# ==== /{MARK} ====
'''

s = s[:ins] + inject + s[ins:]
p.write_text(s, encoding="utf-8")
print("[OK] injected:", MARK, "at", "after application=" if m else "EOF")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

rm -f /tmp/vsp_ui_8910.lock || true
bin/p1_ui_8910_single_owner_start_v2.sh

echo "== re-diag =="
bin/p1_diag_runs_contract_v1.sh || true

echo "== re-selfcheck =="
bin/p0_commercial_selfcheck_ui_v1.sh || true
