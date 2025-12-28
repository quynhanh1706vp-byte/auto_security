#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

PY="vsp_demo_app.py"
JS="static/js/vsp_dash_only_v1.js"
[ -f "$PY" ] || { echo "[ERR] missing $PY"; exit 2; }
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$PY" "${PY}.bak_topfind_v3_${TS}"
cp -f "$JS" "${JS}.bak_topfind_v3_${TS}"
echo "[BACKUP] ${PY}.bak_topfind_v3_${TS}"
echo "[BACKUP] ${JS}.bak_topfind_v3_${TS}"

echo "== [1] append /api/vsp/top_findings_v3 (scan run dir for real tool outputs) =="
python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_TOPFIND_API_V3_SCAN_ANY_V1"

if MARK in s:
    print("[SKIP] already patched:", MARK)
else:
    block = textwrap.dedent(r"""
    # ===================== VSP_P0_TOPFIND_API_V3_SCAN_ANY_V1 =====================
    import os as _os
    import json as _json

    _VSP3_SEV_W = {"CRITICAL":600,"HIGH":500,"MEDIUM":400,"LOW":300,"INFO":200,"TRACE":100}
    def _vsp3_norm(x):
        try: return ("" if x is None else str(x)).strip()
        except Exception: return ""
    def _vsp3_norm_sev(x):
        t = _vsp3_norm(x).upper()
        if t in _VSP3_SEV_W: return t
        if t == "ERROR": return "HIGH"
        if t in ("WARNING","WARN"): return "MEDIUM"
        if t == "NOTE": return "LOW"
        if t == "DEBUG": return "TRACE"
        return t or "INFO"
    def _vsp3_sort(items, limit):
        items.sort(key=lambda it: _VSP3_SEV_W.get(str(it.get("severity","")).upper(), 0), reverse=True)
        return items[:max(1,int(limit))]

    def _vsp3_level_to_sev(level):
        lv = _vsp3_norm(level).lower()
        if lv == "error": return "HIGH"
        if lv == "warning": return "MEDIUM"
        if lv == "note": return "LOW"
        return "INFO"

    def _vsp3_pick(obj, keys):
        for k in keys:
            try:
                v = obj.get(k)
            except Exception:
                v = None
            if v is None: 
                continue
            if isinstance(v, (dict,list)):
                continue
            t = _vsp3_norm(v)
            if t: return t
        return ""

    def _vsp3_candidates(run_dir):
        # only scan plausible finding files; skip huge + irrelevant
        inc_kw = ("sarif","find","result","semgrep","codeql","bandit","gitleaks","kics","trivy","grype","vuln","issue")
        exc_kw = ("sbom","syft","manifest","evidence","gate","summary","status","settings","license","readme","metrics")
        cands=[]
        for root, dirs, files in _os.walk(run_dir):
            # avoid scanning node_modules/static
            dn = root.lower()
            if "/static/" in dn or "/node_modules/" in dn:
                continue
            for fn in files:
                low = fn.lower()
                if not (low.endswith(".sarif") or low.endswith(".json") or low.endswith(".jsonl") or low.endswith(".ndjson")):
                    continue
                full = _os.path.join(root, fn)
                rel = _os.path.relpath(full, run_dir)
                rlow = rel.lower()
                if any(k in rlow for k in exc_kw):
                    continue
                if not any(k in rlow for k in inc_kw):
                    continue
                try:
                    sz = _os.path.getsize(full)
                except Exception:
                    continue
                if sz < 120:  # too small
                    continue
                if sz > 40*1024*1024:  # too big
                    continue
                cands.append((sz, full, rel))
        # prefer smaller first to be fast, but keep reasonable
        cands.sort(key=lambda x: x[0])
        return cands[:120]

    def _vsp3_parse_sarif(path, limit):
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            j = _json.load(f)
        runs = j.get("runs") or []
        items=[]
        for run in runs:
            tool = _vsp3_norm((((run.get("tool") or {}).get("driver") or {}).get("name")))
            for res in (run.get("results") or []):
                props = res.get("properties") or {}
                sev = _vsp3_norm_sev(props.get("severity")) or _vsp3_level_to_sev(res.get("level"))
                msg = _vsp3_norm(((res.get("message") or {}).get("text"))) or _vsp3_norm(res.get("ruleId")) or "Finding"
                loc0 = (((res.get("locations") or [{}])[0]).get("physicalLocation") or {})
                file = _vsp3_norm(((loc0.get("artifactLocation") or {}).get("uri")))
                line = _vsp3_norm(((loc0.get("region") or {}).get("startLine")))
                items.append({"severity":sev,"tool":tool,"title":msg,"file":file,"line":line})
                if len(items) >= 4000:
                    break
        if not items:
            raise RuntimeError("sarif empty results")
        return _vsp3_sort(items, limit)

    def _vsp3_parse_generic_json(path, limit):
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            j = _json.load(f)

        # list-of-findings style
        if isinstance(j, list) and j and isinstance(j[0], dict):
            items=[]
            for fnd in j[:12000]:
                sev = _vsp3_norm_sev(_vsp3_pick(fnd, ["severity","normalized_severity","level"]))
                tool = _vsp3_pick(fnd, ["tool","source","engine"])
                title = _vsp3_pick(fnd, ["title","message","rule_id","ruleId","id"]) or "Finding"
                file = _vsp3_pick(fnd, ["file","path"])
                line = _vsp3_pick(fnd, ["line","startLine"])
                items.append({"severity":sev or "INFO","tool":tool,"title":title,"file":file,"line":line})
            if items:
                return _vsp3_sort(items, limit)

        # dict formats: try Trivy-like
        if isinstance(j, dict):
            items=[]
            # Trivy: Results -> Vulnerabilities
            if isinstance(j.get("Results"), list):
                for r in j["Results"]:
                    for v in (r.get("Vulnerabilities") or []):
                        sev = _vsp3_norm_sev(v.get("Severity"))
                        title = _vsp3_norm(v.get("Title")) or _vsp3_norm(v.get("VulnerabilityID")) or "Vuln"
                        pkg = _vsp3_norm(v.get("PkgName"))
                        file = _vsp3_norm(r.get("Target")) or pkg
                        items.append({"severity":sev,"tool":"trivy","title":title,"file":file,"line":""})
                        if len(items)>=12000: break
            # Grype: matches
            if isinstance(j.get("matches"), list):
                for m in j["matches"]:
                    vuln = m.get("vulnerability") or {}
                    sev = _vsp3_norm_sev(vuln.get("severity"))
                    vid = _vsp3_norm(vuln.get("id")) or "Vuln"
                    pkg = ((m.get("artifact") or {}).get("name")) or ""
                    items.append({"severity":sev,"tool":"grype","title":vid,"file":_vsp3_norm(pkg),"line":""})
                    if len(items)>=12000: break
            if items:
                return _vsp3_sort(items, limit)

        raise RuntimeError("json not recognized as findings")

    @app.get("/api/vsp/top_findings_v3")
    def api_vsp_top_findings_v3():
        rid = request.args.get("rid","")
        limit = request.args.get("limit","25")
        roots = [
            "/home/test/Data/SECURITY-10-10-v4/out_ci",
            "/home/test/Data/SECURITY_BUNDLE/out",
            "/home/test/Data/SECURITY_BUNDLE/out_ci",
        ]
        run_dir = _vsp_resolve_run_dir(rid, roots) if rid else ""
        if not run_dir:
            return jsonify({"ok": False, "err": "rid not found on disk", "rid": rid, "roots": roots}), 200

        cands = _vsp3_candidates(run_dir)
        tried=[]
        all_items=[]
        for sz, full, rel in cands:
            tried.append(rel)
            low = rel.lower()
            try:
                if low.endswith(".sarif"):
                    items = _vsp3_parse_sarif(full, 300)
                else:
                    items = _vsp3_parse_generic_json(full, 300)
                all_items.extend(items)
                if len(all_items) >= 120:
                    break
            except Exception:
                continue

        if not all_items:
            return jsonify({
                "ok": False,
                "rid": rid,
                "err": "no findings found in tool outputs (scan)",
                "tried": tried[:25],
                "hint": "This run seems to have counts only; exporters produced empty CSV/SARIF. Check tool raw outputs exist under run dir.",
            }), 200

        top = _vsp3_sort(all_items, limit)
        return jsonify({
            "ok": True,
            "rid": rid,
            "source": "scan:any_tool_outputs",
            "items": top,
            "scanned": len(cands),
            "tried_sample": tried[:12],
        }), 200
    # ===================== /VSP_P0_TOPFIND_API_V3_SCAN_ANY_V1 =====================
    """).strip("\n") + "\n"

    p.write_text(s + "\n\n" + block, encoding="utf-8")
    print("[OK] appended:", MARK)
