#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="api/vsp_run_export_api_v3.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_export_replace_stubs_${TS}"
echo "[BACKUP] $F.bak_export_replace_stubs_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("api/vsp_run_export_api_v3.py")
s=p.read_text(encoding="utf-8", errors="replace")

marker="### [COMMERCIAL] EXPORT_V3_REPLACE_STUBS_V3 ###"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# 1) Ensure needed imports exist (safe even if duplicates)
need_imports = [
    "import zipfile",
    "import tempfile",
    "import subprocess",
    "import shutil",
    "from datetime import datetime, timezone",
]
for imp in need_imports:
    if imp not in s:
        m2 = re.search(r'(?ms)^((?:import .+\n|from .+ import .+\n)+)', s)
        if m2:
            s = s[:m2.end()] + imp + "\n" + s[m2.end():]
        else:
            s = imp + "\n" + s

# 2) Ensure helper funcs exist (minimal, no @bp usage)
helpers = f"""
{marker}
def _nowz():
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00","Z")

def _ensure_report_dir(run_dir: str):
    report_dir = os.path.join(run_dir, "report")
    os.makedirs(report_dir, exist_ok=True)
    # keep report/findings_unified.* if already produced by runner
    return report_dir

def _build_export_html_min(report_dir: str, rid_norm: str):
    html_path = os.path.join(report_dir, "export_v3.html")
    if os.path.isfile(html_path) and os.path.getsize(html_path) > 0:
        return html_path
    # If findings_unified.json exists, show small summary
    json_path = os.path.join(report_dir, "findings_unified.json")
    total = 0
    sev_counts, tool_counts = {{}}, {{}}
    if os.path.isfile(json_path):
        try:
            data = json.load(open(json_path, "r", encoding="utf-8"))
            items = data.get("items") or []
            total = len(items)
            for it in items:
                sev = (it.get("severity_norm") or it.get("severity") or "INFO").upper()
                tool = (it.get("tool") or "UNKNOWN").upper()
                sev_counts[sev] = sev_counts.get(sev, 0) + 1
                tool_counts[tool] = tool_counts.get(tool, 0) + 1
        except Exception:
            pass

    def rows(d):
        if not d:
            return "<tr><td colspan='2'>(none)</td></tr>"
        return "\\n".join([f"<tr><td>{{k}}</td><td>{{v}}</td></tr>" for k,v in sorted(d.items(), key=lambda kv:(-kv[1],kv[0]))])

    html = f\"\"\"<!doctype html><html><head><meta charset='utf-8'/>
    <title>VSP Export {{rid_norm}}</title>
    <style>body{{font-family:Arial;padding:24px}} table{{border-collapse:collapse;width:100%}}
    td,th{{border:1px solid #eee;padding:6px 8px}}</style></head>
    <body>
    <h2>VSP Export v3 - {{rid_norm}}</h2>
    <p>Generated at: {{_nowz()}}</p>
    <p><b>Total findings:</b> {{total}}</p>
    <h3>By severity</h3><table><tr><th>Severity</th><th>Count</th></tr>{{rows(sev_counts)}}</table>
    <h3>By tool</h3><table><tr><th>Tool</th><th>Count</th></tr>{{rows(tool_counts)}}</table>
    <p style='margin-top:18px;color:#777'>Commercial export (on-demand).</p>
    </body></html>\"\"\"
    with open(html_path, "w", encoding="utf-8") as f:
        f.write(html)
    return html_path

def _zip_dir(src_dir: str):
    tmp = tempfile.NamedTemporaryFile(prefix="vsp_export_", suffix=".zip", delete=False)
    tmp.close()
    with zipfile.ZipFile(tmp.name, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for root, _, files in os.walk(src_dir):
            for fn in files:
                ap = os.path.join(root, fn)
                rel = os.path.relpath(ap, src_dir)
                z.write(ap, arcname=rel)
    return tmp.name

def _pdf_wkhtmltopdf(html_file: str, timeout_sec: int = 180):
    exe = shutil.which("wkhtmltopdf")
    if not exe:
        return None, "wkhtmltopdf_missing"
    tmp = tempfile.NamedTemporaryFile(prefix="vsp_export_", suffix=".pdf", delete=False)
    tmp.close()
    try:
        subprocess.run([exe, "--quiet", html_file, tmp.name], timeout=timeout_sec, check=True)
        if os.path.isfile(tmp.name) and os.path.getsize(tmp.name) > 0:
            return tmp.name, None
        return None, "wkhtmltopdf_empty_output"
    except Exception as e:
        return None, f"wkhtmltopdf_failed:{{type(e).__name__}}"
"""
if marker not in s:
    s = s.rstrip() + "\n\n" + helpers + "\n"

