/* === VSP_DEGRADED_PANEL_HOOK_V1 ===
   - Hooks fetch() to detect /api/vsp/run_status_v1/<RID>
   - Renders a "Degraded Tools" panel inside Runs tab (if #vsp-tab-runs exists), else attaches to body.
*/
(function () {
  if (window.VSP_DEGRADED_PANEL_HOOK_V1) return;
  window.VSP_DEGRADED_PANEL_HOOK_V1 = true;

  function ensurePanel() {
    var host = document.getElementById('vsp-tab-runs') || document.body;
    var panel = document.getElementById('vsp-degraded-tools-panel-v1');
    if (!panel) {
      panel = document.createElement('div');
      panel.id = 'vsp-degraded-tools-panel-v1';
      panel.style.margin = '12px 0';
      panel.style.padding = '12px';
      panel.style.border = '1px solid rgba(255,255,255,0.08)';
      panel.style.borderRadius = '14px';
      panel.style.background = 'rgba(255,255,255,0.03)';
      panel.style.color = '#e5e7eb';
      panel.style.fontFamily = 'Inter, system-ui, -apple-system, Segoe UI, Roboto, Arial';
      panel.style.fontSize = '13px';
      panel.innerHTML = '<div style="font-weight:700; font-size:14px; margin-bottom:8px;">Degraded Tools</div><div id="vsp-degraded-tools-body-v1">No data yet.</div>';
      host.appendChild(panel);
    }
    return panel;
  }

  function esc(s) {
    return String(s ?? '').replace(/[&<>"']/g, function (c) {
      return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]);
    });
  }

  function normalizeList(dt) {
    // dt may be: null | [] | {tool:{...}} | {items:[...]}
    if (!dt) return [];
    if (Array.isArray(dt)) return dt;
    if (Array.isArray(dt.items)) return dt.items;
    if (typeof dt === 'object') {
      // map -> list
      var out = [];
      Object.keys(dt).forEach(function (k) {
        var v = dt[k];
        if (v && typeof v === 'object' && !Array.isArray(v)) {
          var row = Object.assign({ tool: k }, v);
          out.push(row);
        }
      });
      return out;
    }
    return [];
  }

  function render(status) {
    var panel = ensurePanel();
    var body = document.getElementById('vsp-degraded-tools-body-v1');
    if (!body) return;

    var rid = status && (status.request_id || status.req_id || status.rid) || '';
    var finish = status && status.finish_reason;
    var stage = status && status.stage_sig;
    var prog = status && (status.progress_pct ?? null);

    var list = normalizeList(status && status.degraded_tools);

    var meta = '<div style="opacity:.9;margin-bottom:8px;">'
      + '<span style="opacity:.7">RID:</span> <code style="opacity:.95">' + esc(rid) + '</code>'
      + (finish ? ' &nbsp; <span style="opacity:.7">finish:</span> <b>' + esc(finish) + '</b>' : '')
      + (stage ? ' &nbsp; <span style="opacity:.7">stage:</span> <b>' + esc(stage) + '</b>' : '')
      + (prog !== null ? ' &nbsp; <span style="opacity:.7">progress:</span> <b>' + esc(prog) + '%</b>' : '')
      + '</div>';

    if (!list.length) {
      body.innerHTML = meta + '<div style="opacity:.8">No degraded tools reported.</div>';
      return;
    }

    var rows = list.map(function (x) {
      var tool = x.tool || x.name || x.tool_name || '';
      var reason = x.reason || x.status || x.error || '';
      var tsec = x.timeout_sec || x.timeout || x.timeout_seconds || '';
      var log = x.log || x.log_path || x.log_file || '';
      return '<tr>'
        + '<td style="padding:6px 8px; border-top:1px solid rgba(255,255,255,0.06);"><b>' + esc(tool) + '</b></td>'
        + '<td style="padding:6px 8px; border-top:1px solid rgba(255,255,255,0.06);">' + esc(reason) + '</td>'
        + '<td style="padding:6px 8px; border-top:1px solid rgba(255,255,255,0.06); text-align:right;">' + esc(tsec) + '</td>'
        + '<td style="padding:6px 8px; border-top:1px solid rgba(255,255,255,0.06);"><code>' + esc(log) + '</code></td>'
        + '</tr>';
    }).join('');

    body.innerHTML = meta
      + '<table style="width:100%; border-collapse:collapse;">'
      + '<thead><tr>'
      + '<th style="text-align:left; padding:6px 8px; opacity:.8;">Tool</th>'
      + '<th style="text-align:left; padding:6px 8px; opacity:.8;">Reason</th>'
      + '<th style="text-align:right; padding:6px 8px; opacity:.8;">Timeout(s)</th>'
      + '<th style="text-align:left; padding:6px 8px; opacity:.8;">Log</th>'
      + '</tr></thead><tbody>' + rows + '</tbody></table>';
  }

  // Hook fetch
  var _fetch = window.fetch;
  if (typeof _fetch !== 'function') return;

  window.fetch = function () {
    return _fetch.apply(this, arguments).then(function (resp) {
      try {
        var url = (arguments[0] && arguments[0].url) ? arguments[0].url : String(arguments[0] || '');
        if (url.indexOf('/api/vsp/run_status_v1/') >= 0) {
          resp.clone().json().then(function (data) {
            if (data && typeof data === 'object') render(data);
          }).catch(function(){});
        }
      } catch (e) {}
      return resp;
    });
  };

  // Ensure panel exists even before first fetch (Runs tab open)
  try { ensurePanel(); } catch(e) {}
})();
