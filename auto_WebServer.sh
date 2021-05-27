#!/bin/bash

# For automation create web server with nginx and apache2
# Author: Night Barron
# Date: 27/05/2021

install_services() {

    # Disable firewall
    systemctl disable firewalld
    systemctl stop firewalld
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0

    # Install Services
    yum install -y httpd epel-release yum-utils wget nano net-tools
    yum install -y nginx
    yum install -y http://rpms.remirepo.net/enterprise/remi-release-7.rpm
    yum-config-manager --enable remi-php70
    yum install php php-common php-opcache php-mcrypt php-cli php-gd php-curl php-mysql -y
    cd /usr/src 
    wget http://dev.mysql.com/get/mysql57-community-release-el7-9.noarch.rpm
    rpm -Uvh mysql57-community-release-el7-9.noarch.rpm
    yum install -y mysql-server

    # Change port
    sed -i 's/Listen\ 80/Listen\ 8080/' /etc/httpd/conf/httpd.conf

    # Enable at start up
    systemctl enable httpd
    systemctl enable mysqld
    systemctl enable nginx

    echo "Install HTTPD, MYSQLD, PHP, NGINX completed!!!"
}

restart_services() {
    systemctl restart httpd
    systemctl restart mysqld
    systemctl restart nginx
}

setup_vhost() {
    mkdir /etc/nginx/vhost.d 
    sed -i '37a\\tinclude \/etc\/nginx\/vhost.d\/*.conf;'  /etc/nginx/nginx.conf
    sed -i 's/user nginx;/user apache;/'  /etc/nginx/nginx.conf
    mkdir /etc/httpd/vhost.d 
    echo "IncludeOptional vhost.d/*.conf" >> /etc/httpd/conf/httpd.conf
    restart_services
}

start_services() {
    systemctl start httpd
    systemctl start mysqld
    systemctl start nginx
}

secure_mysql() {
    password=$(cat /var/log/mysqld.log | grep password | egrep -o "root\@localhost.*$" | cut -d" " -f2)
    echo Mysql: You temporary password for root@locahost is $password
    echo "You need to secure your Mysql Server!!!"
    mysql_secure_installation

}

setup_wordpress() {
    user=$1
    cd /home/$user/public_html
    wget http://wordpress.org/latest.tar.gz
    tar -xzvf latest.tar.gz
    rm -rf latest.tar.gz

    echo
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
    echo
    echo "Wordpress created!"

}

create_user() {
    username=$1
    echo Creating user $username
    {
        useradd -g apache -m $username        # Change here for ubuntu
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
    printf '<VirtualHost 127.0.0.1:8080>
    \tDocumentRoot "/home/%s/public_html"
    \tServerName %s
    \t<Directory /home/%s/public_html>
    \t\tAllowOverride none
    \t\tRequire all granted
    \t\tDirectoryIndex index.php index.html
    \t</Directory>\n</VirtualHost>' $user $domain $user > /etc/httpd/vhost.d/$domain.conf

    printf 'server {
        server_name %s www.%s;
        root /home/%s/public_html;

        \tlocation = /favicon.ico {
                \t\tlog_not_found off;
                \t\taccess_log off;
        \t}

        \tlocation = /robots.txt {
                \t\tallow all;
                \t\tlog_not_found off;
                \t\taccess_log off;
        \t}

        \tlocation / {
                \t\ttry_files $uri $uri/ /index.php?$args /info.php?$args;
        \t}

        \tlocation /wordpress {
                \t\tproxy_set_header X-Real-IP $remote_addr;
                \t\tproxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                \t\tproxy_set_header Host $http_host;
                \t\tproxy_pass http://127.0.0.1:8080;  #change to your internal server IP
                \t\tproxy_redirect off;
        \t}

        \tlocation ~ \.php$ {
                \t\tproxy_set_header X-Real-IP $remote_addr;
                \t\tproxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                \t\tproxy_set_header Host $http_host;
                \t\tproxy_pass http://127.0.0.1:8080;  #change to your internal server IP
                \t\tproxy_redirect off;
        \t}

        \tlocation ~* \.(js|css|png|jpg|jpeg|gif|ico)$ {
                \t\texpires max;
                \t\tlog_not_found off;
        \t}
}' $domain $domain $user > /etc/nginx/vhost.d/$domain.conf

    echo "<?php phpinfo(); ?>" > /home/$user/public_html/info.php

    # Set up Wordpress
    setup_wordpress $user 

    chown -R $user:apache /home/$user
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
    secure_mysql
    setup_vhost
    create_vhosts

}

main