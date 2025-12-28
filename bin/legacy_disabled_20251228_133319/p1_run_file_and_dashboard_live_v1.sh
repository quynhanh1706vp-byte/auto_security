#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"

# --- locate backend python file (prefer vsp_demo_app.py) ---
PY_CAND=()
[ -f ui/vsp_demo_app.py ] && PY_CAND+=(ui/vsp_demo_app.py)
[ -f vsp_demo_app.py ] && PY_CAND+=(vsp_demo_app.py)
[ -f wsgi_vsp_ui_gateway.py ] && PY_CAND+=(wsgi_vsp_ui_gateway.py)

BACKEND=""
for f in "${PY_CAND[@]}"; do
  if grep -qE "/api/vsp/runs|api/vsp/runs" "$f" 2>/dev/null; then BACKEND="$f"; break; fi
done
[ -n "$BACKEND" ] || { echo "[ERR] cannot find backend file containing /api/vsp/runs in candidates: ${PY_CAND[*]}"; exit 2; }

cp -f "$BACKEND" "${BACKEND}.bak_runfile_${TS}"
echo "[BACKUP] ${BACKEND}.bak_runfile_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap, re

p = None
for cand in ["ui/vsp_demo_app.py","vsp_demo_app.py","wsgi_vsp_ui_gateway.py"]:
    pp = Path(cand)
    if pp.exists():
        s = pp.read_text(encoding="utf-8", errors="replace")
        if ("/api/vsp/runs" in s) or ("api/vsp/runs" in s):
            p = pp
            break
if not p:
    raise SystemExit("[ERR] backend file not found")

s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P1_RUN_FILE_WHITELIST_V1"
if marker in s:
    print("[OK] marker already present in", p)
    raise SystemExit(0)

block = textwrap.dedent(r'''
# --- VSP_P1_RUN_FILE_WHITELIST_V1: safe read-only run_file endpoint (whitelist; no traversal) ---
def _vsp_p1_register_run_file_whitelist_v1():
    try:
        import os, mimetypes
        from pathlib import Path
        from flask import request, jsonify, abort, send_file
    except Exception:
        return

    app_obj = globals().get("app", None)
    if app_obj is None or not hasattr(app_obj, "add_url_rule"):
        # fallback: some deployments might expose `application`
        app_obj = globals().get("application", None)
    if app_obj is None or not hasattr(app_obj, "add_url_rule"):
        return

    # avoid double-register
    try:
        if hasattr(app_obj, "view_functions") and ("vsp_run_file_whitelist_v1" in app_obj.view_functions):
            return
    except Exception:
        pass

    # base dirs to locate runs (best-effort; adjust by env if needed)
    BASE_DIRS = [
        os.environ.get("VSP_OUT_DIR", "") or "",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
    ]
    BASE_DIRS = [d for d in BASE_DIRS if d and os.path.isdir(d)]

    # strict whitelist of readable files (relative to run_dir)
    ALLOW = {
        "run_gate.json",
        "run_gate_summary.json",
        "findings_unified.json",
        "findings_unified.sarif",
        "reports/findings_unified.csv",
        "reports/findings_unified.html",
        "reports/findings_unified.tgz",
        "reports/findings_unified.zip",
        "SUMMARY.txt",
    }

    _CACHE = {"rid2dir": {}}

    def _safe_rel(path: str) -> str:
        if not path:
            return ""
        path = path.strip().lstrip("/")  # no absolute
        if ".." in path.split("/"):
            return ""
        # collapse repeated slashes
        while "//" in path:
            path = path.replace("//", "/")
        return path

    def _find_run_dir(rid: str) -> Path | None:
        rid = (rid or "").strip()
        if not rid:
            return None
        if rid in _CACHE["rid2dir"]:
            pr = _CACHE["rid2dir"][rid]
            return Path(pr) if pr else None

        # 1) direct join base/rid
        for b in BASE_DIRS:
            cand = Path(b) / rid
            if cand.is_dir():
                _CACHE["rid2dir"][rid] = str(cand)
                return cand

        # 2) shallow search: base/*/rid and base/*/*/rid (bounded)
        for b in BASE_DIRS:
            base = Path(b)
            try:
                # depth 1
                for d1 in base.iterdir():
                    if not d1.is_dir():
                        continue
                    cand = d1 / rid
                    if cand.is_dir():
                        _CACHE["rid2dir"][rid] = str(cand)
                        return cand
                # depth 2
                for d1 in base.iterdir():
                    if not d1.is_dir():
                        continue
                    for d2 in d1.iterdir():
                        if not d2.is_dir():
                            continue
                        cand = d2 / rid
                        if cand.is_dir():
                            _CACHE["rid2dir"][rid] = str(cand)
                            return cand
            except Exception:
                continue

        _CACHE["rid2dir"][rid] = ""
        return None

    def _max_bytes(rel: str) -> int:
        # keep safe limits
        if rel.endswith(".tgz") or rel.endswith(".zip"):
            return 200 * 1024 * 1024
        if rel.endswith(".html"):
            return 80 * 1024 * 1024
        return 25 * 1024 * 1024

    def vsp_run_file_whitelist_v1():
        rid = (request.args.get("rid") or "").strip()
        rel = _safe_rel(request.args.get("path") or "")
        if not rid or not rel:
            return jsonify({"ok": False, "err": "missing rid/path"}), 400
        if rel not in ALLOW:
            return jsonify({"ok": False, "err": "path not allowed", "allow": sorted(ALLOW)}), 403

        run_dir = _find_run_dir(rid)
        if not run_dir:
            return jsonify({"ok": False, "err": "run_dir not found", "rid": rid}), 404

        fp = (run_dir / rel)
        try:
            # prevent escape via symlink / traversal
            fp_res = fp.resolve()
            rd_res = run_dir.resolve()
            if rd_res not in fp_res.parents and fp_res != rd_res:
                return jsonify({"ok": False, "err": "blocked escape"}), 403
        except Exception:
            return jsonify({"ok": False, "err": "resolve failed"}), 403

        if not fp.exists() or not fp.is_file():
            return jsonify({"ok": False, "err": "file not found", "path": rel}), 404

        try:
            sz = fp.stat().st_size
        except Exception:
            sz = -1
        if sz >= 0 and sz > _max_bytes(rel):
            return jsonify({"ok": False, "err": "file too large", "size": sz, "limit": _max_bytes(rel)}), 413

        mime, _ = mimetypes.guess_type(str(fp))
        mime = mime or "application/octet-stream"

        # inline for json/html/csv, attachment for archives
        as_attach = rel.endswith(".tgz") or rel.endswith(".zip")
        dl_name = f"{rid}__{rel.replace('/','_')}"

        return send_file(str(fp), mimetype=mime, as_attachment=as_attach, download_name=dl_name)

    try:
        app_obj.add_url_rule("/api/vsp/run_file", "vsp_run_file_whitelist_v1", vsp_run_file_whitelist_v1, methods=["GET"])
        print("[VSP_RUN_FILE] registered /api/vsp/run_file (whitelist)")
    except Exception as e:
        print("[VSP_RUN_FILE] register failed:", e)

# register on import
try:
    _vsp_p1_register_run_file_whitelist_v1()
except Exception:
    pass
# --- end VSP_P1_RUN_FILE_WHITELIST_V1 ---
''').strip("\n") + "\n"

