document.addEventListener("DOMContentLoaded", function () {
  // Tìm nút Run scan
  const btn =
    document.getElementById("btn-run-scan") ||
    document.querySelector("[data-role='btn-run-scan']");

  if (!btn) {
    console.warn("[RUN_SCAN_V3] Không tìm thấy nút Run scan");
    return;
  }

  // Tìm ô nhập Target URL và SRC folder
  const urlInput =
    document.getElementById("target-url-input") ||
    document.querySelector("input[name='target_url']");

  const srcInput =
    document.getElementById("src-folder-input") ||
    document.querySelector("input[name='src_folder']") ||
    document.querySelector("input[data-role='src-folder']");

  function getValue(el) {
    if (!el) return "";
    return (el.value || "").trim();
  }

  async function runScan() {
    const targetUrl = getValue(urlInput);
    let srcFolder = getValue(srcInput);

    if (!srcFolder) {
      alert("Please enter SRC folder to scan.");
      if (srcInput) srcInput.focus();
      return;
    }

    // Log lên console cho dễ debug
    console.log("[RUN_SCAN_V3] targetUrl =", targetUrl, "srcFolder =", srcFolder);

    btn.disabled = true;
    const oldText = btn.textContent;
    btn.textContent = "Running...";

    try {
      const resp = await fetch("/api/run_scan_v2", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          target_url: targetUrl || null,
          src_folder: srcFolder,
        }),
      });

      if (!resp.ok) {
        const txt = await resp.text();
        console.error("[RUN_SCAN_V3] API error:", resp.status, txt);
        alert("Run scan failed: HTTP " + resp.status);
        return;
      }

      const data = await resp.json().catch(() => ({}));
      console.log("[RUN_SCAN_V3] API response:", data);

      alert("Scan started & summary refreshed.\n" +
            "SRC: " + srcFolder + "\n" +
            "Check Dashboard / Runs & Reports for new RUN.");
      // Reload Dashboard để thấy RUN mới
      window.location.href = "/";
    } catch (err) {
      console.error("[RUN_SCAN_V3] Exception:", err);
      alert("Run scan failed: " + err);
    } finally {
      btn.disabled = false;
      btn.textContent = oldText;
    }
  }

  btn.addEventListener("click", function (e) {
    e.preventDefault();
    runScan();
  });
});