# 3) Locate handler by decorator route and function name
route_pat = r'@[\w\.]+\.route\(\s*[\'"][^\'"]*run_export_v3[^\'"]*[\'"][^\)]*\)\s*'
m = re.search(route_pat, s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find run_export_v3 route decorator")

tail = s[m.end():]
m2 = re.search(r'(?m)^\s*def\s+([A-Za-z_]\w*)\s*\(\s*rid\b', tail)
if not m2:
    m2 = re.search(r'(?m)^\s*def\s+([A-Za-z_]\w*)\s*\(\s*rid\s*,', tail)
if not m2:
    raise SystemExit("[ERR] cannot find handler def after decorator")

func_name = m2.group(1)
print("[INFO] handler =", func_name)

# 4) Patch within function: replace stub branches for fmt==html/zip/pdf.
# We'll do line-based indentation aware replacement.
lines = s.splitlines(True)

# find function def line index
def_pat = re.compile(rf'^(\s*)def\s+{re.escape(func_name)}\s*\(.*\):\s*$', re.M)
m3 = def_pat.search(s)
if not m3:
    raise SystemExit("[ERR] cannot find def line for handler")
# compute line index
pre = s[:m3.start()].splitlines(True)
i_def = len(pre)
base_indent = m3.group(1)
in_func_indent = base_indent + "    "

# Find end of function (next top-level def with same base indent)
i_end = len(lines)
for i in range(i_def+1, len(lines)):
    if lines[i].startswith(base_indent + "def ") and not lines[i].startswith(in_func_indent):
        i_end = i
        break
func_lines = lines[i_def:i_end]

def replace_if_block(func_lines, key):
    # key is "html" / "zip" / "pdf"
    # find "if fmt == '<key>':" or "elif fmt == '<key>':"
    pat1 = re.compile(rf'^(\s*)(elif|if)\s+fmt\s*==\s*[\'"]{key}[\'"]\s*:\s*$', re.M)
    text = "".join(func_lines)
    m = pat1.search(text)
    if not m:
        return func_lines, False

    # compute start line index within func_lines
    start_offset = len(text[:m.start()].splitlines(True))
    if_indent = m.group(1)
    start_i = start_offset

    # find end of this if/elif block: first non-blank line with indent <= if_indent and starting with elif/else/return/if (at same nesting)
    end_i = start_i + 1
    def indlen(ln):
        ln2 = ln.replace("\t", "    ")
        return len(ln2) - len(ln2.lstrip(" "))

    base = indlen(if_indent)
    while end_i < len(func_lines):
        ln = func_lines[end_i]
        if ln.strip() == "":
            end_i += 1
            continue
        if indlen(ln) <= base and re.match(r'^\s*(elif|else|if)\b', ln):
            break
        # also stop if we leave function (shouldn't happen)
        end_i += 1

    # build replacement block
    bi = if_indent
    b  = bi + "    "
    rep = []
    rep.append(f"{bi}if fmt == \"{key}\":\n" if "if" in m.group(2) else f"{bi}elif fmt == \"{key}\":\n")

    rep.append(f"{b}rid_norm = rid.replace(\"RUN_\", \"\") if isinstance(rid, str) else str(rid)\n")
    rep.append(f"{b}run_dir = None\n")
    # try use ci_run_dir variable if present in function scope
    rep.append(f"{b}try:\n")
    rep.append(f"{b}    run_dir = ci_run_dir if 'ci_run_dir' in locals() else None\n")
    rep.append(f"{b}except Exception:\n")
    rep.append(f"{b}    run_dir = None\n")
    rep.append(f"{b}if not run_dir or (not os.path.isdir(str(run_dir))):\n")
    rep.append(f"{b}    # fallback best-effort\n")
    rep.append(f"{b}    run_dir = _resolve_run_dir_best_effort(rid_norm) if '_resolve_run_dir_best_effort' in globals() else None\n")
    rep.append(f"{b}if not run_dir or (not os.path.isdir(str(run_dir))):\n")
    rep.append(f"{b}    resp = jsonify({{\"ok\": False, \"error\": \"run_dir_not_found\", \"rid_norm\": rid_norm}})\n")
    rep.append(f"{b}    resp.headers[\"X-VSP-EXPORT-AVAILABLE\"] = \"0\"\n")
    rep.append(f"{b}    return resp, 404\n")
    rep.append(f"{b}report_dir = _ensure_report_dir(str(run_dir))\n")
    rep.append(f"{b}html_file = _build_export_html_min(report_dir, rid_norm)\n")

    if key == "html":
        rep.append(f"{b}resp = send_file(html_file, mimetype=\"text/html\", as_attachment=True, download_name=f\"{ '{' }rid_norm{ '}' }.html\")\n")
        rep.append(f"{b}resp.headers[\"X-VSP-EXPORT-AVAILABLE\"] = \"1\"\n")
        rep.append(f"{b}resp.headers[\"X-VSP-EXPORT-MODE\"] = \"STUB_REPLACED_V3\"\n")
        rep.append(f"{b}return resp\n")
    elif key == "zip":
        rep.append(f"{b}z = _zip_dir(report_dir)\n")
        rep.append(f"{b}resp = send_file(z, mimetype=\"application/zip\", as_attachment=True, download_name=f\"{ '{' }rid_norm{ '}' }.zip\")\n")
        rep.append(f"{b}resp.headers[\"X-VSP-EXPORT-AVAILABLE\"] = \"1\"\n")
        rep.append(f"{b}resp.headers[\"X-VSP-EXPORT-MODE\"] = \"STUB_REPLACED_V3\"\n")
        rep.append(f"{b}return resp\n")
    else:  # pdf
        rep.append(f"{b}pdf_path, err = _pdf_wkhtmltopdf(html_file, timeout_sec=180)\n")
        rep.append(f"{b}if pdf_path:\n")
        rep.append(f"{b}    resp = send_file(pdf_path, mimetype=\"application/pdf\", as_attachment=True, download_name=f\"{ '{' }rid_norm{ '}' }.pdf\")\n")
        rep.append(f"{b}    resp.headers[\"X-VSP-EXPORT-AVAILABLE\"] = \"1\"\n")
        rep.append(f"{b}    resp.headers[\"X-VSP-EXPORT-MODE\"] = \"STUB_REPLACED_V3\"\n")
        rep.append(f"{b}    return resp\n")
        rep.append(f"{b}resp = jsonify({{\"ok\": False, \"error\": \"pdf_export_failed\", \"detail\": err}})\n")
        rep.append(f"{b}resp.headers[\"X-VSP-EXPORT-AVAILABLE\"] = \"0\"\n")
        rep.append(f"{b}return resp, 500\n")

    new_func = func_lines[:start_i] + rep + func_lines[end_i:]
    return new_func, True

# We also need _resolve_run_dir_best_effort; if missing, define minimal one.
if "_resolve_run_dir_best_effort" not in s:
    extra = """
def _resolve_run_dir_best_effort(rid_norm: str):
    import glob, os
    cands = []
    cands += glob.glob(f"/home/test/Data/SECURITY-*/out_ci/{rid_norm}")
    cands += glob.glob(f"/home/test/Data/*/out_ci/{rid_norm}")
    for x in cands:
        try:
            if os.path.isdir(x):
                return x
        except Exception:
            pass
    return None
"""
    s = s.rstrip() + "\n" + extra + "\n"
    lines = s.splitlines(True)
    func_lines = lines[i_def:i_end]

# Replace pdf/html/zip stubs
changed_any = False
for k in ("html","zip","pdf"):
    func_lines, changed = replace_if_block(func_lines, k)
    changed_any = changed_any or changed

if not changed_any:
    print("[WARN] did not find fmt blocks to replace; will still keep helpers (may need manual inspection)")

# write back combined
out_lines = lines[:i_def] + func_lines + lines[i_end:]
p.write_text("".join(out_lines), encoding="utf-8")
print("[OK] wrote patched file with stub replacements =", changed_any)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK => $F"
