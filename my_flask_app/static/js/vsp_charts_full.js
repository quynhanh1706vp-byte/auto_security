/* ============================================================
   VSP Dashboard Charts – FULL COMMERCIAL STYLE
   (Trend + Top CWE + Critical/High by Tool)
   ============================================================ */

/* ------------------------------------------------------------
   1) TREND – FINDINGS OVER TIME
   ------------------------------------------------------------ */
function renderTrendFindingsOverTime(targetSelector, rows) {
  var card = typeof targetSelector === 'string'
    ? document.querySelector(targetSelector)
    : targetSelector;
  if (!card) return;

  if (!Array.isArray(rows)) rows = [];
  var data = rows.slice(0, 10);

  card.innerHTML = `
    <div class="chart-header">
      <div class="chart-title-main">TREND – FINDINGS OVER TIME</div>
      <div class="chart-sub">Last 10 runs.</div>
    </div>
  `;

  var canvas = document.createElement('canvas');
  canvas.className = 'vsp-chart-canvas';
  canvas.style.width = '100%';
  canvas.style.height = '200px';
  card.appendChild(canvas);

  var dpr  = window.devicePixelRatio || 1;
  var rect = canvas.getBoundingClientRect();
  var w    = rect.width || card.clientWidth || 450;
  var h    = 200;

  canvas.width  = w * dpr;
  canvas.height = h * dpr;

  var ctx = canvas.getContext('2d');
  ctx.scale(dpr, dpr);
  ctx.clearRect(0, 0, w, h);

  if (!data.length) {
    ctx.fillStyle = '#9ca3af';
    ctx.font = '12px Inter, sans-serif';
    ctx.textAlign   = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('No data available.', w/2, h/2);
    return;
  }

  var ys = data.map(function(r){ return r.total_findings || r.findings || 0; });
  var minY = Math.min.apply(null, ys);
  var maxY = Math.max.apply(null, ys);
  if (minY === maxY) { minY -= 10; maxY += 10; }
  var pad = (maxY - minY) * 0.2;
  minY = Math.max(0, Math.floor((minY - pad)/10)*10);
  maxY = Math.ceil((maxY + pad)/10)*10;

  var marginLeft   = 50;
  var marginRight  = 20;
  var marginTop    = 18;
  var marginBottom = 32;

  var plotW = w - marginLeft - marginRight;
  var plotH = h - marginTop - marginBottom;

  function xAt(i) {
    if (data.length === 1) return marginLeft + plotW/2;
    var t = i / (data.length - 1);
    return marginLeft + t * plotW;
  }
  function yAt(v) {
    var t = (v - minY) / (maxY - minY);
    return marginTop + plotH - t * plotH;
  }

  // Grid Y
  var steps = 4;
  ctx.font = '10px Inter, sans-serif';
  ctx.fillStyle = '#cbd5e1';
  ctx.textAlign = 'right';
  ctx.textBaseline = 'middle';

  for (var s=0; s<=steps; s++) {
    var v = minY + (maxY - minY)*(s/steps);
    var y = yAt(v);

    ctx.strokeStyle = 'rgba(148,163,184,0.22)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(marginLeft, y);
    ctx.lineTo(marginLeft + plotW, y);
    ctx.stroke();

    ctx.fillText(Math.round(v), marginLeft - 6, y);
  }

  // Axis X
  ctx.strokeStyle = 'rgba(148,163,184,0.35)';
  ctx.lineWidth = 1.3;
  ctx.beginPath();
  ctx.moveTo(marginLeft, marginTop + plotH);
  ctx.lineTo(marginLeft + plotW, marginTop + plotH);
  ctx.stroke();

  // Labels X
  ctx.fillStyle = '#e5e7eb';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'top';

  data.forEach(function(_, i){
    var x = xAt(i);
    ctx.fillText('Run ' + (i+1), x, marginTop + plotH + 6);
  });

  // Area fill
  ctx.beginPath();
  data.forEach(function(r,i){
    var x = xAt(i);
    var y = yAt(r.total_findings || r.findings || 0);
    if (i===0) ctx.moveTo(x,y);
    else       ctx.lineTo(x,y);
  });
  ctx.lineTo(marginLeft+plotW, marginTop+plotH);
  ctx.lineTo(marginLeft,        marginTop+plotH);
  ctx.closePath();
  ctx.fillStyle = 'rgba(56,189,248,0.18)';
  ctx.fill();

  // Line
  ctx.beginPath();
  data.forEach(function(r,i){
    var x = xAt(i);
    var y = yAt(r.total_findings || r.findings || 0);
    if (i===0) ctx.moveTo(x,y);
    else       ctx.lineTo(x,y);
  });
  ctx.strokeStyle = '#38bdf8';
  ctx.lineWidth = 2;
  ctx.stroke();

  // Points
  data.forEach(function(r,i){
    var x = xAt(i);
    var y = yAt(r.total_findings || r.findings || 0);
    ctx.beginPath();
    ctx.arc(x,y,3,0,Math.PI*2);
    ctx.fillStyle='#0f172a';
    ctx.fill();
    ctx.strokeStyle='#38bdf8';
    ctx.lineWidth=2;
    ctx.stroke();
  });
}

