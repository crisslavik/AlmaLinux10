#!/bin/bash
# setup-nvidia-cuda-el10.sh  —  AlmaLinux 10 complete NVIDIA + CUDA install
set -euo pipefail

DRV_VER="580.119.02"
DRV_RUN="NVIDIA-Linux-x86_64-${DRV_VER}.run"
DRV_URL="https://download.nvidia.com/XFree86/Linux-x86_64/${DRV_VER}/${DRV_RUN}"

CUDA_VER="13.1"
CUDA_REPO="https://developer.download.nvidia.com/compute/cuda/repos/rhel10/x86_64/cuda-rhel10.repo"

# Must be root
[[ $EUID -eq 0 ]] || { echo "Run this script as root"; exit 1; }

# Must be in multi-user mode
if systemctl get-default | grep -q graphical; then
    echo "Switch to multi-user.target first:"
    echo "  systemctl set-default multi-user.target && reboot"
    exit 1
fi

########################################
# 1. Build deps for .run driver
########################################
echo "==> Installing kernel/build dependencies"
dnf install -y kernel-devel-$(uname -r) elfutils-libelf-devel \
               libglvnd-devel libX11-devel libXtst-devel \
               pkgconf-pkg-config gcc make akmods openssl curl

# blacklist nouveau
if [[ ! -e /etc/modprobe.d/disable-nouveau.conf ]]; then
    echo "blacklist nouveau" > /etc/modprobe.d/disable-nouveau.conf
    dracut --force
fi

########################################
# 2. Download & install driver
########################################
if [[ ! -f $DRV_RUN ]]; then
    echo "==> Downloading NVIDIA driver ${DRV_VER}"
    curl -L -O "$DRV_URL"
fi
chmod +x "$DRV_RUN"

echo "==> Installing NVIDIA driver ${DRV_VER}"
./"$DRV_RUN" --accept-license --disable-nouveau \
             --run-nvidia-xconfig --dkms --no-questions --silent

########################################
# 3. CUDA toolkit
########################################
echo "==> Adding CUDA repo and installing toolkit ${CUDA_VER}"
dnf config-manager --add-repo "$CUDA_REPO"
dnf install -y cuda-toolkit-13-1

# add PATH/LD_LIBRARY_PATH for all users
cat > /etc/profile.d/cuda.sh <<'EOF'
export PATH=/usr/local/cuda-13.1/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-13.1/lib64:$LD_LIBRARY_PATH
EOF
chmod 644 /etc/profile.d/cuda.sh

########################################
# 4. Enable nvidia-drm modeset + back to GUI
###################################
echo "==> Enabling nvidia-drm.modeset=1"
grubby --update-kernel=ALL --args="nvidia-drm.modeset=1"
dracut --force

echo "==> Switching back to graphical boot"
systemctl set-default graphical.target

echo
echo "Installation complete.  Reboot now:  reboot"
echo "After reboot run:  nvidia-smi   &&   nvcc --version"
