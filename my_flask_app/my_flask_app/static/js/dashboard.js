// JS cho Dashboard – Severity buckets

const SEV_COLORS = {
  critical: '#ff4b5c', // đỏ
  high:     '#ff8c42', // cam
  medium:   '#f4b400', // vàng
  low:      '#4fc3f7'  // xanh cyan
};

function buildSeverityChart(ctx, data) {
  // data = {critical: n1, high: n2, medium: n3, low: n4}
  const values = [
    data.critical || 0,
    data.high     || 0,
    data.medium   || 0,
    data.low      || 0
  ];

  return new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Critical', 'High', 'Medium', 'Low'],
      datasets: [{
        label: 'Findings',
        data: values,
        backgroundColor: [
          SEV_COLORS.critical,
          SEV_COLORS.high,
          SEV_COLORS.medium,
          SEV_COLORS.low
        ],
        borderRadius: 6,
        maxBarThickness: 48
      }]
    },
    options: {
      maintainAspectRatio: false,
      plugins: {
        legend: { display: false },
        tooltip: {
          callbacks: {
            label: (ctx) => `${ctx.formattedValue} findings`
          }
        }
      },
      scales: {
        x: {
          grid: { display: false },
          ticks: { color: 'rgba(255,255,255,0.7)', font: { size: 11 } }
        },
        y: {
          beginAtZero: true,
          grid: { color: 'rgba(255,255,255,0.08)' },
          ticks: { color: 'rgba(255,255,255,0.7)', font: { size: 11 } }
        }
      }
    }
  });
}

// Auto init nếu có thẻ canvas
document.addEventListener('DOMContentLoaded', () => {
  const canvas = document.getElementById('severityBucketsChart');
  if (!canvas) return;

  // Dữ liệu này nên được gán từ backend qua data-* hoặc biến global
  // Ví dụ: window.SEVERITY_DATA = {...}
  const data = window.SEVERITY_DATA || {
    critical: window.SEV_C || 0,
    high:     window.SEV_H || 0,
    medium:   window.SEV_M || 0,
    low:      window.SEV_L || 0
  };

  buildSeverityChart(canvas.getContext('2d'), data);
});
