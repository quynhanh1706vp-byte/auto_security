#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
JS="static/js/vsp_data_source_charts_v1.js"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
[ -f "$JS" ]  || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_ridlatestv2_${TS}"
cp -f "$JS"  "${JS}.bak_ridlatestv2_${TS}"
echo "[BACKUP] ${APP}.bak_ridlatestv2_${TS}"
echo "[BACKUP] ${JS}.bak_ridlatestv2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

APP = Path("vsp_demo_app.py")
s = APP.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_RID_LATEST_HEALTH_V2"
if MARK not in s:
    block = textwrap.dedent(r"""
    # ===================== VSP_P0_RID_LATEST_HEALTH_V2 =====================
    import os, json, re
    from pathlib import Path

    def _vsp_v2_candidate_roots():
        roots = []
        env = os.environ.get("VSP_RUN_ROOTS", "").strip()
        if env:
            for part in re.split(r'[:;,]', env):
                p = part.strip()
                if p:
                    roots.append(p)
        # keep your known roots
        roots += [
            "/home/test/Data/SECURITY-10-10-v4/out_ci",
            "/home/test/Data/SECURITY_BUNDLE/out",
            "/home/test/Data/SECURITY_BUNDLE/out_ci",
            "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        ]
        out=[]
        for r in roots:
            try:
                p = Path(r)
                if p.is_dir():
                    out.append(str(p))
            except Exception:
                pass
        # de-dup
        seen=set(); uniq=[]
        for r in out:
            if r not in seen:
                uniq.append(r); seen.add(r)
        return uniq

    def _vsp_v2_is_rid(name: str) -> bool:
        if not name: return False
        if name.startswith("RUN_"): return True
        if name.startswith("VSP_CI_RUN_"): return True
        if name.startswith("VSP_CI_"): return True
        if "RUN" in name and "_" in name: return True
        return False

    def _vsp_v2_pick_files(run_dir: Path):
        # return (gate_summary_rel, findings_rel) preferred
        cand_gate = [
            "run_gate_summary.json",
            "gate_root_" + run_dir.name + "/run_gate_summary.json",
            "gate_root_" + run_dir.name + "/run_gate.json",
            "run_gate.json",
        ]
        # findings often either root or under reports/ or under gate_root_*/
        cand_find = [
            "findings_unified.json",
            "reports/findings_unified.json",
            "reports/findings_unified_v1.json",
            "gate_root_" + run_dir.name + "/findings_unified.json",
            "gate_root_" + run_dir.name + "/reports/findings_unified.json",
        ]
        g = next((p for p in cand_gate if (run_dir/p).is_file()), None)
        f = next((p for p in cand_find if (run_dir/p).is_file()), None)
        return g, f

    def _vsp_v2_latest():
        roots = _vsp_v2_candidate_roots()
        best = None  # (score, mtime, rid, root, gate_rel, find_rel)
        for root in roots:
            rp = Path(root)
            try:
                for d in rp.iterdir():
                    if not d.is_dir(): 
                        continue
                    rid = d.name
                    if not _vsp_v2_is_rid(rid):
                        continue
                    try:
                        mtime = d.stat().st_mtime
                    except Exception:
                        continue
                    gate_rel, find_rel = _vsp_v2_pick_files(d)
                    score = 0
                    if gate_rel: score += 6
                    if find_rel: score += 10
                    if (d/"reports").is_dir(): score += 1
                    # prefer correctness first, then recency
                    key = (score, mtime, rid, root, gate_rel or "", find_rel or "")
                    if best is None or key > best:
                        best = key
            except Exception:
                continue

        if not best:
            return None

        score, mtime, rid, root, gate_rel, find_rel = best
        return {
            "rid": rid,
            "run_root": root,
            "mtime": mtime,
            "score": score,
            "gate_summary_rel": gate_rel or None,
            "findings_rel": find_rel or None,
            "roots_checked": roots,
        }

    @app.route("/api/vsp/rid_latest_gate_root_v2", methods=["GET"])
    def vsp_rid_latest_gate_root_v2():
        info = _vsp_v2_latest()
        if not info:
            return jsonify(ok=False, err="no run dir found", roots=_vsp_v2_candidate_roots()), 200
        # ok=true even if findings missing, but expose flags so UI knows why
        return jsonify(
            ok=True,
            rid=info["rid"],
            run_root=info["run_root"],
            score=info["score"],
            mtime=info["mtime"],
            has_gate_summary=bool(info["gate_summary_rel"]),
            has_findings=bool(info["findings_rel"]),
            gate_summary_path=info["gate_summary_rel"],
            findings_path=info["findings_rel"],
            roots_checked=info["roots_checked"],
        ), 200

    @app.route("/api/vsp/ui_health_v2", methods=["GET"])
    def vsp_ui_health_v2():
        rid = (request.args.get("rid") or "").strip()
        if not rid:
            latest = _vsp_v2_latest()
            return jsonify(ok=False, err="missing rid", latest=latest), 200

        run_dir = None
        for root in _vsp_v2_candidate_roots():
            p = Path(root)/rid
            if p.is_dir():
                run_dir = p
                break
        if not run_dir:
            latest = _vsp_v2_latest()
            return jsonify(ok=False, err="rid dir not found", rid=rid, latest=latest), 200

        gate_rel, find_rel = _vsp_v2_pick_files(run_dir)

        def _read_json(p: Path):
            try:
                return json.loads(p.read_text(encoding="utf-8", errors="replace"))
            except Exception:
                return None

        checks = {}
        checks["run_dir"] = str(run_dir)
        checks["gate_summary_rel"] = gate_rel
        checks["findings_rel"] = find_rel
        checks["gate_summary_exists"] = bool(gate_rel and (run_dir/gate_rel).is_file())
        checks["findings_exists"] = bool(find_rel and (run_dir/find_rel).is_file())
        checks["gate_summary_json_ok"] = bool(_read_json(run_dir/gate_rel)) if checks["gate_summary_exists"] else False
        checks["findings_json_ok"] = bool(_read_json(run_dir/find_rel)) if checks["findings_exists"] else False

        ok = checks["gate_summary_exists"] and checks["findings_exists"] and checks["gate_summary_json_ok"] and checks["findings_json_ok"]
        return jsonify(ok=ok, rid=rid, checks=checks), 200
    # ===================== /VSP_P0_RID_LATEST_HEALTH_V2 =====================
    """).strip() + "\n"

    s = s.rstrip() + "\n\n" + block + "\n"
    APP.write_text(s, encoding="utf-8")
    py_compile.compile(str(APP), doraise=True)
    print("[OK] injected", MARK)
