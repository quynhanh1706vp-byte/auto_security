#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need ls; need tail; need python3; need date; need curl; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

echo "== [0] pick latest backup before broken V1F =="
BK="$(ls -1t ${W}.bak_trend_v1f_* 2>/dev/null | head -n 1 || true)"
if [ -z "$BK" ]; then
  echo "[ERR] cannot find backup ${W}.bak_trend_v1f_*"
  echo "[HINT] list backups: ls -1 ${W}.bak_* | tail"
  exit 2
fi
echo "[INFO] restore from: $BK"
cp -f "$BK" "$W"

echo "== [1] ensure file compiles after restore =="
python3 -m py_compile "$W"
echo "[OK] py_compile after restore"

echo "== [2] append V1F2 middleware (safe) =="
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_before_v1f2_${TS}"
echo "[BACKUP] ${W}.bak_before_v1f2_${TS}"

python3 - "$W" <<'PY'
from pathlib import Path
import sys

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P2_WSGI_TREND_TUNE_V1F2"
if MARK in s:
    print("[OK] V1F2 already present; skip")
    raise SystemExit(0)

patch = r'''
# --- VSP_P2_WSGI_TREND_TUNE_V1F2 (auto-injected, SAFE append) ---
def _vsp_install_wsgi_trend_tuned_v1f2():
    import json, os, datetime, urllib.parse

    class _VspTrendTunedMiddlewareV1F2:
        def __init__(self, app):
            self.app = app

        def _allow_name(self, name: str) -> bool:
            # Keep chart clean (commercial)
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

        def _total_from_gate(self, j):
            if not isinstance(j, dict):
                return None

            # direct ints (your gate often has counts_total)
            for k in ("counts_total","total","total_findings","findings_total","total_unified"):
                v = j.get(k)
                if isinstance(v, int):
                    return v

            ov = j.get("overall")
            if isinstance(ov, dict):
                for k in ("counts_total","total","total_findings"):
                    v = ov.get(k)
                    if isinstance(v, int):
                        return v

            # map sums
            for mk in ("by_severity","counts","severity_counts","counts_by_severity"):
                c = j.get(mk)
                if isinstance(c, dict):
                    sm = 0
                    hit = False
                    for vv in c.values():
                        if isinstance(vv, int):
                            sm += vv
                            hit = True
                    if hit:
                        return sm
            return None

        def _total_from_findings(self, fu):
            if fu is None:
                return None
            if isinstance(fu, list):
                return len(fu)
            if isinstance(fu, dict):
                if isinstance(fu.get("total"), int):
                    return int(fu.get("total"))
                if isinstance(fu.get("findings"), list):
                    return len(fu.get("findings"))
                if isinstance(fu.get("items"), list):
                    return len(fu.get("items"))
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
                    gate = (self._load_json(os.path.join(d, "run_gate_summary.json"))
                            or self._load_json(os.path.join(d, "reports", "run_gate_summary.json")))
                    total = self._total_from_gate(gate)

                    if total is None:
                        fu = (self._load_json(os.path.join(d, "findings_unified_commercial.json"))
                              or self._load_json(os.path.join(d, "findings_unified.json"))
                              or self._load_json(os.path.join(d, "reports", "findings_unified.json")))
                        total = self._total_from_findings(fu)

                    if total is None:
                        continue

                    ts = datetime.datetime.fromtimestamp(mt).isoformat(timespec="seconds")
                    label = datetime.datetime.fromtimestamp(mt).strftime("%Y-%m-%d %H:%M")
                    points.append({"label": label, "run_id": name, "total": int(total), "ts": ts})
                    if len(points) >= limit:
                        break

                body = json.dumps({
                    "ok": True,
                    "marker": "VSP_P2_WSGI_TREND_TUNE_V1F2",
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
    if getattr(app, "_vsp_trend_tuned_wrapped_v1f2", False):
        return
    mw = _VspTrendTunedMiddlewareV1F2(app)
    mw._vsp_trend_tuned_wrapped_v1f2 = True
    if g.get("application") is not None:
        g["application"] = mw
    else:
        g["app"] = mw

try:
    _vsp_install_wsgi_trend_tuned_v1f2()
except Exception:
    pass
# --- end VSP_P2_WSGI_TREND_TUNE_V1F2 ---
'''.lstrip("\n")

p.write_text(s + ("\n\n" if not s.endswith("\n") else "\n") + patch, encoding="utf-8")
print("[OK] appended V1F2 tuned middleware into", p)
PY

python3 -m py_compile "$W"
echo "[OK] py_compile after V1F2"

echo "== [3] restart service =="
sudo systemctl restart "$SVC"

echo "== [4] smoke trend_v1 (must be marker=V1F2 and list is clean) =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] RID=$RID"
curl -sS "$BASE/api/vsp/trend_v1?rid=$RID&limit=12" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print("ok=", j.get("ok"), "marker=", j.get("marker"), "points=", len(j.get("points") or []))
for p in (j.get("points") or [])[:12]:
    print("-", p.get("run_id"), "total=", p.get("total"))
PY
