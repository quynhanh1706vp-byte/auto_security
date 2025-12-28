#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== [0] sanity =="
[ -f vsp_demo_app.py ] || { echo "[ERR] missing vsp_demo_app.py"; exit 1; }
[ -f static/js/vsp_datasource_tab_v1.js ] || { echo "[ERR] missing static/js/vsp_datasource_tab_v1.js"; exit 1; }
[ -f static/js/vsp_dashboard_enhance_v1.js ] || { echo "[ERR] missing static/js/vsp_dashboard_enhance_v1.js"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"

echo "== [1] add REAL findings_preview_v2 (filesystem-backed) =="
cp -f vsp_demo_app.py "vsp_demo_app.py.bak_real_findings_v2_${TS}"
python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_FINDINGS_PREVIEW_V2_FS_V1 ==="
if TAG in s:
    print("[OK] findings_preview_v2 already present, skip")
    raise SystemExit(0)

BLOCK = r'''
# === VSP_FINDINGS_PREVIEW_V2_FS_V1 ===
# REAL findings preview (NO DEMO): read findings_unified.json from CI run dir, filter + limit.
from pathlib import Path as _Path
import json as _json
import glob as _glob

@app.route("/api/vsp/findings_preview_v2/<path:rid>")
def api_vsp_findings_preview_v2_fs(rid):
    try:
        rid_in = (rid or "").strip()
        rid_norm = rid_in
        if rid_norm.startswith("RUN_"):
            rid_norm = rid_norm[4:]
        rid_norm = rid_norm.strip()

        # Best-effort resolve CI dir (fast path) + fallback glob
        bases = [
            "/home/test/Data/SECURITY-10-10-v4/out_ci",
            "/home/test/Data/SECURITY_BUNDLE/out_ci",
            "/home/test/Data/SECURITY_BUNDLE/out",
        ]
        ci_dir = None
        for b in bases:
            cand = _Path(b) / rid_norm
            if cand.is_dir():
                ci_dir = str(cand)
                break

        if not ci_dir and rid_norm:
            hits = _glob.glob(f"/home/test/Data/**/out_ci/{rid_norm}", recursive=True)
            if hits:
                ci_dir = hits[0]

        if not ci_dir:
            return {
                "ok": False,
                "warning": "ci_run_dir_not_found",
                "rid": rid_in,
                "rid_norm": rid_norm,
                "total": 0,
                "items_n": 0,
                "items": [],
                "file": None,
            }

        # Prefer reports/findings_unified.json
        cands = [
            _Path(ci_dir) / "reports" / "findings_unified.json",
            _Path(ci_dir) / "findings_unified.json",
        ]
        fpath = None
        for c in cands:
            try:
                if c.is_file() and c.stat().st_size > 0:
                    fpath = str(c)
                    break
            except Exception:
                pass

        if not fpath:
            return {
                "ok": True,
                "warning": "findings_file_not_found",
                "rid": rid_in,
                "rid_norm": rid_norm,
                "total": 0,
                "items_n": 0,
                "items": [],
                "file": None,
            }

        data = _json.load(open(fpath, "r", encoding="utf-8", errors="ignore"))
        if isinstance(data, dict) and "items" in data:
            items = data.get("items") or []
        elif isinstance(data, list):
            items = data
        else:
            items = []

        def norm_sev(x):
            return str(x or "").upper().strip()

        q = (request.args.get("q") or request.args.get("text") or "").strip().lower()
        sev = norm_sev(request.args.get("sev") or request.args.get("severity") or "")
        tool = (request.args.get("tool") or "").strip().lower()
        cwe = (request.args.get("cwe") or "").strip().upper()

        show_supp = request.args.get("show_suppressed") or request.args.get("suppressed") or ""
        show_supp = str(show_supp).lower() in ("1","true","yes","y","on")

        def is_supp(it):
            if not isinstance(it, dict):
                return False
            if it.get("suppressed") or it.get("is_suppressed"):
                return True
            flags = it.get("flags") or {}
            return bool(flags.get("suppressed"))

        out = []
        for it in items:
            if not isinstance(it, dict):
                continue
            if (not show_supp) and is_supp(it):
                continue
            if sev and norm_sev(it.get("severity")) != sev:
                continue
            if tool and str(it.get("tool") or "").lower() != tool:
                continue
            if cwe and str(it.get("cwe") or "").upper() != cwe:
                continue
            if q:
                blob = " ".join([
                    str(it.get("title","")),
                    str(it.get("file","")),
                    str(it.get("rule","")),
                    str(it.get("cwe","")),
                    str(it.get("tool","")),
                ]).lower()
                if q not in blob:
                    continue
            out.append(it)

        total = len(out)
        try:
            limit = int(request.args.get("limit") or 200)
        except Exception:
            limit = 200
        if limit < 1: limit = 1
        if limit > 2000: limit = 2000

        return {
            "ok": True,
            "rid": rid_in,
            "rid_norm": rid_norm,
            "ci_run_dir": ci_dir,
            "file": fpath,
            "total": total,
            "items_n": min(total, limit),
            "items": out[:limit],
        }
    except Exception as e:
        return {
            "ok": False,
            "warning": "exception",
            "error": str(e),
            "total": 0,
            "items_n": 0,
            "items": [],
            "file": None,
        }
# === /VSP_FINDINGS_PREVIEW_V2_FS_V1 ===
'''.lstrip("\n")

# insert near existing findings routes if possible, else append
m = re.search(r'@app\.route\(\s*["\']/api/vsp/findings_preview_v1', s)
if m:
    ins = m.start()
    s2 = s[:ins] + BLOCK + "\n\n" + s[ins:]
else:
    s2 = s + "\n\n" + BLOCK + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] inserted findings_preview_v2 FS")
