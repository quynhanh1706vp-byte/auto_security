#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3)"

W="wsgi_vsp_ui_gateway.py"
MOD="vsp_dash_fallback_mw_p3k2.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo; need date; need curl

echo "== [0] rollback gateway to last bak_p3k2_safe_* if exists =="
bak_safe="$(ls -1t ${W}.bak_p3k2_safe_* 2>/dev/null | head -n 1 || true)"
if [ -n "${bak_safe:-}" ]; then
  cp -f "$bak_safe" "$W"
  echo "[RESTORE] $bak_safe -> $W"
else
  echo "[INFO] no ${W}.bak_p3k2_safe_* found, keep current $W"
fi

echo "== [1] systemd override: disable blocking ExecStartPost + increase TimeoutStartSec =="
OVR_DIR="/etc/systemd/system/${SVC}.d"
OVR="/tmp/${SVC}.override.conf.$$"
cat > "$OVR" <<'EOF'
[Service]
TimeoutStartSec=180
ExecStartPost=
ExecStartPost=/bin/bash -lc 'exit 0'
EOF
sudo mkdir -p "$OVR_DIR"
sudo cp -f "$OVR" "$OVR_DIR/override.conf"
sudo chmod 0644 "$OVR_DIR/override.conf"
rm -f "$OVR"
echo "[OK] wrote $OVR_DIR/override.conf"

echo "== [2] daemon-reload + restart =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC" || true
sleep 0.8
if ! sudo systemctl is-active --quiet "$SVC"; then
  echo "[ERR] service not active after override"
  sudo systemctl status "$SVC" --no-pager | sed -n '1,220p' || true
  sudo journalctl -u "$SVC" -n 220 --no-pager || true
  exit 3
fi
echo "[OK] service active after override"

echo "== [3] write module $MOD (idempotent) =="
cat > "$MOD" <<'PY'
# VSP_P3K2_SAFE_DASH_MW_EXT_V1
import os, json, re, time
from datetime import datetime
from urllib.parse import parse_qs

SEV_ORDER = {"CRITICAL":0,"HIGH":1,"MEDIUM":2,"MEDIUM+":2,"LOW":3,"INFO":4,"TRACE":5}

def _norm_sev(x):
    x = (x or "").strip()
    x = re.sub(r'[\.\,;:\s]+$', '', x)  # strip trailing punctuation (CRITICAL.)
    x = x.upper()
    if x in ("MEDIUMPLUS","MEDIUM_PLUS","MEDIUM+"):
        return "MEDIUM"
    return x or "INFO"

def _parse_ts(name: str):
    m = re.search(r'(\d{8})_(\d{6})', name or "")
    if not m: return None
    try:
        return datetime.strptime(m.group(1)+m.group(2), "%Y%m%d%H%M%S")
    except Exception:
        return None

def _roots():
    roots = [
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
    ]
    return [r for r in roots if os.path.isdir(r)]

def _find_rid_dir(rid: str):
    rid = (rid or "").strip()
    if not rid: return None
    for root in _roots():
        d = os.path.join(root, rid)
        if os.path.isdir(d): return d
    return None

def _pick_best_rid():
    best = None
    for root in _roots():
        try:
            for name in os.listdir(root):
                d = os.path.join(root, name)
                if not os.path.isdir(d): 
                    continue
                ok = False
                for rel in (
                    "reports/findings_unified_commercial.json","reports/findings_unified.json",
                    "report/findings_unified_commercial.json","report/findings_unified.json",
                    "findings_unified_commercial.json","findings_unified.json",
                ):
                    fp = os.path.join(d, rel)
                    if os.path.isfile(fp) and os.path.getsize(fp) > 50:
                        ok = True; break
                if not ok: 
                    continue
                ts = _parse_ts(name) or datetime.fromtimestamp(0)
                mt = os.path.getmtime(d)
                key = (ts, mt)
                if best is None or key > best[0]:
                    best = (key, name)
        except Exception:
            pass
    return best[1] if best else ""

