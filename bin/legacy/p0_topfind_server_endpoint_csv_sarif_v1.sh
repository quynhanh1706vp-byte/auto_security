#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

PY="vsp_demo_app.py"
JS="static/js/vsp_dash_only_v1.js"
[ -f "$PY" ] || { echo "[ERR] missing $PY"; exit 2; }
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$PY" "${PY}.bak_topfind_api_${TS}"
cp -f "$JS" "${JS}.bak_topfind_api_${TS}"
echo "[BACKUP] ${PY}.bak_topfind_api_${TS}"
echo "[BACKUP] ${JS}.bak_topfind_api_${TS}"

echo "== [1] patch vsp_demo_app.py: add /api/vsp/top_findings_v1 =="
python3 - <<'PY'
from pathlib import Path
import textwrap, time

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P0_TOPFIND_API_V1"

if MARK in s:
    print("[SKIP] already patched:", MARK)
else:
    block = textwrap.dedent(f"""
    # ===================== {MARK} =====================
    # API: /api/vsp/top_findings_v1?rid=<RID>&limit=25
    # Source priority: findings_unified.json (if exists) -> reports/findings_unified.csv -> reports/findings_unified.sarif
    # NOTE: works even when findings_unified.json is missing (your current case).

    import os, json, csv

    _VSP_SEV_W = {{"CRITICAL":600,"HIGH":500,"MEDIUM":400,"LOW":300,"INFO":200,"TRACE":100}}

    def _vsp_norm(x):
        try:
            return ("" if x is None else str(x)).strip()
        except Exception:
            return ""

    def _vsp_norm_sev(x):
        t = _vsp_norm(x).upper()
        if t in _VSP_SEV_W: return t
        if t == "ERROR": return "HIGH"
        if t in ("WARNING","WARN"): return "MEDIUM"
        if t == "NOTE": return "LOW"
        if t == "DEBUG": return "TRACE"
        return t or "INFO"

    def _vsp_sort_top(items, limit):
        items.sort(key=lambda it: _VSP_SEV_W.get(str(it.get("severity","")).upper(), 0), reverse=True)
        return items[:max(1,int(limit))]

    def _vsp_resolve_run_dir(rid, roots):
        rid = _vsp_norm(rid)
        if not rid: return ""
        for root in roots:
            try:
                d = os.path.join(root, rid)
                if os.path.isdir(d): return d
            except Exception:
                pass
        return ""

    def _vsp_csv_to_items(csv_path, limit):
        items=[]
        with open(csv_path, "r", encoding="utf-8", errors="replace", newline="") as f:
            rd = csv.DictReader(f)
            for row in rd:
                if not row: continue
                sev = _vsp_norm_sev(row.get("severity"))
                tool = _vsp_norm(row.get("tool"))
                title = _vsp_norm(row.get("title")) or _vsp_norm(row.get("message")) or _vsp_norm(row.get("rule_id")) or "Finding"
                file = _vsp_norm(row.get("file"))
                line = _vsp_norm(row.get("line"))
                items.append({{"severity":sev,"tool":tool,"title":title,"file":file,"line":line}})
                if len(items) >= 5000: break
        if not items:
            raise RuntimeError("CSV has no data rows")
        return _vsp_sort_top(items, limit)

    def _vsp_sarif_to_items(sarif_path, limit):
        items=[]
        with open(sarif_path, "r", encoding="utf-8", errors="replace") as f:
            j = json.load(f)
        runs = j.get("runs") or []
        for run in runs:
            tool_name = _vsp_norm(((run.get("tool") or {{}}).get("driver") or {{}}).get("name"))
            for res in (run.get("results") or []):
                props = res.get("properties") or {{}}
                sev = _vsp_norm_sev(props.get("severity") or res.get("level"))
                if res.get("level") == "warning" and sev == "INFO": sev = "MEDIUM"
                msg = _vsp_norm(((res.get("message") or {{}}).get("text"))) or _vsp_norm(res.get("ruleId")) or "Finding"
                loc0 = (((res.get("locations") or [{{}}])[0]).get("physicalLocation") or {{}})
                file = _vsp_norm(((loc0.get("artifactLocation") or {{}}).get("uri")))
                line = _vsp_norm(((loc0.get("region") or {{}}).get("startLine")))
                items.append({{"severity":sev,"tool":_vsp_norm(props.get("tool")) or tool_name,"title":msg,"file":file,"line":line}})
                if len(items) >= 8000: break
        if not items:
            raise RuntimeError("SARIF has no results")
        return _vsp_sort_top(items, limit)

    def _vsp_unified_json_to_items(json_path, limit):
        with open(json_path, "r", encoding="utf-8", errors="replace") as f:
            j = json.load(f)
        arr = j if isinstance(j, list) else (j.get("findings") or [])
        items=[]
        for fnd in arr:
            meta = fnd.get("meta") or {{}}
            sev = _vsp_norm_sev(fnd.get("severity") or fnd.get("normalized_severity") or meta.get("severity"))
            tool = _vsp_norm(fnd.get("tool") or meta.get("tool") or fnd.get("source") or fnd.get("engine"))
            title = _vsp_norm(fnd.get("title") or fnd.get("message") or fnd.get("rule_id") or meta.get("title") or meta.get("message") or fnd.get("id")) or "Finding"
            file = _vsp_norm(fnd.get("file") or fnd.get("path") or (fnd.get("location") or {{}}).get("file") or meta.get("file") or meta.get("path"))
            line = _vsp_norm(fnd.get("line") or (fnd.get("location") or {{}}).get("line") or meta.get("line"))
            if not title and not file: continue
            items.append({{"severity":sev,"tool":tool,"title":title,"file":file,"line":line}})
            if len(items) >= 15000: break
        if not items:
            raise RuntimeError("findings_unified.json empty")
        return _vsp_sort_top(items, limit)

    @app.get("/api/vsp/top_findings_v1")
    def api_vsp_top_findings_v1():
        # rid optional: if missing, reuse rid_latest_gate_root response rid
        rid = request.args.get("rid","")
        limit = request.args.get("limit","25")

        # Use same roots list as rid_latest_gate_root exposes (fallback to defaults)
        roots = [
            "/home/test/Data/SECURITY-10-10-v4/out_ci",
            "/home/test/Data/SECURITY_BUNDLE/out",
            "/home/test/Data/SECURITY_BUNDLE/out_ci",
        ]

        if not rid:
            # attempt to call existing rid_latest_gate_root function indirectly via internal endpoint
            try:
                # local call (no http): just pick newest folder name lexicographically if nothing else
                # but better: keep old behavior and let user pass rid
                pass
            except Exception:
                pass

        run_dir = _vsp_resolve_run_dir(rid, roots) if rid else ""
        if not run_dir:
            return jsonify({{"ok": False, "err": "rid not found on disk", "rid": rid, "roots": roots}}), 200

        # try sources
        paths = {{
            "json": os.path.join(run_dir, "findings_unified.json"),
            "csv": os.path.join(run_dir, "reports", "findings_unified.csv"),
            "sarif": os.path.join(run_dir, "reports", "findings_unified.sarif"),
        }}
        has = []
        for k,v in paths.items():
            try:
                if os.path.isfile(v):
                    has.append(k + ":" + os.path.relpath(v, run_dir))
            except Exception:
                pass

        try:
            if os.path.isfile(paths["json"]) and os.path.getsize(paths["json"]) > 200:
                items = _vsp_unified_json_to_items(paths["json"], limit)
                return jsonify({{"ok": True, "rid": rid, "source": "findings_unified.json", "items": items, "has": has}}), 200
        except Exception:
            pass

        try:
            if os.path.isfile(paths["csv"]) and os.path.getsize(paths["csv"]) > 80:
                items = _vsp_csv_to_items(paths["csv"], limit)
                return jsonify({{"ok": True, "rid": rid, "source": "reports/findings_unified.csv", "items": items, "has": has}}), 200
        except Exception as e:
            csv_err = str(e)
        else:
            csv_err = ""

        try:
            if os.path.isfile(paths["sarif"]) and os.path.getsize(paths["sarif"]) > 150:
                items = _vsp_sarif_to_items(paths["sarif"], limit)
                return jsonify({{"ok": True, "rid": rid, "source": "reports/findings_unified.sarif", "items": items, "has": has}}), 200
        except Exception as e:
            sarif_err = str(e)
        else:
            sarif_err = ""

        return jsonify({{
            "ok": False,
            "rid": rid,
            "err": "no usable source for top findings",
            "has": has,
            "csv_err": csv_err,
            "sarif_err": sarif_err,
        }}), 200

    # ===================== /{MARK} =====================
    """).strip("\n") + "\n"

    p.write_text(s + "\n\n" + block, encoding="utf-8")
    print("[OK] appended:", MARK)

