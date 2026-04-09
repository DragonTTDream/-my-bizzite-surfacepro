#!/bin/bash
set -ouex pipefail

# 1. 环境准备
export TMPDIR=/var/tmp
export KERNEL_INSTALL_SKIP_POSTTRANS=1

# 2. 导入密钥
rpm --import https://packages.microsoft.com/keys/microsoft.asc
rpm --import https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc

# 3. 配置双仓库 (F43 拿内核，F42 作为补位)
cat <<EOF > /etc/yum.repos.d/linux-surface-f43.repo
[linux-surface-f43]
name=linux-surface-f43
baseurl=https://pkg.surfacelinux.com/fedora/f43
enabled=1
gpgcheck=1
gpgkey=https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc
priority=1
EOF

cat <<EOF > /etc/yum.repos.d/linux-surface-f42.repo
[linux-surface-f42]
name=linux-surface-f42
baseurl=https://pkg.surfacelinux.com/fedora/f42
enabled=1
gpgcheck=1
gpgkey=https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc
priority=10
EOF

cat <<EOF > /etc/yum.repos.d/vscode.repo
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

# 4. 社区标准修复：手动注入 IPTS 固件 (绕过损坏的 RPM 仓库)
echo "Manually injecting IPTS firmware from GitHub source..."
# 创建固件存放目录
mkdir -p /usr/lib/firmware/intel/ipts
# 直接从源码仓库抓取最新固件二进制文件并部署
# 使用 curl 抓取 zip 包并解压至目标目录
curl -L https://github.com/linux-surface/surface-ipts-firmware/archive/refs/heads/master.tar.gz | tar -xz -C /tmp
cp -r /tmp/surface-ipts-firmware-master/ipts/* /usr/lib/firmware/intel/ipts/

# 5. 强制清理并安装剩余软件包
dnf clean all

# 注意：移除了报错的 surface-ipts-firmware RPM，改由上方手动注入
# 尝试安装其他核心组件。如果 surface-secureboot 依然 404，则通过 --skip-broken 跳过
dnf install -y --refresh --allowerasing \
    iptsd \
    libwacom-surface \
    libwacom-surface-data \
    code || dnf install -y --refresh --allowerasing --skip-broken iptsd libwacom-surface libwacom-surface-data code

# 6. 强制启用服务
systemctl enable iptsd.service

# 7. 清理非 Surface 内核，确保引导唯一
echo "Cleaning up non-surface kernels..."
KERNEL_VERSION=$(rpm -q kernel-surface --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' | head -n 1)
find /usr/lib
