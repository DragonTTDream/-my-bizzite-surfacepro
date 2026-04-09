#!/bin/bash
set -ouex pipefail

# 1. 环境准备
export TMPDIR=/var/tmp
export KERNEL_INSTALL_SKIP_POSTTRANS=1

# 2. 密钥与仓库配置
# 导入密钥
rpm --import https://packages.microsoft.com/keys/microsoft.asc
rpm --import https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc

# 创建 linux-surface 仓库 (修正了变量转义，确保能够动态匹配 Fedora 版本)
cat <<EOF > /etc/yum.repos.d/linux-surface.repo
[linux-surface]
name=linux-surface
baseurl=https://pkg.surfacelinux.com/fedora/f\$releasever
enabled=1
gpgcheck=1
gpgkey=https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc
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

# 3. 安装 Surface 核心组件
# 强制清理元数据缓存，确保新仓库立即生效
dnf clean all

# 安装软件包，使用 --allowerasing 处理与基础镜像中旧版本 libwacom 的冲突
dnf install -y --refresh --allowerasing \
    iptsd \
    surface-ipts-firmware \
    libwacom-surface \
    libwacom-surface-data \
    surface-secureboot \
    code

# 4. 强制启用服务
# 确保触控笔后台进程在开机时启动
systemctl enable iptsd.service

# 5. 彻底清理非 Surface 内核，确保启动项唯一
echo "Cleaning up non-surface kernels..."
# 获取当前安装的 surface 内核版本号
KERNEL_VERSION=$(rpm -q kernel-surface --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' | head -n 1)
# 移除所有非当前 surface 内核的模块文件夹
find /usr/lib/modules -maxdepth 1 -mindepth 1 -not -name "$KERNEL_VERSION" -exec rm -rf {} +
# 重新生成模块依赖关系
depmod -a "$KERNEL_VERSION"

# 6. 禁用可能冲突的仓库
dnf config-manager --set-disabled terra-mesa || true
sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/terra*.repo || true
