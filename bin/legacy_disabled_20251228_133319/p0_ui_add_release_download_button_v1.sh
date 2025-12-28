#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

TS="$(date +%Y%m%d_%H%M%S)"

TPL="$(python3 - <<'PY'
from pathlib import Path
import re
cand=[]
troot=Path("templates")
if troot.is_dir():
  for p in troot.rglob("*.html"):
    name=p.name.lower()
    if "setting" in name:
      cand.append(str(p))
# prefer exact settings page if exists
prio=[c for c in cand if "vsp_settings" in c.lower()] + cand
print(prio[0] if prio else "")
PY
)"
[ -n "$TPL" ] || { echo "[ERR] cannot find settings template under templates/*.html"; exit 2; }

cp -f "$TPL" "${TPL}.bak_releasebtn_${TS}"
echo "[BACKUP] ${TPL}.bak_releasebtn_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

tpl_path = Path("${TPL}")
s = tpl_path.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_UI_RELEASE_DOWNLOAD_BTN_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

# HTML block (dark-theme safe)
card = textwrap.dedent(r'''
<!-- ===================== VSP_P0_UI_RELEASE_DOWNLOAD_BTN_V1 ===================== -->
<section class="vsp-card" id="vsp_release_card_v1" style="margin-top:14px;">
  <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;">
    <div>
      <div style="font-weight:700;font-size:14px;letter-spacing:.2px;">Release package</div>
      <div style="opacity:.8;font-size:12px;margin-top:2px;">
        Download latest packaged UI/Reports bundle from <code>/api/vsp/release_latest</code>
      </div>
    </div>
    <div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap;">
      <button class="btn" id="btn_release_download_v1" type="button">Download latest package</button>
      <span id="release_status_v1" style="opacity:.8;font-size:12px;"></span>
    </div>
  </div>
  <pre id="release_meta_v1" style="margin-top:10px;max-height:180px;overflow:auto;background:#0a1020;border:1px solid rgba(255,255,255,.08);padding:10px;border-radius:10px;font-size:12px;display:none;"></pre>
</section>

<script>
(()=> {
  if (window.__vsp_release_btn_v1) return;
  window.__vsp_release_btn_v1 = true;
  const $ = (id)=>document.getElementById(id);
  const btn = $("btn_release_download_v1");
  const st  = $("release_status_v1");
  const pre = $("release_meta_v1");
  if (!btn) return;

  function setStatus(t){ if(st) st.textContent = t || ""; }
  function showMeta(obj){
    if(!pre) return;
    pre.style.display = "block";
    try{ pre.textContent = JSON.stringify(obj, null, 2); }catch(e){ pre.textContent = String(obj||""); }
  }

  async function fetchLatest(){
    setStatus("Checking release_latest…");
    const res = await fetch("/api/vsp/release_latest", {cache:"no-store"});
    const j = await res.json();
    if (!j || !j.ok) {
      setStatus("No release available");
      showMeta(j);
      return null;
    }
    setStatus(`OK • ${j.package_name || "package"} • ${j.release_ts || ""}`);
    showMeta(j);
    return j;
  }

  btn.addEventListener("click", async ()=>{
    try{
      btn.disabled = true;
      const j = await fetchLatest();
      const dl = j && j.download_url;
      if (!dl){ setStatus("Missing download_url"); btn.disabled=false; return; }
      setStatus("Downloading…");
      window.location.href = dl;
    }catch(e){
      console.error("[VSP][RELEASE_BTN_V1] err", e);
      setStatus("Error (see console)");
    }finally{
      setTimeout(()=>{ btn.disabled=false; }, 1200);
    }
  });

  // auto load meta once (non-blocking)
  setTimeout(()=>{ fetchLatest().catch(()=>{}); }, 300);
})();
</script>
<!-- ===================== /VSP_P0_UI_RELEASE_DOWNLOAD_BTN_V1 ===================== -->
''').strip() + "\n"

# inject near end of body if possible
if "</body>" in s:
    s2 = s.replace("</body>", card + "\n</body>", 1)
elif "</main>" in s:
    s2 = s.replace("</main>", "</main>\n" + card, 1)
else:
    s2 = s + "\n" + card

tpl_path.write_text(s2, encoding="utf-8")
print("[OK] injected:", MARK, "into", tpl_path)
PY

echo "== restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] Open /settings, you should see 'Release package' card + Download button."
