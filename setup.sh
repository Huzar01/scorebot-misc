#!/usr/bin/bash
# Copyright (C) 2020 iDigitalFlame
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#

VERBOSE=0

SCOREBOT_BRANCH=""
SCOREBOT_VERSION="v3.3"
SCOREBOT_DIR="/opt/scorebot"
#SCOREBOT_URL="https://github.com/quicksandcodes/scorebot-core"
SCOREBOT_URL="https://github.com/iDigitalFlame/scorebot-core"

SYSCONFIG_DIR="/opt/sysconfig"
SYSCONFIG_URL="https://github.com/iDigitalFlame/scorebot-sysconfig"

if [ $# -ge 1 ] && ([ "$1" == "-v" ] || [ "$2" == "-v" ]); then
    VERBOSE=1
fi

log() {
    if [ $# -ne 1 ]; then
        return 0
    fi
    printf "[+] $1\n"
}
run() {
    if [ $# -ne 1 ]; then
        return 0
    fi
    if [ $VERBOSE -eq 1 ]; then
        printf "[V] Running \"$1\"\n"
    fi
    bash -c "$1; exit \$?"
    if [ $? -ne 0 ]; then
        printf "[!] Command \"$1\" did not exit with zero, quitting!\n"
        exit 1
    fi
    return 1
}
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
    #run "rm /etc/hostname" 2> /dev/null
    #run "touch /etc/hostname"
    run "echo "" > /etc/hostname"
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
    db_root_pw=""
    db_scorebot_pw=""
    db_scorebot_ip=""
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
setup_core() {
    log "setup_core starting...Installing core .."
    core_db_pw=""
    core_db_ip=""
    core_django_pw=""
    while [ -z "$core_db_pw" ] || [ -z "$core_django_pw" ] || [ -z "$core_db_ip "]; do
        printf "Django root password? "
        read core_django_pw
        printf "MySQL scorebot password? "
        read core_db_pw
        printf "MySQL Server IP Address? "
        read core_db_ip
    done
    printf "scorebot-core" > "${SYSCONFIG_DIR}/etc/hostname"
    printf "$core_db_ip\tscorebot-database\n" >> "${SYSCONFIG_DIR}/etc/hosts"
    log "MySQL Server IP is \"$core_db_ip\", this can be changed in the \"/etc/hosts\" file.."
    log "Installing core dependencies.."
    #run "sudo pacman -S apache mod_wsgi python python-pip python-virtualenv python-django gcc mariadb-clients python-mysqlclient --noconfirm --noprogressbar"
    ### NEEDED for scorebot_core
    #### Services needed: 
    ##### ADHOC (Cron Job) - Talks with database. 
    ##### Apache 
    
    #### Runtime containers:
    ##### Database
    ##### Apache (DJango env) [Unicorn may be need as wsgi not in repos anymore(if you want to use wsgi need to manually build it)] *see code in slack thread.
    ##### ADHOC (schudeling and DJango configs, not hosting an endpoint)  
    run "pacman -S apache python python-pip python-virtualenv python-django gcc mariadb-clients python-mysqlclient --noconfirm --noprogressbar"
    run "mkdir -p \"${SCOREBOT_DIR}/versions\""
    log "Building virtual env.."
    ### Create virtualenv (Can skip)
    run "virtualenv --always-copy \"${SCOREBOT_DIR}/python\"" 1> /dev/null
    if  [ -d "${SCOREBOT_DIR}/versions/${SCOREBOT_VERSION}" ]; then
	rm -rf "${SCOREBOT_DIR}/versions/${SCOREBOT_VERSION}"
    fi
    ### Pulling git repo 
    ### COPY git repo file into Container
    ### Want all this ahppen in container, so COPY works here. (Runs only on docker build)
    run "git clone \"$SCOREBOT_URL\" \"${SCOREBOT_DIR}/versions/${SCOREBOT_VERSION}\""
    if ! [ -z "$SCOREBOT_BRANCH" ]; then
        run "cd \"${SCOREBOT_DIR}/versions/${SCOREBOT_VERSION}\"; git checkout $SCOREBOT_BRANCH"
    fi
    run "ln -s \"${SCOREBOT_DIR}/versions/${SCOREBOT_VERSION}\" \"${SCOREBOT_DIR}/current\"" 1> /dev/null
    log "Installing PIP requirements.."
    ### Point to repo
    run "source \"${SCOREBOT_DIR}/python/bin/activate\"; cd \"${SCOREBOT_DIR}/current\"; unset PIP_USER; pip install -r requirements.txt" 1> /dev/null
    ### Push database pw to settings.py | Env
    ### Mount to volume to docker (share from host <-> docker)
    ### Settings file should be a Mount, at runtime you may want to change the config dynamically wihtout rebuilding docker. 
    run "sed -ie 's/\"PASSWORD\": \"password\",/\"PASSWORD\": \"$core_db_pw\",/g' \"${SCOREBOT_DIR}/current/scorebot/settings.py\""
    run "rm ${SCOREBOT_DIR}/current/scorebot/*e"
    #
    ### DJango, may need to split this function into the database itself. (Need to ensure DJango is clean and operational after game or closures)
    ### There is database, but it's empty 
    ### Build - loading all software on container (initial config/build)
    ### Interm - optional, INIT phase. Start container, doing init things(Configuring DB, PW) *Things to do after building, but before runtime.
    #### init container starts up in the same env as build container to prepare that container for runtime. 
    #### 1)Build another container for init. 2) 'BusyBox' 
    ### Runtime - Everything interacting with each needed element. 
    
    ### Dump DB to a sql file and mount that file into DB container.
    
    ### Create Token GUID to auth. Universal bootstrap token.
    ###
    log "Attempting to push migrations to database server \"$core_db_ip\".."
    log "migrate.py make migration.."
    run "source \"${SCOREBOT_DIR}/python/bin/activate\"; cd \"${SCOREBOT_DIR}/current\"; env SBE_SQLLITE=0 python manage.py makemigrations scorebot_grid scorebot_core scorebot_game" 1> /dev/null
    #
    log "migrate.py migrate.."
    run "source \"${SCOREBOT_DIR}/python/bin/activate\"; cd \"${SCOREBOT_DIR}/current\"; env SBE_SQLLITE=0 python manage.py migrate" 1> /dev/null
    #
    log "manage.py shell .."
    run "source \"${SCOREBOT_DIR}/python/bin/activate\"; cd \"${SCOREBOT_DIR}/current\"; env SBE_SQLLITE=0 python manage.py shell -c \"from django.contrib.auth.models import User; User.objects.create_superuser('root', '', '$core_django_pw')\""
    #
    log "Created Django admin account \"root\" with supplied password!"
    [ -e /etc/httpd/conf/scorebot-role.conf ] && rm /etc/httpd/conf/scorebot-role.conf
    ### apache conf in repo file. 
    run "ln -s \"${SYSCONFIG_DIR}/etc/httpd/conf/roles/core.conf\" \"/etc/httpd/conf/scorebot-role.conf\"" 1> /dev/null
    #
    run "ln -s /usr/lib/python3.*/site-packages/django/contrib/admin/static/admin \"${SCOREBOT_DIR}/current/scorebot_static/admin\"" 1> /dev/null
    run "chown root:http -R \"${SCOREBOT_DIR}\""
    run "chmod 550 -R \"${SCOREBOT_DIR}/current\""
    run "mkdir -p \"${SCOREBOT_DIR}/current/scorebot_media\""
    run "chown http:http \"${SCOREBOT_DIR}/current/scorebot_media\""
    run "chmod 775 \"${SCOREBOT_DIR}/current/scorebot_media\""
    printf '[Unit]\nDescription     = Scorebot Daemon\nAfter           = syslog.target httpd.service\n' > "${SYSCONFIG_DIR}/etc/systemd/system/scorebot.service"
    printf 'Wants           = network-online.target httpd.service\n\n' >> "${SYSCONFIG_DIR}/etc/systemd/system/scorebot.service"
    printf '[Service]\nType            = simple\nUser            = http\nGroup           = http\n' >> "${SYSCONFIG_DIR}/etc/systemd/system/scorebot.service"
    printf 'ExecStart       = /usr/bin/bash -c "source $PYDIR/bin/activate; python3 $SCOREBOT/daemon.py"\nKillSignal      = SIGINT\n' >> "${SYSCONFIG_DIR}/etc/systemd/system/scorebot.service"
    #printf "Environment     = \"PYDIR=${SCOREBOT_DIR}/python\"\nEnvironment     = \"SCOREBOT=${SCOREBOT_DIR}/current\"\n" >> "${SYSCONFIG_DIR}/etc/system/systemd/scorebot.service"
    printf "Environment     = \"PYDIR=${SCOREBOT_DIR}/python\"\nEnvironment     = \"SCOREBOT=${SCOREBOT_DIR}/current\"\n" >> "${SYSCONFIG_DIR}/etc/systemd/system/scorebot.service"
    printf 'ProtectHome     = true\nProtectSystem   = true\n\n[Install]\nWantedBy        = multi-user.target\n' >> "${SYSCONFIG_DIR}/etc/systemd/system/scorebot.service"
    run "rm -rf /tmp/scorebot3"
    run "systemctl enable httpd.service" 2> /dev/null
    run "systemctl enable scorebot.service" 2> /dev/null
    run "systemctl start httpd.service"
    run "systemctl start scorebot.service"
    log "Core setup complete!"
}
setup_proxy() {
    proxy_scorebot_ip=""
    while [ -z "$proxy_scorebot_ip" ]; do
        printf "Scorebot API IP Address? "
        read proxy_scorebot_ip
    done
    printf "scorebot-proxy" > "${SYSCONFIG_DIR}/etc/hostname"
    printf "$proxy_scorebot_ip\tscorebot-core\n" >> "${SYSCONFIG_DIR}/etc/hosts"
    log "Scorebot IP is \"$proxy_scorebot_ip\", this can be changed in the \"/etc/hosts\" file.."
    log "Installing proxy dependencies.."
    run "pacman -S apache --noconfirm --noprogressbar"
    log "Enabling and starting Apache proxy..."
    run "ln -s \"${SYSCONFIG_DIR}/etc/httpd/conf/roles/proxy.conf\" \"/etc/httpd/conf/scorebot-role.conf\"" 1> /dev/null
    run "sed -ie 's/LoadModule wsgi_module/# LoadModule wsgi_module/g' \"/etc/httpd/conf/httpd.conf\""
    run "systemctl enable httpd.service" 2> /dev/null
    run "systemctl start httpd.service"
    log "Proxy setup complete, please ensure to configure the core component!"
}

log "Scorebot Setup v2.5"
log "iDigitalFlame, The Scorebot Project 2019"

if [ $# -eq 1 ] && [ $1 != "-v" ]; then
    sbe_role=$1
fi
if [ $# -eq 2 ]; then
    if [ $1 != "-v" ]; then
        sbe_role=$1
    fi
    if [ $2 != "-v" ]; then
        sbe_role=$2
    fi
fi

if [ -z "$sbe_role" ]; then
    log "Select the role for this server.."
    #printf "[?] Roles:\n\t1: Core\n\t2: DB\n\t3: Proxy\nChoice [1-3]: "
    printf "[?] Roles:\n\t1: Core\n\t2: DB\n\t3: Proxy\n\t4: Core and DB\nChoice [1-4]: "
    read sbe_role
fi

case $sbe_role in
    1)
    setup
    setup_core
    ;;
    2)
    setup
    setup_db
    ;;
    3)
    setup
    setup_proxy
    ;;
    4)
    setup
    setup_db
    setup_core
    ;;
    *)
    log "Invalid role selected! Please try again..\nGoodbye"
    exit 255
    ;;
esac

log "Finilizing with a syslink.."
run "syslink" 1> /dev/null
log "Done\nHave Fun!"
exit 0
