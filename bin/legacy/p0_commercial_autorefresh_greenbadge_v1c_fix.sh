#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_autorefresh_green_fix_${TS}"
echo "[BACKUP] ${APP}.bak_autorefresh_green_fix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

MARK = "VSP_P0_COMMERCIAL_AUTOREFRESH_GREENBADGE_V1"
app = Path("vsp_demo_app.py")
s = app.read_text(encoding="utf-8", errors="replace")

# ---------- helper: inject alias decorators above run_file_allow ----------
def inject_alias_decorators(src: str) -> str:
    if "Alias common mistaken endpoints to run_file_allow" in src:
        return src

    m = re.search(r'(?m)^\s*def\s+run_file_allow\s*\(.*\)\s*:\s*$', src)
    if not m:
        return src

    start = m.start()
    dec_start = start
    lines = src[:start].splitlines(True)
    i = len(lines) - 1
    while i >= 0 and lines[i].lstrip().startswith("@"):
        dec_start -= len(lines[i])
        i -= 1

    alias_decorators = textwrap.dedent(r"""
    @app.route("/api/vsp/run_file_allow", methods=["GET"])
    @app.route("/api/vsp/run_file_allow_v1", methods=["GET"])
    @app.route("/api/vsp/run_file_allow_v2", methods=["GET"])
    @app.route("/api/vsp/run_file_allow_v3", methods=["GET"])
    @app.route("/api/vsp/run_file_allow_v4", methods=["GET"])
    @app.route("/api/run_file_allow", methods=["GET"])
    @app.route("/api/run_file_allow_v1", methods=["GET"])
    @app.route("/api/run_file_allow_v2", methods=["GET"])
    @app.route("/api/run_file_allow_v3", methods=["GET"])
    @app.route("/api/run_file_allow_v4", methods=["GET"])
    @app.route("/api/vsp/run_file_allow/", methods=["GET"])
    @app.route("/api/vsp/run_file_allow_v3/", methods=["GET"])
    """).rstrip() + "\n"

    return src[:dec_start] + alias_decorators + src[dec_start:]


# ---------- helper: inject endpoints ----------
def inject_endpoints(src: str) -> str:
    if (MARK + "_ENDPOINTS") in src:
        return src

    addon = textwrap.dedent(rf"""
    # ===================== {MARK}_ENDPOINTS =====================
    import os, json
    from pathlib import Path

    def _vsp_candidate_roots():
        roots = []
        env = os.environ.get("VSP_RUN_ROOTS", "").strip()
        if env:
            for part in re.split(r'[:;,]', env):
                p = part.strip()
                if p:
                    roots.append(p)
        roots += [
            "/home/test/Data/SECURITY_BUNDLE/out",
            "/home/test/Data/SECURITY_BUNDLE/out_ci",
            "/home/test/Data/SECURITY-10-10-v4/out_ci",
            "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        ]
        out=[]
        for r in roots:
            try:
                if Path(r).is_dir():
                    out.append(str(Path(r)))
            except Exception:
                pass
        seen=set(); uniq=[]
        for r in out:
            if r not in seen:
                uniq.append(r); seen.add(r)
        return uniq

    def _vsp_is_rid_dirname(name: str) -> bool:
        if not name:
            return False
        if name.startswith("RUN_"):
            return True
        if name.startswith("VSP_CI_RUN_"):
            return True
        if name.startswith("VSP_CI_"):
            return True
        if "RUN" in name and "_" in name:
            return True
        return False

    def _vsp_pick_latest_rid():
        roots = _vsp_candidate_roots()
        best = None  # (mtime, score, rid, root)
        for root in roots:
            rp = Path(root)
            try:
                for d in rp.iterdir():
                    if not d.is_dir():
                        continue
                    rid = d.name
                    if not _vsp_is_rid_dirname(rid):
                        continue
                    try:
                        mtime = d.stat().st_mtime
                    except Exception:
                        continue
                    score = 0
                    if (d/"run_gate_summary.json").is_file(): score += 4
                    if (d/"findings_unified.json").is_file(): score += 3
                    if (d/"reports").is_dir(): score += 1
                    key = (mtime, score, rid, root)
                    if best is None or key > best:
                        best = key
            except Exception:
                continue
        if not best:
            return None
        mtime, score, rid, root = best
        return {{"rid": rid, "root": root, "mtime": mtime, "score": score, "roots_checked": roots}}

    def _vsp_find_rid_dir(rid: str):
        if not rid:
            return None
        for root in _vsp_candidate_roots():
            p = Path(root)/rid
            if p.is_dir():
                return p
        return None

    @app.route("/api/vsp/rid_latest_gate_root", methods=["GET"])
    def vsp_rid_latest_gate_root():
        info = _vsp_pick_latest_rid()
        if not info:
            return jsonify(ok=False, err="no run dir found", roots=_vsp_candidate_roots()), 200
        return jsonify(ok=True, rid=info["rid"], run_root=info["root"],
                       mtime=info["mtime"], score=info["score"],
                       roots_checked=info["roots_checked"]), 200

    @app.route("/api/vsp/ui_health_v1", methods=["GET"])
    def vsp_ui_health_v1():
        rid = (request.args.get("rid") or "").strip()
        if not rid:
            latest = _vsp_pick_latest_rid()
            return jsonify(ok=False, err="missing rid", latest=latest), 200

        d = _vsp_find_rid_dir(rid)
        if not d:
            latest = _vsp_pick_latest_rid()
            return jsonify(ok=False, err="rid dir not found", rid=rid, latest=latest), 200

        checks = {{}}
        def _read_json(p: Path):
            try:
                return json.loads(p.read_text(encoding="utf-8", errors="replace"))
            except Exception:
                return None

        p_gate = d/"run_gate_summary.json"
        p_find = d/"findings_unified.json"

        checks["run_gate_summary_exists"] = p_gate.is_file()
        checks["findings_unified_exists"] = p_find.is_file()
        checks["run_gate_summary_json_ok"] = bool(_read_json(p_gate)) if p_gate.is_file() else False
        j_find = _read_json(p_find) if p_find.is_file() else None
        checks["findings_unified_json_ok"] = bool(j_find)

        ok = all([
            checks["run_gate_summary_exists"],
            checks["findings_unified_exists"],
            checks["run_gate_summary_json_ok"],
            checks["findings_unified_json_ok"],
        ])
        return jsonify(ok=ok, rid=rid, run_dir=str(d), checks=checks), 200

    @app.after_request
    def _vsp_after_request_soft404(resp):
        try:
            path = request.path or ""
        except Exception:
            return resp
        if getattr(resp, "status_code", 0) != 404:
            return resp
        if path.startswith("/api/vsp/run_file_allow") or path.startswith("/api/run_file_allow") or path.startswith("/api/vsp/rid_latest_gate_root") or path.startswith("/api/vsp/ui_health_v1"):
            try:
                return jsonify(ok=False, err="not found (soft404)", path=path), 200
            except Exception:
                return resp
        return resp
    # ===================== /{MARK}_ENDPOINTS =====================
    """).strip() + "\n"

    return src.rstrip() + "\n\n" + addon


