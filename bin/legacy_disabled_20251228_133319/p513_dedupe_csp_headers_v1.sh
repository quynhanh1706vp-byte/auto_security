#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

T="wsgi_vsp_ui_gateway.py"
[ -f "$T" ] || { echo "[ERR] missing $T"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p513_${TS}"
mkdir -p "$OUT"
cp -f "$T" "$OUT/$(basename "$T").bak_${TS}"
echo "[OK] backup => $OUT/$(basename "$T").bak_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P513_DEDUPE_CSP_HEADERS_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Find the CSP middleware class (from P510)
if "class _VSPHeadersCSPR0V1" not in s:
    raise SystemExit("[ERR] cannot find class _VSPHeadersCSPR0V1 (P510 block missing?)")

# Inject _hdr_del and use it before setting headers
# 1) add _hdr_del method after _hdr_set if not exists
if "def _hdr_del(" not in s:
    s = re.sub(
        r"(def _hdr_set\(self, headers, name, value\):[\s\S]*?return out\n)",
        r"\1\n    def _hdr_del(self, headers, name):\n"
        r"        n=name.lower()\n"
        r"        return [(k,v) for (k,v) in (headers or []) if (k or '').lower()!=n]\n",
        s,
        count=1,
    )

# 2) In __call__, before setting CSP/COOP/CORP, delete duplicates
s = s.replace(
    "headers=self._hdr_set(headers, \"Content-Security-Policy\", self.csp_ro)",
    "headers=self._hdr_del(headers, \"Content-Security-Policy\")\n"
    "            headers=self._hdr_set(headers, \"Content-Security-Policy\", self.csp_ro)"
)
s = s.replace(
    "headers=self._hdr_set(headers, \"Content-Security-Policy-Report-Only\", self.csp_ro)",
    "headers=self._hdr_del(headers, \"Content-Security-Policy-Report-Only\")\n"
    "            headers=self._hdr_set(headers, \"Content-Security-Policy-Report-Only\", self.csp_ro)"
)
s = s.replace(
    "headers=self._hdr_set(headers, \"Cross-Origin-Opener-Policy\", \"same-origin\")",
    "headers=self._hdr_del(headers, \"Cross-Origin-Opener-Policy\")\n"
    "            headers=self._hdr_set(headers, \"Cross-Origin-Opener-Policy\", \"same-origin\")"
)
s = s.replace(
    "headers=self._hdr_set(headers, \"Cross-Origin-Resource-Policy\", \"same-origin\")",
    "headers=self._hdr_del(headers, \"Cross-Origin-Resource-Policy\")\n"
    "            headers=self._hdr_set(headers, \"Cross-Origin-Resource-Policy\", \"same-origin\")"
)

# add marker
s = s.rstrip() + "\n# " + MARK + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched", p)
PY

python3 -m py_compile "$T" && echo "[OK] py_compile $T"
sudo systemctl restart vsp-ui-8910.service
echo "[OK] restarted"