else:
    print("[OK] already has", MARK)
PY

echo "[INFO] Restart service: $SVC"
systemctl restart "$SVC" 2>/dev/null || true

python3 - <<'PY'
from pathlib import Path
import re

JS = Path("static/js/vsp_data_source_charts_v1.js")
s = JS.read_text(encoding="utf-8", errors="replace")

OLD = "VSP_P0_JS_AUTOREFRESH_GREENBADGE_V1"
NEW = "VSP_P0_JS_AUTOREFRESH_GREENBADGE_V2"

# remove old injected block if exists (safe)
if OLD in s:
    # delete from comment start to end of IIFE
    s = re.sub(r"/\*\s*VSP_P0_JS_AUTOREFRESH_GREENBADGE_V1.*?\n\}\)\(\);\s*\n", "", s, flags=re.S)

if NEW not in s:
    addon = r"""
/* VSP_P0_JS_AUTOREFRESH_GREENBADGE_V2 - auto poll RID latest (v2) + UI OK badge */
(function(){
  const POLL_MS = 5000;

  function ensureBadge(){
    let el = document.getElementById("vsp-ui-ok-badge");
    if(el) return el;
    el = document.createElement("div");
    el.id = "vsp-ui-ok-badge";
    el.style.cssText = [
      "position:fixed","right:14px","bottom:14px","z-index:99999",
      "padding:10px 12px","border-radius:12px","font:600 12px/1.2 system-ui,Segoe UI,Roboto,Arial",
      "background:#1b2333","color:#d6e2ff","border:1px solid rgba(255,255,255,.12)",
      "box-shadow:0 10px 30px rgba(0,0,0,.35)"
    ].join(";");
    el.textContent = "UI OK: …";
    document.body.appendChild(el);
    return el;
  }

  async function fetchJSON(url){
    try{
      const r = await fetch(url, {cache:"no-store"});
      const ct = (r.headers.get("content-type")||"").toLowerCase();
      if(!ct.includes("application/json")){
        return {ok:false, err:"non-json", status:r.status, url};
      }
      const j = await r.json();
      if(typeof j !== "object" || j === null) return {ok:false, err:"bad-json", status:r.status, url};
      j._http_status = r.status;
      return j;
    }catch(e){
      return {ok:false, err:String(e), url};
    }
  }

  function setBadge(ok, rid, detail){
    const el = ensureBadge();
    if(ok){
      el.textContent = `UI OK: GREEN • ${rid||"-"}`;
      el.style.borderColor = "rgba(65,255,164,.35)";
      el.style.background = "rgba(10,28,18,.92)";
      el.style.color = "#bfffe0";
    }else{
      el.textContent = `UI OK: RED • ${rid||"-"}`;
      el.style.borderColor = "rgba(255,96,96,.45)";
      el.style.background = "rgba(35,10,12,.92)";
      el.style.color = "#ffd4d4";
    }
    if(detail && detail.err){ el.title = detail.err; }
    else if(detail && detail.checks && (!detail.ok)){
      el.title = JSON.stringify(detail.checks).slice(0,600);
    } else { el.title = ""; }
  }

  let lastRID = null;
  async function tick(){
    const latest = await fetchJSON("/api/vsp/rid_latest_gate_root_v2");
    const rid = (latest && latest.ok && latest.rid) ? latest.rid : null;

    if(rid && rid !== lastRID){
      lastRID = rid;
      window.VSP_CURRENT_RID = rid;
      console.log("[AutoRID-V2] new RID =>", rid, "has_findings=", latest.has_findings, "has_gate=", latest.has_gate_summary);
      window.dispatchEvent(new CustomEvent("vsp:rid-changed", {detail:{rid, latest}}));

      // safest commercial behavior: if new RID arrives, refresh current page data
      if(typeof window.VSP_reloadAll === "function"){
        try{ window.VSP_reloadAll(); }catch(e){}
      }
      // if no reload hook, do a soft refresh after a short delay
      if(typeof window.VSP_reloadAll !== "function"){
        setTimeout(()=>{ try{ location.reload(); }catch(e){} }, 800);
      }
    }

    const health = await fetchJSON("/api/vsp/ui_health_v2?rid=" + encodeURIComponent(lastRID||""));
    setBadge(!!(health && health.ok), lastRID, health);
  }

  setTimeout(()=>{ ensureBadge(); tick(); setInterval(tick, POLL_MS); }, 1200);
})();
""".strip()
    s = s.rstrip() + "\n\n" + addon + "\n"

JS.write_text(s, encoding="utf-8")
print("[OK] JS injected V2 badge into", JS)
PY

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== smoke v2 endpoints =="
curl -sS "$BASE/api/vsp/rid_latest_gate_root_v2" | head -c 350; echo
RID="$(curl -sS "$BASE/api/vsp/rid_latest_gate_root_v2" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("rid",""))')"
echo "RID=$RID"
curl -sS "$BASE/api/vsp/ui_health_v2?rid=$RID" | head -c 350; echo
