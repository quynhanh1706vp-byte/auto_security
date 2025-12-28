#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_export_override_forcefs_v2_${TS}"
echo "[BACKUP] $F.bak_export_override_forcefs_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "### [COMMERCIAL] EXPORT_FORCEFS_V2 ###"

m = re.search(r'(?m)^(?P<ind>\s*)def\s+_vsp_export_v3_override\s*(?P<sig>\([^)]*\))\s*:\s*$', s)
if not m:
    raise SystemExit("[ERR] cannot find def _vsp_export_v3_override(...) in vsp_demo_app.py")

ind = m.group("ind")
sig = m.group("sig")
start = m.start()

lines = s.splitlines(True)

# find def line index
def_line_idx = None
pos = 0
for i, ln in enumerate(lines):
    if pos == start:
        def_line_idx = i
        break
    pos += len(ln)
if def_line_idx is None:
    raise SystemExit("[ERR] internal index error")

# find end of function block: next top-level def/class/@ at same indent
end_idx = len(lines)
for j in range(def_line_idx + 1, len(lines)):
    ln = lines[j]
    if ln.strip() == "":
        continue
    if re.match(rf'^{re.escape(ind)}(def\s+|class\s+|@)', ln):
        end_idx = j
        break

old_block = "".join(lines[def_line_idx:end_idx])
if MARK in old_block:
    print("[OK] already patched (marker exists)")
    raise SystemExit(0)

def with_ind(block_lines):
    out = []
    for x in block_lines:
        if x.strip() == "":
            out.append(x)
        else:
            out.append(ind + x)
    return "".join(out)

# keep original def line exactly (first line of old_block)
defline = lines[def_line_idx].rstrip("\n") + "\n"

