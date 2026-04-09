#!/bin/bash

# 打印执行过程，遇错即停
set -ouex pipefail

### --- 1. 环境准备 (跳过容器内的内核脚本报错) ---
export TMPDIR=/var/tmp
export KERNEL_INSTALL_SKIP_POSTTRANS=1

### --- 2. 密钥与仓库准备 ---
# 仅保留微软和 Surface 密钥
rpm --import https://packages.microsoft.com/keys/microsoft.asc
rpm --import https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc

# 仅保留 VS Code 仓库 (已移除 Edge)
cat <<EOF > /etc/yum.repos.d/vscode.repo
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

### --- 3. 物理地址暴力安装 (已移除 Edge) ---

URL="https://pkg.surfacelinux.com/fedora/f43"

# 这里只安装你确认能成功的内核包、驱动包和 VS Code
dnf install -y --refresh --allowerasing \
    $URL/kernel-surface-6.18.8-1.surface.fc43.x86_64.rpm \
    $URL/kernel-surface-core-6.18.8-1.surface.fc43.x86_64.rpm \
    $URL/kernel-surface-modules-6.18.8-1.surface.fc43.x86_64.rpm \
    $URL/kernel-surface-modules-core-6.18.8-1.surface.fc43.x86_64.rpm \
    $URL/kernel-surface-modules-extra-6.18.8-1.surface.fc43.x86_64.rpm \
    $URL/kernel-surface-devel-6.18.8-1.surface.fc43.x86_64.rpm \
    $URL/iptsd-3.1.0-1.fc43.x86_64.rpm \
    $URL/libwacom-surface-2.17.0-1.fc43.x86_64.rpm \
    $URL/libwacom-surface-data-2.17.0-1.fc43.noarch.rpm \
    $URL/surface-secureboot-20251230-1.fc43.noarch.rpm \
    code

### --- 4. 启用服务 (容错处理) ---

# 如果 iptsd 服务文件存在，则启用它；如果不存在，打印警告但不报错挂断构建
if [ -f /usr/lib/systemd/system/iptsd.service ]; then
    systemctl enable iptsd.service
else
    echo "Warning: iptsd.service not found, you may need to enable it manually after install."
fi
# 禁用导致构建失败的 terra 相关仓库
dnf config-manager --set-disabled terra-mesa || true
# 强制修改配置文件以确保在打包阶段不会被调用
sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/terra*.repo || true

# --- 彻底清理旧内核，解决双内核冲突 ---
# 找出不是 surface 的内核版本并删掉它们
echo "Cleaning up non-surface kernels..."
KERNEL_VERSION=$(rpm -q kernel-surface --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')
# 强制删除基础镜像自带的通用内核文件夹
find /usr/lib/modules -maxdepth 1 -mindepth 1 -not -name "$KERNEL_VERSION" -exec rm -rf {} +
# 运行 depmod 确保新内核被正确识别
depmod -a "$KERNEL_VERSION"
