window.addEventListener('DOMContentLoaded', function () {
  console.log('[SB] overlay stats loaded');

  // Tạo overlay container
  var box = document.createElement('div');
  box.id = 'sb_stats_overlay';
  box.style.position = 'fixed';
  box.style.right = '20px';
  box.style.bottom = '20px';
  box.style.zIndex = '9999';
  box.style.padding = '12px 16px';
  box.style.borderRadius = '8px';
  box.style.background = 'rgba(0,0,0,0.8)';
  box.style.border = '1px solid rgba(0,255,180,0.7)';
  box.style.fontFamily = '"Roboto","Segoe UI",sans-serif';
  box.style.fontSize = '12px';
  box.style.color = '#e6fff5';
  box.style.boxShadow = '0 0 12px rgba(0,0,0,0.7)';
  box.style.maxWidth = '260px';
  box.innerHTML = '<div style="font-weight:600;margin-bottom:4px;">SECURITY STATS (UI)</div>'
                + '<div id="sb_stats_content">Loading...</div>';

  document.body.appendChild(box);

  function setContent(html) {
    var el = document.getElementById('sb_stats_content');
    if (el) el.innerHTML = html;
  }

  fetch('/static/last_summary_unified.json')
    .then(function (resp) {
      if (!resp.ok) {
        setContent('Error loading last_summary_unified.json (' + resp.status + ')');
        console.error('[SB] Fetch error:', resp.status);
        return null;
      }
      return resp.json();
    })
    .then(function (summary) {
      if (!summary) return;

      var src = summary.by_severity
        || summary.BY_SEVERITY
        || summary.severity_counts
        || {};

      var crit = src.CRITICAL || src.Critical || 0;
      var high = src.HIGH     || src.High     || 0;
      var med  = src.MEDIUM   || src.Medium   || 0;
      var low  = src.LOW      || src.Low      || 0;
      var info = src.INFO     || src.Info     || 0;

      var total = summary.total_findings
        || summary.TOTAL_FINDINGS
        || (crit + high + med + low + info);

      console.log('[SB] overlay data:', { total: total, crit: crit, high: high, med: med, low: low, info: info });

      var html = ''
        + '<div><b>Total findings:</b> ' + total + '</div>'
        + '<div style="margin-top:4px;"><b>By severity:</b></div>'
        + '<div style="margin-left:8px;margin-top:2px;">CRITICAL: ' + crit + '</div>'
        + '<div style="margin-left:8px;">HIGH: ' + high + '</div>'
        + '<div style="margin-left:8px;">MEDIUM: ' + med + '</div>'
        + '<div style="margin-left:8px;">LOW: ' + low + '</div>'
        + '<div style="margin-left:8px;">INFO: ' + info + '</div>';

      setContent(html);
    })
    .catch(function (e) {
      console.error('[SB] Overlay error:', e);
      setContent('Error: ' + e);
    });
});
