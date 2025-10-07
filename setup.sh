#!/bin/bash

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root" 
   exit 1
fi

# Store results
declare -a FAILED_STEPS
declare -a SUCCESS_STEPS

timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

run_step() {
    local step="$1"
    local cmd="$2"

    echo "[$(timestamp)] Starting: $step ..."
    if eval "$cmd"; then
        echo "[$(timestamp)] ✅ Success: $step"
        SUCCESS_STEPS+=("$step")
    else
        echo "[$(timestamp)] ❌ Failed: $step"
        FAILED_STEPS+=("$step")
    fi
    echo
}


##########################################
### --- Installation & Basic Setup --- ###
##########################################
run_step "Update package repositories..." "apt update && apt upgrade -y"
run_step "Install Apache web server with PHP, MySQL, and CGI support..." "DEBIAN_FRONTEND=noninteractive apt install apache2 php libapache2-mod-php mariadb-server php-mysql -y"
run_step "Configure Apache and MySQL to start automatically..." "systemctl enable --now apache2 && systemctl enable --now mariadb"
run_step "Allow HTTP and HTTPS traffic through the firewall..." "apt install ufw -y && ufw --force enable && ufw allow 'Apache Full'"
run_step "Create dedicated webmaster user for web content management..." "adduser --gecos '' --disabled-password webmaster && echo 'webmaster:root' | chpasswd && usermod -aG www-data webmaster"
run_step "Configure proper ownership for web directories..." "chown -R webmaster:www-data /var/www/html && chmod -R 755 /var/www/html"

#############################################
### --- Configure Secure Access Areas --- ###
#############################################
run_step "Create /privat directory for webmaster access..." "mkdir -p /var/www/html/privat"
run_step "Configure ownership for protected area..." "chown -R webmaster:www-data /var/www/html/privat"
run_step "Add content to protected directory..." "echo '<h1>Private Area</h1><p>This is a protected area.</p>' | tee /var/www/html/privat/index.html"
run_step "Set up access control for /privat directory with directory-based authentication..." "printf '<Directory /var/www/html/privat>\n    AuthType Basic\n    AuthName \"Restricted Area\"\n    AuthUserFile /etc/apache2/.htpasswd\n    Require user webmaster\n    Require ip 192.168.1.0/24\n</Directory>' | tee /etc/apache2/conf-available/privat.conf && a2enconf privat && systemctl reload apache2"
run_step "Create password file for webmaster authentication..." "htpasswd -cb /etc/apache2/.htpasswd webmaster root"

########################################################
### --- Configure User Homepages and CGI Support --- ###
########################################################
run_step "Enable Apache module for user directories..." "a2enmod userdir || true && systemctl restart apache2"
run_step "Create linux1 and linux2 users for CGI testing..." "adduser --gecos '' --disabled-password linux1 && echo 'linux1:root' | chpasswd && adduser --gecos '' --disabled-password linux2 && echo 'linux2:root' | chpasswd"
run_step "Set up public_html directories for users..." "mkdir -p /home/linux1/public_html/cgi-bin /home/linux2/public_html/cgi-bin && chown -R linux1:linux1 /home/linux1/public_html && chown -R linux2:linux2 /home/linux2/public_html && chmod 755 /home/*/public_html"
run_step "Enable CGI execution in user directories..." "echo 'AddHandler cgi-script .cgi .pl' | tee /etc/apache2/mods-available/userdir.conf && a2enmod userdir && systemctl restart apache2"
run_step "Enable Apache CGI module..." "a2enmod cgi || true && systemctl restart apache2"
run_step "Create example CGI script for testing..." "printf '#!/usr/bin/env python3\nprint(\"Content-Type: text/html\")\nprint()\nprint(\"<html><body><h1>Hello from Python CGI script!</h1></body></html>\")' > /home/linux1/public_html/cgi-bin/hello.py && chown linux1:linux1 /home/linux1/public_html/cgi-bin/hello.py"
run_step "Make CGI scripts executable..." "chmod +x /home/linux1/public_html/cgi-bin/hello.py"

