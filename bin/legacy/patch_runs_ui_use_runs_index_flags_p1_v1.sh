#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_use_index_flags_${TS}" && echo "[BACKUP] $F.bak_use_index_flags_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

# Hard patch: remove enrich-by-status logic if present and force row flags from item
# We patch in a targeted way: replace enrichFlags() to only read item fields and disable mapLimit/status calls.

def sub_once(pattern, repl):
    global s
    s2, n = re.subn(pattern, repl, s, flags=re.S|re.M)
    if n:
        s = s2
    return n

# 1) Replace enrichFlags function body (if exists)
sub_once(r'async function enrichFlags\s*\(\s*item\s*\)\s*\{.*?\n\s*\}\n',
r'''async function enrichFlags(item){
    const rid = String(item.run_id || item.rid || item.id || "");
    // Commercial: runs_index is authoritative (already enriched server-side)
    const total = (typeof item.total_findings === "number") ? item.total_findings : null;
    const hasF  = (typeof item.has_findings === "boolean") ? item.has_findings : (total !== null ? total > 0 : null);
    const dn    = (typeof item.degraded_n === "number") ? item.degraded_n : null;
    const da    = (typeof item.degraded_any === "boolean") ? item.degraded_any : (dn !== null ? dn > 0 : null);
    return {rid, hasFindings: hasF, degraded: da, totalFindings: total, degradedN: dn};
}
''')

# 2) Patch applyFlagsToRow to show counts if columns have pills (optional)
if "totalFindings" not in s:
    s = s.replace(
        'function applyFlagsToRow(tr, hasFindings, degraded){',
        'function applyFlagsToRow(tr, hasFindings, degraded, totalFindings, degradedN){'
    )
    s = s.replace(
        'applyFlagsToRow(tr, e.hasFindings, e.degraded);',
        'applyFlagsToRow(tr, e.hasFindings, e.degraded, e.totalFindings, e.degradedN);'
    )
    # inject count rendering
    s = re.sub(r'(if \(hf\) hf\.textContent = [^;]+;)',
               r'''\1
    if (hf && typeof totalFindings === "number") {
      hf.textContent = (hf.textContent === "YES" ? `YES (${totalFindings})` : hf.textContent === "NO" ? "NO (0)" : `UNKNOWN`);
    }''', s, count=1, flags=re.M)
    s = re.sub(r'(if \(dg\) dg\.textContent = [^;]+;)',
               r'''\1
    if (dg && typeof degradedN === "number") {
      dg.textContent = (dg.textContent === "YES" ? `YES (${degradedN})` : dg.textContent === "NO" ? "NO (0)" : `UNKNOWN`);
    }''', s, count=1, flags=re.M)

# 3) Remove status-enrich stage text + mapLimit usage by replacing the block that says "Enriching flags via JSON status..."
s = re.sub(r'if \(meta\) meta\.textContent = `Enriching flags via JSON status\.\.\. \(\$\{items\.length\}\)`;\s*const enriched = await mapLimit\(items,\s*\d+,\s*enrichFlags\);\s*[\s\S]*?if \(meta\) meta\.textContent = `Loaded \$\{items\.length\}\. Enriched flags for \$\{okN\} runs\.`;',
          r'''// Commercial: flags already present in runs_index items (no per-row status fetch)
    const enriched = await Promise.all(items.map(enrichFlags));
    let okN = 0;
    for (const e of enriched){
      const tr = rowByRid.get(e.rid);
      if (!tr) continue;
      applyFlagsToRow(tr, e.hasFindings, e.degraded, e.totalFindings, e.degradedN);
      okN++;
    }
    applyFilters(root);
    if (meta) meta.textContent = `Loaded ${items.length}. Flags from runs_index (${okN}).`;''',
          s, flags=re.S|re.M)

p.write_text(s, encoding="utf-8")
print("[OK] patched runs UI to use runs_index flags (no per-row status fetch)")
PY

node --check "$F" >/dev/null && echo "[OK] runs JS syntax OK"
echo "[DONE] Runs UI now uses runs_index flags. Hard refresh Ctrl+Shift+R."
