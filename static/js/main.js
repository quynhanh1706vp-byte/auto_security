document.addEventListener("DOMContentLoaded", () => {
  setupRunScanButton();
  setupToolConfigSave();
});

function setupRunScanButton() {
  const runBtn = document.getElementById("sb-run-btn");
  if (!runBtn) return;

  runBtn.addEventListener("click", async () => {
    const targetInput = document.getElementById("sb-target-input");
    const srcInput = document.getElementById("sb-src-input");
    const profileSelect = document.getElementById("sb-profile-select");
    const modeSelect = document.getElementById("sb-mode-select");

    const target_url = targetInput ? targetInput.value.trim() : "";
    const src_folder = srcInput ? srcInput.value.trim() : "";
    const profile = profileSelect ? profileSelect.value : "";
    const mode = modeSelect ? modeSelect.value : "";

    if (!src_folder) {
      alert("SRC folder đang trống. Điền đường dẫn mã nguồn trước khi chạy scan.");
      return;
    }

    runBtn.disabled = true;
    const oldText = runBtn.textContent;
    runBtn.textContent = "Running...";

    try {
      const res = await fetch("/run_scan", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ target_url, src_folder, profile, mode }),
      });

      let data = {};
      try {
        data = await res.json();
      } catch (_) {}

      if (!res.ok || data.ok === false) {
        alert("Run scan lỗi: " + (data.error || res.statusText));
      } else {
        alert("Đã gửi lệnh scan.\nXem log trực tiếp ở terminal SECURITY_BUNDLE.");
        setTimeout(() => {
          window.location.reload();
        }, 4000);
      }
    } catch (e) {
      alert("Không gọi được /run_scan: " + e);
    } finally {
      runBtn.disabled = false;
      runBtn.textContent = oldText;
    }
  });
}

function setupToolConfigSave() {
  const saveBtn = document.getElementById("tc-save-btn");
  if (!saveBtn) return;

  saveBtn.addEventListener("click", async () => {
    const rows = document.querySelectorAll("tr[data-tool-row='1']");
    if (!rows.length) {
      alert("Không tìm thấy dòng tool nào trong bảng.");
      return;
    }

    const payload = [];
    rows.forEach((row) => {
      const toolCell = row.querySelector(".tc-tool");
      const enabledBox = row.querySelector(".tc-enabled");
      const levelSelect = row.querySelector(".tc-level");
      const modeBoxes = row.querySelectorAll(".tc-mode");
      const noteInput = row.querySelector(".tc-note");

      const tool = toolCell ? toolCell.textContent.trim() : "";
      if (!tool) return;

      const enabled = !!(enabledBox && enabledBox.checked);
      const level = levelSelect ? levelSelect.value : "fast";

      const modes = [];
      modeBoxes.forEach((cb) => {
        if (cb.checked) {
          const m = cb.dataset.mode || "";
          if (m) modes.push(m);
        }
      });

      const note = noteInput ? noteInput.value.trim() : "";

      payload.push({
        tool,
        enabled,
        level,
        modes,
        note,
      });
    });

    if (!payload.length) {
      alert("Payload rỗng, không có gì để lưu.");
      return;
    }

    if (!confirm("Bạn chắc chắn muốn ghi lại ui/static/tool_config.json?")) {
      return;
    }

    saveBtn.disabled = true;
    const oldText = saveBtn.textContent;
    saveBtn.textContent = "Đang lưu...";

    try {
      const res = await fetch("/api/tool_config/save", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      let data = {};
      try {
        data = await res.json();
      } catch (_) {}

      if (!res.ok || data.ok === false) {
        alert("Lưu cấu hình lỗi: " + (data.error || res.statusText));
      } else {
        alert("Đã lưu tool_config.json thành công.");
      }
    } catch (e) {
      alert("Không gọi được API lưu cấu hình: " + e);
    } finally {
      saveBtn.disabled = false;
      saveBtn.textContent = oldText;
    }
  });
}

// ====================================================================
// RUN_SCAN_HANDLER_V2 – bắt sự kiện nút Run scan, gọi /api/run_scan_v2
// ====================================================================
(function () {
  const btn = document.getElementById('run-scan-btn');
  if (!btn) {
    console.warn('[RUN_SCAN_HANDLER_V2] Không tìm thấy nút #run-scan-btn');
    return;
  }

  function pickInput() {
    // target URL: input có placeholder giống demo cũ
    const targetEl =
      document.querySelector('input[placeholder^="https://app.example.com"]') ||
      document.querySelector('input[name="target_url"]');

    // src folder: input có placeholder /home/test/Data/Khach
    const srcEl =
      document.querySelector('input[placeholder^="/home/test/Data"]') ||
      document.querySelector('input[name="src_folder"]');

    return {
      target_url: targetEl ? targetEl.value.trim() : "",
      src_folder: srcEl ? srcEl.value.trim() : "",
    };
  }

  async function runScan() {
    const { target_url, src_folder } = pickInput();
    const payload = {
      target_url,
      src_folder,
      profile:  (window._sbProfile  || "").toString(),
      mode:     (window._sbMode     || "").toString(),
    };

    const original = btn.textContent;
    btn.disabled = true;
    btn.textContent = 'Running...';

    try {
      const resp = await fetch('/api/run_scan_v2', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });

      if (!resp.ok) {
        console.error('[RUN_SCAN] HTTP error', resp.status);
        alert('Run scan lỗi HTTP ' + resp.status);
      } else {
        const data = await resp.json();
        console.log('[RUN_SCAN] Kết quả:', data);

        // Sau khi quét xong: refresh Dashboard + Run & Report nếu có hàm
        if (typeof window.loadDashboardData === 'function') {
          await window.loadDashboardData();
        }
        if (typeof window.reloadRunsTable === 'function') {
          await window.reloadRunsTable();
        }
      }
    } catch (e) {
      console.error('[RUN_SCAN] Exception', e);
      alert('Run scan gặp lỗi, xem log server.');
    } finally {
      btn.disabled = false;
      btn.textContent = original;
    }
  }

  btn.addEventListener('click', function (ev) {
    ev.preventDefault();
    runScan();
  });
})();