#####################################################
### --- Set up Department-based Virtual Hosts --- ###
#####################################################
run_step "Create separate directories for each department..." "mkdir -p /var/www/{einkauf,verkauf,marketing}"
run_step "Configure ownership for department webmasters..." "chown -R webmaster:www-data /var/www/{einkauf,verkauf,marketing}"
run_step "Create greeting pages for each department..." "echo '<h1>Willkommen auf dem Server der Abteilung Einkauf</h1>' | tee /var/www/einkauf/index.html && echo '<h1>Willkommen auf dem Server der Abteilung Verkauf</h1>' | tee /var/www/verkauf/index.html && echo '<h1>Willkommen auf dem Server der Abteilung Marketing</h1>' | tee /var/www/marketing/index.html"
run_step "Create virtual host for purchasing department..." "printf '<VirtualHost *:80>\n    ServerName einkauf.firma.de\n    DocumentRoot /var/www/einkauf\n    <Directory /var/www/einkauf>\n        Options Indexes FollowSymLinks\n        AllowOverride All\n        Require all granted\n    </Directory>\n</VirtualHost>' | tee /etc/apache2/sites-available/einkauf.conf"
run_step "Create virtual host for sales department..." "printf '<VirtualHost *:80>\n    ServerName verkauf.firma.de\n    DocumentRoot /var/www/verkauf\n    <Directory /var/www/verkauf>\n        Options Indexes FollowSymLinks\n        AllowOverride All\n        Require all granted\n    </Directory>\n</VirtualHost>' | tee /etc/apache2/sites-available/verkauf.conf"
run_step "Create virtual host for marketing department..." "printf '<VirtualHost *:80>\n    ServerName marketing.firma.de\n    DocumentRoot /var/www/marketing\n    <Directory /var/www/marketing>\n        Options Indexes FollowSymLinks\n        AllowOverride All\n        Require all granted\n    </Directory>\n</VirtualHost>' | tee /etc/apache2/sites-available/marketing.conf"
run_step "Activate all department virtual hosts..." "a2ensite einkauf verkauf marketing || true && systemctl reload apache2"
run_step "Set up local DNS resolution for testing..." "echo '127.0.0.1 einkauf.firma.de verkauf.firma.de marketing.firma.de' | tee -a /etc/hosts"

#####################################################
### --- Configure Reverse Proxy Functionality --- ###
#####################################################
run_step "Enable Apache proxy modules..." "a2enmod proxy proxy_http proxy_balancer lbmethod_byrequests && systemctl restart apache2"
run_step "Set up proxy for router admin interface..." "echo 'ProxyPass /router http://192.168.1.1:80' | tee -a /etc/apache2/sites-available/000-default.conf && systemctl restart apache2"

################################################
### --- Configure PHP with MySQL Support --- ###
################################################
# run_step "Run MySQL security configuration..." "mysql -u root --connect-expired-password -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY 'root';\" && mysql_secure_installation --use-default"
# run_step "Restrict MySQL to local connections..." "echo 'bind-address = 127.0.0.1' | tee -a /etc/mysql/mysql.conf.d/mysqld.cnf && systemctl restart mysql"
# run_step "Set up database and limited user for PHP..."
# run_step "Set up secure credential storage..."
# run_step "Prevent PHP access to all webpages..."
# run_step "Create test.php example script..."
# run_step "Create test application with database operations..."

####################################################
### --- Secure Website with HTTPS Encryption --- ###
####################################################
run_step "Enable the Apache SSL module..." "a2enmod ssl && systemctl restart apache2"
run_step "Install Let's Encrypt certificate tool..." "apt install certbot python3-certbot-apache -y"
run_step "Get a free SSL certificate from Let's Encrypt..." "certbot --apache -d einkauf.firma.de -d verkauf.firma.de -d marketing.firma.de"
run_step "Configure automatic SSL certificate renewal..." "echo '0 0 * * * root certbot renew --quiet' | tee -a /etc/crontab"

