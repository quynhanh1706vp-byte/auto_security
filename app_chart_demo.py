#!/usr/bin/env python3
import os
from flask import Flask, render_template_string

app = Flask(__name__)

severity_data = {
    "labels": ["Critical", "High", "Medium", "Low", "Info"],
    "values": [520, 380, 290, 160, 120],
}

TEMPLATE = r"""
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Security Scan - Chart Demo</title>
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
  <style>
    body {
      margin: 0;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #05070c;
      color: #f2f4ff;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
    }
    .card {
      background: #0b0f1a;
      border-radius: 16px;
      padding: 24px 28px;
      width: 800px;
      box-shadow: 0 18px 45px rgba(0,0,0,0.7);
    }
    .card h2 {
      margin: 0 0 16px;
      font-size: 22px;
      letter-spacing: .06em;
    }
    .chart-wrapper {
      background: #05070c;
      border-radius: 12px;
      padding: 16px 20px 8px;
      height: 320px;
    }
    canvas {
      width: 100% !important;
      height: 100% !important;
    }
  </style>
</head>
<body>
  <div class="card">
    <h2>Findings by Severity</h2>
    <div class="chart-wrapper">
      <canvas id="severityChart"></canvas>
    </div>
  </div>

  <script>
    const chartData = {{ severity_data|tojson }};

    const ctx = document.getElementById('severityChart').getContext('2d');
    const sevChart = new Chart(ctx, {
      type: 'bar',
      data: {
        labels: chartData.labels,
        datasets: [{
          label: 'Number of findings',
          data: chartData.values,
          borderWidth: 1
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          x: {
            grid: { display: false },
            ticks: { color: '#c7cffb' }
          },
          y: {
            beginAtZero: true,
            grid: { color: 'rgba(255,255,255,0.08)' },
            ticks: { color: '#c7cffb' }
          }
        },
        plugins: {
          legend: {
            labels: { color: '#e2e6ff' }
          },
          tooltip: {
            callbacks: {
              label: (ctx) => ` ${ctx.parsed.y} findings`
            }
          }
        }
      }
    });
  </script>
</body>
</html>
"""

@app.route("/")
def index():
    return render_template_string(TEMPLATE, severity_data=severity_data)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8906, debug=True)
