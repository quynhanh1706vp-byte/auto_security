#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_afterreq_status_ci_kics_${TS}"
echo "[BACKUP] $F.bak_afterreq_status_ci_kics_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

TAG = "# === VSP_AFTERREQ_STATUS_INJECT_CI_KICS_WINLAST_V1 ==="
if any(TAG in l for l in lines):
    print("[OK] tag already present, skip")
    raise SystemExit(0)

# Find candidate after_request blocks: @app.after_request + def ... containing both run_status_v1 and run_status_v2
cands = []
i = 0
while i < len(lines):
    if re.match(r'^\s*@app\.after_request\b', lines[i]):
        # find def line
        j = i + 1
        while j < len(lines) and not re.match(r'^\s*def\s+\w+\s*\(', lines[j]):
            j += 1
        if j >= len(lines):
            i += 1
            continue
        def_i = j
        indent = re.match(r'^([ \t]*)def\b', lines[def_i]).group(1)
        # find end of function: next def at same indent (or EOF)
        k = def_i + 1
        end = None
        pat_next = re.compile(r'^' + re.escape(indent) + r'def\s+\w+\s*\(')
        while k < len(lines):
            if pat_next.match(lines[k]):
                end = k
                break
            k += 1
        if end is None:
            end = len(lines)
        block = "".join(lines[def_i:end])
        if ("/api/vsp/run_status_v1/" in block) and ("/api/vsp/run_status_v2/" in block):
            cands.append((def_i, end, indent))
        i = end
        continue
    i += 1

if not cands:
    raise SystemExit("[ERR] cannot find after_request block containing run_status_v1/v2")

# Pick the earliest-defined after_request among candidates (registered first => runs LAST => we WIN)
def_i, end, indent = sorted(cands, key=lambda x: x[0])[0]
block_lines = lines[def_i:end]

# Find LAST return line in this block (prefer 'return resp' but accept any return)
ret_idx = None
for idx in range(len(block_lines)-1, -1, -1):
    if re.match(r'^\s*return\b', block_lines[idx]):
        ret_idx = idx
        break
if ret_idx is None:
    raise SystemExit("[ERR] cannot find return in target after_request block")

ret_line = block_lines[ret_idx]
ret_indent = re.match(r'^([ \t]*)return\b', ret_line).group(1)

inj = []
inj.append(ret_indent + TAG + "\n")
inj.append(ret_indent + "try:\n")
inj.append(ret_indent + "    import json as _json\n")
inj.append(ret_indent + "    from pathlib import Path as _Path\n")
inj.append(ret_indent + "    from flask import request as _req\n")
inj.append(ret_indent + "    _path = (_req.path or '')\n")
inj.append(ret_indent + "    if _path.startswith('/api/vsp/run_status_v1/') or _path.startswith('/api/vsp/run_status_v2/'):\n")
inj.append(ret_indent + "        _rid = (_path.rsplit('/', 1)[-1] or '').split('?', 1)[0].strip()\n")
inj.append(ret_indent + "        _rid_norm = _rid[4:].strip() if _rid.startswith('RUN_') else _rid\n")
inj.append(ret_indent + "        _obj = None\n")
inj.append(ret_indent + "        try:\n")
inj.append(ret_indent + "            _obj = resp.get_json(silent=True)\n")
inj.append(ret_indent + "        except Exception:\n")
inj.append(ret_indent + "            _obj = None\n")
inj.append(ret_indent + "        if not isinstance(_obj, dict):\n")
inj.append(ret_indent + "            try:\n")
inj.append(ret_indent + "                _raw = (resp.get_data(as_text=True) or '').lstrip()\n")
inj.append(ret_indent + "                if _raw.startswith('{'):\n")
inj.append(ret_indent + "                    _obj = _json.loads(_raw)\n")
inj.append(ret_indent + "            except Exception:\n")
inj.append(ret_indent + "                _obj = None\n")
inj.append(ret_indent + "        if isinstance(_obj, dict):\n")
inj.append(ret_indent + "            _obj.setdefault('ci_run_dir', None)\n")
inj.append(ret_indent + "            _obj.setdefault('kics_verdict', '')\n")
inj.append(ret_indent + "            _obj.setdefault('kics_total', 0)\n")
inj.append(ret_indent + "            _obj.setdefault('kics_counts', {})\n")
inj.append(ret_indent + "            _ci = (_obj.get('ci_run_dir') or '').strip()\n")
inj.append(ret_indent + "            if (not _ci) and _rid_norm:\n")
inj.append(ret_indent + "                try:\n")
inj.append(ret_indent + "                    _ci = _vsp_guess_ci_run_dir_from_rid_v33(_rid_norm) or ''\n")
inj.append(ret_indent + "                except Exception:\n")
inj.append(ret_indent + "                    _ci = ''\n")
inj.append(ret_indent + "                if _ci:\n")
inj.append(ret_indent + "                    _obj['ci_run_dir'] = _ci\n")
inj.append(ret_indent + "            _ci = (_obj.get('ci_run_dir') or '').strip()\n")
inj.append(ret_indent + "            if _ci:\n")
inj.append(ret_indent + "                _ks = _Path(_ci) / 'kics' / 'kics_summary.json'\n")
inj.append(ret_indent + "                if _ks.is_file():\n")
inj.append(ret_indent + "                    try:\n")
inj.append(ret_indent + "                        _jj = _json.loads(_ks.read_text(encoding='utf-8', errors='ignore') or '{}')\n")
inj.append(ret_indent + "                        if isinstance(_jj, dict):\n")
inj.append(ret_indent + "                            _obj['kics_verdict'] = str(_jj.get('verdict') or _obj.get('kics_verdict') or '')\n")
inj.append(ret_indent + "                            try:\n")
inj.append(ret_indent + "                                _obj['kics_total'] = int(_jj.get('total') or _obj.get('kics_total') or 0)\n")
inj.append(ret_indent + "                            except Exception:\n")
inj.append(ret_indent + "                                pass\n")
inj.append(ret_indent + "                            _cc = _jj.get('counts')\n")
inj.append(ret_indent + "                            if isinstance(_cc, dict):\n")
inj.append(ret_indent + "                                _obj['kics_counts'] = _cc\n")
inj.append(ret_indent + "                    except Exception:\n")
inj.append(ret_indent + "                        pass\n")
inj.append(ret_indent + "            try:\n")
inj.append(ret_indent + "                resp.set_data(_json.dumps(_obj, ensure_ascii=False))\n")
inj.append(ret_indent + "                resp.mimetype = 'application/json'\n")
inj.append(ret_indent + "            except Exception:\n")
inj.append(ret_indent + "                pass\n")
inj.append(ret_indent + "except Exception:\n")
inj.append(ret_indent + "    pass\n")

# Insert before last return
new_block = block_lines[:ret_idx] + inj + block_lines[ret_idx:]
out = lines[:def_i] + new_block + lines[end:]
p.write_text("".join(out), encoding="utf-8")

print(f"[OK] patched after_request def at lines {def_i+1}..{end} (injected before last return)")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-gateway
sudo systemctl is-active vsp-ui-gateway && echo SVC_OK

echo "== [VERIFY] =="
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/RUN_VSP_CI_20251214_224900" \
 | jq '{ci_run_dir,kics_verdict,kics_total,kics_counts}'
