
#!/usr/bin/env bash
# Jetson Orin Nano | JetPack 6.0 (L4T 36.3)
# Installs:
#   - DeepStream 7.0
#   - Flatpak
#   - Chromium (Flatpak)
#   - RustDesk (ARM64 Debian package)
#
# Run as a normal user (not with sudo), from any folder:
#   wget -qO- <short-link> | bash

set -Eeuo pipefail

cd "$HOME"

DS_DEB="$HOME/deepstream-7.0_7.0.0-1_arm64.deb"
DS_URL="https://api.ngc.nvidia.com/v2/resources/org/nvidia/deepstream/7.0/files?redirect=true&path=deepstream-7.0_7.0.0-1_arm64.deb"

# Confirm this is a Jetson device
if [[ ! -f /etc/nv_tegra_release ]]; then
    echo "ERROR: This script is for NVIDIA Jetson devices only."
    exit 1
fi

# Request sudo credentials at the beginning
sudo -v

echo "== Update package lists =="
sudo apt-get update

echo "== Install dependencies + Flatpak =="
sudo apt-get install -y \
    curl \
    jq \
    ca-certificates \
    wget \
    libssl3 \
    libssl-dev \
    libgstreamer1.0-0 \
    gstreamer1.0-tools \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    libgstreamer-plugins-base1.0-dev \
    libgstrtspserver-1.0-0 \
    libjansson4 \
    libyaml-cpp-dev \
    flatpak

echo "== DeepStream 7.0 =="

if dpkg-query -W -f='${Status}' deepstream-7.0 2>/dev/null \
    | grep -q "install ok installed"; then

    echo "DeepStream 7.0 is already installed. Skipping."

else
    if [[ ! -f "$DS_DEB" ]] ||
       ! dpkg-deb --info "$DS_DEB" >/dev/null 2>&1; then

        rm -f "$DS_DEB" "$DS_DEB.part"

        echo "Downloading DeepStream 7.0 package..."

        if wget -q --show-progress \
            -O "$DS_DEB.part" "$DS_URL" &&
            dpkg-deb --info "$DS_DEB.part" >/dev/null 2>&1; then

            mv "$DS_DEB.part" "$DS_DEB"

        else
            rm -f "$DS_DEB.part"

            echo "WARNING: Automatic DeepStream download failed."
            echo "Download the package manually from:"
            echo "https://catalog.ngc.nvidia.com/orgs/nvidia/resources/deepstream/files?version=7.0"
            echo "Save it as:"
            echo "$DS_DEB"
            echo "Then run this script again."
        fi
    fi

    if [[ -f "$DS_DEB" ]] &&
       dpkg-deb --info "$DS_DEB" >/dev/null 2>&1; then

        echo "Installing DeepStream 7.0..."
        sudo apt-get install -y "$DS_DEB"
    fi
fi

echo "== Chromium (Flatpak) =="

# Configure Flathub for system-wide Flatpak applications
if ! sudo flatpak remotes --system --columns=name \
    | grep -qx "flathub"; then

    sudo flatpak remote-add --system \
        flathub https://flathub.org/repo/flathub.flatpakrepo
fi

if sudo flatpak info --system org.chromium.Chromium \
    >/dev/null 2>&1; then

    echo "Chromium is already installed. Skipping."

else
    sudo flatpak install --system -y \
        flathub org.chromium.Chromium
fi

echo "== RustDesk (ARM64 Debian package) =="

RD_API="https://api.github.com/repos/rustdesk/rustdesk/releases/latest"

# Retrieve the latest stable release version, with retries.
RD_VERSION=""

for attempt in 1 2 3; do
    echo "Checking RustDesk release (attempt $attempt/3)..."

    if RD_VERSION=$(curl -fsSL \
        --connect-timeout 15 \
        --max-time 60 \
        "$RD_API" | jq -er '.tag_name | select(type == "string" and length > 0)'); then
        break
    fi

    RD_VERSION=""
    sleep 2
done

if [[ -z "$RD_VERSION" ]]; then
    echo "ERROR: Could not retrieve the RustDesk release version."
    echo "Check internet connectivity or GitHub API availability."
    exit 1
fi

RD_FILE="rustdesk-${RD_VERSION}-aarch64.deb"
RD_DEB="$HOME/$RD_FILE"
RD_URL="https://github.com/rustdesk/rustdesk/releases/download/${RD_VERSION}/${RD_FILE}"

# Skip downloading if RustDesk is already installed.
if dpkg-query -W -f='${Status}' rustdesk 2>/dev/null \
    | grep -q "install ok installed"; then

    echo "RustDesk is already installed. Skipping download."

else
    rm -f "$RD_DEB.part"

    echo "Downloading RustDesk $RD_VERSION..."

    if ! curl -fL \
        --retry 3 \
        --retry-all-errors \
        --connect-timeout 15 \
        --max-time 300 \
        -o "$RD_DEB.part" "$RD_URL"; then

        rm -f "$RD_DEB.part"
        echo "ERROR: RustDesk download failed."
        exit 1
    fi

    # Confirm the downloaded file is a valid Debian package.
    if ! dpkg-deb --info "$RD_DEB.part" >/dev/null 2>&1; then
        rm -f "$RD_DEB.part"
        echo "ERROR: The downloaded RustDesk file is not a valid Debian package."
        exit 1
    fi

    mv "$RD_DEB.part" "$RD_DEB"

    echo "Installing RustDesk..."

    if ! sudo apt-get install -y "$RD_DEB"; then
        echo "ERROR: RustDesk installation failed."
        echo "The package has been retained at $RD_DEB for inspection."
        exit 1
    fi

    rm -f "$RD_DEB"
fi

echo "== Verify installations =="

echo "-- DeepStream --"
if command -v deepstream-app >/dev/null 2>&1; then
    deepstream-app --version-all || true
else
    echo "DeepStream application command not found."
fi

dpkg-query -W -f='${Status}\n' deepstream-7.0 2>/dev/null || true

echo "-- Chromium --"
if sudo flatpak info --system org.chromium.Chromium \
    >/dev/null 2>&1; then
    echo "Chromium Flatpak is installed."
else
    echo "Chromium Flatpak installation could not be verified."
fi

echo "-- RustDesk --"
if dpkg-query -W -f='${Status}\n' rustdesk 2>/dev/null \
    | grep -q "install ok installed"; then

    echo "RustDesk is installed."
    rustdesk --version || true
else
    echo "RustDesk installation could not be verified."
fi

echo
echo "Installation script completed."
