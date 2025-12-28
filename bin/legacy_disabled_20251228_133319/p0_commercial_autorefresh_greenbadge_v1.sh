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
cp -f "$APP" "${APP}.bak_autorefresh_green_${TS}"
echo "[BACKUP] ${APP}.bak_autorefresh_green_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

app = Path("vsp_demo_app.py")
s = app.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_COMMERCIAL_AUTOREFRESH_GREENBADGE_V1"
if MARK not in s:
    # 1) Alias run_file_allow variants: add extra @app.route decorators above def run_file_allow(...)
    # Try find the function definition line
    m = re.search(r'(?m)^(?P<indent>\s*)def\s+run_file_allow\s*\(\s*\)\s*:\s*$', s)
    if not m:
        # sometimes signature has args
        m = re.search(r'(?m)^(?P<indent>\s*)def\s+run_file_allow\s*\(.*\)\s*:\s*$', s)
    if m:
        start = m.start()
        # Find decorator block just above it (consecutive @ lines)
        dec_start = start
        lines = s[:start].splitlines(True)
        i = len(lines) - 1
        while i >= 0 and lines[i].lstrip().startswith("@"):
            dec_start -= len(lines[i])
            i -= 1

        extra_routes = textwrap.dedent(r"""
        # ===================== {MARK} =====================
        # Alias common mistaken endpoints to run_file_allow (commercial harden)
        try:
            _VSP_APP = app  # noqa
        except Exception:
            _VSP_APP = None

        # (Decorators are injected above run_file_allow below)
        # ===================== /{MARK} =====================
        """).format(MARK=MARK)

        # Inject marker block somewhere safe near top (after imports)
        if extra_routes.strip() not in s:
            # insert after last import block
            ins_at = 0
            imp_iter = list(re.finditer(r'(?m)^(from\s+\S+\s+import\s+.+|import\s+\S+.*)\s*$', s))
            if imp_iter:
                ins_at = imp_iter[-1].end()
            s = s[:ins_at] + "\n" + extra_routes + "\n" + s[ins_at:]

        # Now inject decorators
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

        s = s[:dec_start] + alias_decorators + s[dec_start:]
    else:
        # If we cannot locate run_file_allow, we still proceed adding new endpoints below
        pass

    # 2) Add rid_latest_gate_root + ui_health_v1 endpoints at end-of-file (idempotent)
    addon = textwrap.dedent(r"""
    # ===================== {MARK}_ENDPOINTS =====================
    import os, json, time
    from pathlib import Path

    def _vsp_candidate_roots():
        roots = []
        env = os.environ.get("VSP_RUN_ROOTS", "").strip()
        if env:
            for part in re.split(r'[:;,]', env):
                p = part.strip()
                if p:
                    roots.append(p)
        # sensible defaults (safe if missing)
        roots += [
            "/home/test/Data/SECURITY_BUNDLE/out",
            "/home/test/Data/SECURITY_BUNDLE/out_ci",
            "/home/test/Data/SECURITY-10-10-v4/out_ci",
            "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        ]
        out = []
        for r in roots:
            try:
                if Path(r).is_dir():
                    out.append(str(Path(r)))
            except Exception:
                pass
        # de-dup preserving order
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
        # allow some custom patterns you used historically
        if "RUN" in name and "_" in name:
            return True
        return False

    def _vsp_pick_latest_rid():
        roots = _vsp_candidate_roots()
        best = None  # (mtime, rid, root)
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
                    # prefer dirs that contain run_gate_summary/findings_unified (commercial signal)
                    score = 0
                    if (d/"run_gate_summary.json").is_file(): score += 4
                    if (d/"findings_unified.json").is_file(): score += 3
                    if (d/"reports").is_dir(): score += 1
                    # combine into sortable key
                    key = (mtime, score, rid, root)
                    if best is None or key > best:
                        best = key
            except Exception:
                continue
        if not best:
            return None
        mtime, score, rid, root = best
        return {"rid": rid, "root": root, "mtime": mtime, "score": score, "roots_checked": roots}

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
            # if rid missing, still report latest discovery
            latest = _vsp_pick_latest_rid()
            return jsonify(ok=False, err="missing rid", latest=latest), 200

        d = _vsp_find_rid_dir(rid)
        if not d:
            latest = _vsp_pick_latest_rid()
            return jsonify(ok=False, err="rid dir not found", rid=rid, latest=latest), 200

        checks = {}
        def _read_json(p: Path):
            try:
                return json.loads(p.read_text(encoding="utf-8", errors="replace"))
            except Exception:
                return None

        # critical evidence
        p_gate = d/"run_gate_summary.json"
        p_find = d/"findings_unified.json"

        checks["run_gate_summary_exists"] = p_gate.is_file()
        checks["findings_unified_exists"] = p_find.is_file()
        checks["run_gate_summary_json_ok"] = bool(_read_json(p_gate)) if p_gate.is_file() else False
        j_find = _read_json(p_find) if p_find.is_file() else None
        checks["findings_unified_json_ok"] = bool(j_find)
        # basic shape
        if isinstance(j_find, dict):
            checks["findings_has_findings_array"] = isinstance(j_find.get("findings"), list)
            meta = j_find.get("meta") if isinstance(j_find.get("meta"), dict) else {}
            checks["findings_has_counts_by_sev"] = bool(meta.get("counts_by_severity")) if isinstance(meta, dict) else False
        else:
            checks["findings_has_findings_array"] = False
            checks["findings_has_counts_by_sev"] = False

        ok = all([
            checks["run_gate_summary_exists"],
            checks["findings_unified_exists"],
            checks["run_gate_summary_json_ok"],
            checks["findings_unified_json_ok"],
        ])
        return jsonify(ok=ok, rid=rid, run_dir=str(d), checks=checks), 200

    # If some wrong endpoint is still called and returns 404, convert ONLY known commercial ones to 200 JSON
    @app.after_request
    def _vsp_after_request_soft404(resp):
        try:
            path = request.path or ""
        except Exception:
            return resp
        if getattr(resp, "status_code", 0) != 404:
            return resp
        # narrow scope: only endpoints we *want* to be non-404 in commercial UI
        if path.startswith("/api/vsp/run_file_allow") or path.startswith("/api/run_file_allow") or path.startswith("/api/vsp/rid_latest_gate_root") or path.startswith("/api/vsp/ui_health_v1"):
            try:
                return jsonify(ok=False, err="not found (soft404)", path=path), 200
            except Exception:
                return resp
        return resp
    # ===================== /{MARK}_ENDPOINTS =====================
    """).format(MARK=MARK)

    if (MARK + "_ENDPOINTS") not in s:
        s = s.rstrip() + "\n\n" + addon + "\n"
