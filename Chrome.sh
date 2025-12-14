#!/bin/bash

# Google Chrome Installer for AlmaLinux 10
# Based on: https://linuxiac.com/how-to-install-google-chrome-on-almalinux-10/
# This script automates the installation of Google Chrome on AlmaLinux 10

set -e  # Exit on error

echo "========================================="
echo "Google Chrome Installer for AlmaLinux 10"
echo "========================================="

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root or with sudo"
   exit 1
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if curl is available
if ! command_exists curl; then
    echo "Installing curl..."
    dnf install -y curl
fi

echo ""
echo "Step 1: Download and Import Google's GPG Key"
echo "----------------------------------------"
# Download Google's GPG key
curl -O https://dl.google.com/linux/linux_signing_key.pub

# Import the key (with warnings expected due to SHA-1 signatures)
rpm --import --nodigest --nosignature linux_signing_key.pub
echo "✓ GPG key imported successfully"

echo ""
echo "Step 2: Add Google's Chrome Repository"
echo "----------------------------------------"
# Create the repository file
tee /etc/yum.repos.d/google-chrome.repo <<'EOF'
[google-chrome]
name=Google Chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/$basearch
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF
echo "✓ Chrome repository added"

echo ""
echo "Step 3: Refresh Package List"
echo "----------------------------------------"
dnf update -y
echo "✓ Package list updated"

echo ""
echo "Step 4: Install Google Chrome"
echo "----------------------------------------"
dnf install -y google-chrome-stable
echo "✓ Google Chrome installed successfully"

echo ""
echo "Step 5: Fix Missing Chrome Icon (Optional)"
echo "----------------------------------------"
# Download Chrome icon
curl -L https://www.google.com/chrome/static/images/chrome-logo.svg -o /usr/share/icons/hicolor/scalable/apps/google-chrome.svg

# Update icon cache if gtk-update-icon-cache is available
if command_exists gtk-update-icon-cache; then
    gtk-update-icon-cache /usr/share/icons/hicolor
    echo "✓ Icon cache updated"
fi

# Clean up downloaded files
rm -f linux_signing_key.pub

echo ""
echo "========================================="
echo "Installation Complete!"
echo "========================================="
echo ""
echo "Google Chrome has been successfully installed on your AlmaLinux 10 system."
echo ""
echo "To run Google Chrome:"
echo "  - Click on the Chrome icon in your applications menu"
echo "  - Or run: google-chrome-stable"
echo ""
echo "Note: If the icon doesn't appear immediately, try logging out and logging back in."
echo ""
echo "To uninstall Chrome later, run:"
echo "  sudo dnf remove google-chrome-stable"
echo ""