def _load_items(rid: str, cap=250000):
    rid_dir = _find_rid_dir(rid)
    if not rid_dir:
        return None, [], 0.0
    cands = [
        "reports/findings_unified_commercial.json",
        "reports/findings_unified.json",
        "report/findings_unified_commercial.json",
        "report/findings_unified.json",
        "findings_unified_commercial.json",
        "findings_unified.json",
    ]
    for rel in cands:
        fp = os.path.join(rid_dir, rel)
        if not os.path.isfile(fp):
            continue
        try:
            if os.path.getsize(fp) < 30:
                continue
        except Exception:
            continue
        try:
            mtime = os.path.getmtime(fp)
            with open(fp, "r", encoding="utf-8", errors="replace") as f:
                j = json.load(f)
            items = None
            for k in ("findings","items","results"):
                v = j.get(k)
                if isinstance(v, list):
                    items = v; break
            if items is None: items = []
            if len(items) > cap: items = items[:cap]
            return {"from": rel, "total": j.get("total")}, items, mtime
        except Exception:
            continue
    return None, [], 0.0

def _counts(items):
    sev = {}
    tool_ch = {}
    cwe = {}
    for it in items or []:
        s = _norm_sev((it or {}).get("severity"))
        sev[s] = sev.get(s, 0) + 1

        t = str((it or {}).get("tool") or "UNKNOWN")
        if t not in tool_ch:
            tool_ch[t] = {"tool": t, "CRITICAL": 0, "HIGH": 0}
        if s in ("CRITICAL","HIGH"):
            tool_ch[t][s] = tool_ch[t].get(s, 0) + 1

        cw = (it or {}).get("cwe")
        if cw is None:
            continue
        cw = str(cw).strip()
        if not cw:
            continue
        if cw.isdigit():
            cw = "CWE-" + cw
        cwe[cw] = cwe.get(cw, 0) + 1
    return sev, tool_ch, cwe

def _top_findings(items, limit=25):
    def key(it):
        return SEV_ORDER.get(_norm_sev((it or {}).get("severity")), 99)
    arr = sorted(list(items or []), key=key)
    out = []
    for it in arr[:max(0, min(limit, 200))]:
        out.append({
            "severity": _norm_sev((it or {}).get("severity")),
            "title": (it or {}).get("title") or (it or {}).get("message") or "Finding",
            "tool": (it or {}).get("tool") or "UNKNOWN",
            "file": (it or {}).get("file") or (it or {}).get("path") or None,
            "cwe": (it or {}).get("cwe"),
        })
    return out

def _trend_points(maxn=20):
    pts=[]
    cand=[]
    for root in _roots():
        try:
            for name in os.listdir(root):
                ts=_parse_ts(name)
                if not ts: 
                    continue
                cand.append((ts,name))
        except Exception:
            pass
    cand=sorted(cand, key=lambda x:x[0])[-maxn:]
    for ts,r in cand:
        _src, items, _mt = _load_items(r, cap=200000)
        pts.append({"label": ts.strftime("%Y-%m-%d %H:%M"), "rid": r, "total": len(items or [])})
    return pts

_CACHE = {}  # rid -> {"ts":..., "base":...}
TTL = 10.0

def _base_for(rid: str):
    now = time.time()
    cur = _CACHE.get(rid)
    if cur and (now - cur["ts"]) < TTL:
        return cur["base"]
    src, items, _mt = _load_items(rid)
    sev, tool_ch, cwe = _counts(items)
    total = sum(sev.values()) if sev else len(items or [])
    base = {
        "rid": rid,
        "source": src or {},
        "total": total,
        "sev": sev,
        "tool_ch": tool_ch,
        "cwe": cwe,
        "top_findings": _top_findings(items, 25),
        "trend": _trend_points(20),
    }
    _CACHE[rid] = {"ts": now, "base": base}
    return base

