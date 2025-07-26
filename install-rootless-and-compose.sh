#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "Starting Docker Compose Plugin and Rootless installation..."
echo "Checking sudo privileges..."

sudo -v

sudo apt update
sudo apt install -y ca-certificates curl

# Add Docker's official GPG key:
echo "Adding Docker's official GPG key..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo "Adding the Docker repository to Apt sources..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update

# Install Docker Engine, CLI, Containerd, Buildx, and Compose Plugin:
echo "Installing Docker Engine, CLI, Containerd, Buildx, and Compose Plugin (system-wide components)..."
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Install dependencies for Rootless Docker
echo "Installing dependencies for Rootless Docker..."
sudo apt install -y uidmap dbus-user-session slirp4netns docker docker-compose

# Disable and stop the system-wide Docker daemon
echo "Disabling and stopping the system-wide Docker daemon..."
sudo systemctl disable --now docker.service docker.socket
sudo rm /var/run/docker.sock

echo "Running rootless Docker installation for user: $(whoami)"

# Install Rootless Docker for the current user
curl -fsSL https://get.docker.com/rootless | sh

# Start and enable Rootless Docker for the current user
echo "Starting and enabling Rootless Docker for the current user..."
systemctl --user start docker && systemctl --user enable docker

# Enable linger for the current user to run Rootless Docker without an active session
echo "Enabling linger for the current user $(whoami)..."
sudo loginctl enable-linger $(whoami)

docker compose version
docker -v

echo "Docker Compose Plugin and Rootless installation completed successfully!"
