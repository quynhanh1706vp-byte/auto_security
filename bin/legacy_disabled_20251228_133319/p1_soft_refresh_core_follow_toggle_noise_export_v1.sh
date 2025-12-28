#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

echo "== [0] locate commercial bundle js =="
JS_CAND="$(python3 - <<'PY'
from pathlib import Path
root = Path("static/js")
cands = []
if root.exists():
  for p in root.rglob("*.js"):
    try:
      s = p.read_text(encoding="utf-8", errors="ignore")
    except Exception:
      continue
    # strong signals
    if ("VSP_RID_LATEST_VERIFIED_AUTOREFRESH_V1" in s) or ("VSP_VSP5_RID_CHANGED_RELOAD_V1" in s) or ("VSP_DISABLE_OLD_FOLLOW_LATEST_POLL_V1" in s):
      cands.append(str(p))
print(cands[0] if cands else "")
PY
)"
[ -n "${JS_CAND}" ] || { echo "[ERR] cannot find bundle js with markers. abort."; exit 2; }
echo "[OK] bundle=${JS_CAND}"

cp -f "${JS_CAND}" "${JS_CAND}.bak_p1soft_${TS}"
echo "[BACKUP] ${JS_CAND}.bak_p1soft_${TS}"

echo "== [1] patch: replace hard reload on RID change => dispatch event + soft-refresh hook + fallback reload =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("${JS_CAND}")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_SOFT_REFRESH_CORE_V1"
if MARK in s:
  print("[SKIP] already patched")
  raise SystemExit(0)

# Heuristic: replace any location.reload() inside a block that references RID change marker.
# If the marker exists, patch the FIRST occurrence of location.reload() after it.
idx = s.find("VSP_VSP5_RID_CHANGED_RELOAD_V1")
if idx == -1:
  # fallback: patch first location.reload() in whole bundle (least desirable, but still safe with fallback)
  idx = 0

m = re.search(r'location\.reload\s*\(\s*\)\s*;?', s[idx:])
if not m:
  print("[ERR] cannot find location.reload() to patch")
  raise SystemExit(2)

start = idx + m.start()
end   = idx + m.end()

inject = r"""
/* ===================== VSP_P1_SOFT_REFRESH_CORE_V1 ===================== */
try {
  // If FollowLatest is OFF, keep old behavior (reload) unless user pinned RID via later P2.
  var __follow = (localStorage.getItem("vsp_follow_latest") ?? "on");
  // Emit event first: tab can soft refresh and keep state.
  try {
    var __ev = new CustomEvent("vsp:rid_changed", { detail: { rid: (window.__vsp_rid_latest||null), prev: (window.__vsp_rid_prev||null), follow: __follow }});
    window.dispatchEvent(__ev);
  } catch(e) {}
  // Optional soft refresh hook (tab-specific). Must return true if it handled.
  if (__follow !== "off" && typeof window.__vsp_soft_refresh_apply === "function") {
    var __handled = false;
    try { __handled = !!window.__vsp_soft_refresh_apply((window.__vsp_rid_latest||null), (window.__vsp_rid_prev||null)); } catch(e) { __handled = false; }
    if (__handled) { /* handled => no reload */ }
    else { location.reload(); }
  } else {
    location.reload();
  }
} catch(e) { location.reload(); }
/* ===================== /VSP_P1_SOFT_REFRESH_CORE_V1 ===================== */
"""

