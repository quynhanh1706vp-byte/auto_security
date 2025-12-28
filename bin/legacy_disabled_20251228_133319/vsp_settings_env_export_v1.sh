#!/usr/bin/env bash
# VSP_SETTINGS_ENV_EXPORT_V1
set -euo pipefail

UI_ROOT="${VSP_UI_ROOT:-/home/test/Data/SECURITY_BUNDLE/ui}"
SETTINGS="${UI_ROOT}/out_ci/vsp_settings_v2/settings.json"

VSP_TIMEOUT_KICS_SEC="${VSP_TIMEOUT_KICS_SEC:-900}"
VSP_TIMEOUT_CODEQL_SEC="${VSP_TIMEOUT_CODEQL_SEC:-1800}"
VSP_TIMEOUT_TRIVY_SEC="${VSP_TIMEOUT_TRIVY_SEC:-900}"
VSP_DEGRADE_GRACEFUL="${VSP_DEGRADE_GRACEFUL:-true}"

if [ -s "$SETTINGS" ]; then
  read -r VSP_TIMEOUT_KICS_SEC VSP_TIMEOUT_CODEQL_SEC VSP_TIMEOUT_TRIVY_SEC VSP_DEGRADE_GRACEFUL < <(
    python3 - <<'PY'
import json, sys
p=sys.argv[1]
try:
    s=json.load(open(p,'r',encoding='utf-8'))
except Exception:
    s={}
t=s.get("timeouts") if isinstance(s.get("timeouts"), dict) else {}
def geti(k, d):
    try: return int(t.get(k, d))
    except Exception: return d
k=geti("kics_sec", 900)
c=geti("codeql_sec", 1800)
tr=geti("trivy_sec", 900)
dg=s.get("degrade_graceful", True)
dg = "true" if (dg is True or str(dg).strip().lower() not in ("0","false","no","off")) else "false"
print(k, c, tr, dg)
PY
"$SETTINGS"
  )
fi

export VSP_TIMEOUT_KICS_SEC VSP_TIMEOUT_CODEQL_SEC VSP_TIMEOUT_TRIVY_SEC VSP_DEGRADE_GRACEFUL
