#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_force_replace_export_${TS}"
echo "[BACKUP] $F.bak_force_replace_export_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# ensure imports (prepend if missing)
imports = [
  "import os",
  "import json",
  "import csv",
  "import glob",
  "import shutil",
  "import zipfile",
  "import tempfile",
  "import subprocess",
  "from datetime import datetime, timezone",
]
for imp in reversed(imports):
    if imp not in s:
        s = imp + "\n" + s

# locate def line
m = re.search(r'(?m)^(?P<ind>\s*)def\s+api_vsp_run_export_v3_force_fs\s*(?P<sig>\([^)]*\))\s*:\s*$', s)
if not m:
    raise SystemExit("[ERR] cannot find def api_vsp_run_export_v3_force_fs(...) in vsp_demo_app.py")

ind = m.group("ind")
sig = m.group("sig")
start = m.start()

# find end of function block by scanning lines after def
lines = s.splitlines(True)
# compute def line index
def_line_idx = None
pos = 0
for i,ln in enumerate(lines):
    if pos == start:
        def_line_idx = i
        break
    pos += len(ln)
if def_line_idx is None:
    raise SystemExit("[ERR] internal index error")

# function ends at next top-level item with indent <= ind (def/class/@) excluding blank lines
end_idx = len(lines)
for j in range(def_line_idx + 1, len(lines)):
    ln = lines[j]
    if ln.strip() == "":
        continue
    # top-level at same indent
    if re.match(rf'^{re.escape(ind)}(def\s+|class\s+|@)', ln):
        end_idx = j
        break

def with_ind(block_lines):
    return "".join((ind + x if x.strip() != "" else x) for x in block_lines)

