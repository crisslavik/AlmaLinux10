#!/bin/bash
# setup-nvidia-cuda-el10-secureboot.sh — AlmaLinux 10 complete NVIDIA + CUDA install with Secure Boot support
set -euo pipefail

DRV_VER="580.119.02"
DRV_RUN="NVIDIA-Linux-x86_64-${DRV_VER}.run"
DRV_URL="https://download.nvidia.com/XFree86/Linux-x86_64/${DRV_VER}/${DRV_RUN}"
CUDA_VER="13.1"
CUDA_REPO="https://developer.download.nvidia.com/compute/cuda/repos/rhel10/x86_64/cuda-rhel10.repo"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Must be root
[[ $EUID -eq 0 ]] || { echo -e "${RED}Run this script as root${NC}"; exit 1; }

# Must be in multi-user mode
if systemctl get-default | grep -q graphical; then
    echo -e "${YELLOW}Switch to multi-user.target first:${NC}"
    echo "  systemctl set-default multi-user.target && reboot"
    exit 1
fi

########################################
# 0. Check Secure Boot status
########################################
echo -e "${GREEN}==> Checking Secure Boot status${NC}"
SECURE_BOOT_ENABLED=false
if command -v mokutil &> /dev/null; then
    if mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
        SECURE_BOOT_ENABLED=true
        echo -e "${YELLOW}Secure Boot is ENABLED - will set up module signing${NC}"
    else
        echo "Secure Boot is DISABLED"
    fi
fi

########################################
# 1. Build deps for .run driver
########################################
echo -e "${GREEN}==> Installing kernel/build dependencies${NC}"
dnf install -y kernel-devel-$(uname -r) elfutils-libelf-devel \
               libglvnd-devel libX11-devel libXtst-devel \
               pkgconf-pkg-config gcc make akmods openssl curl \
               mokutil kernel-headers dkms

# blacklist nouveau
if [[ ! -e /etc/modprobe.d/disable-nouveau.conf ]]; then
    echo "blacklist nouveau" > /etc/modprobe.d/disable-nouveau.conf
    echo "options nouveau modeset=0" >> /etc/modprobe.d/disable-nouveau.conf
    dracut --force
fi

########################################
# 2. Secure Boot Key Setup (if enabled)
########################################
if [[ "$SECURE_BOOT_ENABLED" == "true" ]]; then
    echo -e "${GREEN}==> Setting up Secure Boot signing keys${NC}"
    
    # Check if keys already exist
    if [[ ! -f /var/lib/nvidia-signatures/MOK.der ]]; then
        mkdir -p /var/lib/nvidia-signatures
        cd /var/lib/nvidia-signatures
        
        # Generate new signing key
        openssl req -new -x509 -newkey rsa:2048 -keyout MOK.priv \
                -outform DER -out MOK.der -nodes -days 36500 \
                -subj "/CN=NVIDIA Driver Signing Key for NOX VFX/"
        
        # Set proper permissions
        chmod 600 MOK.priv
        chmod 644 MOK.der
        
        echo -e "${YELLOW}==> Enrolling MOK key (you'll need to complete this on next reboot)${NC}"
        echo -e "${YELLOW}    You will be prompted for a password - REMEMBER IT!${NC}"
        mokutil --import MOK.der
        
        # Create flag file for post-reboot
        touch /var/lib/nvidia-signatures/pending-enrollment
        
        echo -e "${RED}!!! IMPORTANT !!!${NC}"
        echo -e "${YELLOW}After reboot, you'll see a blue MOK Management screen:${NC}"
        echo "1. Select 'Enroll MOK'"
        echo "2. Select 'Continue'"
        echo "3. Select 'Yes'"
        echo "4. Enter the password you just set"
        echo "5. Select 'Reboot'"
        echo ""
        echo -e "${YELLOW}Then run this script again to continue installation${NC}"
        echo ""
        read -p "Press Enter to acknowledge and reboot..." 
        reboot
        exit 0
    else
        echo "MOK key already exists at /var/lib/nvidia-signatures/MOK.der"
        
        # Check if enrollment is pending
        if [[ -f /var/lib/nvidia-signatures/pending-enrollment ]]; then
            if mokutil --list-enrolled 2>/dev/null | grep -q "NVIDIA Driver Signing Key"; then
                echo -e "${GREEN}MOK key successfully enrolled!${NC}"
                rm -f /var/lib/nvidia-signatures/pending-enrollment
            else
                echo -e "${RED}MOK key enrollment pending - please complete enrollment on reboot${NC}"
                exit 1
            fi
        fi
    fi
    
    # Set up DKMS to auto-sign modules
    echo -e "${GREEN}==> Configuring DKMS for automatic module signing${NC}"
    cat > /etc/dkms/framework.conf.d/nvidia-signing.conf <<EOF
mok_signing_key="/var/lib/nvidia-signatures/MOK.priv"
mok_certificate="/var/lib/nvidia-signatures/MOK.der"
sign_tool="/usr/src/kernels/\$(uname -r)/scripts/sign-file"
EOF
fi

########################################
# 3. Download & install driver
########################################
if [[ ! -f $DRV_RUN ]]; then
    echo -e "${GREEN}==> Downloading NVIDIA driver ${DRV_VER}${NC}"
    curl -L -O "$DRV_URL"
fi

chmod +x "$DRV_RUN"
echo -e "${GREEN}==> Installing NVIDIA driver ${DRV_VER}${NC}"

# Install with DKMS for better kernel update support
./"$DRV_RUN" --accept-license --disable-nouveau \
             --run-nvidia-xconfig --dkms --no-questions --silent

