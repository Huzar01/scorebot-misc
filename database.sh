VERBOSE=0

SCOREBOT_BRANCH=""
SCOREBOT_VERSION="v3.3"
SCOREBOT_DIR="/opt/scorebot"
#SCOREBOT_URL="https://github.com/quicksandcodes/scorebot-core"
SCOREBOT_URL="https://github.com/iDigitalFlame/scorebot-core"
SYSCONFIG_DIR="/opt/sysconfig"
SYSCONFIG_URL="https://github.com/iDigitalFlame/scorebot-sysconfig"

setup() {
    log "Updating system.."
    run "pacman -Syy" 1> /dev/null
    run "pacman -Syu --noconfirm --noprogressbar"
    log "Installing required packages.."
    run "pacman -S git net-tools pacman-contrib --noconfirm --noprogressbar"
    log "Downloading sysconfig base from github.."
    if [ -d "${SYSCONFIG_DIR}.old" ]; then
        rm -rf "${SYSCONFIG_DIR}.old"
    fi
    if [ -d "$SYSCONFIG_DIR" ]; then
        mv "$SYSCONFIG_DIR" "${SYSCONFIG_DIR}.old"
    fi
    run "git clone \"$SYSCONFIG_URL\" \"$SYSCONFIG_DIR\""
    if [ -d "${SYSCONFIG_DIR}.old/etc/systemd/network" ]; then
        mkdir -p "${SYSCONFIG_DIR}/etc/systemd/network"
        cp ${SYSCONFIG_DIR}.old/etc/systemd/network/* "${SYSCONFIG_DIR}/etc/systemd/network/" 2> /dev/null
    fi
    if [ -d "${SYSCONFIG_DIR}.old/etc/udev/rules.d" ]; then
        mkdir -p "${SYSCONFIG_DIR}/etc/udev/rules.d"
        cp ${SYSCONFIG_DIR}.old/etc/udev/rules.d/* "${SYSCONFIG_DIR}/etc/udev/rules.d/" 2> /dev/null
    fi
    run "rm -rf \"${SYSCONFIG_DIR}/.git\""
    printf "SYSCONFIG=${SYSCONFIG_DIR}\n" > "/etc/sysconfig.conf"
    chmod 444 "/etc/sysconfig.conf"
    log "Initilizing sysconfig.."
    run "rm /etc/hostname" 2> /dev/null
    run "touch /etc/hostname"
    run "chmod 555 ${SYSCONFIG_DIR}/bin/relink"
    run "chmod 555 ${SYSCONFIG_DIR}/bin/syslink"
    run "bash \"${SYSCONFIG_DIR}/bin/relink\" \"${SYSCONFIG_DIR}\" / " 1> /dev/null
    run "bash \"${SYSCONFIG_DIR}/bin/syslink\"" 1> /dev/null
    run "syslink" 1> /dev/null
    log "Enabling required services.."
    run "systemctl enable sshd.service" 2> /dev/null
    run "systemctl enable fstrim.timer" 2> /dev/null
    run "systemctl enable checkupdates.timer" 2> /dev/null
    run "systemctl enable checkupdates.service" 2> /dev/null
    run "systemctl enable reflector.timer" 2> /dev/null
    run "systemctl enable reflector.service" 2> /dev/null
    run "locale-gen" 1> /dev/null
    log "Finished basic setup.."
}
setup_db() {
    log "setup_db starting...Installing database .."
    db_root_pw="test123"
    db_scorebot_pw="test123"
    db_scorebot_ip="172.17.0.3"
    while [ -z "$db_root_pw" ] || [ -z "$db_scorebot_pw" ] || [ -z "$db_scorebot_ip" ]; do
        printf "MySQL root password? "
        read db_root_pw
        printf "MySQL scorebot password? "
        read db_scorebot_pw
        printf "Scorebot API IP Address? "
        read db_scorebot_ip
    done
    log "Scorebot IP is \"$db_scorebot_ip\", this can be changed in the \"/etc/hosts\" file.."
    printf "scorebot-database" > "${SYSCONFIG_DIR}/etc/hostname"
    printf "$db_scorebot_ip\tscorebot-core\n" >> "${SYSCONFIG_DIR}/etc/hosts"
    #
    log "Installing database dependencies.."
    run "pacman -S mariadb --noconfirm --noprogressbar"
    log "Installing inital database.."
    run "mysql_install_db --basedir=/usr --ldata=/var/lib/mysql --user=mysql" 1> /dev/null
    run "systemctl enable mariadb" 2> /dev/null
    run "systemctl start mariadb"
    log "Securing database.."
    run "mysql -u root -e \"DELETE FROM mysql.user WHERE User='';\""
    run "mysql -u root -e \"DELETE FROM mysql.user WHERE User='mysql';\""
    run "mysql -u root -e \"DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');\""
    run "mysql -u root -e \"DROP DATABASE IF EXISTS test;\""
    run "mysql -u root -e \"DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';\""
    #
    run "mysql -u root -e \"FLUSH PRIVILEGES;\""
    run "mysql -u root -e \"DROP DATABASE IF EXISTS scorebot_db;\""
    run "mysql -u root -e \"CREATE DATABASE scorebot_db;\""
    run "mysql -u root -e \"GRANT ALL ON scorebot_db.* TO 'scorebot'@'scorebot-core' IDENTIFIED BY '$db_scorebot_pw';\""
    run "mysql -u root -e \"FLUSH PRIVILEGES;\""
    run "mysql -u root -e \"UPDATE mysql.global_priv SET priv=json_set(priv, '$.plugin', 'mysql_native_password', '$.authentication_string', PASSWORD('$db_root_pw')) WHERE User='root';\""
    run "systemctl restart mariadb"
    log "Database setup complete, please configure the core component to use the supplied password!"
}

setup
setup_db
