#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
PY="vsp_demo_app.py"
JS="static/js/vsp_dash_only_v1.js"

[ -f "$PY" ] || { echo "[ERR] missing $PY"; exit 2; }
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$PY" "${PY}.bak_topfind_v4_${TS}"
cp -f "$JS" "${JS}.bak_topfind_v4_${TS}"
echo "[BACKUP] ${PY}.bak_topfind_v4_${TS}"
echo "[BACKUP] ${JS}.bak_topfind_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap, re, py_compile

# -----------------------
# 1) Patch vsp_demo_app.py: add /api/vsp/top_findings_v4 (parse semgrep/semgrep.json)
# -----------------------
py = Path("vsp_demo_app.py")
s = py.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P0_TOPFIND_API_V4_SEMGREP_PARSE_V1"

if MARK not in s:
    block = textwrap.dedent(r"""
    # ===================== VSP_P0_TOPFIND_API_V4_SEMGREP_PARSE_V1 =====================
    # GET /api/vsp/top_findings_v4?rid=...&limit=25
    try:
        import os, glob, json, time, re
        from flask import request, jsonify

        _VSP_TOPFIND_ROOTS_V4 = [
            "/home/test/Data/SECURITY-10-10-v4/out_ci",
            "/home/test/Data/SECURITY_BUNDLE/out",
            "/home/test/Data/SECURITY_BUNDLE/out_ci",
        ]

        def _vsp_topfind_v4_find_run_dir(rid: str):
            if not rid:
                return None
            for root in _VSP_TOPFIND_ROOTS_V4:
                d = os.path.join(root, rid)
                if os.path.isdir(d):
                    return d
            return None

        def _vsp_topfind_v4_norm_sev(sev: str):
            if not sev:
                return "INFO"
            s = str(sev).strip().upper()
            # common semgrep: ERROR/WARNING/INFO
            if s in ("ERROR", "ERR"):
                return "HIGH"
            if s in ("WARNING", "WARN"):
                return "MEDIUM"
            if s in ("INFO", "INFORMATION"):
                return "INFO"
            # already normalized?
            if s in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"):
                return s
            return "INFO"

        def _vsp_topfind_v4_pick_semgrep_file(run_dir: str):
            cand = os.path.join(run_dir, "semgrep", "semgrep.json")
            if os.path.isfile(cand) and os.path.getsize(cand) > 200:
                return cand
            # fallback: any semgrep*.json
            hits = []
            for f in glob.glob(os.path.join(run_dir, "**", "*semgrep*.json"), recursive=True):
                try:
                    if os.path.getsize(f) > 200:
                        hits.append((os.path.getsize(f), f))
                except Exception:
                    continue
            hits.sort(reverse=True)
            return hits[0][1] if hits else None

        def _vsp_topfind_v4_parse_semgrep(path: str, limit: int):
            items = []
            try:
                j = json.load(open(path, "r", encoding="utf-8", errors="ignore"))
            except Exception:
                return items

            results = j.get("results") if isinstance(j, dict) else None
            if not isinstance(results, list):
                return items

            for r in results:
                if not isinstance(r, dict):
                    continue
                extra = r.get("extra") or {}
                sev = _vsp_topfind_v4_norm_sev(extra.get("severity") or extra.get("level") or "")
                msg = extra.get("message") or extra.get("metadata", {}).get("message") or ""
                check_id = r.get("check_id") or r.get("rule_id") or ""
                title = (msg or check_id or "Semgrep finding").strip()
                pathf = (r.get("path") or "").strip()
                start = r.get("start") or {}
                line = start.get("line") if isinstance(start, dict) else ""
                # some semgrep outputs have line under "extra"->"lines"
                if not line and isinstance(extra, dict):
                    try:
                        line = extra.get("line") or ""
                    except Exception:
                        line = ""

                items.append({
                    "severity": sev,
                    "tool": "semgrep",
                    "title": title,
                    "file": pathf,
                    "line": str(line) if line is not None else "",
                })
                if len(items) >= limit:
                    break
            return items

        @app.get("/api/vsp/top_findings_v4")
        def api_vsp_top_findings_v4():
            rid = request.args.get("rid", "").strip()
            try:
                limit = int(request.args.get("limit", "25"))
            except Exception:
                limit = 25
            limit = max(1, min(limit, 200))

            run_dir = _vsp_topfind_v4_find_run_dir(rid)
            if not run_dir:
                return jsonify({"ok": False, "rid": rid, "err": "run_dir not found", "items": [], "ts": int(time.time())}), 200

            sf = _vsp_topfind_v4_pick_semgrep_file(run_dir)
            if not sf:
                return jsonify({
                    "ok": False, "rid": rid,
                    "err": "semgrep.json not found",
                    "hint": "Expected semgrep/semgrep.json or *semgrep*.json under run dir",
                    "items": [], "ts": int(time.time())
                }), 200

            items = _vsp_topfind_v4_parse_semgrep(sf, limit)
            if not items:
                return jsonify({
                    "ok": False, "rid": rid,
                    "err": "semgrep parsed but no results",
                    "source": os.path.relpath(sf, run_dir).replace("\\","/"),
                    "items": [], "ts": int(time.time())
                }), 200

            return jsonify({
                "ok": True, "rid": rid,
                "source": "semgrep:" + os.path.relpath(sf, run_dir).replace("\\","/"),
                "items": items,
                "ts": int(time.time())
            }), 200

        print("[VSP_P0_TOPFIND_API_V4] enabled")
    except Exception as _e:
        print("[VSP_P0_TOPFIND_API_V4] ERROR:", _e)
    # ===================== /VSP_P0_TOPFIND_API_V4_SEMGREP_PARSE_V1 =====================
    """).strip("\n") + "\n\n"
    py.write_text(s + "\n\n" + block, encoding="utf-8")
    print("[OK] appended:", MARK)
