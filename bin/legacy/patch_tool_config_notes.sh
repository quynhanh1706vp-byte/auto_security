#!/usr/bin/env bash
set -euo pipefail

CFG="/home/test/Data/SECURITY_BUNDLE/ui/tool_config.json"

echo "[i] CFG = $CFG"

if [ ! -f "$CFG" ]; then
  echo "[ERR] Không tìm thấy $CFG"
  exit 1
fi

python3 - "$CFG" <<'PY'
import sys, json, pathlib

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))

notes = {
    "Trivy_FS": (
        "Phiên bản Trivy cho File System scan (Aqua Security). Quét vulnerabilities, "
        "misconfigurations và secrets trong filesystem / source code. "
        'Mode "fast": quét nhanh, ưu tiên tốc độ. '
        'Mode "aggr": quét sâu, đầy đủ hơn. Output JSON hoặc CycloneDX SBOM.'
    ),
    "Trivy_IaC": (
        "Scanner cho Infrastructure as Code (Terraform, Kubernetes, …). Kiểm tra "
        "misconfiguration trong IaC. "
        'Mode "fast": chạy nhanh, không đi quá sâu. '
        'Mode "aggr": kiểm tra kỹ hơn, phù hợp cho review bảo mật. '
        "Hỗ trợ cả local (Offline) và remote (Online)."
    ),
    "Grype": (
        "Vulnerability scanner cho container images / filesystem. Thường kết hợp với Syft "
        "để có SBOM. "
        'Mode "aggr": aggressive scan, tra cứu trên nhiều DB CVE hơn. '
        "Output chủ yếu dạng JSON, dùng cho báo cáo và CI/CD."
    ),
    "Syft_SBOM": (
        "Generate Software Bill of Materials (SBOM) cho dependencies. "
        'Mode "fast": tạo SBOM nhanh cho dự án. '
        "Hỗ trợ chuẩn CycloneDX / SPDX. Offline: quét file local; Online: quét image trên registry."
    ),
    "Gitleaks": (
        "Secret scanner (API keys, passwords, tokens trong code / git). "
        'Mode "fast": quét nhanh toàn bộ repo. '
        'Mode "aggr": quét kỹ hơn, phù hợp tiêu chuẩn bảo mật nội bộ. '
        "Thường chạy Offline trên repository local."
    ),
    "Bandit": (
        "Python static analyzer, tìm vulnerabilities trong mã nguồn Python. "
        'Mode "aggr": full scan với bộ rule mạnh hơn. '
        "Chủ yếu chạy Offline; có thể tích hợp Online / CI/CD."
    ),
    "KICS": (
        "Keeping Infrastructure as Code Secure. Scanner misconfiguration trong Terraform, "
        "CloudFormation, … "
        'Mode "fast": quét nhanh. '
        'Mode "aggr": kiểm tra sâu hơn. '
        "Thường chạy Offline trên file IaC."
    ),
    "CodeQL": (
        "Semantic code analysis, query code như dữ liệu để tìm vulnerabilities (đa ngôn ngữ). "
        'Mode "aggr": deep analysis, phù hợp chuẩn ISO / audit. '
        "Offline: build DB & query local; Online: có thể tích hợp GitHub Advanced Security."
    ),
}

if isinstance(data, dict) and "tools" in data:
    tools_list = data["tools"]
else:
    tools_list = data

if not isinstance(tools_list, list):
    print("[ERR] tool_config.json không phải list / không có key 'tools'.", file=sys.stderr)
else:
    changed = 0
    for row in tools_list:
        if not isinstance(row, dict):
            continue
        name = row.get("tool") or row.get("name")
        if not name:
            continue
        if name in notes:
            row["note"] = notes[name]
            # đồng bộ luôn sang key khác nếu UI đang dùng
            row.setdefault("desc", notes[name])
            changed += 1
            print(f"[OK] Update note cho tool {name}")

    if changed == 0:
        print("[WARN] Không tool nào được update – kiểm tra lại tên tool trong tool_config.json.")

path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

echo "[DONE] patch_tool_config_notes.sh hoàn thành."