PY
python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile vsp_demo_app.py"

echo "== [2] patch datasource JS: use findings_preview_v2 + remove demo block if any =="
F="static/js/vsp_datasource_tab_v1.js"
cp -f "$F" "${F}.bak_realdata_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p = Path("static/js/vsp_datasource_tab_v1.js")
t = p.read_text(encoding="utf-8", errors="ignore")

# remove demo button block if exists
t = re.sub(r"/\*\s*===\s*VSP_P2_DS_DEMO_BUTTON_V1\s*===\s*\*/.*?/\*\s*===\s*/VSP_P2_DS_DEMO_BUTTON_V1\s*===\s*\*/\s*",
           "", t, flags=re.S)

# switch endpoint v1 -> v2 (only for findings_preview)
t = t.replace("/api/vsp/findings_preview_v1/", "/api/vsp/findings_preview_v2/")

# also if code builds URLs without trailing slash
t = t.replace("/api/vsp/findings_preview_v1", "/api/vsp/findings_preview_v2")

p.write_text(t, encoding="utf-8")
print("[OK] datasource: endpoint -> v2, demo removed if present")
PY

node --check static/js/vsp_datasource_tab_v1.js
echo "[OK] node --check datasource"

echo "== [3] patch dashboard enhance: always render 8 tools (missing => NOT_RUN) =="
G="static/js/vsp_dashboard_enhance_v1.js"
cp -f "$G" "${G}.bak_8tools_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_dashboard_enhance_v1.js")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "// === VSP_P2_FORCE_8TOOLS_V1 ==="
if TAG in t:
    print("[OK] 8tools patch already present, skip")
    raise SystemExit(0)