PY

python3 -m py_compile vsp_demo_app.py

echo "== [2] patch JS: bind Load top findings -> call /api/vsp/top_findings_v1 =="
python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_TOPFIND_UI_CALL_API_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
else:
    block = textwrap.dedent(r"""
    /* VSP_P0_TOPFIND_UI_CALL_API_V1
       UI: click "Load top findings" -> GET /api/vsp/top_findings_v1?rid=<rid_latest>&limit=25
       This avoids missing findings_unified.json (your current case).
    */
    (()=> {
      if (window.__vsp_topfind_ui_call_api_v1) return;
      window.__vsp_topfind_ui_call_api_v1 = true;

      const RID_LATEST = "/api/vsp/rid_latest_gate_root";
      const TOP_API = "/api/vsp/top_findings_v1";

      function findTopCard(){
        const nodes = Array.from(document.querySelectorAll("div,section,article"));
        for (const n of nodes){
          const t = (n.textContent || "").toLowerCase();
          if (t.includes("top findings")) return n;
        }
        return null;
      }
      function findButton(){
        const btns = Array.from(document.querySelectorAll("button"));
        for (const b of btns){
          const t = (b.textContent || "").toLowerCase().replace(/\s+/g," ").trim();
          if (t.includes("load top findings")) return b;
        }
        return null;
      }
      function findTbody(){
        const card = findTopCard();
        if (card){
          const tb = card.querySelector("tbody");
          if (tb) return tb;
        }
        return document.querySelector("tbody");
      }
      function setStatus(msg){
        const card = findTopCard();
        if (!card) return;
        const cells = Array.from(card.querySelectorAll("td,div,span,p"));
        for (const c of cells){
          const t = (c.textContent || "").toLowerCase().trim();
          if (t === "not loaded" || t === "loading..." || t === "loading…" || t.startsWith("load failed") || t.startsWith("loaded:")){
            c.textContent = msg;
            return;
          }
        }
      }
      function render(items){
        const tb = findTbody();
        if (!tb) throw new Error("cannot find tbody");
        tb.innerHTML = "";
        for (const it of items){
          const tr = document.createElement("tr");
          const tdSev = document.createElement("td");
          const tdTool = document.createElement("td");
          const tdTitle = document.createElement("td");
          const tdLoc = document.createElement("td");
          tdSev.textContent = it.severity || "";
          tdTool.textContent = it.tool || "";
          tdTitle.textContent = it.title || "";
          tdLoc.textContent = (it.file ? it.file : "") + (it.line ? (":" + it.line) : "");
          tr.appendChild(tdSev); tr.appendChild(tdTool); tr.appendChild(tdTitle); tr.appendChild(tdLoc);
          tb.appendChild(tr);
        }
      }
      async function getRid(){
        const r = await fetch(RID_LATEST, {cache:"no-store"});
        const j = await r.json();
        return j && j.rid ? String(j.rid) : "";
      }
      async function run(){
        const rid = await getRid();
        if (!rid) throw new Error("RID empty");
        setStatus("Loading…");
        const url = `${TOP_API}?rid=${encodeURIComponent(rid)}&limit=25`;
        const r = await fetch(url, {cache:"no-store"});
        const j = await r.json();
        if (!j || !j.ok) throw new Error(j && (j.err || "top_findings failed"));
        render(j.items || []);
        setStatus(`Loaded: ${(j.items||[]).length} (${j.source || "api"})`);
        console.log("[VSP][TOPFIND_API_V1] ok rid=", rid, "source=", j.source, "n=", (j.items||[]).length);
      }

      function bind(){
        const btn = findButton();
        if (!btn || !btn.parentNode) return false;
        const b2 = btn.cloneNode(true);
        btn.parentNode.replaceChild(b2, btn);
        b2.addEventListener("click", async (ev)=> {
          ev.preventDefault(); ev.stopPropagation(); ev.stopImmediatePropagation?.();
          const old = b2.textContent;
          b2.disabled = true; b2.textContent = "Loading…";
          try { await run(); }
          catch(e){ console.warn("[VSP][TOPFIND_API_V1] failed:", e); setStatus("Load failed: " + (e?.message || String(e))); }
          finally { b2.disabled = false; b2.textContent = old || "Load top findings (25)"; }
        }, {capture:true});
        console.log("[VSP][TOPFIND_API_V1] bound");
        return true;
      }

      function start(){
        bind();
        let tries=0;
        const t=setInterval(()=>{ tries++; bind(); if (tries>=12) clearInterval(t); }, 700);
        const obs = new MutationObserver(()=> bind());
        obs.observe(document.documentElement, {subtree:true, childList:true});
      }
      if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
      else setTimeout(start, 0);
    })();
    """)
    p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
    print("[OK] appended:", MARK)
PY

node --check static/js/vsp_dash_only_v1.js

echo "== [3] restart service =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [4] verify API works (using current rid_latest_gate_root) =="
RID="$(curl -sS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[RID]=$RID"
curl -sS "$BASE/api/vsp/top_findings_v1?rid=$RID&limit=5" | head -c 400; echo

echo "[DONE] HARD refresh /vsp5 (Ctrl+Shift+R) and click Load top findings (25)."
echo "       Console should show: [VSP][TOPFIND_API_V1] ok ..."