else:
    print("[SKIP] already in vsp_demo_app.py:", MARK)

py_compile.compile(str(py), doraise=True)
print("[OK] vsp_demo_app.py compiles")

# -----------------------
# 2) Patch vsp_dash_only_v1.js: bind button + render table using /api/vsp/top_findings_v4
# -----------------------
js = Path("static/js/vsp_dash_only_v1.js")
s = js.read_text(encoding="utf-8", errors="replace")
JMARK = "VSP_P0_TOPFIND_UI_RENDER_V4_SEMGREP_V1"
if JMARK not in s:
    jblock = r"""
/* ===================== VSP_P0_TOPFIND_UI_RENDER_V4_SEMGREP_V1 ===================== */
(()=> {
  try{
    if (window.__vsp_p0_topfind_ui_v4) return;
    window.__vsp_p0_topfind_ui_v4 = true;

    const log=(...a)=>console.log("[VSP][TOPFIND_UI_V4]",...a);

    function qsAll(sel, root=document){ try{return Array.from(root.querySelectorAll(sel));}catch(_){return [];} }
    function textOf(el){ return (el && (el.textContent||"")).trim(); }

    function findButton(){
      const btns = qsAll("button");
      for (const b of btns){
        const t = textOf(b).toLowerCase();
        if (t.includes("load") && t.includes("top") && t.includes("finding")) return b;
        if (t.includes("top findings")) return b;
      }
      return null;
    }

    function findTopFindTable(){
      // best-effort: find table having headers Severity/Tool/Title
      const tables = qsAll("table");
      for (const tb of tables){
        const ths = qsAll("th", tb).map(x=>textOf(x).toLowerCase());
        if (ths.includes("severity") && ths.includes("tool") && ths.includes("title")) return tb;
      }
      // fallback: first table in section containing "Top findings"
      const heads = qsAll("*").filter(el => textOf(el).toLowerCase()==="top findings (sample)" || textOf(el).toLowerCase().startsWith("top findings"));
      for (const h of heads){
        // search downwards
        const sec = h.closest("section,div") || h.parentElement;
        if (sec){
          const t = sec.querySelector("table");
          if (t) return t;
        }
      }
      return tables[0] || null;
    }

    function ensureTbody(table){
      if (!table) return null;
      let tb = table.querySelector("tbody");
      if (!tb){
        tb = document.createElement("tbody");
        table.appendChild(tb);
      }
      return tb;
    }

    function setStatus(msg){
      // show under button if possible
      let el = document.getElementById("vsp_topfind_status_v4");
      const btn = findButton();
      if (!el && btn){
        el = document.createElement("span");
        el.id = "vsp_topfind_status_v4";
        el.style.marginLeft = "10px";
        el.style.opacity = "0.85";
        el.style.fontSize = "12px";
        btn.parentElement && btn.parentElement.appendChild(el);
      }
      if (el) el.textContent = msg;
    }

    async function getLatestRid(){
      const r = await fetch("/api/vsp/rid_latest_gate_root", {cache:"no-store"});
      const j = await r.json();
      return j && j.rid ? j.rid : "";
    }

    function rowHtml(it){
      const sev = (it.severity||"INFO").toString();
      const tool = (it.tool||"").toString();
      const title = (it.title||"").toString();
      const loc = ((it.file||"") + (it.line? (":" + it.line) : "")).trim();
      return `<tr>
        <td style="white-space:nowrap">${sev}</td>
        <td style="white-space:nowrap">${tool}</td>
        <td>${title}</td>
        <td style="white-space:nowrap">${loc}</td>
      </tr>`;
    }

    async function loadTopFindings(limit=25){
      setStatus("Loading…");
      const rid = await getLatestRid();
      if (!rid){
        setStatus("No RID");
        return;
      }
      const url = `/api/vsp/top_findings_v4?rid=${encodeURIComponent(rid)}&limit=${encodeURIComponent(limit)}`;
      log("fetch", url);
      const res = await fetch(url, {cache:"no-store"});
      const j = await res.json();
      if (!j || !j.ok){
        setStatus(`No data (${(j&&j.err)||"err"})`);
        log("no data", j);
        return;
      }
      const items = Array.isArray(j.items) ? j.items : [];
      const table = findTopFindTable();
      const tb = ensureTbody(table);
      if (!tb){
        setStatus(`Loaded ${items.length} but no table`);
        return;
      }
      tb.innerHTML = items.map(rowHtml).join("");
      setStatus(`Loaded ${items.length} • ${j.source||"v4"}`);
      log("rendered", items.length, "rid", rid);
    }

    function bind(){
      const btn = findButton();
      if (!btn){
        log("button not found; retry");
        return false;
      }
      if (btn.__vspBoundV4) return true;
      btn.__vspBoundV4 = true;
      btn.addEventListener("click", (e)=>{ e.preventDefault(); loadTopFindings(25); });
      setStatus("Ready");
      log("bound button");
      return true;
    }

    function boot(){
      if (bind()) return;
      let n=0;
      const t=setInterval(()=>{
        n++;
        if (bind() || n>40) clearInterval(t);
      }, 250);
    }

    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
    else boot();

  }catch(e){
    console.error("[VSP][TOPFIND_UI_V4] fatal", e);
  }
})();
 /* ===================== /VSP_P0_TOPFIND_UI_RENDER_V4_SEMGREP_V1 ===================== */
"""
    js.write_text(s + "\n\n" + jblock + "\n", encoding="utf-8")
    print("[OK] appended:", JMARK)
else:
    print("[SKIP] already in JS:", JMARK)

# quick JS syntax check (node --check is done in shell)
PY

node --check static/js/vsp_dash_only_v1.js >/dev/null
echo "[OK] node --check passed"

systemctl restart "$SVC" 2>/dev/null || true

echo "== [verify] API v4 returns real semgrep rows =="
RID="$(curl -sS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("rid",""))')"
echo "[RID]=$RID"
curl -sS "$BASE/api/vsp/top_findings_v4?rid=$RID&limit=5" | python3 -m json.tool | head -n 120
echo
echo "[DONE] Ctrl+Shift+R /vsp5 then click Load top findings (25). Look for status text next to the button."
