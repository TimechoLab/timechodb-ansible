#!/usr/bin/env bash
# 一次性引导（在 Ubuntu 被管机上执行，先于 Ansible）：
#   1) 为 fzw 配置 sudo 免密（Ansible become 需要）
#   2) 修正被网关劫持的 DNS（否则 apt 下载失败）
#   3) 安装 ansible-core（本项目把它作为控制节点）
#
# 用法： bash bootstrap.sh [sudo密码]
set -euo pipefail

SUDO_PASS="${1:-}"
sudocmd() {
  if sudo -n true 2>/dev/null; then
    sudo "$@"
  else
    printf '%s\n' "$SUDO_PASS" | sudo -S -p '' "$@"
  fi
}

echo "==> 1/3 配置 sudo 免密"
if sudo -n true 2>/dev/null; then
  echo "    已免密，跳过"
else
  printf '%s\n' "$SUDO_PASS" | sudo -S -p '' sh -c '
    printf "%s\n" "fzw ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-fzw-nopasswd
    chmod 0440 /etc/sudoers.d/90-fzw-nopasswd
    visudo -c >/dev/null'
  sudo -K
  sudo -n true && echo "    完成" || { echo "    失败"; exit 1; }
fi

echo "==> 2/3 修正 DNS"
sudocmd tee /etc/netplan/99-dns-override.yaml >/dev/null <<'NETPLAN'
network:
  version: 2
  ethernets:
    ens33:
      dhcp4: true
      dhcp4-overrides:
        use-dns: false
      nameservers:
        addresses: [223.5.5.5, 119.29.29.29]
NETPLAN
sudocmd chmod 600 /etc/netplan/99-dns-override.yaml
sudocmd netplan apply || true

echo "==> 3/3 安装 ansible-core"
sudocmd apt-get update -qq
DEBIAN_FRONTEND=noninteractive sudocmd apt-get install -y -qq ansible-core python3-apt curl >/dev/null
ansible --version | head -1
echo "==> 引导完成"
