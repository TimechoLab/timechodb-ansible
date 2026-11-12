#!/usr/bin/env bash
# 一次性引导（在被管机上执行，先于 Ansible）：
#   1) 为当前用户（或 SUDO_USER）配置 sudo 免密 —— Ansible become 需要
#   2) 安装 ansible-core / python3-apt / curl（把这台机器当作控制节点时用）
# 时区、DNS、limits、sysctl 等由 roles/common 统一管理，这里不做。
#
# 用法： bash bootstrap.sh [sudo密码]
set -euo pipefail

SUDO_PASS="${1:-}"
TARGET_USER="${SUDO_USER:-$(id -un)}"
SUDOERS_FILE="/etc/sudoers.d/90-${TARGET_USER}-nopasswd"

sudocmd() {
  if sudo -n true 2>/dev/null; then
    sudo "$@"
  else
    printf '%s\n' "$SUDO_PASS" | sudo -S -p '' "$@"
  fi
}

echo "==> 1/2 配置 sudo 免密（用户：$TARGET_USER）"
if sudo -n true 2>/dev/null; then
  echo "    已免密，跳过"
else
  printf '%s\n' "$SUDO_PASS" | sudo -S -p '' tee "$SUDOERS_FILE" >/dev/null <<EOF
$TARGET_USER ALL=(ALL) NOPASSWD:ALL
EOF
  sudocmd chmod 0440 "$SUDOERS_FILE"
  sudocmd visudo -c >/dev/null
  sudo -K
  sudo -n true && echo "    完成" || { echo "    失败"; exit 1; }
fi

echo "==> 2/2 安装 ansible-core"
sudocmd apt-get update -qq
DEBIAN_FRONTEND=noninteractive sudocmd apt-get install -y -qq ansible-core python3-apt curl >/dev/null
ansible --version | head -1
echo "==> 引导完成"