########################################
# 4. Sign NVIDIA modules if Secure Boot
########################################
if [[ "$SECURE_BOOT_ENABLED" == "true" ]]; then
    echo -e "${GREEN}==> Signing NVIDIA kernel modules for Secure Boot${NC}"
    
    KERNEL_VERSION=$(uname -r)
    
    # Function to sign a module
    sign_module() {
        local module="$1"
        if [[ -f "$module" ]]; then
            echo "Signing: $module"
            /usr/src/kernels/$KERNEL_VERSION/scripts/sign-file sha256 \
                /var/lib/nvidia-signatures/MOK.priv \
                /var/lib/nvidia-signatures/MOK.der \
                "$module" 2>/dev/null || true
        fi
    }
    
    # Find and sign all NVIDIA modules
    for module in $(find /lib/modules/$KERNEL_VERSION -name "nvidia*.ko*" -type f 2>/dev/null); do
        sign_module "$module"
    done
    
    # Also check updates/dkms directory
    for module in $(find /lib/modules/$KERNEL_VERSION/updates -name "nvidia*.ko*" -type f 2>/dev/null); do
        sign_module "$module"
    done
fi

########################################
# 5. CUDA toolkit
########################################
echo -e "${GREEN}==> Adding CUDA repo and installing toolkit ${CUDA_VER}${NC}"
dnf config-manager --add-repo "$CUDA_REPO"
dnf install -y cuda-toolkit-13-1

# add PATH/LD_LIBRARY_PATH for all users
cat > /etc/profile.d/cuda.sh <<'EOF'
export PATH=/usr/local/cuda-13.1/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-13.1/lib64:$LD_LIBRARY_PATH
EOF
chmod 644 /etc/profile.d/cuda.sh

########################################
# 6. Enable nvidia-drm modeset
########################################
echo -e "${GREEN}==> Enabling nvidia-drm.modeset=1 (required for Wayland)${NC}"

# Add as module option
echo 'options nvidia_drm modeset=1' > /etc/modprobe.d/nvidia-modeset.conf

# Add to kernel command line
grubby --update-kernel=ALL --args="nvidia-drm.modeset=1"

# Add udev rule for NVIDIA device permissions
cat > /etc/udev/rules.d/70-nvidia.rules <<'EOF'
# Create /dev/nvidia* devices
KERNEL=="nvidia", RUN+="/bin/bash -c '/usr/bin/nvidia-smi -L && /bin/chmod 0666 /dev/nvidia*'"
KERNEL=="nvidia_uvm", RUN+="/bin/bash -c '/usr/bin/nvidia-modprobe -c0 -u && /bin/chmod 0666 /dev/nvidia*'"
KERNEL=="nvidia_modeset", RUN+="/bin/chmod 0666 /dev/nvidia-modeset"
EOF

########################################
# 7. Create systemd service for persistence
########################################
echo -e "${GREEN}==> Creating NVIDIA persistence service${NC}"
cat > /etc/systemd/system/nvidia-persistenced.service <<'EOF'
[Unit]
Description=NVIDIA Persistence Daemon
Wants=syslog.target

[Service]
Type=forking
ExecStart=/usr/bin/nvidia-persistenced --user nvidia-persistenced
ExecStopPost=/bin/rm -rf /var/run/nvidia-persistenced
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# Create nvidia-persistenced user if doesn't exist
if ! id nvidia-persistenced &>/dev/null; then
    useradd -r -s /sbin/nologin -d /var/run/nvidia-persistenced nvidia-persistenced
fi

systemctl daemon-reload
systemctl enable nvidia-persistenced

########################################
# 8. Rebuild initramfs & back to GUI
########################################
echo -e "${GREEN}==> Rebuilding initramfs with signed modules${NC}"
dracut --force

echo -e "${GREEN}==> Switching back to graphical boot${NC}"
systemctl set-default graphical.target

########################################
# 9. Final verification commands
########################################
cat > /root/verify-nvidia.sh <<'EOF'
#!/bin/bash
echo "=== NVIDIA Driver Verification ==="
echo ""
echo "1. Secure Boot Status:"
mokutil --sb-state 2>/dev/null || echo "mokutil not available"
echo ""
echo "2. NVIDIA Modules Loaded:"
lsmod | grep nvidia
echo ""
echo "3. NVIDIA SMI:"
nvidia-smi
echo ""
echo "4. CUDA Version:"
nvcc --version 2>/dev/null || echo "CUDA not in PATH yet - relogin or source /etc/profile.d/cuda.sh"
echo ""
echo "5. OpenGL Renderer (if in GUI):"
DISPLAY=:0 glxinfo 2>/dev/null | grep "OpenGL renderer" || echo "Run from GUI session"
echo ""
echo "6. DRM Modeset Status:"
cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null || echo "Module not loaded"
echo ""
EOF
chmod +x /root/verify-nvidia.sh

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}     Installation complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${YELLOW}Required actions:${NC}"
echo "1. Reboot system: ${GREEN}reboot${NC}"
echo "2. After reboot, verify installation: ${GREEN}/root/verify-nvidia.sh${NC}"
echo ""
if [[ "$SECURE_BOOT_ENABLED" == "true" ]]; then
    echo -e "${GREEN}Secure Boot module signing is configured!${NC}"
    echo "Your NVIDIA modules will be automatically signed for future kernel updates."
fi
echo ""
echo "Expected after reboot:"
echo "  - nvidia-smi should show your GPU"
echo "  - GNOME Settings > About > Graphics should show 'NVIDIA GeForce RTX 4090'"
echo "  - Wayland session should work with hardware acceleration"
echo ""
