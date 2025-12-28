#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed; need grep

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }
cp -f "$W" "${W}.bak_realdata_${TS}"
echo "[BACKUP] ${W}.bak_realdata_${TS}"

# backup JS
for f in static/js/vsp_data_source_tab_v3.js static/js/vsp_settings_tab_v3.js static/js/vsp_rule_overrides_tab_v3.js; do
  [ -f "$f" ] && cp -f "$f" "${f}.bak_realdata_${TS}" || true
done

python3 - <<'PY'
from pathlib import Path
import time

W = Path("wsgi_vsp_ui_gateway.py")
s = W.read_text(encoding="utf-8", errors="replace")
marker = "VSP_TABS3_REALDATA_ENRICH_P1_V1"

if marker not in s:
    block = r'''
# ===================== {MARK} =====================
try:
    import os as __os, json as __json, time as __time
    import urllib.parse as __urlparse
    import re as __re

    __VSP_REALDATA_CACHE = {"ts": 0, "runs": None}

    def __vsp_json(start_response, obj, code=200):
        body = (__json.dumps(obj, ensure_ascii=False)).encode("utf-8")
        hdrs = [
            ("Content-Type","application/json; charset=utf-8"),
            ("Cache-Control","no-store"),
            ("Content-Length", str(len(body))),
        ]
        start_response(f"{code} OK" if code==200 else f"{code} ERROR", hdrs)
        return [body]

    def __vsp_qs(environ):
        return __urlparse.parse_qs(environ.get("QUERY_STRING",""), keep_blank_values=True)

    def __vsp_get1(qs, k, default=None):
        v = qs.get(k)
        if not v: return default
        return v[0]

    def __vsp_int(x, d):
        try: return int(x)
        except Exception: return d

    def __vsp_read_json(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return __json.load(f)
        except Exception:
            return None

    def __vsp_has_any(run_dir, rels):
        for r in rels:
            if __os.path.isfile(__os.path.join(run_dir, r)):
                return True
        return False

    def __vsp_findings_path(run_dir):
        cand = [
            "findings_unified.json",
            "reports/findings_unified.json",
            "reports/findings_unified_v1.json",
        ]
        for r in cand:
            fp = __os.path.join(run_dir, r)
            if __os.path.isfile(fp):
                return fp
        # note: csv/sarif exist but we don't parse here
        return None

    def __vsp_gate_path(run_dir):
        cand = [
            "run_gate_summary.json",
            "run_gate.json",
            "reports/run_gate_summary.json",
            "reports/run_gate.json",
        ]
        for r in cand:
            fp = __os.path.join(run_dir, r)
            if __os.path.isfile(fp):
                return fp
        return None

    def __vsp_norm_overall(x):
        x = (x or "").strip().upper()
        if x in ("GREEN","PASS","OK","SUCCESS"): return "GREEN"
        if x in ("AMBER","WARN","WARNING","DEGRADED"): return "AMBER"
        if x in ("RED","FAIL","FAILED","ERROR","BLOCK"): return "RED"
        return "UNKNOWN"

    def __vsp_guess_overall(run_dir):
        fp = __vsp_gate_path(run_dir)
        if fp:
            j = __vsp_read_json(fp)
            if isinstance(j, dict):
                for k in ("overall","overall_status","status","verdict","overall_status_final"):
                    v = j.get(k)
                    if isinstance(v, str) and v.strip():
                        return __vsp_norm_overall(v)
        # fallback: SUMMARY.txt
        sp = __os.path.join(run_dir, "SUMMARY.txt")
        if __os.path.isfile(sp):
            try:
                t = open(sp, "r", encoding="utf-8", errors="ignore").read()
                m = __re.search(r"\boverall\b\s*[:=]\s*([A-Za-z]+)", t, flags=__re.I)
                if m:
                    return __vsp_norm_overall(m.group(1))
            except Exception:
                pass
        return "UNKNOWN"

    def __vsp_list_runs(out_root="/home/test/Data/SECURITY_BUNDLE/out", cache_ttl=10):
        now = int(__time.time())
        c = __VSP_REALDATA_CACHE
        if c["runs"] is not None and (now - c["ts"]) <= cache_ttl:
            return c["runs"]

        runs = []
        try:
            if __os.path.isdir(out_root):
                for name in __os.listdir(out_root):
                    if not name.startswith("RUN_"):
                        continue
                    run_dir = __os.path.join(out_root, name)
                    if not __os.path.isdir(run_dir):
                        continue
                    try:
                        mtime = int(__os.path.getmtime(run_dir))
                    except Exception:
                        mtime = 0
                    has_findings = __vsp_findings_path(run_dir) is not None
                    has_gate = __vsp_gate_path(run_dir) is not None
                    overall = __vsp_guess_overall(run_dir)
                    runs.append((mtime, name, run_dir, has_findings, has_gate, overall))
        except Exception:
            runs = []

        runs.sort(key=lambda x: (x[0], x[1]), reverse=True)
        c["ts"] = now
        c["runs"] = runs
        return runs

    def __vsp_runs_page_payload(limit, offset):
        runs = __vsp_list_runs()
        total = len(runs)
        limit = max(1, min(limit, 200))
        offset = max(0, min(offset, total))
        page = runs[offset:offset+limit]
        items = []
        for mtime, rid, run_dir, has_findings, has_gate, overall in page:
            items.append({
                "rid": rid, "run_dir": run_dir, "mtime": mtime,
                "has_findings": bool(has_findings),
                "has_gate": bool(has_gate),
                "overall": overall,
            })
        return {
            "ok": True, "items": items,
            "limit": limit, "offset": offset, "total": total,
            "has_more": (offset + limit) < total,
            "ts": int(__time.time()),
        }

    def __vsp_runs_kpi_payload(cap=2000):
        runs = __vsp_list_runs()
        runs = runs[:max(1, min(int(cap), 5000))]
        b = {"GREEN":0,"AMBER":0,"RED":0,"UNKNOWN":0}
        hf = 0
        hg = 0
        latest = runs[0][1] if runs else ""
        for mtime, rid, run_dir, has_findings, has_gate, overall in runs:
            b[overall] = b.get(overall, 0) + 1
            if has_findings: hf += 1
            if has_gate: hg += 1
        return {
            "ok": True,
            "total_runs": len(runs),
            "latest_rid": latest,
            "by_overall": b,
            "has_findings": hf,
            "has_gate": hg,
            "ts": int(__time.time()),
        }

    def __vsp_extract_items(j):
        if isinstance(j, list):
            return j
        if isinstance(j, dict):
            for k in ("items","findings","results"):
                v = j.get(k)
                if isinstance(v, list):
                    return v
        return []

    def __vsp_norm_sev(x):
        x = (x or "").strip().upper()
        if x in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"):
            return x
        # some tools use ERROR/WARN/NOTE
        if x in ("ERROR","FATAL"): return "HIGH"
        if x in ("WARN","WARNING"): return "MEDIUM"
        if x in ("NOTE","NOTICE"): return "INFO"
        return "INFO"

    def __vsp_findings_payload(rid, limit, offset, q=""):
        runs = __vsp_list_runs()
        chosen = None
        if rid:
            for mtime, r, run_dir, hf, hg, ov in runs:
                if r == rid:
                    chosen = (mtime, r, run_dir, hf, hg, ov)
                    break
        if chosen is None:
            # default: first run that has findings, else first run
            for row in runs:
                if row[3]:
                    chosen = row
                    break
            if chosen is None and runs:
                chosen = runs[0]

        if not chosen:
            return {"ok": True, "rid":"", "run_dir":"", "items":[], "counts": {"TOTAL":0}, "limit":limit, "offset":offset, "total":0,
                    "reason":"NO_RUNS_FOUND", "ts": int(__time.time())}

        mtime, rid2, run_dir, has_findings, has_gate, overall = chosen
        fp = __vsp_findings_path(run_dir)
        if not fp:
            # report reason + common paths
            return {
                "ok": True, "rid": rid2, "run_dir": run_dir,
                "items": [], "counts": {"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0,"INFO":0,"TRACE":0,"TOTAL":0},
                "limit": limit, "offset": offset, "total": 0,
                "overall": overall,
                "reason": "NO_findings_unified.json (try run SECURITY_BUNDLE unify/pack_report)",
                "hint_paths": [
                    f"{run_dir}/findings_unified.json",
                    f"{run_dir}/reports/findings_unified.json",
                    f"{run_dir}/reports/findings_unified.csv",
                    f"{run_dir}/reports/findings_unified.sarif",
                ],
                "ts": int(__time.time())
            }

        raw = __vsp_read_json(fp)
        items = __vsp_extract_items(raw)

        # optional search
        q = (q or "").strip().lower()
        if q:
            def hit(it):
                try:
                    s = __json.dumps(it, ensure_ascii=False).lower()
                    return q in s
                except Exception:
                    return False
            items = [x for x in items if hit(x)]

        total = len(items)
        limit = max(1, min(limit, 200))
        offset = max(0, min(offset, total))
        page = items[offset:offset+limit]

        counts = {"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0,"INFO":0,"TRACE":0,"TOTAL": total}
        for it in items:
            sev = __vsp_norm_sev(it.get("severity_norm") or it.get("severity") or it.get("level") or it.get("impact"))
            counts[sev] = counts.get(sev,0) + 1

        return {
            "ok": True,
            "rid": rid2, "run_dir": run_dir, "overall": overall,
            "items": page, "counts": counts,
            "limit": limit, "offset": offset, "total": total,
            "findings_path": fp,
            "ts": int(__time.time()),
        }

    def __vsp_wrap_wsgi(inner):
        def _app(environ, start_response):
            path = environ.get("PATH_INFO","") or ""
            qs = __vsp_qs(environ)

            # unify endpoints (accept both v1/v2 names)
            if path in ("/api/ui/runs_page_v1", "/api/ui/runs_page", "/api/ui/runs_page_v2"):
                limit = __vsp_int(__vsp_get1(qs,"limit","20"), 20)
                offset = __vsp_int(__vsp_get1(qs,"offset","0"), 0)
                return __vsp_json(start_response, __vsp_runs_page_payload(limit, offset), 200)

            if path in ("/api/ui/runs_kpi_v1", "/api/ui/runs_kpi", "/api/ui/runs_kpi_v2"):
                cap = __vsp_int(__vsp_get1(qs,"cap","2000"), 2000)
                return __vsp_json(start_response, __vsp_runs_kpi_payload(cap), 200)

            # upgrade runs_v2: now supports offset + extras
            if path == "/api/ui/runs_v2":
                limit = __vsp_int(__vsp_get1(qs,"limit","200"), 200)
                offset = __vsp_int(__vsp_get1(qs,"offset","0"), 0)
                return __vsp_json(start_response, __vsp_runs_page_payload(limit, offset), 200)

            # findings: accept rid/limit/offset/q
            if path in ("/api/ui/findings_v2", "/api/ui/findings_v1"):
                rid = __vsp_get1(qs, "rid", "") or ""
                limit = __vsp_int(__vsp_get1(qs,"limit","50"), 50)
                offset = __vsp_int(__vsp_get1(qs,"offset","0"), 0)
                q = __vsp_get1(qs, "q", "") or ""
                return __vsp_json(start_response, __vsp_findings_payload(rid, limit, offset, q=q), 200)

            return inner(environ, start_response)
        return _app

    __inner = globals().get("application") or globals().get("app")
    if __inner:
        __wrapped = __vsp_wrap_wsgi(__inner)
        globals()["application"] = __wrapped
        globals()["app"] = __wrapped
except Exception:
    pass
# =================== END {MARK} ===================
'''.replace("{MARK}", marker)

    s = s + "\n" + block
    W.write_text(s, encoding="utf-8")
    print("[OK] appended:", marker)