/* ------------------------------------------------------------
   2) TOP CWE EXPOSURE – horizontal bar
   ------------------------------------------------------------ */
function renderTopCWEExposure(targetSelector, cweStats) {
  var card = typeof targetSelector === 'string'
    ? document.querySelector(targetSelector)
    : targetSelector;
  if (!card) return;

  if (!Array.isArray(cweStats)) cweStats = [];

  var sorted = cweStats
    .slice()
    .sort((a,b)=> (b.count||0)-(a.count||0))
    .slice(0,5);

  card.innerHTML = `
    <div class="chart-header">
      <div class="chart-title-main">TOP CWE EXPOSURE</div>
      <div class="chart-sub">Mapped from rules / CVEs.</div>
    </div>
  `;

  var canvas = document.createElement('canvas');
  canvas.style.width = '100%';
  canvas.style.height = '180px';
  card.appendChild(canvas);

  var dpr = window.devicePixelRatio || 1;
  var rect = canvas.getBoundingClientRect();
  var w = rect.width || card.clientWidth || 420;
  var h = 180;

  canvas.width = w*dpr;
  canvas.height = h*dpr;

  var ctx = canvas.getContext('2d');
  ctx.scale(dpr, dpr);
  ctx.clearRect(0,0,w,h);

  if (!sorted.length) {
    ctx.fillStyle='#9ca3af';
    ctx.font='12px Inter, sans-serif';
    ctx.textAlign='center';
    ctx.textBaseline='middle';
    ctx.fillText('No CWE mapped.', w/2, h/2);
    return;
  }

  var maxVal = sorted.reduce((m,r)=>Math.max(m,r.count||0), 0);
  if (maxVal===0) maxVal=1;

  var ml = 70, mr = 20, mt = 10, mb = 10;
  var plotW = w - ml - mr;
  var plotH = h - mt - mb;

  var barGap = 6;
  var barH = (plotH - barGap*(sorted.length-1)) / sorted.length;

  ctx.font='11px Inter, sans-serif';
  ctx.textBaseline='middle';

  sorted.forEach(function(row,i){
    var v = row.count || 0;
    var y = mt + i*(barH+barGap) + barH/2;

    ctx.fillStyle='#e5e7eb';
    ctx.textAlign='right';
    ctx.fillText(row.cwe || row.id || 'CWE', ml-10, y);

    var barW = plotW*(v/maxVal);

    ctx.fillStyle='rgba(59,130,246,0.85)';
    ctx.fillRect(ml, y - barH/2, barW, barH);

    ctx.fillStyle='#e5e7eb';
    ctx.textAlign='left';
    ctx.fillText(String(v), ml+barW+6, y);
  });
}

/* ------------------------------------------------------------
   3) CRITICAL / HIGH BY TOOL – grouped bars
   ------------------------------------------------------------ */