############################################################
### --- Implement Security Best Practices for Apache --- ###
############################################################
run_step "Configure Apache to hide version information..." "echo 'ServerTokens Prod' | tee -a /etc/apache2/conf-available/security.conf && echo 'ServerSignature Off' | tee -a /etc/apache2/conf-available/security.conf && systemctl restart apache2"
run_step "Enable the headers module for security headers..." "a2enmod headers && systemctl restart apache2"
run_step "Add security headers to your virtual Host..." "echo 'Header always set X-Frame-Options \"DENY\"' | tee -a /etc/apache2/conf-available/security.conf && echo 'Header always set X-XSS-Protection \"1; mode=block\"' | tee -a /etc/apache2/conf-available/security.conf && systemctl restart apache2"
run_step "Prevent directory listing when no index file exists..." "echo 'Options -Indexes' | tee -a /etc/apache2/conf-available/security.conf && systemctl restart apache2"
run_step "Install and configure fail2ban for intrusion prevention..." "apt install fail2ban -y && systemctl enable fail2ban && systemctl start fail2ban"
run_step "Set up fail2ban rules for Apache..." "echo '[apache]' | tee -a /etc/fail2ban/jail.local && echo 'enabled = true' | tee -a /etc/fail2ban/jail.local && echo 'port = http,https' | tee -a /etc/fail2ban/jail.local && echo 'filter = apache-auth' | tee -a /etc/fail2ban/jail.local && echo 'logpath = /var/log/apache2/error.log' | tee -a /etc/fail2ban/jail.local && echo 'maxretry = 5' | tee -a /etc/fail2ban/jail.local && systemctl restart fail2ban"

######################################################
### --- Optimize Apache for Better Performance --- ###
######################################################
run_step "Enable gzip compression for better performance..." "a2enmod deflate && systemctl restart apache2"
run_step "Enable caching modules for static content..." "a2enmod expires headers cache cache_disk && systemctl restart apache2"
run_step "Set up compression for text-based content..." "echo 'AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css text/javascript application/javascript' | tee -a /etc/apache2/mods-available/deflate.conf && systemctl restart apache2"
run_step "Set up browser caching for static files..." "printf '<IfModule mod_expires.c>\n    ExpiresActive On\n    ExpiresByType image/jpg \"access plus 1 month\"\n    ExpiresByType image/jpeg \"access plus 1 month\"\n    ExpiresByType image/gif \"access plus 1 month\"\n    ExpiresByType image/png \"access plus 1 month\"\n    ExpiresByType text/css \"access plus 1 month\"\n    ExpiresByType application/pdf \"access plus 1 month\"\n    ExpiresByType text/javascript \"access plus 1 month\"\n    ExpiresByType application/javascript \"access plus 1 month\"\n    ExpiresByType application/x-javascript \"access plus 1 month\"\n    ExpiresByType application/x-shockwave-flash \"access plus 1 month\"\n</IfModule>' | tee -a /etc/apache2/mods-available/expires.conf && systemctl restart apache2"
run_step "Tune Apache settings for your server by adjusting worker processes and memory usage..." "printf 'StartServers 5\nMinSpareServers 5\nMaxSpareServers 10\nMaxRequestWorkers 150\nMaxConnectionsPerChild 1000' | tee -a /etc/apache2/mods-available/mpm_prefork.conf && systemctl restart apache2"
run_step "Enable HTTP/2 for better performance" "a2enmod http2 && systemctl restart apache2"

########################################
### --- Essential Apache Modules --- ###
########################################
run_step "Enable mod_rewrite for URL manipulation..." "a2enmod rewrite && systemctl restart apache2"
run_step "Allow .htaccess files for directory-level configuration..." "echo 'AllowOverride All' | tee -a /etc/apache2/apache2.conf && systemctl restart apache2"
run_step "Enable server status monitoring..." "a2enmod status && systemctl restart apache2"
run_step "Set up server status page..." "printf '<Location /server-status>\n    SetHandler server-status\n    Require host localhost\n</Location>' | tee -a /etc/apache2/conf-available/status.conf && systemctl restart apache2"
run_step "Enable server information module..." "a2enmod info && systemctl restart apache2"


# Summary
echo "==================== SUMMARY ===================="
if [[ ${#SUCCESS_STEPS[@]} -gt 0 ]]; then
    echo "✅ Successful steps:"
    for step in "${SUCCESS_STEPS[@]}"; do
        echo "   - $step"
    done
fi

if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
    echo "❌ Failed steps:"
    for step in "${FAILED_STEPS[@]}"; do
        echo "   - $step"
    done
    exit 1
else
    echo "🎉 All steps completed successfully!"
fi