PATCH = r'''
// === VSP_P2_FORCE_8TOOLS_V1 ===
// Force Gate Summary to show 8 tools (commercial). Missing tool => NOT_RUN/0.
// Also capture latest /api/vsp/run_status_v2 JSON via fetch clone.
(function(){
  try{
    if (window.__VSP_P2_FORCE_8TOOLS_V1_INSTALLED) return;
    window.__VSP_P2_FORCE_8TOOLS_V1_INSTALLED = true;

    const TOOL_ORDER = ["BANDIT","CODEQL","GITLEAKS","GRYPE","KICS","SEMGREP","SYFT","TRIVY"];
    window.__VSP_TOOL_ORDER = TOOL_ORDER;

    const origFetch = window.fetch;
    window.fetch = async function(){
      const resp = await origFetch.apply(this, arguments);
      try{
        const u = (typeof arguments[0] === "string") ? arguments[0] : (arguments[0] && arguments[0].url) || "";
        if (u.includes("/api/vsp/run_status_v2")) {
          resp.clone().json().then(j => {
            window.__VSP_LAST_STATUS_V2 = j;
            try { window.__VSP_RENDER_GATE_8TOOLS(); } catch(e){}
          }).catch(()=>{});
        }
      }catch(e){}
      return resp;
    };

    function pickToolObj(st, T){
      if (!st || typeof st !== "object") return null;
      const k = T.toLowerCase();
      return st[k + "_summary"] || st[k] || (st.tools && (st.tools[T] || st.tools[k])) || null;
    }

    function normVerdict(v){
      v = String(v || "").toUpperCase();
      if (!v) return "NOT_RUN";
      return v;
    }

    window.__VSP_RENDER_GATE_8TOOLS = function(){
      const st = window.__VSP_LAST_STATUS_V2;
      // find a plausible gate summary container
      const box =
        document.querySelector("#vsp-gate-summary") ||
        document.querySelector("#gate-summary") ||
        document.querySelector("[data-vsp-gate-summary]") ||
        document.querySelector(".vsp-gate-summary") ||
        document.querySelector("section#vsp-pane-dashboard .vsp-card .vsp-gate") ||
        null;
      if (!box) return;

      // create or find list container
      let list = box.querySelector(".vsp-gate-list");
      if (!list) {
        list = document.createElement("div");
        list.className = "vsp-gate-list";
        box.appendChild(list);
      }

      const rows = TOOL_ORDER.map(T => {
        const o = pickToolObj(st, T) || {};
        const verdict = normVerdict(o.verdict || o.status || o.result || (st && st[(T.toLowerCase()) + "_verdict"]) || "");
        const total = (o.total != null) ? Number(o.total) : Number((st && st[(T.toLowerCase()) + "_total"]) || 0) || 0;
        const pillCls = "vsp-pill vsp-pill-" + verdict.toLowerCase();

        return `
          <div class="vsp-gate-row" style="display:flex;align-items:center;justify-content:space-between;padding:6px 0;border-top:1px solid rgba(255,255,255,.06)">
            <div style="font-weight:650;letter-spacing:.2px">${T}</div>
            <div style="display:flex;gap:10px;align-items:center">
              <span class="${pillCls}">${verdict}</span>
              <span style="opacity:.75">total: ${total}</span>
            </div>
          </div>`;
      }).join("");

      list.innerHTML = rows;
    };

    // attempt render once later (in case status fetched before patch)
    setTimeout(()=>{ try{ window.__VSP_RENDER_GATE_8TOOLS(); }catch(e){} }, 1200);
  }catch(e){}
})();
 // === /VSP_P2_FORCE_8TOOLS_V1 ===
'''.lstrip("\n")

p.write_text(t + "\n\n" + PATCH + "\n", encoding="utf-8")
print("[OK] appended force-8tools patch")
PY

node --check static/js/vsp_dashboard_enhance_v1.js
echo "[OK] node --check dashboard enhance"

echo "== [4] restart 8910 (commercial) =="
/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh || true

echo "== [5] verify API (latest RID) =="
RID="$(curl -sS 'http://127.0.0.1:8910/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1' | jq -er '.items[0].run_id')"
RN="$(curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" | jq -r '.rid_norm // empty')"
echo "RID=$RID"
echo "RID_NORM=$RN"

echo "-- v2 (RID) --"
curl -sS -D- "http://127.0.0.1:8910/api/vsp/findings_preview_v2/${RID}?limit=3" -o /tmp/fp_v2_rid.json | sed -n '1,20p'
jq '{ok,warning,total,items_n,file,ci_run_dir}' /tmp/fp_v2_rid.json || true

if [ -n "$RN" ]; then
  echo "-- v2 (RID_NORM) --"
  curl -sS -D- "http://127.0.0.1:8910/api/vsp/findings_preview_v2/${RN}?limit=3" -o /tmp/fp_v2_rn.json | sed -n '1,20p'
  jq '{ok,warning,total,items_n,file,ci_run_dir}' /tmp/fp_v2_rn.json || true
fi

echo
echo "[DONE] Now hard refresh Ctrl+Shift+R and test:"
echo "  http://127.0.0.1:8910/vsp4#tab=datasource&limit=200"
echo "  http://127.0.0.1:8910/vsp4#tab=datasource&sev=HIGH&limit=200"
