
// __VSP_CIO_HELPER_V1
(function(){
  try{
    window.__VSP_CIO = window.__VSP_CIO || {};
    const qs = new URLSearchParams(location.search);
    window.__VSP_CIO.debug = (qs.get("debug")==="1") || (localStorage.getItem("VSP_DEBUG")==="1");
    window.__VSP_CIO.visible = ()=>document.visibilityState === "visible";
    window.__VSP_CIO.sleep = (ms)=>new Promise(r=>setTimeout(r, ms));
    window.__VSP_CIO.api = {
      ridLatestV3: ()=>"/api/vsp/rid_latest_v3",
      dashboardV3: (rid)=> rid ? `/api/vsp/dashboard_v3?rid=${encodeURIComponent(rid)}` : "/api/vsp/dashboard_v3",
      runsV3: (limit,offset)=>`/api/vsp/runs_v3?limit=${limit||50}&offset=${offset||0}`,
      gateV3: (rid)=>`/api/vsp/run_gate_v3?rid=${encodeURIComponent(rid||"")}`,
      findingsV3: (rid,limit,offset)=>`/api/vsp/findings_v3?rid=${encodeURIComponent(rid||"")}&limit=${limit||100}&offset=${offset||0}`,
      artifactV3: (rid,kind,download)=>`/api/vsp/artifact_v3?rid=${encodeURIComponent(rid||"")}&kind=${encodeURIComponent(kind||"")}${download?"&download=1":""}`
    };
  }catch(_){}
})();

/**
 * security_bundle.js V4
 *  - Đọc /api/vsp/settings/get để fill Settings.
 *  - Nút "Run now" gọi /api/vsp/run_full_ext với JSON body {src, profile, mode}.
 */

(function () {
if(window.__VSP_CIO&&window.__VSP_CIO.debug) console.log('[VSP] security_bundle.js V4 loaded');

  function $(sel) { return document.querySelector(sel); }
  function setText(sel, text) { var el = $(sel); if (el) el.textContent = text; }
  function setVal(sel, val) { var el = $(sel); if (el) el.value = val; }

  function findSrcInput() {
    return (
      $('#vsp-run-src-input') ||
      $('#vsp-trigger-src') ||
      $('#trigger_src_path') ||
      $('input[name="vsp_trigger_src"]') ||
      $('input[data-role="vsp-trigger-src"]')
    );
  }

  function findRunButton() {
    return (
      $('#vsp-run-now-btn') ||
      $('#vsp-run-now') ||
      $('#trigger_run_now') ||
      $('button[data-role="vsp-run-now"]')
    );
  }

  // ===== SETTINGS =====
  async function loadSettings() {
    try {
if(window.__VSP_CIO&&window.__VSP_CIO.debug) console.log('[VSP][SETTINGS] GET /api/vsp/settings/get');
      const res = await fetch('/api/vsp/settings/get', {
        method: 'GET',
        headers: { 'Accept': 'application/json' }
      });

      if (!res.ok) {
        console.error('[VSP][SETTINGS] HTTP', res.status);
        return;
      }

      const js = await res.json();
      if (!js.ok) {
        console.error('[VSP][SETTINGS] payload not ok', js);
        return;
      }

      const env = js.env || {};
      const tools = js.tools || {};

      if (env.root_dir) {
        setVal('#vsp-setting-root-dir', env.root_dir);
        setText('#vsp-setting-root-dir-label', env.root_dir);
      }

      if (env.profile) {
        setText('#vsp-setting-current-profile', env.profile);
      }

      const entries = Object.entries(tools);
      const enabled = entries.filter(function (kv) {
        return kv[1] && kv[1].enabled;
      });

      const labelEl = $('#vsp-setting-tools-enabled');
      if (labelEl) {
        const labels = enabled.map(function (kv) {
          const key = kv[0];
          const cfg = kv[1] || {};
          return cfg.label || key;
        });
        labelEl.textContent =
          enabled.length + '/' + entries.length +
          ' tools enabled: ' + labels.join(', ');
      }

      enabled.forEach(function (kv) {
        const key = kv[0];
        const cfg = kv[1] || {};
        const toggle =
          document.querySelector('[data-tool-toggle="' + key + '"]') ||
          document.querySelector('input[name="tool_toggle_' + key + '"]');
        if (toggle && 'checked' in toggle) {
          toggle.checked = !!cfg.enabled;
        }
      });

      // Nếu BE có default_src thì fill luôn vào ô Trigger
      const srcInput = findSrcInput();
      if (srcInput && env.default_src) {
        srcInput.value = env.default_src;
      }
if(window.__VSP_CIO&&window.__VSP_CIO.debug) console.log('[VSP][SETTINGS] done');
    } catch (e) {
      console.error('[VSP][SETTINGS] error', e);
    }
  }

  // ===== RUN FULL EXT+ (JSON, key = "src") =====
  async function runFullExt() {
    const btn = findRunButton();
    const srcInput = findSrcInput();

    if (!srcInput) {
      alert('Không tìm thấy ô nhập SRC path!');
      return;
    }

    const rawSrc = (srcInput.value || '').trim();
    if (!rawSrc) {
      alert('Bạn chưa nhập SRC path (ví dụ: /home/test/Data/Khach6).');
      srcInput.focus();
      return;
    }

    const profileSpan = $('#vsp-setting-current-profile');
    const profile = profileSpan && profileSpan.textContent
      ? profileSpan.textContent.trim()
      : 'EXT+';
if(window.__VSP_CIO&&window.__VSP_CIO.debug) console.log('[VSP][RUN] /api/vsp/run_full_ext với src =', rawSrc, ', profile =', profile);

    if (btn) {
      btn.disabled = true;
      btn.textContent = 'Running...';
    }

    try {
      const payload = {
        src: rawSrc,        // <<< KEY CHUẨN BE ĐANG ĐỌC
        profile: profile,
        mode: 'ext'
      };

      const res = await fetch('/api/vsp/run_full_ext', {
        method: 'POST',
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json;charset=UTF-8'
        },
        body: JSON.stringify(payload)
      });

      const status = res.status;
      let js = {};
      try {
        js = await res.json();
      } catch (e) {
        console.warn('[VSP][RUN] response not JSON, status', status);
      }
if(window.__VSP_CIO&&window.__VSP_CIO.debug) console.log('[VSP][RUN] HTTP', status, js);

      const ok = js && js.ok === true;
      const runId = js && js.run_id;
      const msg =
        'Run ' + (runId || '(—)') +
        ' – HTTP ' + status +
        (ok ? ' (OK)' : ' (BAD REQUEST)') +
        '. Reload Dashboard để xem KPI.';

      alert(window.location.host + ' cho biết\n\n' + msg);
    } catch (e) {
      console.error('[VSP][RUN] error', e);
      alert('Lỗi khi gọi /api/vsp/run_full_ext: ' + e);
    } finally {
      if (btn) {
        btn.disabled = false;
        btn.textContent = 'Run now';
      }
    }
  }

  function bindRunButton() {
    const btn = findRunButton();
    if (!btn) {
      console.warn('[VSP][RUN] Không thấy nút Run now để bind.');
      return;
    }
if(window.__VSP_CIO&&window.__VSP_CIO.debug) console.log('[VSP][RUN] Bind click Run now');
    btn.addEventListener('click', function (e) {
      e.preventDefault();
      runFullExt();
    });
  }

  document.addEventListener('DOMContentLoaded', function () {
    loadSettings();
    bindRunButton();
  });
})();