s2 = s[:start] + inject + s[end:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched reload => soft refresh core")
PY

echo "== [2] append: Follow Latest toggle overlay (safe, non-invasive) =="
python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("${JS_CAND}")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P1_FOLLOW_TOGGLE_UI_V1"
if MARK in s:
  print("[SKIP] toggle already exists")
  raise SystemExit(0)

addon = textwrap.dedent(r"""
/* ===================== VSP_P1_FOLLOW_TOGGLE_UI_V1 ===================== */
(()=> {
  if (window.__vsp_p1_follow_toggle_ui_v1) return;
  window.__vsp_p1_follow_toggle_ui_v1 = true;

  function get(){ return (localStorage.getItem("vsp_follow_latest") ?? "on"); }
  function set(v){ localStorage.setItem("vsp_follow_latest", v); }

  function mount(){
    try {
      if (document.getElementById("vsp_follow_toggle_v1")) return;
      const box = document.createElement("div");
      box.id = "vsp_follow_toggle_v1";
      box.style.cssText = "position:fixed;z-index:99999;top:10px;right:12px;background:rgba(10,18,32,.82);border:1px solid rgba(255,255,255,.10);backdrop-filter: blur(10px);padding:8px 10px;border-radius:12px;font:12px/1.2 system-ui,Segoe UI,Roboto;color:#cfe3ff;box-shadow:0 10px 30px rgba(0,0,0,.35)";
      box.innerHTML = `
        <div style="display:flex;align-items:center;gap:10px">
          <div style="font-weight:700;letter-spacing:.2px">Follow latest</div>
          <label style="display:flex;align-items:center;gap:8px;cursor:pointer;user-select:none">
            <input id="vsp_follow_toggle_chk_v1" type="checkbox" style="width:14px;height:14px;accent-color:#3aa0ff">
            <span id="vsp_follow_toggle_txt_v1" style="opacity:.9">ON</span>
          </label>
        </div>
      `;
      document.body.appendChild(box);

      const chk = document.getElementById("vsp_follow_toggle_chk_v1");
      const txt = document.getElementById("vsp_follow_toggle_txt_v1");
      const cur = get();
      chk.checked = (cur !== "off");
      txt.textContent = chk.checked ? "ON" : "OFF";

      chk.addEventListener("change", ()=> {
        const v = chk.checked ? "on" : "off";
        set(v);
        txt.textContent = chk.checked ? "ON" : "OFF";
        // Emit state change so tabs can react (optional)
        try { window.dispatchEvent(new CustomEvent("vsp:follow_latest_changed",{detail:{value:v}})); } catch(e) {}
      }, {passive:true});
    } catch(e) {}
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", mount);
  else mount();
})();
/* ===================== /VSP_P1_FOLLOW_TOGGLE_UI_V1 ===================== */
""")

# Append near end
p.write_text(s + "\n\n" + addon + "\n", encoding="utf-8")
print("[OK] appended Follow toggle overlay")
PY

echo "== [3] add: Noise Panel copy/clear/counters helper (only activates if noise buffer exists) =="
python3 - <<'PY'
from pathlib import Path
import textwrap, re

p = Path("${JS_CAND}")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P1_NOISE_PANEL_EXPORT_V1"
if MARK in s:
  print("[SKIP] noise export already exists")
  raise SystemExit(0)

addon = textwrap.dedent(r"""
/* ===================== VSP_P1_NOISE_PANEL_EXPORT_V1 ===================== */
(()=> {
  if (window.__vsp_p1_noise_export_v1) return;
  window.__vsp_p1_noise_export_v1 = true;

  function safeJson(v){ try { return JSON.stringify(v, null, 2); } catch(e){ return String(v); } }

  function counts(items){
    const c = { "404":0,"403":0,"500":0,"JS":0,"OTHER":0, total:0 };
    if (!Array.isArray(items)) return c;
    for (const it of items){
      c.total++;
      const st = (it && (it.status||it.code||it.http)) ? String(it.status||it.code||it.http) : "";
      const typ = (it && (it.type||it.kind)) ? String(it.type||it.kind) : "";
      if (st === "404") c["404"]++;
      else if (st === "403") c["403"]++;
      else if (st === "500") c["500"]++;
      else if (typ.toLowerCase().includes("js") || (it && it.msg && String(it.msg).toLowerCase().includes("js"))) c["JS"]++;
      else c["OTHER"]++;
    }
    return c;
  }

  function mount(){
    // Heuristic: noise panel container exists?
    const panel = document.querySelector("[data-vsp-noise-panel],#vsp_noise_panel,.vsp-noise-panel");
    if (!panel) return;

    // Noise buffer heuristic
    const buf = window.__vsp_noise_items || window.__vsp_noise_log || window.__vsp_noise_buffer;
    const items = Array.isArray(buf) ? buf : (Array.isArray(buf?.items) ? buf.items : null);

    // toolbar
    if (panel.querySelector("#vsp_noise_tools_v1")) return;
    const bar = document.createElement("div");
    bar.id = "vsp_noise_tools_v1";
    bar.style.cssText = "display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:8px 0;padding:6px 0;border-top:1px solid rgba(255,255,255,.08)";
    bar.innerHTML = `
      <button id="vsp_noise_copy_v1" style="padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.12);background:rgba(30,60,110,.35);color:#d8ecff;cursor:pointer">Copy JSON</button>
      <button id="vsp_noise_clear_v1" style="padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.12);background:rgba(80,20,20,.35);color:#ffd7d7;cursor:pointer">Clear</button>
      <span id="vsp_noise_counts_v1" style="opacity:.85;font:12px/1.2 system-ui,Segoe UI,Roboto"></span>
    `;
    panel.appendChild(bar);

    function refreshCounts(){
      const b = window.__vsp_noise_items || window.__vsp_noise_log || window.__vsp_noise_buffer;
      const its = Array.isArray(b) ? b : (Array.isArray(b?.items) ? b.items : []);
      const c = counts(its);
      const el = document.getElementById("vsp_noise_counts_v1");
      if (el) el.textContent = `total=${c.total} | 404=${c["404"]} 403=${c["403"]} 500=${c["500"]} JS=${c["JS"]} other=${c["OTHER"]}`;
    }
    refreshCounts();

    document.getElementById("vsp_noise_copy_v1")?.addEventListener("click", async ()=>{
      const b = window.__vsp_noise_items || window.__vsp_noise_log || window.__vsp_noise_buffer;
      const its = Array.isArray(b) ? b : (Array.isArray(b?.items) ? b.items : b);
      const text = safeJson(its ?? []);
      try {
        await navigator.clipboard.writeText(text);
      } catch(e) {
        // fallback
        const ta = document.createElement("textarea");
        ta.value = text;
        ta.style.cssText="position:fixed;left:-10000px;top:-10000px";
        document.body.appendChild(ta);
        ta.select();
        try { document.execCommand("copy"); } catch(_){}
        ta.remove();
      }
      refreshCounts();
    }, {passive:true});

    document.getElementById("vsp_noise_clear_v1")?.addEventListener("click", ()=>{
      if (Array.isArray(window.__vsp_noise_items)) window.__vsp_noise_items.length = 0;
      if (Array.isArray(window.__vsp_noise_log)) window.__vsp_noise_log.length = 0;
      if (Array.isArray(window.__vsp_noise_buffer)) window.__vsp_noise_buffer.length = 0;
      if (window.__vsp_noise_buffer && Array.isArray(window.__vsp_noise_buffer.items)) window.__vsp_noise_buffer.items.length = 0;
      refreshCounts();
      try { window.dispatchEvent(new CustomEvent("vsp:noise_cleared",{detail:{ok:true}})); } catch(e){}
    }, {passive:true});

    // Update counts when rid changes (optional)
    window.addEventListener("vsp:rid_changed", refreshCounts);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", mount);
  else mount();
})();
/* ===================== /VSP_P1_NOISE_PANEL_EXPORT_V1 ===================== */
""")
p.write_text(s + "\n\n" + addon + "\n", encoding="utf-8")
print("[OK] appended Noise export tools")
PY

echo "== [4] sanity checks =="
node_ok=0; command -v node >/dev/null 2>&1 && node_ok=1
if [ "$node_ok" = "1" ]; then node --check "${JS_CAND}" >/dev/null; fi
python3 - <<'PY'
import sys
print("[OK] patch file looks syntactically OK (node check if available)")
PY

echo "== [5] restart service =="
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] P1 Soft refresh core + Follow toggle + Noise export applied."
