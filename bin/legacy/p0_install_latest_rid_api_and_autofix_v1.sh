#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl
command -v node >/dev/null 2>&1 || true

WSGI="wsgi_vsp_ui_gateway.py"
RIDJS="static/js/vsp_rid_autofix_v1.js"
SVC="vsp-ui-8910.service"
BASE="http://127.0.0.1:8910"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }
[ -f "$RIDJS" ] || { echo "[ERR] missing $RIDJS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_latest_rid_api_${TS}"
cp -f "$RIDJS" "${RIDJS}.bak_autofix_${TS}"
echo "[BACKUP] ${WSGI}.bak_latest_rid_api_${TS}"
echo "[BACKUP] ${RIDJS}.bak_autofix_${TS}"

echo "== [1/3] Install /api/vsp/latest_rid into WSGI (append-safe) =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_LATEST_RID_ENDPOINT_V1"
if marker in s:
    print("[OK] latest_rid endpoint already present")
else:
    patch = r'''
# ===================== VSP_P0_LATEST_RID_ENDPOINT_V1 =====================
try:
    import os, time, json
    from pathlib import Path
    from flask import jsonify, request

    _VSP_APP = globals().get("application") or globals().get("app")
    if _VSP_APP is not None:
        @_VSP_APP.get("/api/vsp/latest_rid")
        def vsp_latest_rid__p0_v1():
            # Resolve newest RID by scanning known run roots; only accept dirs that contain gate artifacts
            roots = [
                Path("/home/test/Data/SECURITY_BUNDLE/out"),
                Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
                Path("/home/test/Data/SECURITY_BUNDLE/ui/out"),
                Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
            ]
            roots = [r for r in roots if r.exists() and r.is_dir()]

            must_files = [
                "run_gate_summary.json",
                "run_gate.json",
                "findings_unified.json",
            ]

            cands = []
            for root in roots:
                try:
                    for d in root.iterdir():
                        if not d.is_dir(): 
                            continue
                        rid = d.name
                        # heuristic: prefer RUN_* / VSP_* but do not block other ids
                        score = 0
                        if rid.startswith("VSP_"): score += 3
                        if rid.startswith("RUN_"): score += 2

                        # must have at least one gate file
                        have = []
                        for f in must_files:
                            fp = d / f
                            if fp.exists() and fp.is_file() and fp.stat().st_size > 20:
                                have.append(f)
                        if not have:
                            continue

                        mtime = d.stat().st_mtime
                        cands.append((mtime, score, rid, str(d), have))
                except Exception:
                    continue

            if not cands:
                return jsonify({"ok": False, "err": "no run dir with gate artifacts found"}), 404

            # newest first; tie-breaker by score
            cands.sort(key=lambda x: (x[0], x[1]), reverse=True)
            mtime, score, rid, path, have = cands[0]

            return jsonify({
                "ok": True,
                "rid": rid,
                "path": path,
                "have": have,
                "mtime": mtime,
                "mtime_iso": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(mtime)),
                "roots_checked": [str(r) for r in roots],
            })
except Exception:
    pass
# ===================== /VSP_P0_LATEST_RID_ENDPOINT_V1 =====================
'''
    # append with a leading newline to avoid gluing to last line
    s = s.rstrip() + "\n" + patch.lstrip("\n")
    p.write_text(s, encoding="utf-8")
    print("[OK] appended latest_rid endpoint block")
PY

echo "== py_compile WSGI =="
python3 -m py_compile "$WSGI" && echo "[OK] py_compile OK"

echo
echo "== [2/3] Replace RID autofix JS with commercial-safe version (event + localStorage) =="
python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_rid_autofix_v1.js")

js = r"""/* VSP_P0_RID_AUTOFIX_V2_COMMERCIAL */
(()=> {
  try{
    if (window.__vsp_p0_rid_autofix_v2) return;
    window.__vsp_p0_rid_autofix_v2 = true;

    const BASE = "";
    const API_LATEST = (BASE + "/api/vsp/latest_rid");
    const API_RUNS = (BASE + "/api/vsp/runs?limit=20");

    const LS_KEYS = [
      "vsp_selected_rid",
      "vsp_rid",
      "VSP_RID",
      "vsp5_rid",
      "vsp_gate_story_rid"
    ];

    const timeoutFetch = async (url, ms=2500) => {
      const ctrl = new AbortController();
      const t = setTimeout(()=>ctrl.abort(), ms);
      try{
        const r = await fetch(url, {signal: ctrl.signal, credentials: "same-origin"});
        return r;
      } finally {
        clearTimeout(t);
      }
    };

    const fetchJson = async (url, ms=2500) => {
      const r = await timeoutFetch(url, ms);
      if (!r || !r.ok) throw new Error("http_"+(r? r.status : "0"));
      return await r.json();
    };

    const pickRidFromRuns = (j) => {
      // accept many shapes: {runs:[{rid}]} | [{rid}] | {items:[...]} | {data:[...]}
      const arr =
        (Array.isArray(j) ? j :
         (Array.isArray(j?.runs) ? j.runs :
          (Array.isArray(j?.items) ? j.items :
           (Array.isArray(j?.data) ? j.data : null))));
      if (!arr || !arr.length) return "";
      const first = arr[0];
      if (typeof first === "string") return first;
      return String(first?.rid || first?.run_id || first?.id || "");
    };

    const setRid = (rid) => {
      if (!rid) return false;
      try{ window.__VSP_SELECTED_RID = rid; }catch(e){}

      // keep previous (for debugging)
      try{
        const prev = localStorage.getItem("vsp_selected_rid") || "";
        if (prev && prev !== rid) localStorage.setItem("vsp_prev_rid", prev);
      }catch(e){}

      for (const k of LS_KEYS){
        try{ localStorage.setItem(k, rid); }catch(e){}
      }

      // broadcast for any panels
      try{ window.dispatchEvent(new CustomEvent("vsp:rid", {detail:{rid}})); }catch(e){}
      try{ window.dispatchEvent(new CustomEvent("VSP_RID_CHANGED", {detail:{rid}})); }catch(e){}
      try{ window.dispatchEvent(new Event("storage")); }catch(e){}

      // optional hooks if available
      try{
        if (typeof window.vspSetRID === "function") window.vspSetRID(rid);
        if (window.__vsp_gate_story && typeof window.__vsp_gate_story.setRID === "function") window.__vsp_gate_story.setRID(rid);
        if (typeof window.__vsp_gate_story_set_rid === "function") window.__vsp_gate_story_set_rid(rid);
      }catch(e){}

      return true;
    };

    (async ()=> {
      // 1) prefer server resolver
      let rid = "";
      try{
        const j = await fetchJson(API_LATEST, 2000);
        if (j && j.ok && j.rid) rid = String(j.rid);
      }catch(e){}

      // 2) fallback to runs list
      if (!rid){
        try{
          const j = await fetchJson(API_RUNS, 2200);
          rid = pickRidFromRuns(j);
        }catch(e){}
      }

      if (!rid) return;

      // if already set the same, do nothing
      try{
        const cur = localStorage.getItem("vsp_selected_rid") || "";
        if (cur === rid) return;
      }catch(e){}

      setRid(rid);
    })();

  }catch(e){}
})();
"""
p.write_text(js, encoding="utf-8")
print("[OK] wrote commercial rid autofix v2")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$RIDJS" && echo "[OK] node --check rid js OK"
fi

echo
echo "== [3/3] restart + verify =="
systemctl restart "$SVC" || true
systemctl --no-pager --full status "$SVC" | sed -n '1,18p' || true

echo "== verify latest_rid endpoint =="
curl -fsS "$BASE/api/vsp/latest_rid" | head -c 400; echo
echo "== verify /vsp5 =="
curl -fsS -I "$BASE/vsp5" | head -n 8
