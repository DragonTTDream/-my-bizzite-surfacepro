#!/bin/bash
set -ouex pipefail

# ==============================================================================
# 1. 构建环境初始化
# ==============================================================================
export TMPDIR=/var/tmp
export KERNEL_INSTALL_SKIP_POSTTRANS=1

# ==============================================================================
# 2. 软件源与安全密钥配置
# ==============================================================================
rpm --import https://packages.microsoft.com/keys/microsoft.asc
rpm --import https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc

cat <<EOF > /etc/yum.repos.d/vscode.repo
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

# ==============================================================================
# 3. 硬件级内核参数修复
# ==============================================================================
echo "Integrating kernel arguments into image..."
mkdir -p /usr/lib/bootc/kargs.d
printf 'i915.enable_psr=0\n' > /usr/lib/bootc/kargs.d/50-surface-pro-8.kargs

# ==============================================================================
# 4. 核心驱动与依赖包物理路径声明
# ==============================================================================
GH_RELEASE="https://github.com/linux-surface/linux-surface/releases/download/fedora-43-6.18.8-1"
IPTSD_URL="https://github.com/linux-surface/iptsd/releases/download/v3.1.0/iptsd-3.1.0-1.fc43.x86_64.rpm"
SURFACE_CONTROL_URL="https://github.com/linux-surface/surface-control/releases/download/v0.5.0-1/surface-control-0.5.0-1.fc43.x86_64.rpm"
SECUREBOOT_URL="https://github.com/linux-surface/secureboot-mok/releases/download/20251230-1/surface-secureboot-20251230-1.fc43.noarch.rpm"

LIBWACOM_BASE="https://github.com/linux-surface/libwacom-surface/releases/download/v2.17.0-1"
LIBWACOM_CORE="${LIBWACOM_BASE}/libwacom-surface-2.17.0-1.fc43.x86_64.rpm"
LIBWACOM_DATA="${LIBWACOM_BASE}/libwacom-surface-data-2.17.0-1.fc43.noarch.rpm"
LIBWACOM_UTILS="${LIBWACOM_BASE}/libwacom-surface-utils-2.17.0-1.fc43.x86_64.rpm"

# ==============================================================================
# 5. 执行系统底层组件与应用安装
# ==============================================================================
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
    $IPTSD_URL \
    $SURFACE_CONTROL_URL \
    $LIBWACOM_CORE \
    $LIBWACOM_DATA \
    $LIBWACOM_UTILS \
    code

# ==============================================================================
# 6. 核心修复：强制 udev 绑定 (修正 Systemd 路径转义)
# ==============================================================================
echo "Applying Surface Pro 8 specific systemd path fix..."
mkdir -p /usr/lib/udev/rules.d
cat <<EOF > /usr/lib/udev/rules.d/99-iptsd-sp8-force.rules
# 使用 dev- 前缀强制 Systemd 将实例名解析为 /dev/ 路径下的设备
KERNEL=="hidraw0", SUBSYSTEM=="hidraw", TAG+="systemd", ENV{SYSTEMD_WANTS}+="iptsd@dev-%k.service"
EOF

# ==============================================================================
# 7. 镜像构建后期清理 (修正 RPM 查询格式以解决 bootc lint 报错)
# ==============================================================================
# 获取新安装内核的确切版本名（使用正确的 RPM 宏定义）
KERNEL_VERSION=$(rpm -q kernel-surface --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' | head -n 1)

if [ -n "$KERNEL_VERSION" ]; then
    echo "Cleaning up redundant kernel modules for version: $KERNEL_VERSION"
    # 删除 /usr/lib/modules 下除新内核以外的所有目录，确保符合 bootc 单一内核标准
    find /usr/lib/modules -maxdepth 1 -mindepth 1 -not -name "$KERNEL_VERSION" -exec rm -rf {} +
    depmod -a "$KERNEL_VERSION"
fi

# 禁用构建环境冗余软件源
sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/terra-extras.repo /etc/yum.repos.d/terra-mesa.repo /etc/yum.repos.d/terra.repo || true
