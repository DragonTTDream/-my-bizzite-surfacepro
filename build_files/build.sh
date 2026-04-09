#!/bin/bash
set -ouex pipefail

# 1. 环境准备
export TMPDIR=/var/tmp
export KERNEL_INSTALL_SKIP_POSTTRANS=1

# 2. 导入密钥
rpm --import https://packages.microsoft.com/keys/microsoft.asc
rpm --import https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc

# 3. 配置双仓库
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

# 4. 社区标准修复：手动注入 IPTS 固件
echo "Manually injecting IPTS firmware from GitHub source..."
mkdir -p /usr/lib/firmware/intel/ipts

# 下载并解压
curl -L https://github.com/linux-surface/surface-ipts-firmware/archive/refs/heads/master.tar.gz | tar -xz -C /tmp

# 修正路径并移除单引号，确保通配符展开
# 注意：该仓库的固件实际位于 firmware/intel/ipts 目录下
if [ -d /tmp/surface-ipts-firmware-master/firmware/intel/ipts ]; then
    cp -r /tmp/surface-ipts-firmware-master/firmware/intel/ipts/* /usr/lib/firmware/intel/ipts/
else
    # 兼容性处理：如果 master 路径不存在，尝试 main 路径（GitHub 默认分支名变更可能导致此问题）
    # 或者尝试直接搜索 ipts 目录
    SOURCE_PATH=$(find /tmp -type d -name "ipts" | head -n 1)
    cp -r "${SOURCE_PATH}"/* /usr/lib/firmware/intel/ipts/
fi

# 5. 强制清理并安装软件包
dnf clean all

# 仅安装 iptsd 和配套工具，固件已由上方手动注入
dnf install -y --refresh --allowerasing \
    iptsd \
    libwacom-surface \
    libwacom-surface-data \
    code || dnf install -y --refresh --allowerasing --skip-broken iptsd libwacom-surface libwacom-surface-data code

# 6. 强制启用服务
systemctl enable iptsd.service

# 7. 清理非 Surface 内核
echo "Cleaning up non-surface kernels..."
KERNEL_VERSION=$(rpm -q kernel-surface --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' | head -n 1)
find /usr/lib/modules -maxdepth 1 -mindepth 1 -not -name "$KERNEL_VERSION" -exec rm -rf {} +
depmod -a "$KERNEL_VERSION"

# 8. 禁用冲突仓库
dnf config-manager --set-disabled terra-mesa || true
sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/terra*.repo || true
