#!/usr/bin/env bash
# Jetson Orin Nano | JetPack 6.0 (L4T 36.3)
# Installs DeepStream 7.0, Flatpak, Chromium (Flatpak), RustDesk (Flatpak), then verifies.
# Run as a normal user (not with sudo), from any folder:
#   wget -qO- <short-link> | bash
set -e
cd "$HOME"

DS_DEB="$HOME/deepstream-7.0_7.0.0-1_arm64.deb"
DS_URL="https://api.ngc.nvidia.com/v2/resources/org/nvidia/deepstream/7.0/files?redirect=true&path=deepstream-7.0_7.0.0-1_arm64.deb"

[ -f /etc/nv_tegra_release ] || { echo "This script is for Jetson devices only."; exit 1; }
sudo -v

echo "== Dependencies + Flatpak =="
sudo apt-get update
sudo apt-get install -y libssl3 libssl-dev libgstreamer1.0-0 gstreamer1.0-tools \
  gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly \
  gstreamer1.0-libav libgstreamer-plugins-base1.0-dev libgstrtspserver-1.0-0 \
  libjansson4 libyaml-cpp-dev flatpak

echo "== DeepStream 7.0 =="
if dpkg -s deepstream-7.0 >/dev/null 2>&1; then
  echo "DeepStream 7.0 already installed, skipping."
else
  if [ ! -f "$DS_DEB" ]; then
    wget -q --show-progress -O "$DS_DEB.part" "$DS_URL" && mv "$DS_DEB.part" "$DS_DEB" || rm -f "$DS_DEB.part"
  fi
  if [ -f "$DS_DEB" ] && dpkg-deb -I "$DS_DEB" >/dev/null 2>&1; then
    sudo apt-get install -y "$DS_DEB"
  else
    rm -f "$DS_DEB"
    echo "!! Could not download DeepStream automatically."
    echo "   Download deepstream-7.0_7.0.0-1_arm64.deb from:"
    echo "   https://catalog.ngc.nvidia.com/orgs/nvidia/resources/deepstream/files?version=7.0"
    echo "   save it in your home folder (~) and run this command again."
  fi
fi

echo "== Chromium + RustDesk (Flatpak) =="
sudo apt install -y flatpak
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
# Using --noninteractive to prevent the script from hanging for user input
sudo flatpak install -y flathub org.chromium.Chromium
RD_VERSION=$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
RD_URL="https://github.com/rustdesk/rustdesk/releases/download/${RD_VERSION}/rustdesk-${RD_VERSION}-aarch64.deb"

wget "$RD_URL" -O rustdesk_arm64.deb
sudo apt install -y ./rustdesk_arm64.deb
rm rustdesk_arm64.deb

echo "== Verify =="
deepstream-app --version-all || true
dpkg -s deepstream-7.0 || true
flatpak list --app | grep -E "Chromium|RustDesk" || true