new_body = [
    defline,
    f"    {MARK}\n",
    "    # NOTE: this is the REAL handler bound to /api/vsp/run_export_v3/<rid>\n",
    "    import os, json, csv, glob, shutil, zipfile, tempfile, subprocess\n",
    "    from datetime import datetime, timezone\n",
    "\n",
    "    fmt = (request.args.get('fmt') or 'zip').lower()\n",
    "    rid_str = str(rid)\n",
    "    rid_norm = rid_str.replace('RUN_', '')\n",
    "\n",
    "    def nowz():\n",
    "        return datetime.now(timezone.utc).isoformat(timespec='microseconds').replace('+00:00','Z')\n",
    "\n",
    "    def find_run_dir(rid_norm: str):\n",
    "        cands = []\n",
    "        cands += glob.glob('/home/test/Data/SECURITY-*/out_ci/' + rid_norm)\n",
    "        cands += glob.glob('/home/test/Data/*/out_ci/' + rid_norm)\n",
    "        for x in cands:\n",
    "            try:\n",
    "                if os.path.isdir(x):\n",
    "                    return x\n",
    "            except Exception:\n",
    "                pass\n",
    "        return None\n",
    "\n",
    "    def ensure_report(run_dir: str):\n",
    "        report_dir = os.path.join(run_dir, 'report')\n",
    "        os.makedirs(report_dir, exist_ok=True)\n",
    "\n",
    "        # copy unified json into report/ if needed\n",
    "        src_json = os.path.join(run_dir, 'findings_unified.json')\n",
    "        dst_json = os.path.join(report_dir, 'findings_unified.json')\n",
    "        if os.path.isfile(src_json) and (not os.path.isfile(dst_json)):\n",
    "            try:\n",
    "                shutil.copy2(src_json, dst_json)\n",
    "            except Exception:\n",
    "                pass\n",
    "\n",
    "        # build csv if missing\n",
    "        dst_csv = os.path.join(report_dir, 'findings_unified.csv')\n",
    "        if (not os.path.isfile(dst_csv)) and os.path.isfile(dst_json):\n",
    "            cols = ['tool','severity','title','file','line','cwe','fingerprint']\n",
    "            try:\n",
    "                d = json.load(open(dst_json,'r',encoding='utf-8'))\n",
    "                items = d.get('items') or []\n",
    "                with open(dst_csv,'w',encoding='utf-8',newline='') as f:\n",
    "                    w = csv.DictWriter(f, fieldnames=cols)\n",
    "                    w.writeheader()\n",
    "                    for it in items:\n",
    "                        cwe = it.get('cwe')\n",
    "                        if isinstance(cwe, list):\n",
    "                            cwe = ','.join(cwe)\n",
    "                        w.writerow({\n",
    "                            'tool': it.get('tool'),\n",
    "                            'severity': (it.get('severity_norm') or it.get('severity')),\n",
    "                            'title': it.get('title'),\n",
    "                            'file': it.get('file'),\n",
    "                            'line': it.get('line'),\n",
    "                            'cwe': cwe,\n",
    "                            'fingerprint': it.get('fingerprint'),\n",
    "                        })\n",
    "            except Exception:\n",
    "                pass\n",
    "\n",
    "        # build minimal html if missing\n",
    "        html_path = os.path.join(report_dir, 'export_v3.html')\n",
    "        if not (os.path.isfile(html_path) and os.path.getsize(html_path) > 0):\n",
    "            total = 0\n",
    "            sev = {}\n",
    "            try:\n",
    "                if os.path.isfile(dst_json):\n",
    "                    d = json.load(open(dst_json,'r',encoding='utf-8'))\n",
    "                    items = d.get('items') or []\n",
    "                    total = len(items)\n",
    "                    for it in items:\n",
    "                        k = (it.get('severity_norm') or it.get('severity') or 'INFO').upper()\n",
    "                        sev[k] = sev.get(k, 0) + 1\n",
    "            except Exception:\n",
    "                pass\n",
    "            rows = ''\n",
    "            for k,v in sorted(sev.items(), key=lambda kv:(-kv[1], kv[0])):\n",
    "                rows += f\"<tr><td>{k}</td><td>{v}</td></tr>\\n\"\n",
    "            if not rows:\n",
    "                rows = \"<tr><td colspan='2'>(none)</td></tr>\"\n",
    "            html = (\n",
    "                \"<!doctype html><html><head><meta charset='utf-8'/>\"\n",
    "                \"<title>VSP Export</title>\"\n",
    "                \"<style>body{font-family:Arial;padding:24px} table{border-collapse:collapse;width:100%}\"\n",
    "                \"td,th{border:1px solid #eee;padding:6px 8px}</style></head><body>\"\n",
    "                f\"<h2>VSP Export v3</h2><p>Generated: {nowz()}</p><p><b>Total findings:</b> {total}</p>\"\n",
    "                \"<h3>By severity</h3><table><tr><th>Severity</th><th>Count</th></tr>\" + rows + \"</table>\"\n",
    "                \"</body></html>\"\n",
    "            )\n",
    "            try:\n",
    "                with open(html_path,'w',encoding='utf-8') as f:\n",
    "                    f.write(html)\n",
    "            except Exception:\n",
    "                pass\n",
    "\n",
    "        return report_dir\n",
    "\n",
    "    def zip_dir(report_dir: str):\n",
    "        tmp = tempfile.NamedTemporaryFile(prefix='vsp_export_', suffix='.zip', delete=False)\n",
    "        tmp.close()\n",
    "        with zipfile.ZipFile(tmp.name, 'w', compression=zipfile.ZIP_DEFLATED) as z:\n",
    "            for root, _, files in os.walk(report_dir):\n",
    "                for fn in files:\n",
    "                    ap = os.path.join(root, fn)\n",
    "                    rel = os.path.relpath(ap, report_dir)\n",
    "                    z.write(ap, arcname=rel)\n",
    "        return tmp.name\n",
    "\n",
    "    def pdf_from_html(html_file: str, timeout_sec: int = 180):\n",
    "        exe = shutil.which('wkhtmltopdf')\n",
    "        if not exe:\n",
    "            return None, 'wkhtmltopdf_missing'\n",
    "        tmp = tempfile.NamedTemporaryFile(prefix='vsp_export_', suffix='.pdf', delete=False)\n",
    "        tmp.close()\n",
    "        try:\n",
    "            subprocess.run([exe, '--quiet', html_file, tmp.name], timeout=timeout_sec, check=True)\n",
    "            if os.path.isfile(tmp.name) and os.path.getsize(tmp.name) > 0:\n",
    "                return tmp.name, None\n",
    "            return None, 'wkhtmltopdf_empty_output'\n",
    "        except Exception as ex:\n",
    "            return None, 'wkhtmltopdf_failed:' + type(ex).__name__\n",
    "\n",
    "    # PROBE proves this handler is active\n",
    "    if (request.args.get('probe') or '') == '1':\n",
    "        resp = jsonify({'ok': True, 'probe': 'EXPORT_FORCEFS_V2', 'rid_norm': rid_norm, 'fmt': fmt})\n",
    "        resp.headers['X-VSP-EXPORT-AVAILABLE'] = '1'\n",
    "        resp.headers['X-VSP-EXPORT-MODE'] = 'EXPORT_FORCEFS_V2'\n",
    "        return resp\n",
    "\n",
    "    run_dir = find_run_dir(rid_norm)\n",
    "    if (not run_dir) or (not os.path.isdir(run_dir)):\n",
    "        resp = jsonify({'ok': False, 'error': 'RUN_DIR_NOT_FOUND', 'rid_norm': rid_norm})\n",
    "        resp.headers['X-VSP-EXPORT-AVAILABLE'] = '0'\n",
    "        resp.headers['X-VSP-EXPORT-MODE'] = 'EXPORT_FORCEFS_V2'\n",
    "        return resp, 404\n",
    "\n",
    "    report_dir = ensure_report(run_dir)\n",
    "    html_file = os.path.join(report_dir, 'export_v3.html')\n",
    "\n",
    "    if fmt == 'html':\n",
    "        resp = send_file(html_file, mimetype='text/html', as_attachment=True, download_name=rid_norm + '.html')\n",
    "        resp.headers['X-VSP-EXPORT-AVAILABLE'] = '1'\n",
    "        resp.headers['X-VSP-EXPORT-MODE'] = 'EXPORT_FORCEFS_V2'\n",
    "        return resp\n",
    "\n",
    "    if fmt == 'zip':\n",
    "        zpath = zip_dir(report_dir)\n",
    "        resp = send_file(zpath, mimetype='application/zip', as_attachment=True, download_name=rid_norm + '.zip')\n",
    "        resp.headers['X-VSP-EXPORT-AVAILABLE'] = '1'\n",
    "        resp.headers['X-VSP-EXPORT-MODE'] = 'EXPORT_FORCEFS_V2'\n",
    "        return resp\n",
    "\n",
    "    if fmt == 'pdf':\n",
    "        pdf_path, err = pdf_from_html(html_file, timeout_sec=180)\n",
    "        if pdf_path:\n",
    "            resp = send_file(pdf_path, mimetype='application/pdf', as_attachment=True, download_name=rid_norm + '.pdf')\n",
    "            resp.headers['X-VSP-EXPORT-AVAILABLE'] = '1'\n",
    "            resp.headers['X-VSP-EXPORT-MODE'] = 'EXPORT_FORCEFS_V2'\n",
    "            return resp\n",
    "        resp = jsonify({'ok': False, 'error': 'PDF_EXPORT_FAILED', 'detail': err})\n",
    "        resp.headers['X-VSP-EXPORT-AVAILABLE'] = '0'\n",
    "        resp.headers['X-VSP-EXPORT-MODE'] = 'EXPORT_FORCEFS_V2'\n",
    "        return resp, 500\n",
    "\n",
    "    resp = jsonify({'ok': False, 'error': 'BAD_FMT', 'fmt': fmt, 'allowed': ['html','zip','pdf']})\n",
    "    resp.headers['X-VSP-EXPORT-AVAILABLE'] = '0'\n",
    "    resp.headers['X-VSP-EXPORT-MODE'] = 'EXPORT_FORCEFS_V2'\n",
    "    return resp, 400\n",
]

new_func = with_ind(new_body)
new_lines = lines[:def_line_idx] + [new_func] + lines[end_idx:]
p.write_text("".join(new_lines), encoding="utf-8")
print("[OK] patched _vsp_export_v3_override => EXPORT_FORCEFS_V2")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