marker = "### [COMMERCIAL] FORCE_EXPORT_FORCEFS_V1 ###"
helper_marker = "### [COMMERCIAL] FORCE_EXPORT_HELPERS_V1 ###"
if helper_marker not in s:
    helpers = [
        "\n",
        f"{helper_marker}\n",
        "def _nowz_export_v1():\n",
        "    return datetime.now(timezone.utc).isoformat(timespec=\"microseconds\").replace(\"+00:00\",\"Z\")\n",
        "\n",
        "def _find_run_dir_export_v1(rid_norm: str):\n",
        "    cands = []\n",
        "    cands += glob.glob(\"/home/test/Data/SECURITY-*/out_ci/\" + rid_norm)\n",
        "    cands += glob.glob(\"/home/test/Data/*/out_ci/\" + rid_norm)\n",
        "    for x in cands:\n",
        "        try:\n",
        "            if os.path.isdir(x):\n",
        "                return x\n",
        "        except Exception:\n",
        "            pass\n",
        "    return None\n",
        "\n",
        "def _ensure_report_export_v1(run_dir: str):\n",
        "    report_dir = os.path.join(run_dir, \"report\")\n",
        "    os.makedirs(report_dir, exist_ok=True)\n",
        "\n",
        "    src_json = os.path.join(run_dir, \"findings_unified.json\")\n",
        "    dst_json = os.path.join(report_dir, \"findings_unified.json\")\n",
        "    if os.path.isfile(src_json) and (not os.path.isfile(dst_json)):\n",
        "        try:\n",
        "            shutil.copy2(src_json, dst_json)\n",
        "        except Exception:\n",
        "            pass\n",
        "\n",
        "    dst_csv = os.path.join(report_dir, \"findings_unified.csv\")\n",
        "    if (not os.path.isfile(dst_csv)) and os.path.isfile(dst_json):\n",
        "        cols = [\"tool\",\"severity\",\"title\",\"file\",\"line\",\"cwe\",\"fingerprint\"]\n",
        "        try:\n",
        "            data = json.load(open(dst_json, \"r\", encoding=\"utf-8\"))\n",
        "            items = data.get(\"items\") or []\n",
        "            with open(dst_csv, \"w\", encoding=\"utf-8\", newline=\"\") as f:\n",
        "                w = csv.DictWriter(f, fieldnames=cols)\n",
        "                w.writeheader()\n",
        "                for it in items:\n",
        "                    cwe = it.get(\"cwe\")\n",
        "                    if isinstance(cwe, list):\n",
        "                        cwe = \",\".join(cwe)\n",
        "                    w.writerow({\n",
        "                        \"tool\": it.get(\"tool\"),\n",
        "                        \"severity\": (it.get(\"severity_norm\") or it.get(\"severity\")),\n",
        "                        \"title\": it.get(\"title\"),\n",
        "                        \"file\": it.get(\"file\"),\n",
        "                        \"line\": it.get(\"line\"),\n",
        "                        \"cwe\": cwe,\n",
        "                        \"fingerprint\": it.get(\"fingerprint\"),\n",
        "                    })\n",
        "        except Exception:\n",
        "            pass\n",
        "\n",
        "    html_path = os.path.join(report_dir, \"export_v3.html\")\n",
        "    if not (os.path.isfile(html_path) and os.path.getsize(html_path) > 0):\n",
        "        total = 0\n",
        "        sev_counts = {}\n",
        "        try:\n",
        "            if os.path.isfile(dst_json):\n",
        "                d = json.load(open(dst_json, \"r\", encoding=\"utf-8\"))\n",
        "                items = d.get(\"items\") or []\n",
        "                total = len(items)\n",
        "                for it in items:\n",
        "                    sev = (it.get(\"severity_norm\") or it.get(\"severity\") or \"INFO\").upper()\n",
        "                    sev_counts[sev] = sev_counts.get(sev, 0) + 1\n",
        "        except Exception:\n",
        "            pass\n",
        "        def rows(dct):\n",
        "            if not dct:\n",
        "                return \"<tr><td colspan='2'>(none)</td></tr>\"\n",
        "            out = []\n",
        "            for k,v in sorted(dct.items(), key=lambda kv:(-kv[1],kv[0])):\n",
        "                out.append(f\"<tr><td>{k}</td><td>{v}</td></tr>\")\n",
        "            return \"\\n\".join(out)\n",
        "        html = \"<!doctype html><html><head><meta charset='utf-8'/>\" \\\n",
        "               \"<title>VSP Export</title>\" \\\n",
        "               \"<style>body{font-family:Arial;padding:24px} table{border-collapse:collapse;width:100%}\" \\\n",
        "               \"td,th{border:1px solid #eee;padding:6px 8px}</style></head><body>\" \\\n",
        "               f\"<h2>VSP Export v3</h2><p>Generated at: {_nowz_export_v1()}</p><p><b>Total findings:</b> {total}</p>\" \\\n",
        "               \"<h3>By severity</h3><table><tr><th>Severity</th><th>Count</th></tr>\" + rows(sev_counts) + \"</table>\" \\\n",
        "               \"</body></html>\"\n",
        "        try:\n",
        "            with open(html_path, \"w\", encoding=\"utf-8\") as f:\n",
        "                f.write(html)\n",
        "        except Exception:\n",
        "            pass\n",
        "\n",
        "    return report_dir\n",
        "\n",
        "def _zip_report_export_v1(report_dir: str):\n",
        "    tmp = tempfile.NamedTemporaryFile(prefix=\"vsp_export_\", suffix=\".zip\", delete=False)\n",
        "    tmp.close()\n",
        "    with zipfile.ZipFile(tmp.name, \"w\", compression=zipfile.ZIP_DEFLATED) as z:\n",
        "        for root, _, files in os.walk(report_dir):\n",
        "            for fn in files:\n",
        "                ap = os.path.join(root, fn)\n",
        "                rel = os.path.relpath(ap, report_dir)\n",
        "                z.write(ap, arcname=rel)\n",
        "    return tmp.name\n",
        "\n",
        "def _pdf_from_html_wk_export_v1(html_file: str, timeout_sec: int = 180):\n",
        "    exe = shutil.which(\"wkhtmltopdf\")\n",
        "    if not exe:\n",
        "        return None, \"wkhtmltopdf_missing\"\n",
        "    tmp = tempfile.NamedTemporaryFile(prefix=\"vsp_export_\", suffix=\".pdf\", delete=False)\n",
        "    tmp.close()\n",
        "    try:\n",
        "        subprocess.run([exe, \"--quiet\", html_file, tmp.name], timeout=timeout_sec, check=True)\n",
        "        if os.path.isfile(tmp.name) and os.path.getsize(tmp.name) > 0:\n",
        "            return tmp.name, None\n",
        "        return None, \"wkhtmltopdf_empty_output\"\n",
        "    except Exception as ex:\n",
        "        return None, \"wkhtmltopdf_failed:\" + type(ex).__name__\n",
        "\n"
    ]
    s = s + "".join(helpers)

