#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need ls; need head; need python3; need date; need curl; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

echo "== [0] restore from latest bak_trend_total_v1g_* =="
BK="$(ls -1t ${W}.bak_trend_total_v1g_* 2>/dev/null | head -n 1 || true)"
if [ -z "$BK" ]; then
  echo "[ERR] cannot find ${W}.bak_trend_total_v1g_*"
  exit 2
fi
echo "[INFO] restore from: $BK"
cp -f "$BK" "$W"

echo "== [1] compile after restore =="
python3 -m py_compile "$W"
echo "[OK] py_compile after restore"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_before_v1g2_${TS}"
echo "[BACKUP] ${W}.bak_before_v1g2_${TS}"

python3 - "$W" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P2_WSGI_TREND_TOTAL_FIX_V1G2"
if MARK in s:
    print("[OK] V1G2 already present; skip")
    raise SystemExit(0)

patch = r'''
# --- VSP_P2_WSGI_TREND_TOTAL_FIX_V1G2 (SAFE append) ---
def _vsp_install_wsgi_trend_totalfix_v1g2():
    import json, os, datetime, urllib.parse

    class _VspTrendTotalFixMiddlewareV1G2:
        def __init__(self, app):
            self.app = app

        def _allow_name(self, name: str) -> bool:
            # keep chart clean (commercial)
            if name.startswith("VSP_CI_"):
                return True
            if name.startswith("RUN_VSP_FULL") or name.startswith("RUN_VSP_CI") or name.startswith("RUN_VSP_FULL_EXT"):
                # exclude noisy experiments
                if "KICS_TEST" in name or "GITLEAKS_TEST" in name or "gitleaks" in name.lower():
                    return False
                return True
            return False

        def _list_run_dirs(self, limit: int):
            roots = ["/home/test/Data/SECURITY_BUNDLE/out_ci", "/home/test/Data/SECURITY_BUNDLE/out"]
            roots = [r for r in roots if os.path.isdir(r)]
            dirs = []
            for r in roots:
                try:
                    for name in os.listdir(r):
                        if not self._allow_name(name):
                            continue
                        full = os.path.join(r, name)
                        if os.path.isdir(full):
                            try:
                                mt = os.path.getmtime(full)
                            except Exception:
                                mt = 0
                            dirs.append((mt, name, full))
                except Exception:
                    pass
            dirs.sort(key=lambda x: x[0], reverse=True)
            return dirs[: max(limit*3, limit)]

        def _load_json(self, path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                return None

        def _sum_int_dict(self, d):
            if not isinstance(d, dict):
                return None
            sm = 0
            hit = False
            for vv in d.values():
                if isinstance(vv, int):
                    sm += vv
                    hit = True
            return sm if hit else None

        def _total_from_gate(self, j):
            # supports: counts_total as dict(sev->count)
            if not isinstance(j, dict):
                return None

            for k in ("total","total_findings","findings_total","total_unified"):
                v = j.get(k)
                if isinstance(v, int):
                    return v

            ct = j.get("counts_total")
            if isinstance(ct, int):
                return ct
            sm = self._sum_int_dict(ct)
            if sm is not None:
                return sm

            ov = j.get("overall")
            if isinstance(ov, dict):
                for k in ("total","total_findings"):
                    v = ov.get(k)
                    if isinstance(v, int):
                        return v
                sm = self._sum_int_dict(ov.get("counts_total"))
                if sm is not None:
                    return sm

            # map sums
            for mk in ("by_severity","counts","severity_counts","counts_by_severity"):
                sm = self._sum_int_dict(j.get(mk))
                if sm is not None:
                    return sm

            return None

        def _total_from_findings(self, fu):
            # supports: counts_by_severity even when findings empty
            if fu is None:
                return None
            if isinstance(fu, list):
                return len(fu)
            if isinstance(fu, dict):
                if isinstance(fu.get("total"), int):
                    return int(fu.get("total"))

                sm = self._sum_int_dict(fu.get("counts_by_severity"))
                if sm is not None:
                    return sm

                items = fu.get("items")
                if isinstance(items, list) and len(items) > 0:
                    return len(items)
                findings = fu.get("findings")
                if isinstance(findings, list) and len(findings) > 0:
                    return len(findings)
            return None

        def _compute_total(self, d):
            gate = (self._load_json(os.path.join(d, "run_gate_summary.json"))
                    or self._load_json(os.path.join(d, "reports", "run_gate_summary.json")))
            total = self._total_from_gate(gate)
            if total is not None:
                return total

            # IMPORTANT: if commercial json yields None (or 0 without counts), continue to unified.json
            for fp in (
                os.path.join(d, "findings_unified_commercial.json"),
                os.path.join(d, "findings_unified.json"),
                os.path.join(d, "reports", "findings_unified.json"),
            ):
                fu = self._load_json(fp)
                t = self._total_from_findings(fu)
                if t is not None:
                    return t

            return None

        def __call__(self, environ, start_response):
            path = environ.get("PATH_INFO", "") or ""
            if path == "/api/vsp/trend_v1":
                qs = urllib.parse.parse_qs(environ.get("QUERY_STRING",""), keep_blank_values=True)
                rid = (qs.get("rid", [""])[0] or "").strip()
                try:
                    limit = int((qs.get("limit", ["20"])[0] or "20"))
                except Exception:
                    limit = 20
                if limit < 5: limit = 5
                if limit > 80: limit = 80

                points = []
                for mt, name, d in self._list_run_dirs(limit):
                    total = self._compute_total(d)
                    if total is None:
                        continue
                    ts = datetime.datetime.fromtimestamp(mt).isoformat(timespec="seconds")
                    label = datetime.datetime.fromtimestamp(mt).strftime("%Y-%m-%d %H:%M")
                    points.append({"label": label, "run_id": name, "total": int(total), "ts": ts})
                    if len(points) >= limit:
                        break

                body = json.dumps({
                    "ok": True,
                    "marker": "VSP_P2_WSGI_TREND_TOTAL_FIX_V1G2",
                    "rid_requested": rid,
                    "limit": limit,
                    "points": points
                }, ensure_ascii=False).encode("utf-8")

                start_response("200 OK", [
                    ("Content-Type", "application/json; charset=utf-8"),
                    ("Cache-Control", "no-store"),
                    ("Content-Length", str(len(body))),
                ])
                return [body]

            return self.app(environ, start_response)

    g = globals()
    app = g.get("application") or g.get("app")
    if app is None:
        return
    if getattr(app, "_vsp_trend_totalfix_wrapped_v1g2", False):
        return
    mw = _VspTrendTotalFixMiddlewareV1G2(app)
    mw._vsp_trend_totalfix_wrapped_v1g2 = True
    if g.get("application") is not None:
        g["application"] = mw
    else:
        g["app"] = mw

try:
    _vsp_install_wsgi_trend_totalfix_v1g2()
except Exception:
    pass
# --- end VSP_P2_WSGI_TREND_TOTAL_FIX_V1G2 ---
'''.lstrip("\n")

p.write_text(s + ("\n\n" if not s.endswith("\n") else "\n") + patch, encoding="utf-8")
print("[OK] appended V1G2 total-fix middleware into", p)
PY

python3 -m py_compile "$W"
echo "[OK] py_compile after V1G2"

sudo systemctl restart "$SVC"

RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] RID=$RID"
echo "== [SMOKE] trend_v1 first 6 points (marker must be V1G2) =="
curl -sS "$BASE/api/vsp/trend_v1?rid=$RID&limit=6" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print("ok=", j.get("ok"), "marker=", j.get("marker"))
for p in (j.get("points") or [])[:6]:
    print("-", p.get("run_id"), "total=", p.get("total"))
PY
