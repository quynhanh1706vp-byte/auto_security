#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BIN="bin"
OUT="out_ci"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need awk; need sed; need grep; need find; need sort; need head; need wc; need python3

TS="$(date +%Y%m%d_%H%M%S)"
LOG_TXT="$OUT/p44_index_inventory_${TS}.txt"
LOG_JSON="$OUT/p44_index_inventory_${TS}.json"

ACTIVE_MD="$BIN/INDEX_ACTIVE_SCRIPTS.md"
QUAR_MD="$BIN/INDEX_QUARANTINE.md"

backup_if_exists(){
  local f="$1"
  if [ -f "$f" ]; then
    cp -f "$f" "${f}.bak_${TS}"
    echo "[BACKUP] ${f}.bak_${TS}"
  fi
}

desc_of_file(){
  local f="$1"
  python3 - "$f" <<'PY'
import re, sys, pathlib
p=pathlib.Path(sys.argv[1])
lines=p.read_text(encoding="utf-8", errors="replace").splitlines()

# 1) banner line: == [X] ...
for ln in lines[:80]:
    m=re.search(r'==\s*\[([^\]]+)\]\s*(.+)?', ln)
    if m:
        out=f"{m.group(1)}: {(m.group(2) or '').strip()}".strip(": ").strip()
        print(out[:160] if out else "—")
        raise SystemExit(0)

# 2) first comment line after shebang
start=1 if (lines and lines[0].startswith("#!")) else 0
for ln in lines[start:start+80]:
    t=ln.strip()
    if not t:
        continue
    if t.startswith("#"):
        t=t.lstrip("#").strip()
        print((t[:160] if t else "—"))
        raise SystemExit(0)
    break

print("—")
PY
}

run_cmd_of_file(){
  local f="$1"
  local base
  base="$(basename "$f")"
  case "$base" in
    *.sh) echo "bash $BIN/$base" ;;
    *.py) echo "python3 $BIN/$base" ;;
    *) echo "$BIN/$base" ;;
  esac
}

is_disabled(){ [[ "$(basename "$1")" == *.disabled_* ]]; }
is_backup(){ [[ "$(basename "$1")" == *.bak_* ]]; }
is_quarantine(){
  local b="$(basename "$1")"
  [[ "$b" == _quarantine_* || "$b" == *quarantine* ]]
}

reason_from_readme(){
  local base="$1"
  python3 - "$base" <<'PY'
import sys, pathlib, glob
base=sys.argv[1]
cands=[]
for pat in ["README*", "docs/README*", "bin/README*"]:
    cands += glob.glob(pat)
cands=[p for p in cands if pathlib.Path(p).is_file()]
for fp in cands:
    try:
        for ln in pathlib.Path(fp).read_text(encoding="utf-8", errors="replace").splitlines():
            if base in ln:
                s=ln.strip()
                if len(s)>220: s=s[:217]+"..."
                print(f"{fp}: {s}")
                raise SystemExit(0)
    except Exception:
        continue
print("README: (no match) — see file header")
PY
}

echo "== [P44] index & inventory ==" | tee "$LOG_TXT"

backup_if_exists "$ACTIVE_MD" | tee -a "$LOG_TXT"
backup_if_exists "$QUAR_MD"   | tee -a "$LOG_TXT"

mapfile -t ALL < <(find "$BIN" -maxdepth 1 -type f \( -name "*.sh" -o -name "*.py" -o -name "*.md" \) | sort)

active_list=()
quar_list=()

for f in "${ALL[@]}"; do
  [ -f "$f" ] || continue
  is_backup "$f" && continue
  is_disabled "$f" && continue

  if is_quarantine "$f"; then
    quar_list+=("$f")
    continue
  fi

  case "$(basename "$f")" in
    *.sh|*.py) active_list+=("$f") ;;
    *) : ;;
  esac
done

{
  echo "# INDEX_ACTIVE_SCRIPTS"
  echo
  echo "- Generated: ${TS}"
  echo "- Root: $(pwd)"
  echo
  echo "| Script | 1-line purpose | Run |"
  echo "|---|---|---|"
  for f in "${active_list[@]}"; do
    base="$(basename "$f")"
    desc="$(desc_of_file "$f" | tr '\n' ' ' | sed 's/|/\\|/g')"
    run="$(run_cmd_of_file "$f" | sed 's/|/\\|/g')"
    echo "| \`$base\` | $desc | \`$run\` |"
  done
  echo
  echo "## Notes"
  echo "- \"Active\" = not *.disabled_*, not *.bak_*, not quarantine."
} > "$ACTIVE_MD"

{
  echo "# INDEX_QUARANTINE"
  echo
  echo "- Generated: ${TS}"
  echo "- Root: $(pwd)"
  echo
  echo "## Summary"
  echo "- Quarantine files in bin/: **${#quar_list[@]}**"
  echo
  echo "| File | Why (from README or fallback) |"
  echo "|---|---|"
  for f in "${quar_list[@]}"; do
    base="$(basename "$f")"
    why="$(reason_from_readme "$base" | tr '\n' ' ' | sed 's/|/\\|/g')"
    echo "| \`$base\` | $why |"
  done
  echo
  echo "## Detail"
  echo "- Quarantine convention: keep risky/legacy/experimental scripts here; do not call from release gate."
} > "$QUAR_MD"

active_count="${#active_list[@]}"
quar_count="${#quar_list[@]}"

echo "[OK] wrote: $ACTIVE_MD (active=$active_count)" | tee -a "$LOG_TXT"
echo "[OK] wrote: $QUAR_MD (quarantine=$quar_count)" | tee -a "$LOG_TXT"

python3 - <<PY > "$LOG_JSON"
import json
print(json.dumps({
  "ok": True,
  "ts": "$TS",
  "active_count": int("$active_count"),
  "quarantine_count": int("$quar_count"),
  "files": {
    "INDEX_ACTIVE_SCRIPTS": "$ACTIVE_MD",
    "INDEX_QUARANTINE": "$QUAR_MD"
  }
}, indent=2))
PY

echo "[OK] log: $LOG_TXT"
echo "[OK] json: $LOG_JSON"
