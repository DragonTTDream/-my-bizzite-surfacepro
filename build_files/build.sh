#!/bin/bash
set -ouex pipefail

# 1. 环境准备
export TMPDIR=/var/tmp
export KERNEL_INSTALL_SKIP_POSTTRANS=1

# 2. 导入密钥
rpm --import https://packages.microsoft.com/keys/microsoft.asc
rpm --import https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc

# 3. 配置仓库 (锁定 F42 稳定版，因为 F43 还是坏的)
cat <<EOF > /etc/yum.repos.d/linux-surface.repo
[linux-surface]
name=linux-surface-f42-stable
baseurl=https://pkg.surfacelinux.com/fedora/f42
enabled=1
gpgcheck=1
gpgkey=https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc
EOF

cat <<EOF > /etc/yum.repos.d/vscode.repo
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

# 4. 社区标准修复：手动注入 IPTS 固件 (修正路径并移除单引号)
echo "Manually injecting IPTS firmware from GitHub source..."
mkdir -p /usr/lib/firmware/intel/ipts

# 下载并解压
curl -L https://github.com/linux-surface/surface-ipts-firmware/archive/refs/heads/master.tar.gz | tar -xz -C /tmp

# ！！！修正后的路径：GitHub 仓库里的 .bin 文件在 firmware/intel/ipts 目录下
# 且移除单引号，允许通配符展开
cp -r /tmp/surface-ipts-firmware-master/firmware/intel/ipts/* /usr/lib/firmware/intel/ipts/

# 5. 安装组件 (不再安装 surface-ipts-firmware RPM，因为它已被手动注入)
dnf clean all
dnf install -y --refresh --allowerasing \
    iptsd \
    libwacom-surface \
    libwacom-surface-data \
    surface-secureboot \
    code

# 6. 【关键修改】不再手动 enable iptsd.service
# 社区解释该服务由 udev 自动触发，手动 enable 会因 unit 不存在而报错。
# 只要上面的固件注入成功，系统重启后硬件被识别，iptsd 会自动启动。

# 7. 清理非 Surface 内核
echo "Cleaning up non-surface kernels..."
KERNEL_VERSION=$(rpm -q kernel-surface --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' | head -n 1)
find /usr/lib/modules -maxdepth 1 -mindepth 1 -not -name "$KERNEL_VERSION" -exec rm -rf {} +
depmod -a "$KERNEL_VERSION"

# 8. 禁用冲突仓库
dnf config-manager --set-disabled terra-mesa || true
sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/terra*.repo || true
