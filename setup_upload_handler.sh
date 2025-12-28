#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
JS_DIR="$ROOT/static"
TPL="$ROOT/templates/index.html"

echo "[i] ROOT = $ROOT"
echo "[i] JS_DIR = $JS_DIR"
echo "[i] TEMPLATE = $TPL"

mkdir -p "$JS_DIR"

# === Ghi file upload_handler.js ===
cat > "$JS_DIR/upload_handler.js" <<'JS'
(function () {
  // ==== CẤU HÌNH ID (sửa nếu HTML của bạn dùng id khác) ====
  const SUMMARY_INPUT_ID = "uploadSummary";      // input chọn summary_unified.json
  const FINDINGS_INPUT_ID = "uploadFindings";    // input chọn findings.json
  const RENDER_BTN_ID    = "btnRenderFromFiles"; // nút "Render from files"

  const summaryInput = document.getElementById(SUMMARY_INPUT_ID);
  const findingsInput = document.getElementById(FINDINGS_INPUT_ID);
  const renderBtn = document.getElementById(RENDER_BTN_ID);

  if (!summaryInput || !findingsInput || !renderBtn) {
    console.warn(
      "[upload_handler] Không tìm thấy element:",
      SUMMARY_INPUT_ID,
      FINDINGS_INPUT_ID,
      RENDER_BTN_ID
    );
    return;
  }

  function showError(msg) {
    alert(msg);
  }

  function readJsonFile(file) {
    return new Promise(function (resolve, reject) {
      const reader = new FileReader();

      reader.onerror = function () {
        reject(new Error("Lỗi khi đọc file " + file.name));
      };

      reader.onload = function () {
        try {
          const text = String(reader.result || "");
          const json = JSON.parse(text);
          resolve(json);
        } catch (e) {
          reject(new Error("File " + file.name + " không phải JSON hợp lệ."));
        }
      };

      reader.readAsText(file);
    });
  }

  function validateSummary(summary) {
    if (!summary || typeof summary !== "object" || Array.isArray(summary)) {
      throw new Error("File summary phải là một JSON object (không phải mảng).");
    }

    const hasByTool = Object.prototype.hasOwnProperty.call(summary, "by_tool");
    const hasBySev  = Object.prototype.hasOwnProperty.call(summary, "by_severity");

    if (!hasByTool || !hasBySev) {
      console.warn("[upload_handler] summary thiếu by_tool/by_severity:", summary);
    }
  }

  function validateFindings(findings) {
    if (!Array.isArray(findings)) {
      throw new Error("File findings.json phải là một mảng (list) JSON.");
    }

    if (findings.length === 0) {
      console.warn("[upload_handler] findings.json là mảng rỗng.");
      return;
    }

    for (let i = 0; i < Math.min(findings.length, 5); i++) {
      const item = findings[i];
      if (typeof item !== "object" || item === null) {
        throw new Error("Một số phần tử trong findings.json không phải object JSON.");
      }
    }
  }

  renderBtn.addEventListener("click", function () {
    const summaryFile  = summaryInput.files[0];
    const findingsFile = findingsInput.files[0];

    // 1) Kiểm tra đủ file
    if (!summaryFile && !findingsFile) {
      showError("Vui lòng chọn đủ 2 file: summary_unified.json và findings.json.");
      return;
    }
    if (!summaryFile) {
      showError("Thiếu file summary (summary_unified.json).");
      return;
    }
    if (!findingsFile) {
      showError("Thiếu file findings (findings.json).");
      return;
    }

    // 2) Kiểm tra tên file (nhắc nhẹ)
    const isSummaryNameOk =
      /summary/i.test(summaryFile.name) && /\.json$/i.test(summaryFile.name);
    const isFindingsNameOk =
      /findings/i.test(findingsFile.name) && /\.json$/i.test(findingsFile.name);

    if (!isSummaryNameOk || !isFindingsNameOk) {
      const msg =
        "Tên file không giống mẫu \"summary_unified.json\" / \"findings.json\".\n" +
        "- Summary:  " + summaryFile.name + "\n" +
        "- Findings: " + findingsFile.name + "\n\n" +
        "Bạn vẫn muốn tiếp tục thử parse JSON chứ?";
      if (!window.confirm(msg)) {
        return;
      }
    }

    // 3) Đọc cả 2 file song song
    Promise.all([readJsonFile(summaryFile), readJsonFile(findingsFile)])
      .then(function ([summaryJson, findingsJson]) {
        try {
          validateSummary(summaryJson);
          validateFindings(findingsJson);
        } catch (e) {
          console.error("[upload_handler] validation error:", e);
          showError(e.message);
          return;
        }

        // 4) Giao cho hàm render chính của dashboard
        if (typeof window.applyUploadedData === "function") {
          window.applyUploadedData(summaryJson, findingsJson);
          return;
        }

        if (typeof window.ingest === "function") {
          window.ingest(findingsJson, summaryJson); // fallback
          return;
        }

        console.warn(
          "[upload_handler] Không tìm thấy handler (applyUploadedData/ingest)."
        );
        showError(
          "Đã đọc JSON thành công nhưng không có hàm xử lý để render.\n" +
          "Kiểm tra lại JS (applyUploadedData/ingest)."
        );
      })
      .catch(function (err) {
        console.error("[upload_handler] read/parse error:", err);
        showError("Không đọc được JSON upload.\nChi tiết: " + err.message);
      });
  });
})();
JS

# === Chèn thẻ <script> vào template index.html (nếu chưa có) ===
if [ -f "$TPL" ]; then
  if grep -q 'upload_handler.js' "$TPL"; then
    echo "[i] Template đã có upload_handler.js rồi."
  else
    echo "[i] Thêm <script> upload_handler.js vào $TPL"
    printf '\n  <script src="{{ url_for('"'"'static'"'"', filename='"'"'upload_handler.js'"'"') }}"></script>\n' >> "$TPL"
  fi
else
  echo "[WARN] Không tìm thấy template: $TPL" >&2
fi

echo "[OK] setup_upload_handler done."
