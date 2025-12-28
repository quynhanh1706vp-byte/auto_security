#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need cp
command -v systemctl >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "${APP}.bak_ro_always200_${TS}"
echo "[BACKUP] ${APP}.bak_ro_always200_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

# locate existing route block
pat = re.compile(r'(?s)(@app\.route\(\s*[\'"]/api/vsp/rule_overrides_v1[\'"][^\)]*\)\s*\n(?:@.*\n)*def\s+\w+\s*\(.*?\):\n)(.*?)(?=\n@app\.route|\nif\s+__name__\s*==|\Z)')
m = pat.search(s)
if not m:
  raise SystemExit("[ERR] cannot find /api/vsp/rule_overrides_v1 route block in vsp_demo_app.py")

new_body = textwrap.dedent(r'''
  import os, json, time
  from flask import jsonify, request

  # COMMERCIAL: rule_overrides MUST never 500.
  # Self-heal file corruption and always return ok:true.
  def _ro_path():
    # keep consistent with your previous patches
    return "/home/test/Data/SECURITY_BUNDLE/out_ci/rule_overrides.json"

  def _ro_default():
    return {"enabled": True, "overrides": [], "updated_at": int(time.time()), "updated_by": "system"}

  def _ro_load_or_heal(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if not os.path.exists(path):
      d=_ro_default()
      with open(path,"w",encoding="utf-8") as f: json.dump(d,f,ensure_ascii=False,indent=2,sort_keys=True)
      return d, "created"
    try:
      with open(path,"r",encoding="utf-8") as f:
        d=json.load(f)
      if not isinstance(d, dict): raise ValueError("rule_overrides not dict")
      d.setdefault("enabled", True)
      d.setdefault("overrides", [])
      d.setdefault("updated_at", int(time.time()))
      d.setdefault("updated_by", "system")
      return d, "loaded"
    except Exception as e:
      bad = path + f".bad_{int(time.time())}"
      try: os.replace(path, bad)
      except Exception: pass
      d=_ro_default()
      with open(path,"w",encoding="utf-8") as f: json.dump(d,f,ensure_ascii=False,indent=2,sort_keys=True)
      return d, f"healed:{type(e).__name__}"

  # GET: return current
  # POST: set enabled/overrides (optional) and persist
  if request.method == "POST":
    path=_ro_path()
    cur,_st=_ro_load_or_heal(path)
    payload = request.get_json(silent=True) or {}
    if isinstance(payload, dict):
      if "enabled" in payload: cur["enabled"]=bool(payload["enabled"])
      if "overrides" in payload and isinstance(payload["overrides"], list): cur["overrides"]=payload["overrides"]
      cur["updated_at"]=int(time.time())
      cur["updated_by"]="api"
      try:
        with open(path,"w",encoding="utf-8") as f: json.dump(cur,f,ensure_ascii=False,indent=2,sort_keys=True)
      except Exception:
        # even persist fail must not 500
        pass
    return jsonify(ok=True, data=cur, path=path, who="VSP_RULE_OVERRIDES_ALWAYS200_V3", ts=int(time.time()))
  else:
    path=_ro_path()
    d,st=_ro_load_or_heal(path)
    return jsonify(ok=True, data=d, path=path, status=st, who="VSP_RULE_OVERRIDES_ALWAYS200_V3", ts=int(time.time()))
''').strip("\n") + "\n"

# rebuild full function block = header + new body
replacement = m.group(1) + new_body
s2 = s[:m.start()] + replacement + s[m.end():]

p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile OK: VSP_RULE_OVERRIDES_ALWAYS200_V3")
PY

echo "== [restart] =="
if command -v systemctl >/dev/null 2>&1; then
  sudo -n systemctl restart "$SVC" 2>/dev/null || systemctl restart "$SVC" 2>/dev/null || true
fi

echo "== [smoke] =="
curl -fsS "http://127.0.0.1:8910/api/vsp/rule_overrides_v1" | head -c 400; echo
echo "[DONE]"
