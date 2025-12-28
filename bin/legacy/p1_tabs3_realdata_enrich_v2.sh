#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed; need grep; need ls; need head

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

# nếu wsgi đang lỗi cú pháp thì restore backup gần nhất
if ! python3 -m py_compile "$W" >/dev/null 2>&1; then
  echo "[WARN] $W has SyntaxError -> restoring best backup..."
  BAK="$(ls -1t ${W}.bak_runs_kpi_fix_* 2>/dev/null | head -n1 || true)"
  [ -z "$BAK" ] && BAK="$(ls -1t ${W}.bak_apiui_shim_* 2>/dev/null | head -n1 || true)"
  [ -z "$BAK" ] && BAK="$(ls -1t ${W}.bak_tabs3_bundle_fix1_* 2>/dev/null | head -n1 || true)"
  [ -z "$BAK" ] && BAK="$(ls -1t ${W}.bak_* 2>/dev/null | head -n1 || true)"
  [ -n "$BAK" ] || { echo "[ERR] no backup found"; exit 2; }
  echo "[RESTORE] $BAK -> $W"
  cp -f "$BAK" "$W"
fi

cp -f "$W" "${W}.bak_realdata_v2_${TS}"
echo "[BACKUP] ${W}.bak_realdata_v2_${TS}"

# backup JS
for f in static/js/vsp_data_source_tab_v3.js static/js/vsp_tabs3_common_v3.js; do
  [ -f "$f" ] && cp -f "$f" "${f}.bak_realdata_v2_${TS}" || true
done

python3 - <<'PY'
from pathlib import Path
import time

W = Path("wsgi_vsp_ui_gateway.py")
s = W.read_text(encoding="utf-8", errors="replace")
marker = "VSP_TABS3_REALDATA_ENRICH_P1_V2"

