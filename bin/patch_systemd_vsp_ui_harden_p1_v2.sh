#!/usr/bin/env bash
set -euo pipefail

UNIT="/etc/systemd/system/vsp-ui-8910.service"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need sudo; need systemctl; need date; need python3

sudo test -f "$UNIT" || { echo "[ERR] missing unit: $UNIT"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
sudo cp -f "$UNIT" "${UNIT}.bak_harden_${TS}"
echo "[BACKUP] ${UNIT}.bak_harden_${TS}"

python3 - <<'PY'
import re, subprocess, sys
UNIT="/etc/systemd/system/vsp-ui-8910.service"

# read
s=subprocess.check_output(["sudo","cat",UNIT], text=True, errors="replace")

def upsert_kv(section, key, value):
    # ensure section exists
    nonlocal_s = globals().get("S")
    S=globals()["S"]
    if f"[{section}]" not in S:
        S += f"\n[{section}]\n"
    # replace if exists in section else append right after section header
    sec_pat = rf"(?ms)^\[{re.escape(section)}\]\s*(.*?)(?=^\[|\Z)"
    m=re.search(sec_pat, S)
    if not m:
        return
    block=m.group(0)
    # if key exists (even multiple), replace all with single key=value
    if re.search(rf"(?m)^{re.escape(key)}=", block):
        block2=re.sub(rf"(?m)^{re.escape(key)}=.*$", f"{key}={value}", block)
        # collapse duplicates: keep first occurrence only
        lines=block2.splitlines()
        out=[]
        seen=False
        for ln in lines:
            if ln.startswith(key+"="):
                if not seen:
                    out.append(ln); seen=True
            else:
                out.append(ln)
        block2="\n".join(out) + ("\n" if block2.endswith("\n") else "")
    else:
        # insert right after header
        block2=re.sub(rf"(?m)^\[{re.escape(section)}\]\s*$",
                      f"[{section}]\n{key}={value}", block, count=1)
    S = S[:m.start()] + block2 + S[m.end():]
    globals()["S"]=S

def upsert_exec(section, directive, cmd):
    # remove existing directive lines in section and add one clean line
    nonlocal_s = globals().get("S")
    S=globals()["S"]
    if f"[{section}]" not in S:
        S += f"\n[{section}]\n"
    sec_pat = rf"(?ms)^\[{re.escape(section)}\]\s*(.*?)(?=^\[|\Z)"
    m=re.search(sec_pat, S)
    if not m:
        return
    block=m.group(0)
    block=re.sub(rf"(?m)^{re.escape(directive)}=.*$\n?", "", block)
    # append at end of section block (before next section)
    if not block.endswith("\n"): block += "\n"
    block += f"{directive}={cmd}\n"
    S = S[:m.start()] + block + S[m.end():]
    globals()["S"]=S

S=s

# --- commercial hardening knobs ---
upsert_kv("Service","Type","simple")
upsert_kv("Service","Restart","on-failure")
upsert_kv("Service","RestartSec","1")
upsert_kv("Service","TimeoutStartSec","45")
upsert_kv("Service","TimeoutStopSec","25")
upsert_kv("Service","KillSignal","SIGINT")      # faster than SIGTERM with gunicorn in practice
upsert_kv("Service","KillMode","mixed")         # kill workers too
upsert_kv("Service","SendSIGKILL","yes")
upsert_kv("Service","SuccessExitStatus","143")  # SIGTERM/SIGINT common “clean” exits

# clean ExecStartPre: don't show FAILURE when nothing to kill
# Keep your fuser-kill, but make pkill non-fatal and quiet.
upsert_exec("Service","ExecStartPre","/usr/sbin/fuser -k 8910/tcp || true")
upsert_exec("Service","ExecStartPre","/bin/bash -lc '/usr/bin/pkill -f \"gunicorn .*8910\" >/dev/null 2>&1 || true'")
upsert_exec("Service","ExecStartPre","/bin/bash -lc 'sleep 0.2'")

# Force a deterministic stop + port cleanup
upsert_exec("Service","ExecStop","/bin/kill -s SIGINT $MAINPID")
upsert_exec("Service","ExecStopPost","/usr/sbin/fuser -k 8910/tcp || true")

# Readiness gate: fail if /vsp5 not reachable after ~18s (60*0.3)
upsert_exec(
    "Service",
    "ExecStartPost",
    "/bin/bash -lc 'for i in $(seq 1 60); do "
    "curl -fsS --connect-timeout 1 http://127.0.0.1:8910/vsp5 >/dev/null && exit 0; "
    "sleep 0.3; "
    "done; echo \"[READY] /vsp5 not reachable\" >&2; exit 1'"
)

# Write back
subprocess.check_call(["sudo","bash","-lc", f"cat > {UNIT} <<'EOF'\n{S.rstrip()}\nEOF\n"])
print("[OK] unit hardened (P1 v2)")
PY

sudo systemctl daemon-reload
sudo systemctl restart vsp-ui-8910.service

echo "== status =="
sudo systemctl --no-pager -l status vsp-ui-8910.service | sed -n '1,90p' || true

echo "== ss =="
ss -ltnp | grep ':8910' || true

echo "== curl =="
curl -sS -I http://127.0.0.1:8910/vsp5 | head -n 12 || true
