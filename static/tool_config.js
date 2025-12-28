// tool_config.js
// Cấu hình hiển thị cho các tool, nhưng vẫn linh động:
// - Nếu có tool mới chưa khai báo -> vẫn show bình thường
// - Có thể override bằng window.SECBUNDLE_TOOL_CONFIG_OVERRIDE

(function () {
  const DEFAULT_CONFIG = {
    order: [
      "Bandit", "codeql",
      "Gitleaks",
      "Semgrep",
      "TrivyVuln",
      "TrivySecret",
      "TrivyMisconfig",
      "TrivySBOM",
      "Grype"
      "CodeQL",
    ],
    tools: {
      Bandit: {
        label: "Bandit (Python)",
        enabled: true,
        category: "SAST"
      },
      Gitleaks: {
        label: "Gitleaks (Secrets)",
        enabled: true,
        category: "Secrets"
      },
      Semgrep: {
        label: "Semgrep (Code)",
        enabled: true,
        category: "SAST"
      },
      TrivyVuln: {
        label: "Trivy FS (Vuln)",
        enabled: true,
        category: "Vuln"
      },
      TrivySecret: {
        label: "Trivy FS (Secrets)",
        enabled: false,
        category: "Secrets"
      },
      TrivyMisconfig: {
        label: "Trivy FS (Misconfig)",
        enabled: false,
        category: "Misconfig"
      },
      TrivySBOM: {
        label: "Trivy SBOM",
        enabled: false,
        category: "SBOM"
      },
      Grype: {
        label: "Grype (SBOM SCA)",
        enabled: true,
        category: "SBOM"
      }
    }
  };

  // Cho phép override mềm bằng biến global:
  // window.SECBUNDLE_TOOL_CONFIG_OVERRIDE = {
  //   tools: { TrivySecret: { enabled: true } }
  // };
  function mergeConfig() {
    const override = window.SECBUNDLE_TOOL_CONFIG_OVERRIDE || {};
    const cfg = JSON.parse(JSON.stringify(DEFAULT_CONFIG));

    if (override.order && Array.isArray(override.order)) {
      cfg.order = override.order.slice();
    }

    if (override.tools && typeof override.tools === "object") {
      Object.keys(override.tools).forEach(function (k) {
        const base = cfg.tools[k] || {};
        cfg.tools[k] = Object.assign({}, base, override.tools[k]);
      });
    }

    return cfg;
  }

  const EFFECTIVE_CONFIG = mergeConfig();

  function getToolMeta(name) {
    const meta = EFFECTIVE_CONFIG.tools[name] || {};
    const label = meta.label || name;
    const enabled = typeof meta.enabled === "boolean" ? meta.enabled : true;
    return {
      key: name,
      label: label,
      enabled: enabled,
      category: meta.category || null
    };
  }

  // Chuẩn hoá danh sách tool dựa trên by_tool trong summary
  function normalizeTools(byTool) {
    const names = Object.keys(byTool || {});

    // Gộp theo thứ tự config trước, sau đó tới các tool mới chưa có trong order
    const seen = {};
    const ordered = [];

    EFFECTIVE_CONFIG.order.forEach(function (name) {
      if (names.indexOf(name) !== -1) {
        ordered.push(name);
        seen[name] = true;
      }
    });

    names.forEach(function (name) {
      if (!seen[name]) {
        ordered.push(name);
      }
    });

    return ordered.map(function (name) {
      const meta = getToolMeta(name);
      const data = byTool[name] || {};
      const total = Number(data.total || 0);
      return {
        key: name,
        label: meta.label,
        enabled: meta.enabled,
        total: total,
        raw: data
      
  CodeQL: {
    label: "CodeQL (SAST)",
    note: "SAST",
  },
};
    });
  }

  window.SECBUNDLE_TOOL_CONFIG = EFFECTIVE_CONFIG;
  window.SECBUNDLE_getToolMeta = getToolMeta;
  window.SECBUNDLE_normalizeTools = normalizeTools;
})();

// PATCH_HIDE_TOOLS_ENABLED
document.addEventListener('DOMContentLoaded', function () {
  try {
    var patterns = [
      'Tools enabled:',
      'Mỗi dòng tương ứng với 1 tool',
      'tool_config.json'
    ];

    var nodes = document.querySelectorAll('*');
    nodes.forEach(function (el) {
      if (!el || !el.textContent) return;
      var txt = el.textContent;
      for (var i = 0; i < patterns.length; i++) {
        if (txt.indexOf(patterns[i]) !== -1) {
          el.style.display = 'none';
          break;
        }
      }
    });
  } catch (e) {
    console.log('PATCH_HIDE_TOOLS_ENABLED error', e);
  }
});


// PATCH_HIDE_CRIT_8_7_AND_HELP
(function () {
  function patchSettingsHeaderAndHelp() {
    try {
      var nodes = document.querySelectorAll('*');
      nodes.forEach(function (el) {
        if (!el || !el.textContent) return;
        var txt = el.textContent;

        // 1) Ẩn đoạn mô tả tiếng Việt dưới SETTINGS – TOOL CONFIG
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
          // xóa 8/7 trong HTML, rồi dọn bớt khoảng trắng
          var html = el.innerHTML || '';
          html = html.replace(/8\/7/g, '').replace(/\s{2,}/g, ' ');
          el.innerHTML = html.trim();
        }
      });
    } catch (e) {
      console.log('PATCH_HIDE_CRIT_8_7_AND_HELP error', e);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', patchSettingsHeaderAndHelp);
  } else {
    patchSettingsHeaderAndHelp();
  }

  // Theo dõi SPA/tab load lại
  var obs = new MutationObserver(function () {
    patchSettingsHeaderAndHelp();
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
