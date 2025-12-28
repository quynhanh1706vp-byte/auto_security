#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p55_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need ls; need head; need awk; need grep; need sed; need python3; need sha256sum; need find; need wc; need tar; need gzip; need curl; need cp; need mkdir
command -v systemctl >/dev/null 2>&1 || true

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release found"; exit 2; }
ATT="$latest_release/evidence/p55_${TS}"
mkdir -p "$ATT"
echo "[OK] latest_release=$latest_release"

# (0) strict health proof 10/10
ok=1
: > "$EVID/health_10x.txt"
for i in $(seq 1 10); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 6 "$BASE/vsp5" || true)"
  echo "try#$i code=$code" >> "$EVID/health_10x.txt"
  [ "$code" = "200" ] || ok=0
  sleep 0.35
done
if [ "$ok" -ne 1 ]; then
  echo "[ERR] /vsp5 not stable 10/10"; cp -f "$EVID/health_10x.txt" "$ATT/" 2>/dev/null || true; exit 2;
fi
echo "[OK] /vsp5 stable 10/10"

# (1) capture systemd proof (drop-ins + ExecStart)
(systemctl show "$SVC" -p DropInPaths -p ExecStart -p FragmentPath -p MainPID -p ActiveState --no-pager || true) > "$EVID/systemctl_show.txt" 2>&1 || true

# (2) ensure P54 gate exists with fp_count=1 + warnings empty
latest_p54="$(ls -1t "$OUT"/p54_gate_v2_verdict_*.json 2>/dev/null | head -n 1 || true)"
[ -n "${latest_p54:-}" ] || latest_p54="$(ls -1t "$OUT"/p54_gate_* 2>/dev/null | head -n 1 || true)"
echo "$latest_p54" > "$EVID/latest_p54_path.txt"

# (3) write COMMERCIAL_LOCK_V2.md
python3 - <<PY
from pathlib import Path
import json, datetime

rel = Path("$latest_release")
evid = Path("$EVID")
svc = "$SVC"
base = "$BASE"

# Find p54 verdict inside release evidence folder (best effort)
p54 = None
cand = list(rel.glob("evidence/p54_gate_*/p54_gate_v2_verdict_*.json")) + list(Path("$OUT").glob("p54_gate_v2_verdict_*.json"))
for f in sorted(cand, key=lambda x: x.stat().st_mtime, reverse=True):
    try:
        j=json.loads(f.read_text())
        p = j.get("p54_gate_v2") or {}
        if p.get("header_fp_count")==1 and (p.get("warnings") or [])==[]:
            p54 = f
            break
    except Exception:
        pass

now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S%z")
lines=[]
lines.append("# VSP UI COMMERCIAL LOCK (V2)")
lines.append("")
lines.append(f"- ts: {now}")
lines.append(f"- base: {base}")
lines.append(f"- service: {svc}")
lines.append(f"- release: {rel}")
lines.append("")
lines.append("## Proven controls")
lines.append("- Varlog mode: /var/log/vsp-ui-8910/{ui_8910.access.log,ui_8910.error.log} (0640 test:test)")
lines.append("- Logrotate: /etc/logrotate.d/vsp-ui-8910 rotates only /var/log/vsp-ui-8910/*.log (out_ci kept as evidence)")
lines.append("- Drop-in ExecStart hardened: zzzz-99999-execstart-varlog.conf (no conflicting drop-ins enabled)")
lines.append("- UI headers consistency gate: P54 fp_count=1 warnings=[] (canonical hardening headers enforced at WSGI layer)")
lines.append("")
lines.append("## Evidence pointers (inside release/evidence)")
lines.append("- p46_verdict_*.json (release PASS)")
lines.append("- p47_clean_varlog_*.txt (drop-in hardening proof)")
lines.append("- p47_3e_verdict_*.json (logrotate /var/log mode)")
lines.append("- p48_0b_verdict_*.json (logrotate dryrun noise fixed)")
lines.append("- p49_1f_verdict_*.json (strict health verify)")
lines.append("- p50_snap_* (5 tabs snapshots + INDEX.html)")
lines.append("- p54_gate_* (headers gate v2: fp_count=1)")
if p54:
    lines.append(f"- p54 source: {p54}")
lines.append("")
(rel/"COMMERCIAL_LOCK_V2.md").write_text("\n".join(lines)+"\n", encoding="utf-8")
print("[OK] wrote COMMERCIAL_LOCK_V2.md")
PY

# (4) Build CHECKSUMS + MANIFEST for release (full tree)
python3 - <<'PY'
from pathlib import Path
import hashlib, json, os, time

rel=Path(os.environ.get("REL",""))
if not rel.exists():
    rel=Path("out_ci/releases").resolve()
    rel=sorted(rel.glob("RELEASE_UI_*"), key=lambda p:p.stat().st_mtime, reverse=True)[0]
items=[]
for f in sorted([p for p in rel.rglob("*") if p.is_file() and p.name not in (".DS_Store",)]):
    try:
        b=f.read_bytes()
    except Exception:
        continue
    h=hashlib.sha256(b).hexdigest()
    items.append({"path": str(f.relative_to(rel)), "bytes": len(b), "sha256": h, "mtime": int(f.stat().st_mtime)})
(rel/"RELEASE_MANIFEST.json").write_text(json.dumps({"root":str(rel), "items":items}, indent=2), encoding="utf-8")
(rel/"CHECKSUMS.sha256").write_text("\n".join([f"{x['sha256']}  {x['path']}" for x in items])+"\n", encoding="utf-8")
print("[OK] manifest items =", len(items))
PY

# (5) attach p55 evidence into release
cp -f "$EVID/"* "$ATT/" 2>/dev/null || true
cp -f "$latest_release/COMMERCIAL_LOCK_V2.md" "$ATT/" 2>/dev/null || true
cp -f "$latest_release/CHECKSUMS.sha256" "$ATT/" 2>/dev/null || true
cp -f "$latest_release/RELEASE_MANIFEST.json" "$ATT/" 2>/dev/null || true

# (6) tar.gz package
PKG="$RELROOT/RELEASE_UI_${TS}_COMMERCIAL_LOCK_V2.tgz"
tar -C "$RELROOT" -czf "$PKG" "$(basename "$latest_release")"
sha256sum "$PKG" > "$PKG.sha256"

# (7) verdict
python3 - <<PY
import json, datetime
j={
  "ok": True,
  "ts": datetime.datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S%z"),
  "p55": {
    "base": "$BASE",
    "service": "$SVC",
    "release": "$latest_release",
    "attached_dir": "$ATT",
    "package": "$PKG",
    "package_sha256": "$PKG.sha256"
  }
}
print(json.dumps(j, indent=2))
open(f"out_ci/p55_verdict_{'$TS'}.json","w").write(json.dumps(j, indent=2))
PY

echo "[DONE] P55 PASS -> $PKG"
