#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# Check if the script is running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Please use 'su -' to switch to the root user and then run the script."
   exit 1
fi

echo "==================================================="
echo "Starting Pelican Panel and Wings Installation Script"
echo "==================================================="
echo ""

echo "==============================================="
echo "Segment: Install PHP 8.4, Extensions and Dependencies"
echo "==============================================="
echo "Updating apt package list..."
apt update

echo "Installing core dependencies (curl, tar, unzip, nginx)..."
apt install -y curl tar unzip nginx

echo "Installing prerequisites for Sury PHP repository..."
apt install -y lsb-release ca-certificates curl apt-transport-https

echo "Adding Sury PHP repository key..."
# Download and install the GPG key for Sury's PHP repository
curl -sSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb
dpkg -i /tmp/debsuryorg-archive-keyring.deb

echo "Adding Sury PHP repository to apt sources list..."
# Add the repository to your system's sources list.
# `lsb_release -sc` gets the codename (e.g., 'bookworm' for Debian 12).
sh -c 'echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'

echo "Updating apt package list again after adding new repository..."
apt update

echo "Installing PHP 8.4 and necessary extensions..."
apt install -y php8.4 php8.4-gd php8.4-mysql php8.4-mbstring php8.4-bcmath php8.4-xml php8.4-curl php8.4-zip php8.4-intl php8.4-sqlite3 php8.4-fpm

echo ""
echo "==============================================="
echo "Segment: Create directories and download Pelican Panel"
echo "==============================================="
echo "Creating installation directory /var/www/pelican..."
mkdir -p /var/www/pelican

echo "Changing directory to /var/www/pelican..."
cd /var/www/pelican

echo "Downloading and extracting the latest Pelican Panel release..."
curl -L https://github.com/pelican-dev/panel/releases/latest/download/panel.tar.gz | tar -xzv

echo ""
echo "==============================================="
echo "Segment: Install Composer"
echo "==============================================="
echo "Downloading Composer installer..."
# Download Composer and place it in /usr/local/bin for global access
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

echo "Running Composer install to fetch Pelican Panel dependencies..."
# COMPOSER_ALLOW_SUPERUSER=1 is required because we are running as root.
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

echo ""
echo "==============================================="
echo "Segment: Webserver configuration (Nginx)"
echo "==============================================="
echo "Removing default Nginx site configuration..."
rm -f /etc/nginx/sites-enabled/default

echo "Creating Pelican Nginx configuration file at /etc/nginx/sites-available/pelican.conf with updated content..."
echo "IMPORTANT: After the script finishes, you MUST edit this file to replace '<domain>' with your actual domain or server's IP address."
cat << 'EOF' > /etc/nginx/sites-available/pelican.conf
server {
    listen 80;
    server_name <domain>; # IMPORTANT: Change this to your actual domain or IP address!


    root /var/www/pelican/public;
    index index.html index.htm index.php;
    charset utf-8;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log off;
    error_log  /var/log/nginx/pelican.app-error.log error;

    # allow larger file uploads and longer script runtimes
    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.4-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

echo "Enabling Pelican Nginx configuration by creating a symlink..."
ln -s /etc/nginx/sites-available/pelican.conf /etc/nginx/sites-enabled/pelican.conf

echo "Restarting Nginx service to apply changes..."
systemctl restart nginx
echo "Enabling Nginx to start on boot..."
systemctl enable nginx

echo ""
echo "==============================================="
echo "Segment: Panel Setup (Pelican Panel)"
echo "==============================================="
echo "Running Pelican Panel environment setup. This will be an interactive process."
echo "You will be prompted to enter database connection details, application URL, timezone, and administrator user details."
php artisan p:environment:setup

echo ""
echo "==============================================="
echo "Segment: Setting permissions"
echo "==============================================="
echo "Setting appropriate file and directory permissions for Pelican Panel..."
# Set permissions for storage and cache directories for web server write access
chmod -R 755 /var/www/pelican/storage/ /var/www/pelican/bootstrap/cache/
# Change ownership to the web server user (www-data)
chown -R www-data:www-data /var/www/pelican

echo ""
echo "==============================================="
echo "Segment: Post-Install panel configuration"
echo "==============================================="
echo "The next step requires you to access the web installer in your browser."
echo "Please navigate to: http://10.10.0.90/installer (Replace 10.10.0.90 with your server's actual IP address or domain)."
echo "Follow the on-screen instructions to complete the final panel configuration."

echo ""
echo "==============================================="
echo "Segment: Install Docker"
echo "==============================================="
echo "Installing Docker Engine (stable channel). This may take a few moments..."
curl -sSL https://get.docker.com/ | CHANNEL=stable sh

echo "Enabling Docker to start on boot and starting the Docker service..."
systemctl enable docker
systemctl start docker

echo ""
echo "==============================================="
echo "Segment: Install Wings"
echo "==============================================="
echo "Creating directories for Wings configuration and runtime files..."
mkdir -p /etc/pelican /var/run/wings

echo "Downloading Wings executable..."
# Determine the system architecture to download the correct Wings binary
ARCH=$(uname -m)
WINGS_ARCH=""
if [ "$ARCH" == "x86_64" ]; then
    WINGS_ARCH="amd64"
elif [ "$ARCH" == "aarch64" ]; then
    WINGS_ARCH="arm64"
else
    echo "ERROR: Unsupported architecture '$ARCH'. Cannot download Wings automatically."
    echo "Please download Wings manually from https://github.com/pelican-dev/wings/releases and place it in /usr/local/bin."
    exit 1
fi
curl -L -o /usr/local/bin/wings "https://github.com/pelican-dev/wings/releases/latest/download/wings_linux_$WINGS_ARCH"

echo "Making Wings executable..."
chmod u+x /usr/local/bin/wings

echo ""
echo "==============================================="
echo "Segment: Daemonizing Wings (Systemd Service)"
echo "==============================================="
echo "Creating Wings systemd service file at /etc/systemd/system/wings.service with updated content..."
echo "NOTE: The Pelican Panel's p:environment:setup command usually generates the /etc/pelican/config.yml file which Wings requires."
cat << 'EOF' > /etc/systemd/system/wings.service
[Unit]
Description=Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pelican
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

echo "Reloading systemd daemon to recognize the new service file..."
systemctl daemon-reload

echo "Enabling and starting the Wings service..."
systemctl enable --now wings

echo ""
echo "==================================================="
echo "Pelican Panel and Wings Installation Script Completed!"
echo "==================================================="
echo "IMPORTANT NEXT STEPS:"
echo "1.  **Edit Nginx Config:** Modify `/etc/nginx/sites-available/pelican.conf` and replace `<domain>` with your actual domain name or server's IP address. Then run `systemctl restart nginx`."
echo "2.  **Complete Web Installation:** Open your web browser and navigate to `http://YOUR_SERVER_IP/installer` (replace `YOUR_SERVER_IP` with your server's actual IP address or domain) to finalize the Pelican Panel setup."
echo "3.  **Firewall Configuration:** Ensure your server's firewall (e.g., UFW) allows incoming connections on ports 80 (HTTP), 443 (HTTPS - if you configure SSL), and typically 8080 (Wings daemon API - check Pelican documentation for exact port)."
echo "4.  **Link Wings to Panel:** After the web installation is complete, go to your Pelican Panel, create a new node (server location), and follow the instructions to link it to your Wings daemon. This usually involves generating a token in the panel and running `wings configure` in your server's terminal, pasting the token when prompted."
