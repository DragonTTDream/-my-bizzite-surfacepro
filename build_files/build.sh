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

# 配置 Linux-Surface 仓库 (用于安装最新版 iptsd)
cat <<EOF > /etc/yum.repos.d/linux-surface.repo
[linux-surface]
name=Linux Surface
baseurl=https://pkg.surfacelinux.com/fedora/f\$releasever
enabled=1
gpgcheck=1
gpgkey=https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc
EOF

# 3. 手动注入 IPTS 固件
echo "Manually injecting IPTS firmware..."
mkdir -p /usr/lib/firmware/intel/ipts
curl -L https://github.com/linux-surface/surface-ipts-firmware/archive/refs/heads/master.tar.gz | tar -xz -C /tmp
cp -r /tmp/surface-ipts-firmware-master/firmware/intel/ipts/* /usr/lib/firmware/intel/ipts/

# 4. 修复内核参数 (解决中断验证失败导致的触控笔失效与屏幕闪烁)
echo "Integrating kernel arguments into image..."
mkdir -p /usr/lib/bootc/kargs.d
printf 'intremap=nosid i915.enable_psr=0\n' > /usr/lib/bootc/kargs.d/50-surface-pro-8.kargs

# 5. 修复手写笔模式 (注入深度位偏移描述以激活 Stylus Mode)
echo "Creating deep-offset iptsd configuration for SP8..."
mkdir -p /usr/share/iptsd
cat <<EOF > /usr/share/iptsd/045E:0C37.conf
[Device]
Name=Surface Pro 8
Model=045E:0C37

[Config]
SensorWidth=2880
SensorHeight=1920
Touchscreen=true
Stylus=true

[Stylus]
# 核心位偏移参数：解决从 3500 字节原始数据中提取压感的问题
X.Offset = 0
X.Size = 16
Y.Offset = 16
Y.Size = 16
Pressure.Offset = 32
Pressure.Size = 12
Tip.Offset = 44
Tip.Size = 1
Eraser.Offset = 45
Eraser.Size = 1
Invert.Offset = 46
Invert.Size = 1
EOF

# 6. 修复服务自动启动逻辑
mkdir -p /etc/udev/rules.d
printf 'ACTION=="add", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="045e", ATTRS{idProduct}=="0c37", ENV{SYSTEMD_WANTS}+="iptsd@$env{DEVNAME}.service"' > /etc/udev/rules.d/99-ipts-force.rules

# 7. 基于 GitHub Assets 的物理路径安装
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

# 8. 精准清理内核模块 (解决 bootc lint 报错)
KERNEL_VERSION=$(rpm -q kernel-surface --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' | head -n 1)
if [ -n "$KERNEL_VERSION" ]; then
    find /usr/lib/modules -maxdepth 1 -mindepth 1 -not -name "$KERNEL_VERSION" -exec rm -rf {} +
    depmod -a "$KERNEL_VERSION"
fi

# 9. 禁用冗余仓库
sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/terra-extras.repo /etc/yum.repos.d/terra-mesa.repo /etc/yum.repos.d/terra.repo /etc/yum.repos.d/linux-surface.repo || true
