#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "Starting Docker Compose Plugin and Rootless installation..."

# Check if script is run by root or with sudo
if [ "$EUID" -ne 0 ]; then
  echo "This script requires root privileges for initial setup. Please run with sudo."
  exit 1
fi

# Add Docker's official GPG key:
echo "Adding Docker's official GPG key..."
apt update > /dev/null 2>&1 # Hide apt update output
apt install -y ca-certificates curl > /dev/null 2>&1 # Hide apt install output
install -m 0755 -d /etc/apt/keyrings > /dev/null 2>&1
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc > /dev/null 2>&1
chmod a+r /etc/apt/keyrings/docker.asc > /dev/null 2>&1

# Add the repository to Apt sources:
echo "Adding the Docker repository to Apt sources..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update > /dev/null 2>&1 # Hide apt update output

# Install Docker Engine, CLI, Containerd, Buildx, and Compose Plugin:
echo "Installing Docker Engine, CLI, Containerd, Buildx, and Compose Plugin (system-wide components)..."
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1

# Install dependencies for Rootless Docker
echo "Installing dependencies for Rootless Docker..."
apt install -y uidmap dbus-user-session slirp4netns > /dev/null 2>&1

# Disable and stop the system-wide Docker daemon
echo "Disabling and stopping the system-wide Docker daemon..."
systemctl disable --now docker.service docker.socket > /dev/null 2>&1
# Remove the system-wide Docker socket if it exists
if [ -S "/var/run/docker.sock" ]; then
    rm /var/run/docker.sock > /dev/null 2>&1
fi

echo "Switching to current user for rootless Docker setup..."

# Get the current non-root user
CURRENT_USER=$(logname || id -un)
if [ "$CURRENT_USER" = "root" ]; then
    echo "ERROR: The script is still running as root. The rootless Docker setup must be run as a non-root user."
    echo "Please consider running the script without 'sudo' for the rootless part, or using 'su - <username> -c \"...\"'."
    exit 1
fi

echo "Running rootless Docker installation for user: $CURRENT_USER"

# Install Rootless Docker for the current user
curl -fsSL https://get.docker.com/rootless | sh > /dev/null 2>&1

# Start and enable Rootless Docker for the current user
echo "Starting and enabling Rootless Docker for the current user..."
systemctl --user start docker > /dev/null 2>&1
systemctl --user enable docker > /dev/null 2>&1

# Enable linger for the current user to run Rootless Docker without an active session
echo "Enabling linger for the current user ($CURRENT_USER)..."
sudo loginctl enable-linger "$CURRENT_USER" > /dev/null 2>&1

echo "Docker Compose Plugin and Rootless installation completed successfully!"
echo "Please log out and log back in, or run 'source ~/.bashrc' (or your shell's equivalent) to ensure all environment variables are loaded."
echo "You should now be able to run 'docker' commands without 'sudo'."
