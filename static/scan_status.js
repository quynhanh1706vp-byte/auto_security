let lastScanStatus = "unknown";

function ensureScanStatusPill() {
  let pill = document.getElementById("scan-status-pill");
  if (!pill) {
    pill = document.createElement("div");
    pill.id = "scan-status-pill";
    pill.className = "scan-status-pill scan-status-idle";
    pill.textContent = "Idle";
    document.body.appendChild(pill);
  }
  return pill;
}

function setScanStatusPill(status) {
  const pill = ensureScanStatusPill();
  if (!pill) return;

  pill.classList.remove(
    "scan-status-idle",
    "scan-status-running",
    "scan-status-error"
  );

  if (status === "running") {
    pill.classList.add("scan-status-running");
    pill.textContent = "Running…";
  } else if (status === "idle") {
    pill.classList.add("scan-status-idle");
    pill.textContent = "Idle";
  } else {
    pill.classList.add("scan-status-error");
    pill.textContent = "Unknown";
  }
}

async function pollScanStatus() {
  try {
    const res = await fetch("/api/scan_status");
    const data = await res.json();
    const status = data.status || "unknown";

    if (status !== lastScanStatus) {
      // nếu vừa từ running -> idle thì reload lại dữ liệu
      if (lastScanStatus === "running" && status === "idle") {
        if (typeof loadDashboardData === "function") {
          loadDashboardData();
        }
        if (typeof loadDataSource === "function") {
          loadDataSource(1);
        }
      }

      setScanStatusPill(status);
      lastScanStatus = status;
    }
  } catch (err) {
    console.error("pollScanStatus error:", err);
    setScanStatusPill("unknown");
  }
}

document.addEventListener("DOMContentLoaded", () => {
  ensureScanStatusPill();
  setScanStatusPill("idle");
  pollScanStatus();
  setInterval(pollScanStatus, 3000);
});


// PATCH_STUBBORN_HIDE
(function () {
  function hideHelpAndRatio() {
    try {
      var nodes = document.querySelectorAll('*');
      nodes.forEach(function (el) {
        if (!el || !el.textContent) return;
        var txt = el.textContent;

        // 1) Ẩn đoạn help tiếng Việt ở SETTINGS – TOOL CONFIG
        if (txt.indexOf('Mỗi dòng tương ứng với 1 tool') !== -1 ||
            txt.indexOf('/home/test/Data/SECURITY_BUNDLE/ui/static/tool_config.json') !== -1) {
          if (el.parentElement) {
            el.parentElement.style.display = 'none';
          } else {
            el.style.display = 'none';
          }
          return;
        }

        // 2) Xóa riêng phần "8/7" trong header Crit/High
        if (txt.indexOf('Crit/High:') !== -1 && txt.indexOf('8/7') !== -1) {
          var html = el.innerHTML || '';
          html = html.replace(/8\/7/g, '').replace(/\s{2,}/g, ' ');
          el.innerHTML = html.trim();
        }
      });
    } catch (e) {
      console.log('PATCH_STUBBORN_HIDE error', e);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', hideHelpAndRatio);
  } else {
    hideHelpAndRatio();
  }

  var obs = new MutationObserver(function () {
    hideHelpAndRatio();
  });
  if (document.body) {
    obs.observe(document.body, { childList: true, subtree: true });
  }
})();


// PATCH_GLOBAL_HIDE_8_7_AND_HELP
(function () {
  function hideStuff() {
    try {
      var nodes = document.querySelectorAll('*');
      nodes.forEach(function (el) {
        if (!el || !el.textContent) return;
        var txt = el.textContent;

        // 1) Ẩn đoạn help tiếng Việt ở SETTINGS – TOOL CONFIG
        if (txt.indexOf('Mỗi dòng tương ứng với 1 tool') !== -1 ||
            txt.indexOf('/home/test/Data/SECURITY_BUNDLE/ui/static/tool_config.json') !== -1) {
          if (el.parentElement) {
            el.parentElement.style.display = 'none';
          } else {
            el.style.display = 'none';
          }
          return;
        }

        // 2) Xóa riêng phần "8/7" trong header Crit/High
        if (txt.indexOf('Crit/High:') !== -1 && txt.indexOf('8/7') !== -1) {
          var html = el.innerHTML || '';
          html = html.split('8/7').join('');      // bỏ mọi "8/7"
          html = html.replace(/\s{2,}/g, ' ');    // gom bớt khoảng trắng
          el.innerHTML = html.trim();
        }
      });
    } catch (e) {
      console.log('PATCH_GLOBAL_HIDE_8_7_AND_HELP error', e);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', hideStuff);
  } else {
    hideStuff();
  }

  var obs = new MutationObserver(function () {
    hideStuff();
  });
  if (document.body) {
    obs.observe(document.body, { childList: true, subtree: true });
  }
})();


// PATCH_FINAL_STRIP_CRIT_RATIO
(function () {
  function fixHeaderAndHelp() {
    try {
      var nodes = document.querySelectorAll('*');
      nodes.forEach(function (el) {
        if (!el || !el.textContent) return;
        var txt = el.textContent;

        // 1) Ẩn đoạn help tiếng Việt dưới SETTINGS – TOOL CONFIG
        if (txt.indexOf('Mỗi dòng tương ứng với 1 tool') !== -1 ||
            txt.indexOf('/home/test/Data/SECURITY_BUNDLE/ui/static/tool_config.json') !== -1) {
          if (el.parentElement) {
            el.parentElement.style.display = 'none';
          } else {
            el.style.display = 'none';
          }
          return;
        }

        // 2) Bỏ ratio thứ 2 sau Crit/High (vd: 0/170 8/7 -> 0/170)
        if (txt.indexOf('Crit/High:') !== -1) {
          var idx = txt.indexOf('Crit/High:');
          var after = txt.slice(idx);           // từ "Crit/High:" trở đi
          var parts = after.split(' ');         // tách theo khoảng trắng
          var ratios = [];
          for (var i = 0; i < parts.length; i++) {
            if (parts[i].indexOf('/') !== -1) {
              ratios.push(parts[i]);
            }
          }
          if (ratios.length >= 2) {
            var firstRatio = ratios[0];         // vd "0/170"
            var before = txt.slice(0, idx);
            var newTxt = before + 'Crit/High: ' + firstRatio;
            el.textContent = newTxt;
          }
        }
      });
    } catch (e) {
      console.log('PATCH_FINAL_STRIP_CRIT_RATIO error', e);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', fixHeaderAndHelp);
  } else {
    fixHeaderAndHelp();
  }

  var obs = new MutationObserver(function () {
    fixHeaderAndHelp();
  });
  if (document.body) {
    obs.observe(document.body, { childList: true, subtree: true });
  }

  console.log('PATCH_FINAL_STRIP_CRIT_RATIO installed');
})();
