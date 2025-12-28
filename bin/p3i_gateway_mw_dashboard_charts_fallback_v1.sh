#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3)"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_p3i_${TS}"
echo "[BACKUP] ${W}.bak_p3i_${TS}"

"$PY" - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P3I_DASHBOARD_CHARTS_FALLBACK_V1"

# remove old block if any (idempotent)
s = re.sub(r'(?s)\n?# === '+re.escape(MARK)+r' ===.*?# === END '+re.escape(MARK)+r' ===\n?', "\n", s)

mw = r'''
# === __MARK__ ===
import os, json, re, csv
from datetime import datetime
from urllib.parse import parse_qs

def _p3i_parse_ts(name: str):
    m = re.search(r'(\d{8})_(\d{6})', name or "")
    if not m:
        return None
    try:
        return datetime.strptime(m.group(1)+m.group(2), "%Y%m%d%H%M%S")
    except Exception:
        return None

def _p3i_roots():
    roots = [
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
    ]
    return [r for r in roots if os.path.isdir(r)]

def _p3i_find_rid_dir(rid: str):
    rid=(rid or "").strip()
    if not rid: return None
    for root in _p3i_roots():
        d=os.path.join(root, rid)
        if os.path.isdir(d): return d
    return None

def _p3i_candidates(rid_dir: str):
    return [
        os.path.join(rid_dir, "reports/findings_unified.json"),
        os.path.join(rid_dir, "report/findings_unified.json"),
        os.path.join(rid_dir, "findings_unified.json"),
        os.path.join(rid_dir, "reports/findings_unified.csv"),
        os.path.join(rid_dir, "report/findings_unified.csv"),
        os.path.join(rid_dir, "findings_unified.csv"),
    ]

def _p3i_json_load_items(fp: str):
    with open(fp, "r", encoding="utf-8", errors="replace") as f:
        j=json.load(f)
    items=[]
    for k in ("findings","items","results"):
        v=j.get(k)
        if isinstance(v, list):
            items=v; break
    return j, items

def _p3i_csv_load_items(fp: str, cap=200000):
    items=[]
    with open(fp, "r", encoding="utf-8", errors="replace", newline="") as f:
        rd=csv.DictReader(f)
        for i,row in enumerate(rd):
            if i>=cap: break
            items.append({
                "tool": row.get("tool") or row.get("Tool") or "CSV",
                "severity": (row.get("severity") or row.get("Severity") or "INFO").upper(),
                "title": row.get("title") or row.get("Title") or row.get("message") or "Finding",
                "cwe": row.get("cwe") or row.get("CWE"),
                "file": row.get("file") or row.get("File") or row.get("path"),
            })
    return {"csv": True}, items

def _p3i_load_items_for_rid(rid: str):
    rid_dir=_p3i_find_rid_dir(rid)
    if not rid_dir: return None, []
    for fp in _p3i_candidates(rid_dir):
        if not os.path.isfile(fp): continue
        try:
            if os.path.getsize(fp) < 30: continue
        except Exception:
            continue
        try:
            if fp.endswith(".json"):
                meta, items = _p3i_json_load_items(fp)
                if items:
                    return {"from": os.path.relpath(fp, rid_dir), "meta": meta}, items
                # if json has "total">0 but items missing, still accept
                t = meta.get("total")
                if isinstance(t, int) and t > 0:
                    return {"from": os.path.relpath(fp, rid_dir), "meta": meta}, items
            if fp.endswith(".csv"):
                meta, items = _p3i_csv_load_items(fp)
                if items:
                    return {"from": os.path.relpath(fp, rid_dir), "meta": meta}, items
        except Exception:
            continue
    return None, []

def _p3i_is_usable_dir(d: str) -> bool:
    for rel in ("reports/findings_unified.json","report/findings_unified.json","findings_unified.json",
                "reports/findings_unified.csv","report/findings_unified.csv","findings_unified.csv"):
        fp=os.path.join(d, rel)
        if not os.path.isfile(fp): continue
        try:
            if fp.endswith(".json"):
                meta, items = _p3i_json_load_items(fp)
                if (isinstance(meta.get("total"), int) and meta["total"]>0) or (isinstance(items,list) and len(items)>0):
                    return True
            if fp.endswith(".csv"):
                with open(fp,"r",encoding="utf-8",errors="replace") as f:
                    a=f.readline(); b=f.readline()
                if (a and b and b.strip()): return True
        except Exception:
            pass
    return False

def _p3i_pick_best_rid():
    best=None
    for root in _p3i_roots():
        try:
            for name in os.listdir(root):
                if name.startswith("."): continue
                d=os.path.join(root, name)
                if not os.path.isdir(d): continue
                if not _p3i_is_usable_dir(d): continue
                ts=_p3i_parse_ts(name) or datetime.fromtimestamp(0)
                try: mt=os.path.getmtime(d)
                except Exception: mt=0
                key=(ts, mt)
                if best is None or key>best[0]:
                    best=(key, name)
        except Exception:
            pass
    return best[1] if best else ""

_SEV_ORDER={"CRITICAL":0,"HIGH":1,"MEDIUM":2,"MEDIUM+":2,"LOW":3,"INFO":4,"TRACE":5}
def _sev_key(it):
    s=str((it or {}).get("severity","")).upper()
    return _SEV_ORDER.get(s, 99)

def _counts(items):
    sev={}
    tool={}
    cwe={}
    for it in items or []:
        s=str((it or {}).get("severity","INFO")).upper() or "INFO"
        sev[s]=sev.get(s,0)+1
        t=str((it or {}).get("tool","UNKNOWN"))
        tool[t]=tool.get(t,0)+1
        cw=(it or {}).get("cwe")
        if cw is None: continue
        cw=str(cw).strip()
        if not cw: continue
        if not cw.upper().startswith("CWE-") and cw.isdigit():
            cw="CWE-"+cw
        cwe[cw]=cwe.get(cw,0)+1
    return sev, tool, cwe

class _P3IChartsFallbackMW:
    def __init__(self, app): self.app=app
    def _json(self, start_response, obj):
        data=(json.dumps(obj, ensure_ascii=False)+"\n").encode("utf-8")
        start_response("200 OK", [("Content-Type","application/json; charset=utf-8"),
                                 ("Content-Length", str(len(data))),
                                 ("Cache-Control","no-store")])
        return [data]

    def __call__(self, environ, start_response):
        path=(environ.get("PATH_INFO") or "")
        qs=parse_qs(environ.get("QUERY_STRING") or "")
        rid=(qs.get("rid") or [""])[0].strip() or _p3i_pick_best_rid()

        # 1) trend (minimal but ok): returns points list across last N usable dirs
        if path in ("/api/vsp/trend_v1", "/api/vsp/trend"):
            pts=[]
            # scan last N usable rids
            cand=[]
            for root in _p3i_roots():
                try:
                    for name in os.listdir(root):
                        d=os.path.join(root,name)
                        if not os.path.isdir(d): continue
                        if not _p3i_is_usable_dir(d): continue
                        ts=_p3i_parse_ts(name) or datetime.fromtimestamp(0)
                        cand.append((ts, name))
                except Exception:
                    pass
            cand=sorted(cand, key=lambda x:x[0])[-20:]
            for ts,name in cand:
                src, items = _p3i_load_items_for_rid(name)
                total = None
                if src and isinstance((src.get("meta") or {}).get("total"), int):
                    total = (src.get("meta") or {}).get("total")
                if total is None:
                    total = len(items or [])
                pts.append({"label": ts.strftime("%Y-%m-%d %H:%M"), "rid": name, "total": int(total or 0)})
            return self._json(start_response, {"ok": True, "points": pts})

        # 2) topcwe
        if path in ("/api/vsp/topcwe_v1", "/api/vsp/top_cwe_v1", "/api/vsp/topcwe"):
            src, items = _p3i_load_items_for_rid(rid)
            if not items:
                return self._json(start_response, {"ok": False, "rid": rid, "items": [], "err":"no findings"})
            _, _, cwe = _counts(items)
            top = sorted(cwe.items(), key=lambda kv: kv[1], reverse=True)[:20]
            out=[{"cwe":k,"count":v} for k,v in top]
            return self._json(start_response, {"ok": True, "rid": rid, "items": out, "from": (src or {}).get("from")})

        # 3) severity by tool (critical/high focus)
        if path in ("/api/vsp/sev_by_tool_v1", "/api/vsp/critical_high_by_tool_v1", "/api/vsp/by_tool_v1"):
            src, items = _p3i_load_items_for_rid(rid)
            if not items:
                return self._json(start_response, {"ok": False, "rid": rid, "items": [], "err":"no findings"})
            by={}
            for it in items:
                t=str((it or {}).get("tool","UNKNOWN"))
                s=str((it or {}).get("severity","INFO")).upper()
                if t not in by: by[t]={"tool":t,"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0,"INFO":0,"TRACE":0}
                if s not in by[t]: by[t][s]=0
                by[t][s]+=1
            arr=list(by.values())
            arr=sorted(arr, key=lambda x: (-(x.get("CRITICAL",0)+x.get("HIGH",0)), x.get("tool","")))
            return self._json(start_response, {"ok": True, "rid": rid, "items": arr[:30], "from": (src or {}).get("from")})

        return self.app(environ, start_response)

try:
    application = _P3IChartsFallbackMW(application)
except Exception:
    pass
# === END __MARK__ ===
'''.replace("__MARK__", MARK).lstrip("\n")

s = s.rstrip() + "\n\n" + mw + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] installed", MARK)
PY

"$PY" -c "import wsgi_vsp_ui_gateway; print('IMPORT_OK')" >/dev/null

sudo systemctl restart "${SVC}"
sleep 0.6
sudo systemctl is-active --quiet "${SVC}" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 3; }

echo "== [SMOKE] trend/topcwe/bytool =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | "$PY" -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
curl -fsS "$BASE/api/vsp/trend_v1" | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("trend ok=",j.get("ok"),"points=",len(j.get("points") or []))'
curl -fsS "$BASE/api/vsp/topcwe_v1?rid=$RID" | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("topcwe ok=",j.get("ok"),"items=",len(j.get("items") or []))'
curl -fsS "$BASE/api/vsp/sev_by_tool_v1?rid=$RID" | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("bytool ok=",j.get("ok"),"items=",len(j.get("items") or []))'

echo "[DONE] p3i_gateway_mw_dashboard_charts_fallback_v1"
