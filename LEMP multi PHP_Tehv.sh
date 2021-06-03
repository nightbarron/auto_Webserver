#!/bin/bash

# Host multiple wordpress site on one server nginx (LEMP) with multi PHP version
# Made by: tehv1007
# Date: 02/06/2021

install_services() {

    # Disable firewall
    systemctl disable firewalld
    systemctl stop firewalld
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0

    # Install Services
    yum update -y
    yum install -y epel-release yum-utils wget nano net-tools vim expect

    # Install latest MariaDB version
    wget https://downloads.mariadb.com/MariaDB/mariadb_repo_setup
    chmod +x mariadb_repo_setup
    sudo ./mariadb_repo_setup
    yum install -y MariaDB-server

    # Install Nginx
    yum install -y nginx

    # Install PHP multiple versions including 5.6, 7.1, 7.2, 7.3, 7.4
    yum install -y http://rpms.remirepo.net/enterprise/remi-release-7.rpm
    yum repolist remi-safe
    yum-config-manager --enable remi-php70
    yum install php php-common php-opcache php-mcrypt php-cli php-gd php-curl php-mysql -y
}
    # Enable at start up
    systemctl enable mariadb
    systemctl enable nginx


create_multiphp() {
    echo "Setup multiple PHP versions!!!"
    while true; do 
        echo "Enter PHP version will be install (Enter for Cancel)"
        echo "It corresponds to one of the numbers 56,70,71,72,73,74"
        echo -n "Let's choose your number:"
        read version

        if [ ${#version} -eq 0 ];
        then
            echo "Cancelled!!!"
            break
        else
            config_PHP $version
        fi
done
}

# Configure PHP-FPM
config_PHP() {
    version=$1
    echo Creating PHP version $version
    yum install php$version-php-fpm php$version-php-mysql -y
    sed -i s/:9000/:90$version/ /etc/opt/remi/php$version/php-fpm.d/www.conf
    echo "#!/bin/bash exec /bin/php$version-cgi" > /var/www/cgi-bin/php$version.fcgi
    
    sed -i 's/user = apache/user = nginx/'  /etc/opt/remi/php$version/php-fpm.d/www.conf
    sed -i 's/group = apache/group = nginx/'  /etc/opt/remi/php$version/php-fpm.d/www.conf
    sed -i 's/;listen.owner = nobody/listen.owner = nginx/'  /etc/opt/remi/php$version/php-fpm.d/www.conf
    sed -i 's/;listen.group = nobody/listen.group = nginx/'  /etc/opt/remi/php$version/php-fpm.d/www.conf

    systemctl enable php$version-php-fpm
    systemctl start php$version-php-fpm

    echo "The installation of MYSQLD, PHP, NGINX has been completed!"
}

restart_services() {
    systemctl restart mariadb
    systemctl restart nginx
}

start_services() {
    systemctl start mariadb
    systemctl start nginx
}

secure_mysql() {
    password=$(cat /var/log/yum.log | grep password | egrep -o "root\@localhost.*$" | cut -d" " -f2)
    echo Mysql: You temporary password for root@locahost is $password
    echo "You need to secure your Mysql Server!!!"
    mysql_secure_installation
}

config_nginx() {
    # Config for connecting NGINX to PHP FPM
    # We must tell NGINX to proxy requests to PHP FPM via the FCGI protocol
    sed -i '43alocation ~ [^/]\.php(/|$) {' /etc/nginx/nginx.conf
    sed -i '44afastcgi_split_path_info ^(.+?\.php)(/.*)$;' /etc/nginx/nginx.conf
    sed -i '45aif (!-f $document_root$fastcgi_script_name) {' /etc/nginx/nginx.conf
    sed -i '46areturn 404;' /etc/nginx/nginx.conf
    sed -i '47a}' /etc/nginx/nginx.conf

    # Mitigate https://httpoxy.org/ vulnerabilities
    sed -i '48afastcgi_param HTTP_PROXY "";' /etc/nginx/nginx.conf
    
    # fastcgi_pass unix:/var/run/php-fpm.sock; # for using unix socket
    sed -i '49afastcgi_pass 127.0.0.1:9000;' /etc/nginx/nginx.conf
    sed -i '50afastcgi_index index.php;' /etc/nginx/nginx.conf

    # include the fastcgi_param setting
    sed -i '51ainclude fastcgi_params;' /etc/nginx/nginx.conf
    sed -i '52afastcgi_param  SCRIPT_FILENAME   $document_root$fastcgi_script_name;' /etc/nginx/nginx.conf
    sed -i '53a}' /etc/nginx/nginx.conf

    restart_services
}

setup_wordpress() {
    user=$1
    cd /home/$user/public_html
    wget http://wordpress.org/latest.tar.gz
    tar -xzvf latest.tar.gz
    rm -rf latest.tar.gz
    
    echo "Your MySQL account for Wordpress will be: "
    echo "Mysql User: $user@localhost"
    echo -n "Mysql Password (please input STRONG one): "
    read password
    echo "Enter root password for creating Database using for Wordpress: "
    mysql -uroot -p -e "CREATE DATABASE wp$user;create user $user@localhost identified by '$password';grant all privileges on wp$user.* to $user@localhost;flush privileges;"
    
    cp wordpress/wp-config-sample.php wordpress/wp-config.php

    sed -i s/database_name_here/wp$user/ wordpress/wp-config.php
    sed -i s/username_here/$user/ wordpress/wp-config.php
    sed -i s/password_here/$password/ wordpress/wp-config.php
  
    echo "Wordpress created!"
}

create_user() {
    username=$1
    echo Creating user $username
    {
        useradd -g nginx -m $username  
        passwd $username
        chmod 710 /home/$username
        echo User $username is created!!
        return 0
    } || {
        echo "Error while creating user!!!"
        return 0
    }
}

create_vhost() {
    user=$1
    domain=$2
    mkdir /home/$user/public_html

    printf 'server {
    listen 80;
    server_name %s;

    root /home/%s/public_html;
    index index.php;
    access_log /var/log/nginx/%s.access.log;
    error_log /var/log/nginx/%s.error.log;

    location = /favicon.ico {
      log_not_found off;
      access_log off;
    }

    location = /robots.txt {
      allow all;
      log_not_found off;
      access_log off;
    }

    location / {
      try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
      try_files $uri =404;
      fastcgi_pass 127.0.0.1:9000;
      fastcgi_index   index.php;
      fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
      include fastcgi_params;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
      expires max;
      log_not_found off;
    }
    }' $domain $user $domain $domain > /etc/nginx/conf.d/$domain.conf

    echo "Select PHP version for this user"
    echo "You need to remember which versions you have installed and select one!"
    read version
    sed -i s/:9000/:90$version/ /etc/nginx/conf.d/$domain.conf
    echo "<?php phpinfo(); ?>" > /home/$user/public_html/info.php
    
    config_nginx $version

    systemctl restart php$version-php-fpm

    # Set up Wordpress
    setup_wordpress $user 

    chown -R $user:nginx /home/$user/public_html
    chmod g+x -R /home/$user/public_html/wordpress
    echo "Your site is set up !!!!"
}

create_vhosts() {
    echo
    echo "SETTING UP DONE, NOW is your time to create your VHOSTs!!!"
    while true; do 
        echo -n "Enter your username (Enter for Cancel): "
        read username

        if [ ${#username} -eq 0 ];
        then
            echo "Cancelled!!!"
            break
        else
            create_user $username
        fi

        echo -n "Your domain: "
        read domain
        create_vhost $username $domain

    done
    echo "Mission completed !!!"
    restart_services
}

main() {
    install_services
    start_services
    create_multiphp
    secure_mysql
    create_vhosts
}
main