PY

python3 -m py_compile vsp_demo_app.py

echo "== [2] patch JS to call /api/vsp/top_findings_v3 =="
python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_TOPFIND_UI_CALL_API_V3"
if MARK in s:
    print("[SKIP] already patched:", MARK)
else:
    block = textwrap.dedent(r"""
    /* VSP_P0_TOPFIND_UI_CALL_API_V3
       Click -> /api/vsp/top_findings_v3 (scan any tool outputs)
    */
    (()=> {
      if (window.__vsp_topfind_ui_call_api_v3) return;
      window.__vsp_topfind_ui_call_api_v3 = true;

      const RID_LATEST = "/api/vsp/rid_latest_gate_root";
      const TOP_API = "/api/vsp/top_findings_v3";

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
        if (!j || !j.ok) throw new Error(j && (j.err || "top_findings_v3 failed"));
        render(j.items || []);
        setStatus(`Loaded: ${(j.items||[]).length} (${j.source || "scan"})`);
        console.log("[VSP][TOPFIND_API_V3] ok rid=", rid, "n=", (j.items||[]).length, "scanned=", j.scanned);
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
          catch(e){ console.warn("[VSP][TOPFIND_API_V3] failed:", e); setStatus("Load failed: " + (e?.message || String(e))); }
          finally { b2.disabled = false; b2.textContent = old || "Load top findings (25)"; }
        }, {capture:true});
        console.log("[VSP][TOPFIND_API_V3] bound");
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

echo "== [4] verify API v3 now =="
RID="$(curl -sS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[RID]=$RID"
curl -sS "$BASE/api/vsp/top_findings_v3?rid=$RID&limit=5" | head -c 900; echo

echo "[DONE] HARD refresh /vsp5 (Ctrl+Shift+R) and click Load top findings (25)."