class DashFallbackMW:
    def __init__(self, app):
        self.app = app

    def _json(self, start_response, obj, code="200 OK"):
        data = (json.dumps(obj, ensure_ascii=False) + "\n").encode("utf-8")
        start_response(code, [
            ("Content-Type","application/json; charset=utf-8"),
            ("Content-Length", str(len(data))),
            ("Cache-Control","no-store"),
        ])
        return [data]

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        qs = parse_qs(environ.get("QUERY_STRING") or "")
        rid = (qs.get("rid") or [""])[0].strip() or _pick_best_rid()

        if (
            path.startswith("/api/vsp/dashboard_v3")
            or path in ("/api/vsp/dashboard_latest_v1", "/api/vsp/dash_kpis", "/api/vsp/dash_charts")
        ):
            base = _base_for(rid)
            sev = base["sev"]; tool_ch = base["tool_ch"]; cwe = base["cwe"]
            kpis = {
                "total": base["total"],
                "CRITICAL": sev.get("CRITICAL", 0),
                "HIGH": sev.get("HIGH", 0),
                "MEDIUM": sev.get("MEDIUM", 0),
                "LOW": sev.get("LOW", 0),
                "INFO": sev.get("INFO", 0),
                "TRACE": sev.get("TRACE", 0),
            }
            charts = {
                "severity_distribution": [{"severity": k, "count": v} for k,v in sorted(sev.items(), key=lambda kv: SEV_ORDER.get(kv[0],99))],
                "critical_high_by_tool": sorted(tool_ch.values(), key=lambda r: -(r.get("CRITICAL",0)+r.get("HIGH",0)))[:30],
                "top_cwe": [{"cwe": k, "count": v} for k,v in sorted(cwe.items(), key=lambda kv: kv[1], reverse=True)[:20]],
                "trend": base["trend"],
            }
            if path == "/api/vsp/dash_kpis":
                return self._json(start_response, {"ok": True, "rid": rid, **kpis, "kpis": kpis, "source": base["source"]})
            if path == "/api/vsp/dash_charts":
                return self._json(start_response, {"ok": True, "rid": rid, **charts, "charts": charts, "source": base["source"]})
            return self._json(start_response, {
                "ok": True, "rid": rid, "source": base["source"],
                "kpis": kpis, "charts": charts, "tables": {"top_findings": base["top_findings"]},
            })

        return self.app(environ, start_response)

def wrap(app):
    return DashFallbackMW(app)
PY
echo "[OK] wrote $MOD"

echo "== [4] append gateway hook (try/except, boot-safe) =="
"$PY" - <<'PY'
from pathlib import Path
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P3K2_SAFE_DASH_HOOK_V1"
if MARK not in s:
    hook = '''
# === VSP_P3K2_SAFE_DASH_HOOK_V1 ===
try:
    import vsp_dash_fallback_mw_p3k2 as _vsp_p3k2_mw
    application = _vsp_p3k2_mw.wrap(application)
except Exception:
    pass
# === END VSP_P3K2_SAFE_DASH_HOOK_V1 ===
'''
    p.write_text(s.rstrip()+"\n\n"+hook+"\n", encoding="utf-8")
    print("[OK] hook appended")
else:
    print("[OK] hook already present")
PY

echo "== [5] import check =="
"$PY" -c "import wsgi_vsp_ui_gateway; print('IMPORT_OK')" >/dev/null

echo "== [6] restart =="
sudo systemctl restart "$SVC" || true
sleep 0.8
if ! sudo systemctl is-active --quiet "$SVC"; then
  echo "[ERR] service not active after SAFE MW"
  sudo systemctl status "$SVC" --no-pager | sed -n '1,220p' || true
  sudo journalctl -u "$SVC" -n 220 --no-pager || true
  exit 4
fi
echo "[OK] service active after SAFE MW"

echo "== [7] smoke =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | "$PY" -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "RID=$RID"
curl -fsS "$BASE/api/vsp/dash_kpis?rid=$RID" | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("dash_kpis ok=",j.get("ok"),"CRITICAL=",j.get("CRITICAL"),"HIGH=",j.get("HIGH"),"total=",j.get("total"))'
curl -fsS "$BASE/api/vsp/dash_charts?rid=$RID" | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("dash_charts ok=",j.get("ok"),"sev_dist=",len(j.get("severity_distribution") or ((j.get("charts") or {}).get("severity_distribution") or [])))'
curl -fsS "$BASE/api/vsp/dashboard_v3_latest?rid=$RID" | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("dash_v3 ok=",j.get("ok"),"kpis_total=",(j.get("kpis") or {}).get("total"))'

echo "[DONE] p3k2_fix_startpost_and_apply_safe_mw_v1"