else:
    print("[OK] marker already present:", marker)
PY

# Patch Data Source JS to show "real reason" and pick run with findings
cat > static/js/vsp_data_source_tab_v3.js <<'JS'
/* VSP Data Source tab v3 (realdata) */
(function(){
  if (window.__VSP_DS_V3_REALDATA) return;
  window.__VSP_DS_V3_REALDATA = true;

  const root = document.getElementById("vsp_tab_root");
  if (!root) return;

  const api = async (url, opt={}) => {
    const r = await fetch(url, Object.assign({credentials:"same-origin"}, opt));
    const j = await r.json().catch(()=>({ok:false,error:"bad_json"}));
    if (!j || j.ok !== true) throw new Error((j && (j.error||j.reason)) || ("API_FAIL "+url));
    return j;
  };

  const el = (t, a={}, c=[])=>{
    const n=document.createElement(t);
    for (const k in a){
      if (k==="style") Object.assign(n.style, a[k]);
      else if (k.startsWith("on")) n.addEventListener(k.slice(2), a[k]);
      else n.setAttribute(k, a[k]);
    }
    (Array.isArray(c)?c:[c]).forEach(x=>{
      if (x==null) return;
      if (typeof x==="string") n.appendChild(document.createTextNode(x));
      else n.appendChild(x);
    });
    return n;
  };

  let state = { rid:"", limit:50, offset:0, q:"" };

  const header = el("div", {style:{display:"flex",gap:"10px",alignItems:"center",flexWrap:"wrap",margin:"6px 0 12px 0"}}, []);
  const sel = el("select", {style:{padding:"6px 8px",minWidth:"360px"}}, []);
  const qin = el("input", {placeholder:"search in findings (free text)", style:{padding:"6px 8px",minWidth:"260px"}});
  const btnReload = el("button", {style:{padding:"6px 10px",cursor:"pointer"}, onclick:()=>loadFindings(true)}, ["Reload"]);
  const stat = el("div", {style:{margin:"8px 0",opacity:"0.9"}}, ["Loading..."]);
  const table = el("div", {style:{marginTop:"8px"}}, []);

  header.appendChild(el("div",{style:{fontWeight:"700"}},["Data Source"]));
  header.appendChild(sel);
  header.appendChild(qin);
  header.appendChild(btnReload);

  root.innerHTML = "";
  root.appendChild(header);
  root.appendChild(stat);
  root.appendChild(table);

  qin.addEventListener("change", ()=>{ state.q = qin.value||""; state.offset=0; loadFindings(false); });

  function renderCounts(j){
    const c = j.counts || {};
    const msg = `RID=${j.rid} • TOTAL=${c.TOTAL||0} • CRITICAL=${c.CRITICAL||0} HIGH=${c.HIGH||0} MEDIUM=${c.MEDIUM||0} LOW=${c.LOW||0} INFO=${c.INFO||0} TRACE=${c.TRACE||0}`;
    return msg;
  }

  function renderRows(items){
    table.innerHTML = "";
    if (!items || !items.length){
      table.appendChild(el("div",{style:{padding:"10px",border:"1px dashed #666",borderRadius:"8px"}},[
        "No findings to show."
      ]));
      return;
    }
    const t = el("table",{style:{width:"100%",borderCollapse:"collapse"}});
    const th = (x)=>el("th",{style:{textAlign:"left",borderBottom:"1px solid #555",padding:"8px"}},[x]);
    const td = (x)=>el("td",{style:{verticalAlign:"top",borderBottom:"1px solid #333",padding:"8px"}},[x]);

    t.appendChild(el("thead",{},[
      el("tr",{},[
        th("Severity"), th("Tool"), th("Title"), th("File"), th("Line"), th("Rule")
      ])
    ]));

    const tb = el("tbody");
    for (const it of items){
      const sev = (it.severity_norm||it.severity||it.level||"INFO")+"";
      const tool = (it.tool||it.engine||it.source||"")+"";
      const title = (it.title||it.message||it.desc||it.check_name||it.rule_name||"")+"";
      const file = (it.file||it.path||it.filename||((it.location&&it.location.path)||""))+"";
      const line = (it.line||it.start_line||((it.location&&it.location.line)||""))+"";
      const rule = (it.rule_id||it.rule||it.check_id||it.id||"")+"";
      tb.appendChild(el("tr",{},[
        td(sev), td(tool), td(title||"(no title)"), td(file), td(String(line||"")), td(rule)
      ]));
    }
    t.appendChild(tb);
    table.appendChild(t);
  }

  async function loadRunsAndPick(){
    const j = await api("/api/ui/runs_v2?limit=200&offset=0");
    sel.innerHTML = "";
    let picked = "";
    for (const it of (j.items||[])){
      const label = `${it.rid} ${it.has_findings?"[F]":""}${it.has_gate?"[G]":""} ${it.overall||""}`.trim();
      sel.appendChild(el("option",{value:it.rid},[label]));
      if (!picked && it.has_findings) picked = it.rid;
    }
    if (!picked && (j.items||[]).length) picked = j.items[0].rid;
    state.rid = picked || "";
    sel.value = state.rid;
    sel.addEventListener("change", ()=>{ state.rid = sel.value; state.offset=0; loadFindings(false); });
  }

  async function loadFindings(force=false){
    if (!state.rid) return;
    stat.textContent = "Loading findings...";
    table.innerHTML = "";
    try{
      const url = `/api/ui/findings_v2?rid=${encodeURIComponent(state.rid)}&limit=${state.limit}&offset=${state.offset}&q=${encodeURIComponent(state.q||"")}`;
      const j = await api(url);
      stat.textContent = renderCounts(j);
      if (j.reason){
        table.appendChild(el("div",{style:{margin:"10px 0",padding:"10px",border:"1px dashed #666",borderRadius:"8px"}},[
          "Reason: "+j.reason,
          el("div",{style:{marginTop:"6px",opacity:"0.9"}},["Hint paths: "+(j.hint_paths||[]).join(" , ")])
        ]));
      }
      renderRows(j.items||[]);
      if (j.findings_path){
        table.appendChild(el("div",{style:{marginTop:"8px",opacity:"0.8",fontSize:"12px"}},["Source: "+j.findings_path]));
      }
    }catch(e){
      stat.textContent = "Error: "+(e && e.message ? e.message : String(e));
      table.innerHTML = "";
      table.appendChild(el("div",{style:{padding:"10px",border:"1px solid #a44",borderRadius:"8px"}},[
        "Failed to load findings. Open console for details."
      ]));
    }
  }

  (async ()=>{
    await loadRunsAndPick();
    await loadFindings(true);
  })();
})();
JS

echo "[OK] wrote static/js/vsp_data_source_tab_v3.js (realdata renderer)"

# Settings/RuleOverrides: keep existing v3 files (they already POST OK),
# but ensure they show something even when empty (minimal empty-state).
for f in ("static/js/vsp_settings_tab_v3.js","static/js/vsp_rule_overrides_tab_v3.js"):
    pass
PY

echo "== py_compile =="
python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== restart =="
bash bin/p1_ui_8910_single_owner_start_v2.sh >/dev/null 2>&1 || bash bin/p1_ui_8910_single_owner_start_v2.sh

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== quick verify =="
echo "--- runs_kpi_v1"; curl -fsS "$BASE/api/ui/runs_kpi_v1" | head -c 260; echo
echo "--- runs_v2(1)";  curl -fsS "$BASE/api/ui/runs_v2?limit=1&offset=0" | head -c 260; echo
echo "--- findings_v2(latest with findings)"; curl -fsS "$BASE/api/ui/findings_v2?limit=1&offset=0" | head -c 260; echo
echo "[DONE] realdata enrich applied. Now hard-refresh /data_source."
