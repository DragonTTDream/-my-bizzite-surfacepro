#!/bin/bash
set -ouex pipefail

# 1. 环境准备
export TMPDIR=/var/tmp
export KERNEL_INSTALL_SKIP_POSTTRANS=1

# 2. 导入密钥与配置仓库
rpm --import https://packages.microsoft.com/keys/microsoft.asc
rpm --import https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc

# 配置 VS Code 仓库
cat <<EOF > /etc/yum.repos.d/vscode.repo
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

# 3. 修复内核参数 (解决屏幕闪烁)
echo "Integrating kernel arguments into image..."
mkdir -p /usr/lib/bootc/kargs.d
printf 'i915.enable_psr=0\n' > /usr/lib/bootc/kargs.d/50-surface-pro-8.kargs

# 4. 基于物理路径安装 (使用 GitHub 与 SourceForge 官方镜像)
GH_RELEASE="https://github.com/linux-surface/linux-surface/releases/download/fedora-43-6.18.8-1"
# 您指定的 iptsd v3.1.0 资产地址
IPTSD_URL="https://github.com/linux-surface/iptsd/releases/download/v3.1.0/iptsd-3.1.0-1.fc43.x86_64.rpm"

# 解决 pkg.surfacelinux.com 失效：使用官方 SourceForge 镜像路径
MIRROR_BASE="https://sourceforge.net/projects/linux-surface.mirror/files/fedora-43"
SECUREBOOT_URL="${MIRROR_BASE}/surface-secureboot-20251230-1.noarch.rpm/download"
FIRMWARE_URL="${MIRROR_BASE}/surface-firmware-20250814-1.noarch.rpm/download"

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
    $SECUREBOOT_URL \
    $FIRMWARE_URL \
    $IPTSD_URL \
    code

# 5. 精准清理内核模块 (解决 bootc lint 报错)
KERNEL_VERSION=$(rpm -q kernel-surface --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' | head -n 1)
if [ -n "$KERNEL_VERSION" ]; then
    find /usr/lib/modules -maxdepth 1 -mindepth 1 -not -name "$KERNEL_VERSION" -exec rm -rf {} +
    depmod -a "$KERNEL_VERSION"
fi

# 6. 禁用冗余仓库
sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/terra-extras.repo /etc/yum.repos.d/terra-mesa.repo /etc/yum.repos.d/terra.repo || true
