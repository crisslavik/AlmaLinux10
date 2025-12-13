# NVIDIA + CUDA Installer for AlmaLinux 10

This repository contains a script to install NVIDIA drivers and CUDA on AlmaLinux 10.

> Tested with: AlmaLinux 10 (user-provided script). Always review the script before running it, and consider testing in a VM first.

---

## Important — Secure Boot warning

WARNING: This installation mode does NOT support Secure Boot. If Secure Boot is enabled in your firmware (UEFI), the NVIDIA kernel module will be blocked and the installation may fail or the driver will not load. Disable Secure Boot in your system firmware before running this installer.

---

## Overview

This script automates common tasks required to install the NVIDIA proprietary driver and CUDA toolkit on AlmaLinux 10, including:
- Disabling the open-source `nouveau` driver (if applicable)
- Installing required kernel headers/development packages
- Downloading and installing the NVIDIA driver and CUDA toolkit (depending on script behavior)
- Rebuilding the kernel module as needed

Because kernel and driver interactions are sensitive, please read the prerequisites and troubleshooting sections before running the installer.

---

## Prerequisites

- AlmaLinux 10 up-to-date:
  - `sudo dnf update`
  - Reboot if the kernel was updated: `sudo reboot`
- A supported NVIDIA GPU (check NVIDIA's driver page for compatibility)
- Sufficient free disk space for driver + CUDA packages
- Network access to download packages

Important: Secure Boot must be disabled in firmware for this installer to work. See the warning above.

Recommended checks:
- Kernel version: `uname -r`
- Installed kernel-devel to match running kernel: `sudo dnf install kernel-devel-$(uname -r)`

---

## Usage

Make the script executable and run it with root privileges:

chmod +x setup-nvidia-cuda-el10.sh
sudo ./setup-nvidia-cuda-el10.sh
sudo reboot

Post-reboot verification:
- Check GPU and driver:
  - `nvidia-smi`
  - Example expected output (truncated):  
    NVIDIA-SMI 535.86.05 Driver Version: 535.86.05 CUDA Version: 12.2  
    +-----------------------------------------------------------------------------+
- Check nvcc (CUDA compiler) if CUDA toolkit installed:
  - `nvcc --version`
  - Example expected output:  
    nvcc: NVIDIA (R) Cuda compiler driver  
    Copyright (c) 2005-2025 NVIDIA Corporation  
    Built on ...  
    Cuda compilation tools, release 12.2, V12.2.91

Note: The exact driver and CUDA versions depend on the script and the time it was run.

---

## What the script does (high-level)

- Checks for and installs required packages (kernel-devel, kernel-headers, etc.)
- Blacklists `nouveau` (if necessary) and regenerates initramfs
- Downloads and installs NVIDIA driver (or configures repository and installs via dnf)
- Installs CUDA toolkit if the script includes that step
- Rebuilds kernel modules and ensures the NVIDIA kernel module is loaded

Always inspect the script before running to confirm specific behavior and any optional flags it may support.

---

## Troubleshooting

Common issues and checks:

1. nvidia-smi not found or "No devices were found"
   - Ensure kernel module is loaded: `lsmod | grep nvidia`
   - Inspect kernel messages: `dmesg | grep -i nvidia`
   - Verify driver installation: `rpm -qa | grep -i nvidia`
   - Ensure the NVIDIA card is present: `lspci | grep -i nvidia`

2. Module build failed
   - Check that `kernel-devel` matches `uname -r`:  
     `rpm -q kernel-devel` and `uname -r`
   - Install compiler and make: `sudo dnf install -y gcc make`
   - Re-run the installer or rebuild module manually.

3. X server / Wayland issues
   - If using a display server, verify `/etc/X11/xorg.conf.d/` or generated xorg.conf
   - Check logs: `/var/log/Xorg.0.log` or `journalctl -b _COMM=Xorg`

4. CUDA not found (`nvcc` missing) after install
   - Ensure CUDA's bin path is in PATH: e.g. add `export PATH=/usr/local/cuda/bin:$PATH` to `~/.bashrc`
   - Verify library path: `export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH`

If you share any error messages (exact output), I can help diagnose further.

---

## Uninstall / Rollback

If you need to remove the NVIDIA driver and CUDA:

- If installed via dnf:
  - `sudo dnf remove 'xorg-x11-drv-nvidia*' cuda\*`
- If installed via NVIDIA runfile:
  - Re-run the runfile with `--uninstall` (if available), or consult the runfile's README for proper uninstall steps.
- Restore any backed-up configuration files created by the installer (the script may create backups — inspect the script to find any backup locations).

Always reboot after uninstalling.

---

## Security & Safety Notes

- Secure Boot is not supported by this installation mode — disable Secure Boot in firmware before running the script.
- Review the script before running. Installing kernel drivers and disabling `nouveau` can make the system unbootable in some edge cases.
- Consider testing first in a virtual machine or on a non-critical system.
- Keep backups of important configuration files.

---

## Contributing / Issues

If you find problems with the script or this README, please open an issue in the repository with:
- AlmaLinux version & kernel (`uname -a`)
- GPU model (`lspci | grep -i nvidia`)
- Exact error messages or logs

---

## References

- NVIDIA Linux driver download: https://www.nvidia.com/Download/index.aspx
- CUDA toolkit docs: https://developer.nvidia.com/cuda-toolkit
- AlmaLinux docs: https://wiki.almalinux.org

---

License: Use at your own risk. No warranty provided.