# Apply patches (idempotent)
s2 = s
s2 = inject_alias_decorators(s2)
s2 = inject_endpoints(s2)

if s2 != s:
    app.write_text(s2, encoding="utf-8")
    py_compile.compile(str(app), doraise=True)
    print("[OK] patched vsp_demo_app.py markers:", MARK)
else:
    print("[OK] vsp_demo_app.py already patched (no change)")
PY

echo "[INFO] Restart service: $SVC"
systemctl restart "$SVC" 2>/dev/null || true

python3 - <<'PY'
from pathlib import Path
import re, textwrap, time

MARK = "VSP_P0_JS_AUTOREFRESH_GREENBADGE_V1"
tpl_root = Path("templates")
js_candidates = []

if tpl_root.is_dir():
    for html in tpl_root.rglob("*.html"):
        t = html.read_text(encoding="utf-8", errors="replace")
        for m in re.finditer(r'src=["\'](/static/js/[^"\']+\.js)["\']', t):
            js_candidates.append(m.group(1))

prio = [
    "/static/js/vsp_bundle_commercial_v2.js",
    "/static/js/vsp_bundle_commercial_v1.js",
    "/static/js/vsp_dash_only_v1.js",
    "/static/js/vsp_dashboard_kpi_force_any_v1.js",
]
picked = None
for p in prio:
    if p in js_candidates:
        picked = p; break
if not picked and js_candidates:
    picked = js_candidates[0]
if not picked:
    for fb in prio:
        if Path(fb.lstrip("/")).is_file():
            picked = fb; break

if not picked:
    print("[WARN] cannot find dashboard JS to patch; skipped")
    raise SystemExit(0)

jsp = Path(picked.lstrip("/"))
if not jsp.is_file():
    print("[WARN] detected JS not found on disk:", jsp)
    raise SystemExit(0)

s = jsp.read_text(encoding="utf-8", errors="replace")
if MARK in s:
    print("[OK] JS already patched:", jsp)
    raise SystemExit(0)

# IMPORTANT: no .format() here (JS has ${...} braces). Use replace only.
addon = r"""
/* __MARK__ - auto poll RID latest + UI OK badge */
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
    if(detail && detail.err){ el.title = detail.err; } else { el.title = ""; }
  }

  let lastRID = null;
  async function tick(){
    const latest = await fetchJSON("/api/vsp/rid_latest_gate_root");
    const rid = (latest && latest.ok && latest.rid) ? latest.rid : null;

    if(rid && rid !== lastRID){
      lastRID = rid;
      window.VSP_CURRENT_RID = rid;
      console.log("[AutoRID] new RID =>", rid);
      window.dispatchEvent(new CustomEvent("vsp:rid-changed", {detail:{rid}}));
      if(typeof window.VSP_reloadAll === "function"){
        try{ window.VSP_reloadAll(); }catch(e){}
      }
    }

    const health = await fetchJSON("/api/vsp/ui_health_v1?rid=" + encodeURIComponent(lastRID||""));
    setBadge(!!(health && health.ok), lastRID, health);
  }

  setTimeout(()=>{ ensureBadge(); tick(); setInterval(tick, POLL_MS); }, 1200);
})();
""".strip().replace("__MARK__", MARK)

bak = jsp.with_suffix(jsp.suffix + ".bak_greenbadge_fix_" + time.strftime("%Y%m%d_%H%M%S"))
bak.write_text(s, encoding="utf-8")
jsp.write_text(s.rstrip() + "\n\n" + addon + "\n", encoding="utf-8")
print("[BACKUP]", bak)
print("[OK] patched JS:", jsp)
PY

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== smoke /rid_latest_gate_root =="
curl -sS "$BASE/api/vsp/rid_latest_gate_root" | head -c 260; echo
