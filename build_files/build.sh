#!/bin/bash
set -ouex pipefail

# 1. 环境准备
export TMPDIR=/var/tmp
export KERNEL_INSTALL_SKIP_POSTTRANS=1

# 2. 导入密钥
rpm --import https://packages.microsoft.com/keys/microsoft.asc
rpm --import https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc

# 3. 配置双仓库 (F43 拿内核，F42 拿补丁依赖)
# 创建 F43 仓库
cat <<EOF > /etc/yum.repos.d/linux-surface-f43.repo
[linux-surface-f43]
name=linux-surface-f43
baseurl=https://pkg.surfacelinux.com/fedora/f43
enabled=1
gpgcheck=1
gpgkey=https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc
priority=1
EOF

# 创建 F42 仓库
cat <<EOF > /etc/yum.repos.d/linux-surface-f42.repo
[linux-surface-f42]
name=linux-surface-f42
baseurl=https://pkg.surfacelinux.com/fedora/f42
enabled=1
gpgcheck=1
gpgkey=https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc
priority=10
EOF

# 创建 VS Code 仓库
cat <<EOF > /etc/yum.repos.d/vscode.repo
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

# 4. 强制清理并安装
dnf clean all

# 针对报错的 surface-ipts-firmware 和 surface-secureboot，采用直接物理路径安装以绕过损坏的仓库索引
dnf install -y --refresh --allowerasing \
    iptsd \
    https://pkg.surfacelinux.com/fedora/f42/surface-ipts-firmware-20191215-1.noarch.rpm \
    https://pkg.surfacelinux.com/fedora/f42/surface-secureboot-20251230-1.fc42.noarch.rpm \
    libwacom-surface \
    libwacom-surface-data \
    code

# 5. 强制启用服务
systemctl enable iptsd.service

# 6. 清理非 Surface 内核，确保引导唯一
echo "Cleaning up non-surface kernels..."
KERNEL_VERSION=$(rpm -q kernel-surface --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' | head -n 1)
find /usr/lib/modules -maxdepth 1 -mindepth 1 -not -name "$KERNEL_VERSION" -exec rm -rf {} +
depmod -a "$KERNEL_VERSION"

# 7. 禁用冲突仓库
dnf config-manager --set-disabled terra-mesa || true
sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/terra*.repo || true