# append safely at end (least intrusive)
p.write_text(s + "\n\n" + block, encoding="utf-8")
print("[OK] appended run_file whitelist block into", p)
PY

# --- patch dashboard live KPI into bundle ---
JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_dash_live_${TS}"
echo "[BACKUP] ${JS}.bak_dash_live_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P1_DASH_LIVE_KPI_V1"
if marker in s:
    print("[OK] marker already present in bundle")
    raise SystemExit(0)

addon = textwrap.dedent(r"""
/* VSP_P1_DASH_LIVE_KPI_V1 (safe: poll /api/vsp/runs; fetch run_gate.json only for latest; no bulk probing) */
(()=> {
  if (window.__vsp_p1_dash_live_kpi_v1) return;
  window.__vsp_p1_dash_live_kpi_v1 = true;

  function onDash(){
    try {
      const p = (location && location.pathname) ? location.pathname : "";
      // support /vsp5 and /dashboard routes
      return (p === "/vsp5" || p === "/dashboard" || /\/vsp5\/?$/.test(p) || /\/dashboard\/?$/.test(p));
    } catch(e){ return false; }
  }
  if (!onDash()) return;

  const S = { live:true, delay:8000, timer:null, lastRid:"", running:false };

  const now=()=>Date.now();
  const qs=(o)=>Object.keys(o).map(k=>encodeURIComponent(k)+"="+encodeURIComponent(o[k])).join("&");

  function mount(){
    if (document.getElementById("vsp_dash_live_kpi_v1")) return;

    const host =
      document.querySelector("#vsp_tab_dashboard") ||
      document.querySelector("[data-tab='dashboard']") ||
      document.querySelector("main") ||
      document.body;

    const wrap=document.createElement("div");
    wrap.id="vsp_dash_live_kpi_v1";
    wrap.style.cssText=[
      "margin:10px 0 12px 0",
      "padding:10px 12px",
      "border-radius:14px",
      "border:1px solid rgba(255,255,255,0.08)",
      "background:rgba(255,255,255,0.03)",
      "display:flex",
      "gap:10px",
      "align-items:center",
      "flex-wrap:wrap"
    ].join(";");

    wrap.innerHTML = `
      <span style="opacity:.9;font-weight:600">Dashboard Live</span>
      <button id="vsp_dash_live_toggle_v1" style="padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,0.10);background:rgba(255,255,255,0.05);color:inherit;cursor:pointer">Live: ON</button>
      <span id="vsp_dash_live_status_v1" style="opacity:.8;font-size:12px">Last: --</span>
      <span style="opacity:.55">|</span>
      <span id="vsp_dash_live_counts_v1" style="opacity:.92">runs: --</span>
      <span style="opacity:.55">|</span>
      <span id="vsp_dash_live_latest_v1" style="opacity:.92">latest: --</span>
      <button id="vsp_dash_open_gate_json_v1" style="padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,0.10);background:rgba(255,255,255,0.05);color:inherit;cursor:pointer">Open gate JSON</button>
      <button id="vsp_dash_open_html_v1" style="padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,0.10);background:rgba(255,255,255,0.05);color:inherit;cursor:pointer">Open HTML</button>
    `;

    host.insertAdjacentElement("afterbegin", wrap);

    const tgl = document.getElementById("vsp_dash_live_toggle_v1");
    tgl.addEventListener("click", ()=>{
      S.live = !S.live;
      tgl.textContent = S.live ? "Live: ON" : "Live: OFF";
      if (S.live) kick();
    });

    document.getElementById("vsp_dash_open_gate_json_v1").addEventListener("click", ()=>{
      if (!S.lastRid) return;
      window.open(`/api/vsp/run_file?${qs({rid:S.lastRid, path:"run_gate.json"})}`, "_blank");
    });
    document.getElementById("vsp_dash_open_html_v1").addEventListener("click", ()=>{
      if (!S.lastRid) return;
      window.open(`/api/vsp/run_file?${qs({rid:S.lastRid, path:"reports/findings_unified.html"})}`, "_blank");
    });
  }

  function setText(id, t){
    const el=document.getElementById(id);
    if (el) el.textContent=t;
  }

  async function getRuns(){
    const url = `/api/vsp/runs?limit=30&offset=0&_=${now()}`;
    const r = await fetch(url, { cache:"no-store", credentials:"same-origin" });
    if (!r.ok) throw new Error("runs "+r.status);
    return await r.json();
  }

  async function getGate(rid){
    const url = `/api/vsp/run_file?${qs({rid, path:"run_gate.json", _: now()})}`;
    const r = await fetch(url, { cache:"no-store", credentials:"same-origin" });
    if (!r.ok) return null;
    try { return await r.json(); } catch(e){ return null; }
  }

  function normOverall(x){
    const s=(x||"").toString().toUpperCase();
    if (!s) return "UNKNOWN";
    if (["GREEN","PASS","OK"].includes(s)) return "GREEN";
    if (["AMBER","WARN"].includes(s)) return "AMBER";
    if (["RED","FAIL","BLOCK"].includes(s)) return "RED";
    if (["DEGRADED"].includes(s)) return "DEGRADED";
    return s;
  }

  function schedule(ms){
    clearTimeout(S.timer);
    S.timer=setTimeout(()=>tick(), ms);
  }
  function kick(){ schedule(400); }

  async function tick(){
    if (!S.live) return schedule(S.delay);
    if (document.hidden) return schedule(S.delay);
    if (S.running) return schedule(600);
    S.running=true;
    try{
      mount();
      const j = await getRuns();
      const items = (j && j.items) ? j.items : [];
      const total = (typeof j.total === "number") ? j.total : items.length;

      const first = items[0] || null;
      const rid = (first && (first.rid || first.run_id || first.id)) ? (first.rid || first.run_id || first.id).toString() : "";
      if (rid) S.lastRid = rid;

      // counts: prefer item.overall/overall_status if present; else UNKNOWN
      const cnt = {GREEN:0, AMBER:0, RED:0, DEGRADED:0, UNKNOWN:0};
      for (const it of items){
        const ov = normOverall(it.overall || it.overall_status || it.status || "");
        if (cnt[ov] === undefined) cnt.UNKNOWN++;
        else cnt[ov]++;
      }

      // try to get "real" overall for latest via run_gate.json (only 1 file)
      let latestOverall = "UNKNOWN";
      if (rid){
        const gate = await getGate(rid);
        if (gate){
          latestOverall = normOverall(gate.overall || gate.overall_status || "");
        }
      }

      const ts = new Date().toLocaleTimeString();
      setText("vsp_dash_live_status_v1", `Last: ${ts}`);
      setText("vsp_dash_live_counts_v1", `runs: ${total} | G:${cnt.GREEN} A:${cnt.AMBER} R:${cnt.RED} D:${cnt.DEGRADED} U:${cnt.UNKNOWN}`);
      setText("vsp_dash_live_latest_v1", `latest: ${rid || "--"} | overall: ${latestOverall}`);

      schedule(S.delay);
    }catch(e){
      const ts = new Date().toLocaleTimeString();
      setText("vsp_dash_live_status_v1", `Last: ${ts} • err`);
      schedule(Math.min(60000, S.delay*2));
    }finally{
      S.running=false;
    }
  }

  document.addEventListener("visibilitychange", ()=>{ if (!document.hidden && S.live) kick(); });
  kick();
})();
""").rstrip() + "\n"

p.write_text(s + "\n" + addon, encoding="utf-8")
print("[OK] appended dash live KPI module")
PY

echo "[DONE] Patched backend + dashboard JS."
echo "Restart UI service now:"
echo "  sudo systemctl restart vsp-ui-8910.service  # if you use systemd"
echo "  # or: bin/p1_ui_8910_single_owner_start_v2.sh"