else:
    # already patched
    pass

# Write + compile check
app.write_text(s, encoding="utf-8")
try:
    py_compile.compile(str(app), doraise=True)
except Exception as e:
    print("[ERR] py_compile failed:", e)
    raise

print("[OK] patched vsp_demo_app.py with", MARK)
PY

echo "[INFO] Restart service: $SVC"
systemctl restart "$SVC" 2>/dev/null || true

# 3) Patch dashboard JS bundle to auto refresh + UI OK badge
python3 - <<'PY'
from pathlib import Path
import re, textwrap

MARK = "VSP_P0_JS_AUTOREFRESH_GREENBADGE_V1"

# auto-detect a main JS file referenced by templates
tpl_root = Path("templates")
js_candidates = []

if tpl_root.is_dir():
    for html in tpl_root.rglob("*.html"):
        t = html.read_text(encoding="utf-8", errors="replace")
        for m in re.finditer(r'src=["\'](/static/js/[^"\']+\.js)["\']', t):
            js_candidates.append(m.group(1))

# prioritize known commercial bundles
prio = [
    "/static/js/vsp_bundle_commercial_v2.js",
    "/static/js/vsp_bundle_commercial_v1.js",
    "/static/js/vsp_dash_only_v1.js",
    "/static/js/vsp_dash_only_v1h.js",
    "/static/js/vsp_dashboard_kpi_force_any_v1.js",
]
picked = None
for p in prio:
    if p in js_candidates:
        picked = p
        break
if not picked and js_candidates:
    picked = js_candidates[0]

if not picked:
    # fallback: try common locations
    for fb in prio:
        if Path(fb.lstrip("/")).is_file():
            picked = fb
            break

if not picked:
    print("[WARN] cannot find dashboard JS to patch; skipped JS patch")
    raise SystemExit(0)

jsp = Path(picked.lstrip("/"))
if not jsp.is_file():
    print("[WARN] detected JS not found on disk:", jsp)
    raise SystemExit(0)

s = jsp.read_text(encoding="utf-8", errors="replace")
if MARK in s:
    print("[OK] JS already patched:", jsp)
    raise SystemExit(0)

addon = textwrap.dedent(r"""
/* {MARK} - auto poll RID latest + UI OK badge */
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
    if(detail && detail.err){
      el.title = detail.err;
    }else{
      el.title = "";
    }
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
      // if your dashboard exposes a reload hook, call it
      if(typeof window.VSP_reloadAll === "function"){
        try{ window.VSP_reloadAll(); }catch(e){}
      }
    }

    const health = await fetchJSON("/api/vsp/ui_health_v1?rid=" + encodeURIComponent(lastRID||""));
    setBadge(!!(health && health.ok), lastRID, health);
  }

  setTimeout(()=>{ ensureBadge(); tick(); setInterval(tick, POLL_MS); }, 1200);
})();
""").strip().format(MARK=MARK)

# Inject near end of file (safe)
s2 = s.rstrip() + "\n\n" + addon + "\n"
jsp_bak = jsp.with_suffix(jsp.suffix + ".bak_autorefresh_green_" + __import__("time").strftime("%Y%m%d_%H%M%S"))
jsp_bak.write_text(s, encoding="utf-8")
jsp.write_text(s2, encoding="utf-8")
print("[BACKUP]", jsp_bak)
print("[OK] patched JS:", jsp)
PY

echo "[OK] Done. Quick smoke curls:"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -sS "$BASE/api/vsp/rid_latest_gate_root" | head -c 260; echo
