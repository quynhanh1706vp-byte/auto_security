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

cp -f "$PY" "${PY}.bak_topfind_v2_${TS}"
cp -f "$JS" "${JS}.bak_topfind_v2_${TS}"
echo "[BACKUP] ${PY}.bak_topfind_v2_${TS}"
echo "[BACKUP] ${JS}.bak_topfind_v2_${TS}"

echo "== [1] add /api/vsp/top_findings_v2 with HTML fallback =="
python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P0_TOPFIND_API_V2_HTML_FALLBACK"

if MARK in s:
    print("[SKIP] already patched:", MARK)
else:
    block = textwrap.dedent(r"""
    # ===================== VSP_P0_TOPFIND_API_V2_HTML_FALLBACK =====================
    import re as _vsp_re
    import html as _vsp_html

    def _vsp__strip_tags(x: str) -> str:
        x = "" if x is None else str(x)
        x = _vsp_re.sub(r"<script\b[^>]*>.*?</script>", " ", x, flags=_vsp_re.I|_vsp_re.S)
        x = _vsp_re.sub(r"<style\b[^>]*>.*?</style>", " ", x, flags=_vsp_re.I|_vsp_re.S)
        x = _vsp_re.sub(r"<[^>]+>", " ", x)
        x = _vsp_html.unescape(x)
        x = _vsp_re.sub(r"\s+", " ", x).strip()
        return x

    def _vsp__parse_loc(loc: str):
        loc = _vsp__strip_tags(loc)
        # try "...:123" at the end
        m = _vsp_re.search(r"(.*?):(\d+)\s*$", loc)
        if m:
            return m.group(1).strip(), m.group(2).strip()
        return loc, ""

    def _vsp_html_to_items(html_path, limit):
        # Parse first reasonable table rows (<tr><td>..)
        txt = Path(html_path).read_text(encoding="utf-8", errors="replace")
        trs = _vsp_re.findall(r"<tr\b[^>]*>(.*?)</tr>", txt, flags=_vsp_re.I|_vsp_re.S)
        items = []
        for tr in trs:
            tds = _vsp_re.findall(r"<td\b[^>]*>(.*?)</td>", tr, flags=_vsp_re.I|_vsp_re.S)
            if len(tds) < 3:
                continue
            cells = [_vsp__strip_tags(x) for x in tds]
            # skip header-like rows
            h0 = (cells[0] or "").lower()
            if h0 in ("severity","sev") or "severity" in h0:
                continue

            # heuristics by column count:
            # 7+: severity, tool, rule_id, title, file, line, message
            # 4+: severity, tool, title, location
            sev = _vsp_norm_sev(cells[0])
            tool = cells[1] if len(cells) > 1 else ""
            if len(cells) >= 7:
                title = cells[3] or cells[6] or "Finding"
                file = cells[4]
                line = cells[5]
            elif len(cells) >= 4:
                title = cells[2] or "Finding"
                file, line = _vsp__parse_loc(cells[3])
            else:
                title = cells[2] or "Finding"
                file = ""
                line = ""
            items.append({"severity": sev, "tool": tool, "title": title, "file": file, "line": line})
            if len(items) >= 20000:
                break
        if not items:
            raise RuntimeError("HTML has no parsable table rows")
        return _vsp_sort_top(items, limit)

    @app.get("/api/vsp/top_findings_v2")
    def api_vsp_top_findings_v2():
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

        paths = {
            "json":  os.path.join(run_dir, "findings_unified.json"),
            "csv":   os.path.join(run_dir, "reports", "findings_unified.csv"),
            "sarif": os.path.join(run_dir, "reports", "findings_unified.sarif"),
            "html":  os.path.join(run_dir, "reports", "findings_unified.html"),
        }
        has=[]
        for k,v in paths.items():
            try:
                if os.path.isfile(v):
                    has.append(k+":"+os.path.relpath(v, run_dir))
            except Exception:
                pass

        # json
        try:
            if os.path.isfile(paths["json"]) and os.path.getsize(paths["json"]) > 200:
                items = _vsp_unified_json_to_items(paths["json"], limit)
                return jsonify({"ok": True, "rid": rid, "source":"findings_unified.json", "items": items, "has": has}), 200
        except Exception as e:
            json_err = str(e)
        else:
            json_err = ""

        # csv
        try:
            if os.path.isfile(paths["csv"]) and os.path.getsize(paths["csv"]) > 80:
                items = _vsp_csv_to_items(paths["csv"], limit)
                return jsonify({"ok": True, "rid": rid, "source":"reports/findings_unified.csv", "items": items, "has": has}), 200
        except Exception as e:
            csv_err = str(e)
        else:
            csv_err = ""

        # sarif
        try:
            if os.path.isfile(paths["sarif"]) and os.path.getsize(paths["sarif"]) > 150:
                items = _vsp_sarif_to_items(paths["sarif"], limit)
                return jsonify({"ok": True, "rid": rid, "source":"reports/findings_unified.sarif", "items": items, "has": has}), 200
        except Exception as e:
            sarif_err = str(e)
        else:
            sarif_err = ""

        # html (NEW)
        try:
            if os.path.isfile(paths["html"]) and os.path.getsize(paths["html"]) > 300:
                items = _vsp_html_to_items(paths["html"], limit)
                return jsonify({"ok": True, "rid": rid, "source":"reports/findings_unified.html", "items": items, "has": has}), 200
        except Exception as e:
            html_err = str(e)
        else:
            html_err = ""

        return jsonify({
            "ok": False,
            "rid": rid,
            "err": "no usable source for top findings",
            "has": has,
            "json_err": json_err,
            "csv_err": csv_err,
            "sarif_err": sarif_err,
            "html_err": html_err,
        }), 200
    # ===================== /VSP_P0_TOPFIND_API_V2_HTML_FALLBACK =====================
    """).strip("\n") + "\n"

    p.write_text(s + "\n\n" + block, encoding="utf-8")
    print("[OK] appended:", MARK)
PY

python3 -m py_compile vsp_demo_app.py

echo "== [2] patch JS to call /api/vsp/top_findings_v2 (override bind) =="
python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_TOPFIND_UI_CALL_API_V2"
if MARK in s:
    print("[SKIP] already patched:", MARK)
else:
    block = textwrap.dedent(r"""
    /* VSP_P0_TOPFIND_UI_CALL_API_V2
       Override click -> call /api/vsp/top_findings_v2 (includes HTML fallback)
    */
    (()=> {
      if (window.__vsp_topfind_ui_call_api_v2) return;
      window.__vsp_topfind_ui_call_api_v2 = true;

      const RID_LATEST = "/api/vsp/rid_latest_gate_root";
      const TOP_API = "/api/vsp/top_findings_v2";

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
        console.log("[VSP][TOPFIND_API_V2] ok rid=", rid, "source=", j.source, "n=", (j.items||[]).length);
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
          catch(e){ console.warn("[VSP][TOPFIND_API_V2] failed:", e); setStatus("Load failed: " + (e?.message || String(e))); }
          finally { b2.disabled = false; b2.textContent = old || "Load top findings (25)"; }
        }, {capture:true});
        console.log("[VSP][TOPFIND_API_V2] bound");
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

echo "== [4] verify API v2 works =="
RID="$(curl -sS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[RID]=$RID"
curl -sS "$BASE/api/vsp/top_findings_v2?rid=$RID&limit=5" | head -c 700; echo

echo "[DONE] HARD refresh /vsp5 (Ctrl+Shift+R) and click Load top findings (25)."
echo "       Console should show: [VSP][TOPFIND_API_V2] ok ..."