function renderCriticalHighByTool(targetSelector, toolStats) {
  var card = typeof targetSelector === 'string'
    ? document.querySelector(targetSelector)
    : targetSelector;
  if (!card) return;

  if (!Array.isArray(toolStats)) toolStats = [];

  var order = ['semgrep','codeql','trivy_fs','gitleaks','grype','kics','bandit'];
  toolStats = toolStats.slice().sort(function(a,b){
    var ia = order.indexOf(a.tool);
    var ib = order.indexOf(b.tool);
    if (ia===-1 && ib===-1) return a.tool.localeCompare(b.tool);
    if (ia===-1) return 1;
    if (ib===-1) return -1;
    return ia-ib;
  });

  card.innerHTML = `
    <div class="chart-header">
      <div class="chart-title-main">CRITICAL / HIGH BY TOOL</div>
      <div class="chart-sub">Semgrep, CodeQL, Trivy, Gitleaks, KICS…</div>
      <div class="chart-legend-row chart-legend-row--center">
        <div class="chart-legend-item"><span class="legend-color" style="background:#38bdf8"></span><span>Critical</span></div>
        <div class="chart-legend-item"><span class="legend-color" style="background:#fb7185"></span><span>High</span></div>
      </div>
    </div>
  `;

  var canvas = document.createElement('canvas');
  canvas.style.width = '100%';
  canvas.style.height = '180px';
  card.appendChild(canvas);

  var dpr = window.devicePixelRatio || 1;
  var rect = canvas.getBoundingClientRect();
  var w = rect.width || card.clientWidth || 440;
  var h = 180;

  canvas.width = w*dpr;
  canvas.height = h*dpr;

  var ctx = canvas.getContext('2d');
  ctx.scale(dpr, dpr);
  ctx.clearRect(0,0,w,h);

  if (!toolStats.length) {
    ctx.fillStyle='#9ca3af';
    ctx.font='12px Inter, sans-serif';
    ctx.textAlign='center';
    ctx.textBaseline='middle';
    ctx.fillText('No data.', w/2, h/2);
    return;
  }

  var maxVal = 0;
  toolStats.forEach(r=>{
    maxVal = Math.max(maxVal, r.critical||0, r.high||0);
  });
  if (maxVal===0) maxVal=1;

  var ml=40, mr=20, mt=10, mb=26;
  var plotW = w - ml - mr;
  var plotH = h - mt - mb;

  // Grid
  ctx.font='10px Inter, sans-serif';
  ctx.textBaseline='middle';
  ctx.textAlign='right';
  ctx.fillStyle='#e5e7eb';
  ctx.strokeStyle='rgba(148,163,184,0.2)';

  for (var s=0; s<=4; s++){
    var v = maxVal*(s/4);
    var y = mt + plotH - plotH*(v/maxVal);

    ctx.beginPath();
    ctx.moveTo(ml, y);
    ctx.lineTo(ml+plotW, y);
    ctx.stroke();

    ctx.fillText(Math.round(v), ml-6, y);
  }

  var n = toolStats.length;
  var groupW = plotW / n;
  var barW = groupW * 0.28;
  var gap = barW * 0.25;

  ctx.textAlign='center';
  ctx.textBaseline='top';
  ctx.fillStyle='#e5e7eb';

  toolStats.forEach(function(r,i){
    var gx = ml + groupW*(i+0.5);
    ctx.fillText(r.tool.toUpperCase(), gx, mt+plotH+4);

    var yc = (r.critical||0);
    var yh = (r.high||0);

    var hC = plotH*(yc/maxVal);
    var hH = plotH*(yh/maxVal);

    var xC = gx - gap - barW;
    var xH = gx + gap;

    ctx.fillStyle='#38bdf8';
    ctx.fillRect(xC, mt+plotH-hC, barW, hC);

    ctx.fillStyle='#fb7185';
    ctx.fillRect(xH, mt+plotH-hH, barW, hH);
  });
}
