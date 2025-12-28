#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_ui_4tabs_commercial_v1.js"
TPL="templates/vsp_4tabs_commercial_v1.html"
PYAPP="vsp_demo_app.py"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 1; }
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 1; }
[ -f "$PYAPP" ] || { echo "[ERR] missing $PYAPP"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS"   "$JS.bak_export8_${TS}"
cp -f "$TPL"  "$TPL.bak_export8_${TS}"
cp -f "$PYAPP" "$PYAPP.bak_export8_${TS}"
echo "[BACKUP] $JS.bak_export8_${TS}"
echo "[BACKUP] $TPL.bak_export8_${TS}"
echo "[BACKUP] $PYAPP.bak_export8_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

# ------------------ (1) Template: rename columns for 8 tools ------------------
tpl = Path("templates/vsp_4tabs_commercial_v1.html")
t = tpl.read_text(encoding="utf-8", errors="ignore")

TAG = "<!-- === VSP4_8TOOLS_HEADER_V1 === -->"
if TAG not in t:
    # Replace column headers in Runs table: "Gitleaks" -> "Tools A", "CodeQL" -> "Tools B"
    # (best-effort: only first occurrence)
    t2 = t
    t2 = t2.replace(">Gitleaks<", ">Tools A<", 1)
    t2 = t2.replace(">CodeQL<", ">Tools B<", 1)
    t2 = t2.replace(">Degraded<", ">Degraded<"+TAG, 1)  # mark patched
    t = t2
    print("[OK] template headers patched (Tools A/B)")
else:
    print("[SKIP] template headers already patched")

tpl.write_text(t, encoding="utf-8")

# ------------------ (2) JS: export use ci_run_dir + render 8 tool badges ------------------
js = Path("static/js/vsp_ui_4tabs_commercial_v1.js")
j = js.read_text(encoding="utf-8", errors="ignore")

TAG2 = "/* === VSP_UI_EXPORT_CI_AND_8TOOLS_V1 === */"
if TAG2 in j:
    print("[SKIP] JS already patched")
    raise SystemExit(0)

# Ensure global status cache exists
if "window.__VSP_STATUS_CACHE" not in j:
    j = TAG2 + "\n" + 'window.__VSP_STATUS_CACHE = window.__VSP_STATUS_CACHE || {};\n' + j
else:
    j = TAG2 + "\n" + j

# Patch loadOne(rid): cache status by rid
# insert after `updateMeta(s);` if exists, else after `renderGateByTool(s);`
if "window.__VSP_STATUS_CACHE[rid]" not in j:
    j2 = re.sub(r'updateMeta\(s\);\s*', 'updateMeta(s);\n    window.__VSP_STATUS_CACHE[rid]=s;\n', j, count=1)
    if j2 == j:
        j2 = re.sub(r'renderGateByTool\(s\);\s*', 'renderGateByTool(s);\n    window.__VSP_STATUS_CACHE[rid]=s;\n', j, count=1)
    j = j2
    print("[OK] JS cached status by rid")
else:
    print("[SKIP] status cache already in JS")

# Patch _vsp_setup_export_links to include ci if available
# Find mk(fmt)=>[...] block and add candidates with ci=
def add_ci_candidates(src: str) -> str:
    m = re.search(r'function _vsp_setup_export_links\([\s\S]*?\n\}', src)
    if not m:
        print("[WARN] cannot find _vsp_setup_export_links; skip ci candidates")
        return src

    block = m.group(0)
    if "&ci=" in block:
        print("[SKIP] export already uses ci")
        return src

    # add ci_run_dir from status cache
    ins = r'''
  const __st = (window.__VSP_STATUS_CACHE||{})[selectedRid] || null;
  const __ci = (__st && (__st.ci_run_dir || __st.ci || __st.run_dir)) ? String(__st.ci_run_dir || __st.ci || __st.run_dir) : "";
  const __ciQ = __ci ? `&ci=${encodeURIComponent(__ci)}` : "";
'''
    # inject after selectedRid check block (after "if (!selectedRid) { ... }")
    block2 = re.sub(r'(if\s*\(!selectedRid\)\s*\{[\s\S]*?\}\s*)', r'\1' + ins, block, count=1)

    # in mk(fmt) add ci variants first (so they probe gateway route that uses ci)
    block2 = block2.replace(
        "`/api/vsp/run_export_v3/${encodeURIComponent(selectedRid)}?fmt=${fmt}`",
        "`/api/vsp/run_export_v3/${encodeURIComponent(selectedRid)}?fmt=${fmt}${__ciQ}`"
    )
    block2 = block2.replace(
        "`/api/vsp/run_export_v3/${encodeURIComponent(selectedRid)}?format=${fmt}`",
        "`/api/vsp/run_export_v3/${encodeURIComponent(selectedRid)}?format=${fmt}${__ciQ}`"
    )
    block2 = block2.replace(
        "`/api/vsp/run_export_v3?rid=${encodeURIComponent(selectedRid)}&fmt=${fmt}`",
        "`/api/vsp/run_export_v3?rid=${encodeURIComponent(selectedRid)}&fmt=${fmt}${__ciQ}`"
    )
    block2 = block2.replace(
        "`/api/vsp/run_export_v3?run_id=${encodeURIComponent(selectedRid)}&fmt=${fmt}`",
        "`/api/vsp/run_export_v3?run_id=${encodeURIComponent(selectedRid)}&fmt=${fmt}${__ciQ}`"
    )
    block2 = block2.replace(
        "`/api/vsp/run_export_v3?rid=${encodeURIComponent(selectedRid)}&format=${fmt}`",
        "`/api/vsp/run_export_v3?rid=${encodeURIComponent(selectedRid)}&format=${fmt}${__ciQ}`"
    )

    return src[:m.start()] + block2 + src[m.end():]

j = add_ci_candidates(j)

# Add helpers to build 8 tool badges
if "_vsp_toolBadge" not in j:
    addon = r'''
function _vsp_normVerd(v){
  const s = (v||"").toString().toUpperCase();
  if (!s) return "N/A";
  return s;
}
function _vsp_toolBadge(name, verdict, total){
  const v = _vsp_normVerd(verdict);
  const cls = (v==="RED"||v==="CRITICAL"||v==="HIGH") ? "pill red"
            : (v==="AMBER"||v==="MEDIUM") ? "pill amber"
            : (v==="GREEN"||v==="LOW"||v==="OK") ? "pill green"
            : (v==="DEGRADED") ? "pill amber"
            : (v==="DISABLED"||v==="NOT_RUN") ? "pill gray"
            : "pill gray";
  const tt = `${name}: ${v} (${total??0})`;
  return `<span class="${cls}" title="${tt}">${name} <span class="vsp-muted">(${total??0})</span></span>`;
}
function _vsp_pickTool(s, key){
  // allow either flat fields or *_summary
  if (!s) return {verdict:"N/A", total:0};
  const up = key.toUpperCase();
  // run_gate_summary.by_tool preferred
  const gate = (s.run_gate_summary && s.run_gate_summary.by_tool) ? s.run_gate_summary.by_tool : null;
  if (gate && gate[up]) return {verdict: gate[up].verdict||"N/A", total: gate[up].total||0};
  // direct fields
  const v1 = s[`${key}_verdict`];
  const t1 = s[`${key}_total`];
  if (v1 !== undefined || t1 !== undefined) return {verdict: v1||"N/A", total: (t1||0)};
  // summary object
  const sum = s[`${key}_summary`];
  if (sum && typeof sum === "object") return {verdict: sum.verdict||sum.status||"N/A", total: sum.total||0};
  // special known: codeql in our wrapper
  if (key==="codeql"){
    return {verdict: s.codeql_verdict||"NOT_RUN", total: s.codeql_total||0};
  }
  if (key==="gitleaks"){
    return {verdict: s.gitleaks_verdict||"NOT_RUN", total: s.gitleaks_total||0};
  }
  return {verdict:"NOT_RUN", total:0};
}
'''
    # inject before boot()
    j = re.sub(r'\n\s*async function boot\(\)\{', "\n"+addon+"\n\nasync function boot(){", j, count=1)

# Patch renderRuns table row creation:
# best-effort: replace places where it renders gitleaks/codeql cells
# We'll search for strings "gitleaks_verdict" and "codeql_verdict" in row html.
def patch_runs_row(src: str) -> str:
    # Replace single-cell rendering for gitleaks and codeql with tool groups
    # Try common pattern: `${badge(s.gitleaks_verdict, s.gitleaks_total)}`
    s = src

    # group A: semgrep,trivy,kics,gitleaks
    groupA = r'''${(function(){const a=_vsp_pickTool(s,"semgrep");const b=_vsp_pickTool(s,"trivy");const c=_vsp_pickTool(s,"kics");const d=_vsp_pickTool(s,"gitleaks");
      return _vsp_toolBadge("SEMGREP",a.verdict,a.total)+" "+_vsp_toolBadge("TRIVY",b.verdict,b.total)+" "+_vsp_toolBadge("KICS",c.verdict,c.total)+" "+_vsp_toolBadge("GITLEAKS",d.verdict,d.total);})()}'''
    # group B: codeql,bandit,syft,grype
    groupB = r'''${(function(){const a=_vsp_pickTool(s,"codeql");const b=_vsp_pickTool(s,"bandit");const c=_vsp_pickTool(s,"syft");const d=_vsp_pickTool(s,"grype");
      return _vsp_toolBadge("CODEQL",a.verdict,a.total)+" "+_vsp_toolBadge("BANDIT",b.verdict,b.total)+" "+_vsp_toolBadge("SYFT",c.verdict,c.total)+" "+_vsp_toolBadge("GRYPE",d.verdict,d.total);})()}'''

    # Replace first occurrence of gitleaks badge cell
    s2 = re.sub(r'\$\{\s*[^}]*gitleaks[^}]*\}', groupA, s, count=1)
    # Replace first occurrence of codeql badge cell
    s2 = re.sub(r'\$\{\s*[^}]*codeql[^}]*\}', groupB, s2, count=1)

    if s2 != s:
        print("[OK] patched runs row to show 8 tools groups")
    else:
        print("[WARN] cannot auto-patch runs row (pattern mismatch). You still have export route, UI tool groups may remain old until manual tweak.")
    return s2

j = patch_runs_row(j)

js.write_text(j, encoding="utf-8")
print("[OK] JS written")

# ------------------ (3) Backend: add /api/vsp/run_export_v3 (read-only) ------------------
app = Path("vsp_demo_app.py")
p = app.read_text(encoding="utf-8", errors="ignore")

TAG3 = "# === VSP_RUN_EXPORT_V3_GATEWAY_V1 ==="
if TAG3 in p:
    print("[SKIP] export route already exists")
else:
    # append minimal route near end of file
    add = r'''
''' + TAG3 + r'''
import os, glob
from flask import request, send_file

def _vsp__export_pick_run_dir(rid: str, ci: str|None):
    # prefer explicit ci_run_dir from UI (validated)
    if ci:
        ci = str(ci)
        # allow only under /home/test/Data and must contain "/out_ci/"
        if ci.startswith("/home/test/Data/") and "/out_ci/" in ci and os.path.isdir(ci):
            return ci
    # fallback: try locate by folder name under /home/test/Data/*/out_ci/<rid_norm>
    rid_norm = rid
    if rid_norm.startswith("RUN_"):
        rid_norm = rid_norm[4:]
    # rid_norm like VSP_CI_YYYY...
    targets = []
    for root in ["/home/test/Data"]:
        # shallow walk to avoid heavy
        for base in glob.glob(root+"/*/out_ci/"+rid_norm):
            if os.path.isdir(base):
                targets.append(base)
    if targets:
        targets.sort(key=lambda x: os.path.getmtime(x), reverse=True)
        return targets[0]
    return None

def _vsp__export_pick_file(run_dir: str, fmt: str):
    fmt = (fmt or "html").lower()
    # common candidates
    if fmt == "html":
        cands = [
            os.path.join(run_dir, "reports", "*.html"),
            os.path.join(run_dir, "report*.html"),
            os.path.join(run_dir, "*.html"),
        ]
    elif fmt == "pdf":
        cands = [
            os.path.join(run_dir, "reports", "*.pdf"),
            os.path.join(run_dir, "report*.pdf"),
            os.path.join(run_dir, "*.pdf"),
        ]
    elif fmt == "zip":
        cands = [
            os.path.join(run_dir, "reports", "*.zip"),
            os.path.join(run_dir, "report*.zip"),
            os.path.join(run_dir, "*.zip"),
        ]
    else:
        return None
    files = []
    for g in cands:
        files += glob.glob(g)
    files = [f for f in files if os.path.isfile(f)]
    if not files:
        return None
    files.sort(key=lambda x: os.path.getmtime(x), reverse=True)
    return files[0]

@app.route("/api/vsp/run_export_v3/<rid>", methods=["GET"])
@app.route("/api/vsp/run_export_v3", methods=["GET"])
def api_vsp_run_export_v3(rid=None):
    rid = rid or request.args.get("rid") or request.args.get("run_id")
    fmt = request.args.get("fmt") or request.args.get("format") or "html"
    ci  = request.args.get("ci") or request.args.get("ci_run_dir")
    if not rid:
        return jsonify({"ok":False,"http_code":400,"error":"missing_rid","rid":None}), 400

    run_dir = _vsp__export_pick_run_dir(rid, ci)
    if not run_dir:
        return jsonify({"ok":False,"http_code":404,"error":"run_dir_not_found","rid":rid}), 404

    f = _vsp__export_pick_file(run_dir, fmt)
    if not f:
        return jsonify({"ok":False,"http_code":404,"error":"export_file_not_found","rid":rid,"fmt":fmt,"run_dir":run_dir}), 404

    # choose mimetype
    mt = "application/octet-stream"
    if fmt == "html": mt = "text/html"
    if fmt == "pdf":  mt = "application/pdf"
    if fmt == "zip":  mt = "application/zip"
    return send_file(f, mimetype=mt, as_attachment=(fmt!="html"))
'''
    app.write_text(p + "\n" + add + "\n", encoding="utf-8")
    print("[OK] appended export route to vsp_demo_app.py")

print("[DONE]")
PY

python3 -m py_compile vsp_demo_app.py >/dev/null
rm -f out_ci/ui_8910.lock 2>/dev/null || true
bin/restart_8910_gunicorn_commercial_v5.sh

echo "== SMOKE export endpoint =="
RID="$(curl -sS "http://127.0.0.1:8910/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1" | python3 -c 'import sys,json;print(json.load(sys.stdin)["items"][0]["run_id"])')"
echo "RID=$RID"
curl -sS -D- "http://127.0.0.1:8910/api/vsp/run_export_v3/${RID}?fmt=html" -o /tmp/vsp_export_smoke.html | head -n 12 || true
echo "[OK] open UI: http://127.0.0.1:8910/vsp4#runs"