# build new function block
defline = f"def api_vsp_run_export_v3_force_fs{sig}:\n"
block = [
    defline,
    f"    {marker}\n",
    "    fmt = (request.args.get(\"fmt\") or \"zip\").lower()\n",
    "    rid_str = str(rid)\n",
    "    rid_norm = rid_str.replace(\"RUN_\", \"\")\n",
    "\n",
    "    # PROBE: proves this handler is actually serving requests\n",
    "    if (request.args.get(\"probe\") or \"\") == \"1\":\n",
    "        resp = jsonify({\"ok\": True, \"probe\": \"EXPORT_FORCEFS_V1\", \"rid_norm\": rid_norm, \"fmt\": fmt})\n",
    "        resp.headers[\"X-VSP-EXPORT-AVAILABLE\"] = \"1\"\n",
    "        resp.headers[\"X-VSP-EXPORT-MODE\"] = \"EXPORT_FORCEFS_V1\"\n",
    "        return resp\n",
    "\n",
    "    run_dir = _find_run_dir_export_v1(rid_norm)\n",
    "    if (not run_dir) or (not os.path.isdir(run_dir)):\n",
    "        resp = jsonify({\"ok\": False, \"error\": \"run_dir_not_found\", \"rid_norm\": rid_norm})\n",
    "        resp.headers[\"X-VSP-EXPORT-AVAILABLE\"] = \"0\"\n",
    "        resp.headers[\"X-VSP-EXPORT-MODE\"] = \"EXPORT_FORCEFS_V1\"\n",
    "        return resp, 404\n",
    "\n",
    "    report_dir = _ensure_report_export_v1(run_dir)\n",
    "    html_file = os.path.join(report_dir, \"export_v3.html\")\n",
    "\n",
    "    if fmt == \"html\":\n",
    "        resp = send_file(html_file, mimetype=\"text/html\", as_attachment=True, download_name=f\"{rid_norm}.html\")\n",
    "        resp.headers[\"X-VSP-EXPORT-AVAILABLE\"] = \"1\"\n",
    "        resp.headers[\"X-VSP-EXPORT-MODE\"] = \"EXPORT_FORCEFS_V1\"\n",
    "        return resp\n",
    "\n",
    "    if fmt == \"zip\":\n",
    "        zpath = _zip_report_export_v1(report_dir)\n",
    "        resp = send_file(zpath, mimetype=\"application/zip\", as_attachment=True, download_name=f\"{rid_norm}.zip\")\n",
    "        resp.headers[\"X-VSP-EXPORT-AVAILABLE\"] = \"1\"\n",
    "        resp.headers[\"X-VSP-EXPORT-MODE\"] = \"EXPORT_FORCEFS_V1\"\n",
    "        return resp\n",
    "\n",
    "    if fmt == \"pdf\":\n",
    "        pdf_path, err = _pdf_from_html_wk_export_v1(html_file, timeout_sec=180)\n",
    "        if pdf_path:\n",
    "            resp = send_file(pdf_path, mimetype=\"application/pdf\", as_attachment=True, download_name=f\"{rid_norm}.pdf\")\n",
    "            resp.headers[\"X-VSP-EXPORT-AVAILABLE\"] = \"1\"\n",
    "            resp.headers[\"X-VSP-EXPORT-MODE\"] = \"EXPORT_FORCEFS_V1\"\n",
    "            return resp\n",
    "        resp = jsonify({\"ok\": False, \"error\": \"pdf_export_failed\", \"detail\": err})\n",
    "        resp.headers[\"X-VSP-EXPORT-AVAILABLE\"] = \"0\"\n",
    "        resp.headers[\"X-VSP-EXPORT-MODE\"] = \"EXPORT_FORCEFS_V1\"\n",
    "        return resp, 500\n",
    "\n",
    "    resp = jsonify({\"ok\": False, \"error\": \"bad_fmt\", \"fmt\": fmt, \"allowed\": [\"html\",\"zip\",\"pdf\"]})\n",
    "    resp.headers[\"X-VSP-EXPORT-AVAILABLE\"] = \"0\"\n",
    "    resp.headers[\"X-VSP-EXPORT-MODE\"] = \"EXPORT_FORCEFS_V1\"\n",
    "    return resp, 400\n",
]

new_func = with_ind(block)

# replace old function block in file
new_lines = lines[:def_line_idx] + [new_func] + lines[end_idx:]
p.write_text("".join(new_lines), encoding="utf-8")
print("[OK] force-replaced api_vsp_run_export_v3_force_fs in", p)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
