#!/bin/bash
set -ouex pipefail

# 1. 环境准备
export TMPDIR=/var/tmp
export KERNEL_INSTALL_SKIP_POSTTRANS=1

# 2. 导入密钥
rpm --import https://packages.microsoft.com/keys/microsoft.asc
rpm --import https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc

# 3. 配置 VS Code 仓库 (保持官方源以获取持续更新)
cat <<EOF > /etc/yum.repos.d/vscode.repo
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

# 4. 手动注入 IPTS 固件 (利用您确认成功的逻辑)
echo "Manually injecting IPTS firmware from GitHub source..."
mkdir -p /usr/lib/firmware/intel/ipts
curl -L https://github.com/linux-surface/surface-ipts-firmware/archive/refs/heads/master.tar.gz | tar -xz -C /tmp
# 显式拷贝所有 MSHW 固件文件夹
cp -r /tmp/surface-ipts-firmware-master/firmware/intel/ipts/* /usr/lib/firmware/intel/ipts/

# 5. 暴力安装：直接指定 GitHub 资产的物理路径
# 绕过损坏的服务器索引，直接从 GitHub Release 下载并安装这 10 个 fc43 组件
GH_RELEASE="https://github.com/linux-surface/linux-surface/releases/download/fedora-43-6.18.8-1"

dnf install -y --refresh --allowerasing \
    $GH_RELEASE/kernel-surface-6.18.8-1.surface.fc43.x86_64.rpm \
    $GH_RELEASE/kernel-surface-core-6.18.8-1.surface.fc43.x86_64.rpm \
    $GH_RELEASE/kernel-surface-default-watchdog-6.18.8-1.surface.fc43.x86_64.rpm \
    $GH_RELEASE/kernel-surface-devel-6.18.8-1.surface.fc43.x86_64.rpm \
    $GH_RELEASE/kernel-surface-devel-matched-6.18.8-1.surface.fc43.x86_64.rpm \
    $GH_RELEASE/kernel-surface-modules-6.18.8-1.surface.fc43.x86_64.rpm \
    $GH_RELEASE/kernel-surface-modules-core-6.18.8-1.surface.fc43.x86_64.rpm \
    $GH_RELEASE/kernel-surface-modules-extra-6.18.8-1.surface.fc43.x86_64.rpm \
    $GH_RELEASE/kernel-surface-modules-extra-matched-6.18.8-1.surface.fc43.x86_64.rpm \
    $GH_RELEASE/kernel-surface-modules-internal-6.18.8-1.surface.fc43.x86_64.rpm \
    https://pkg.surfacelinux.com/fedora/f42/surface-secureboot-20251230-1.fc42.noarch.rpm \
    code \
    iptsd

# 6. 内核清理逻辑
# 确保系统仅保留刚刚安装的 surface-6.18.8 内核
echo "Cleaning up non-surface kernels..."
KERNEL_VERSION=$(rpm -q kernel-surface --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' | head -n 1)
find /usr/lib/modules -maxdepth 1 -mindepth 1 -not -name "$KERNEL_VERSION" -exec rm -rf {} +
depmod -a "$KERNEL_VERSION"

# 7. 禁用冲突仓库
dnf config-manager --set-disabled terra-mesa || true
sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/terra*.repo || true