if marker not in s:
    block = r'''
# ===================== {MARK} =====================
# Enrich /api/ui/runs_v2 + /api/ui/findings_v2 (real data + reasons)
try:
    import os as __os, json as __json, time as __time
    import urllib.parse as __urlparse
    import re as __re

    def __vsp__json(start_response, obj, code=200):
        body = (__json.dumps(obj, ensure_ascii=False)).encode("utf-8")
        hdrs = [
            ("Content-Type","application/json; charset=utf-8"),
            ("Cache-Control","no-store"),
            ("Content-Length", str(len(body))),
        ]
        start_response(f"{code} OK" if code==200 else f"{code} ERROR", hdrs)
        return [body]

    def __vsp__qs(environ):
        return __urlparse.parse_qs(environ.get("QUERY_STRING",""), keep_blank_values=True)

    def __vsp__get1(qs, k, default=None):
        v = qs.get(k)
        if not v: return default
        return v[0]

    def __vsp__int(x, d):
        try: return int(x)
        except Exception: return d

    def __vsp__read_json(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return __json.load(f)
        except Exception:
            return None

    def __vsp__findings_path(run_dir):
        cand = [
            "findings_unified.json",
            "reports/findings_unified.json",
            "reports/findings_unified_v1.json",
        ]
        for r in cand:
            fp = __os.path.join(run_dir, r)
            if __os.path.isfile(fp):
                return fp
        return None

    def __vsp__gate_path(run_dir):
        cand = [
            "run_gate_summary.json",
            "run_gate.json",
            "reports/run_gate_summary.json",
            "reports/run_gate.json",
            "verdict_4t.json",
        ]
        for r in cand:
            fp = __os.path.join(run_dir, r)
            if __os.path.isfile(fp):
                return fp
        return None

    def __vsp__norm_overall(x):
        x = (x or "").strip().upper()
        if x in ("GREEN","PASS","OK","SUCCESS"): return "GREEN"
        if x in ("AMBER","WARN","WARNING","DEGRADED"): return "AMBER"
        if x in ("RED","FAIL","FAILED","ERROR","BLOCK"): return "RED"
        return "UNKNOWN"

    def __vsp__guess_overall(run_dir):
        gp = __vsp__gate_path(run_dir)
        if gp:
            j = __vsp__read_json(gp)
            if isinstance(j, dict):
                for k in ("overall_status","overall","status","verdict","overall_status_final"):
                    v = j.get(k)
                    if isinstance(v, str) and v.strip():
                        return __vsp__norm_overall(v)
        sp = __os.path.join(run_dir, "SUMMARY.txt")
        if __os.path.isfile(sp):
            try:
                t = open(sp, "r", encoding="utf-8", errors="ignore").read()
                m = __re.search(r"\boverall\b\s*[:=]\s*([A-Za-z]+)", t, flags=__re.I)
                if m:
                    return __vsp__norm_overall(m.group(1))
            except Exception:
                pass
        return "UNKNOWN"

    def __vsp__list_runs(out_root="/home/test/Data/SECURITY_BUNDLE/out", cap=2000):
        rows = []
        if not __os.path.isdir(out_root):
            return rows
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
            fp = __vsp__findings_path(run_dir)
            has_findings = bool(fp)
            has_gate = bool(__vsp__gate_path(run_dir))
            overall = __vsp__guess_overall(run_dir)
            rows.append((mtime, name, run_dir, has_findings, has_gate, overall, fp or ""))
        rows.sort(key=lambda x: (x[0], x[1]), reverse=True)
        return rows[:max(1, min(int(cap), 5000))]

    def __vsp__runs_payload(limit, offset):
        rows = __vsp__list_runs()
        total = len(rows)
        limit = max(1, min(int(limit), 200))
        offset = max(0, min(int(offset), total))
        page = rows[offset:offset+limit]
        items = []
        for mtime, rid, run_dir, has_findings, has_gate, overall, fpath in page:
            items.append({
                "rid": rid, "run_dir": run_dir, "mtime": mtime,
                "has_findings": bool(has_findings),
                "has_gate": bool(has_gate),
                "overall": overall,
                "findings_path": fpath if fpath else None,
            })
        return {
            "ok": True,
            "items": items,
            "limit": limit,
            "offset": offset,
            "total": total,
            "has_more": (offset + limit) < total,
            "ts": int(__time.time()),
        }

    def __vsp__extract_items(j):
        if isinstance(j, list):
            return j
        if isinstance(j, dict):
            for k in ("items","findings","results"):
                v = j.get(k)
                if isinstance(v, list):
                    return v
        return []

    def __vsp__norm_sev(x):
        x = (x or "").strip().upper()
        if x in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"):
            return x
        if x in ("ERROR","FATAL"): return "HIGH"
        if x in ("WARN","WARNING"): return "MEDIUM"
        if x in ("NOTE","NOTICE"): return "INFO"
        return "INFO"

    def __vsp__findings_payload(rid, limit, offset, q=""):
        rows = __vsp__list_runs()
        chosen = None
        if rid:
            for row in rows:
                if row[1] == rid:
                    chosen = row
                    break
        if chosen is None:
            for row in rows:
                if row[3]:  # has_findings
                    chosen = row
                    break
        if chosen is None and rows:
            chosen = rows[0]

        if not chosen:
            return {
                "ok": True, "rid":"", "run_dir":"", "items":[],
                "counts":{"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0,"INFO":0,"TRACE":0,"TOTAL":0},
                "limit": limit, "offset": offset, "total": 0,
                "reason":"NO_RUNS_FOUND", "ts": int(__time.time()),
            }

        mtime, rid2, run_dir, has_findings, has_gate, overall, fpath = chosen
        fp = fpath or __vsp__findings_path(run_dir)
        if not fp:
            return {
                "ok": True, "rid": rid2, "run_dir": run_dir, "overall": overall,
                "items": [],
                "counts":{"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0,"INFO":0,"TRACE":0,"TOTAL":0},
                "limit": limit, "offset": offset, "total": 0,
                "reason":"NO_findings_unified.json",
                "hint_paths":[
                    f"{run_dir}/findings_unified.json",
                    f"{run_dir}/reports/findings_unified.json",
                    f"{run_dir}/reports/findings_unified.csv",
                    f"{run_dir}/reports/findings_unified.sarif",
                ],
                "ts": int(__time.time()),
            }

        raw = __vsp__read_json(fp)
        items = __vsp__extract_items(raw)

        q = (q or "").strip().lower()
        if q:
            def hit(it):
                try:
                    return q in __json.dumps(it, ensure_ascii=False).lower()
                except Exception:
                    return False
            items = [it for it in items if hit(it)]

        total = len(items)
        limit = max(1, min(int(limit), 200))
        offset = max(0, min(int(offset), total))
        page = items[offset:offset+limit]

        counts = {"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0,"INFO":0,"TRACE":0,"TOTAL": total}
        for it in items:
            sev = __vsp__norm_sev(it.get("severity_norm") or it.get("severity") or it.get("level") or it.get("impact"))
            counts[sev] = counts.get(sev,0) + 1

        return {
            "ok": True,
            "rid": rid2, "run_dir": run_dir, "overall": overall,
            "items": page, "counts": counts,
            "limit": limit, "offset": offset, "total": total,
            "findings_path": fp,
            "ts": int(__time.time()),
        }

    def __vsp__wrap_wsgi(inner):
        def _app(environ, start_response):
            path = environ.get("PATH_INFO","") or ""
            qs = __vsp__qs(environ)

            if path == "/api/ui/runs_v2":
                limit = __vsp__int(__vsp__get1(qs, "limit", "200"), 200)
                offset = __vsp__int(__vsp__get1(qs, "offset", "0"), 0)
                return __vsp__json(start_response, __vsp__runs_payload(limit, offset), 200)

            if path in ("/api/ui/findings_v2", "/api/ui/findings_v1"):
                rid = __vsp__get1(qs, "rid", "") or ""
                limit = __vsp__int(__vsp__get1(qs, "limit", "50"), 50)
                offset = __vsp__int(__vsp__get1(qs, "offset", "0"), 0)
                q = __vsp__get1(qs, "q", "") or ""
                return __vsp__json(start_response, __vsp__findings_payload(rid, limit, offset, q=q), 200)

            return inner(environ, start_response)
        return _app

    __inner = globals().get("application") or globals().get("app")
    if __inner:
        __wrapped = __vsp__wrap_wsgi(__inner)
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

# rewrite Data Source JS (safe)
JS = Path("static/js/vsp_data_source_tab_v3.js")
JS.parent.mkdir(parents=True, exist_ok=True)
JS.write_text(r'''/* VSP Data Source tab v3 (real data) */
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

  root.innerHTML = "";
  const header = el("div", {style:{display:"flex",gap:"10px",alignItems:"center",flexWrap:"wrap",margin:"6px 0 12px 0"}}, []);
  const sel = el("select", {style:{padding:"6px 8px",minWidth:"360px"}}, []);
  const qin = el("input", {placeholder:"search in findings", style:{padding:"6px 8px",minWidth:"260px"}});
  const btn = el("button", {style:{padding:"6px 10px",cursor:"pointer"}, onclick:()=>loadFindings(true)}, ["Reload"]);
  const stat = el("div", {style:{margin:"8px 0",opacity:"0.9"}}, ["Loading..."]);
  const table = el("div", {style:{marginTop:"8px"}}, []);

  header.appendChild(el("div",{style:{fontWeight:"700"}},["Data Source"]));
  header.appendChild(sel);
  header.appendChild(qin);
  header.appendChild(btn);

  root.appendChild(header);
  root.appendChild(stat);
  root.appendChild(table);

  qin.addEventListener("change", ()=>{ state.q = qin.value||""; state.offset=0; loadFindings(false); });

  function renderCounts(j){
    const c = j.counts || {};
    return `RID=${j.rid} • TOTAL=${c.TOTAL||0} • CRITICAL=${c.CRITICAL||0} HIGH=${c.HIGH||0} MEDIUM=${c.MEDIUM||0} LOW=${c.LOW||0} INFO=${c.INFO||0} TRACE=${c.TRACE||0}`;
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
      const sev = String(it.severity_norm||it.severity||it.level||"INFO");
      const tool = String(it.tool||it.engine||it.source||"");
      const title = String(it.title||it.message||it.desc||it.check_name||it.rule_name||"(no title)");
      const file = String(it.file||it.path||it.filename||((it.location&&it.location.path)||""));
      const line = String(it.line||it.start_line||((it.location&&it.location.line)||"")||"");
      const rule = String(it.rule_id||it.rule||it.check_id||it.id||"");
      tb.appendChild(el("tr",{},[
        td(sev), td(tool), td(title), td(file), td(line), td(rule)
      ]));
    }
    t.appendChild(tb);
    table.appendChild(t);
  }

  async function loadRunsPick(){
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

  async function loadFindings(){
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
          el("div",{style:{marginTop:"6px",opacity:"0.9"}},["Hint: "+(j.hint_paths||[]).join(" , ")])
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
        "Failed to load findings. (Check console)"
      ]));
    }
  }

  (async ()=>{
    await loadRunsPick();
    await loadFindings();
  })();
})();
''', encoding="utf-8")
print("[OK] rewrote static/js/vsp_data_source_tab_v3.js")
PY

echo "== py_compile =="
python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== restart =="
bash bin/p1_ui_8910_single_owner_start_v2.sh >/dev/null 2>&1 || bash bin/p1_ui_8910_single_owner_start_v2.sh

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== verify =="
echo "--- runs_v2";     curl -fsS "$BASE/api/ui/runs_v2?limit=3&offset=0" | head -c 320; echo
echo "--- findings_v2"; curl -fsS "$BASE/api/ui/findings_v2?limit=1&offset=0" | head -c 320; echo

echo "[DONE] realdata v2 applied. Now hard-refresh /data_source (Ctrl+Shift+R)."
