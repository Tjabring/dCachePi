#!/bin/bash

# dCache AIO (dCache all-in-one) for Raspberry Pi
#
# A script that sets up a simple dCache all-in-one server on a Raspberry Pi.
# It creates a self-signed host certificate, which is only needed to start the service.
#
# Use on a test system only, at your own risk!
# DON'T RUN THIS ON A PRODUCTION SERVER!

# Default values for variables
DATADIR=""
PASSWD=""

# Help function to explain usage
function show_help {
    echo "Usage: $0 --datadir=<directory> --passwd=<password>"
    echo "  --datadir=DIR   Specify the data directory."
    echo "  --passwd=PASS   Specify the password."
    echo
    echo "Both --datadir and --passwd are required."
    echo "If not provided, you will be prompted to enter them."
    echo
    echo "Perform as root."
    echo "Information about dCache itself can be found at: https://www.dcache.org"
}

# Detect Linux distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
else
    echo "Unsupported Linux distribution."
    exit 1
fi

# Parse command line arguments
for arg in "$@"
do
    case $arg in
        --datadir=*)
        DATADIR="${arg#*=}"
        shift
        ;;
        --passwd=*)
        PASSWD="${arg#*=}"
        shift
        ;;
        --help|-h)
        show_help
        exit 0
        ;;
        *)
        echo "Invalid option: $arg"
        show_help
        exit 1
        ;;
    esac
done

# If no arguments were provided or if DATADIR or PASSWD are still empty, display help and prompt
if [ -z "$DATADIR" ] || [ -z "$PASSWD" ]; then
    show_help
    echo
    read -p "No or incomplete arguments provided. Do you want to continue and provide the values interactively? (Y/n) " answer
    case $answer in
        [Nn]* )
            echo "Exiting."
            exit 0
            ;;
        * )
            echo "Continuing with interactive input..."
            ;;
    esac
fi

# Prompt for DATADIR if not provided, with default /opt/dcache
while [ -z "$DATADIR" ]; do
    read -p "Please enter the DATADIR [/opt/dcache]: " DATADIR
    DATADIR=${DATADIR:-/opt/dcache}
done

# Prompt for PASSWD if not provided, with default dcache123
while [ -z "$PASSWD" ]; do
    read -sp "Please enter the PASSWD [dcache123]: " PASSWD
    PASSWD=${PASSWD:-dcache123}
    echo
done

# Display the values
echo "DATADIR is set to: $DATADIR"
echo "PASSWD is set to: $PASSWD"


if [ -x ${DATADIR} ]; then
echo "Old DATADIR $DATADIR will be removed."
    rm -rf ${DATADIR}
fi

# fix if rerun 
apt --fix-broken install
apt update && apt install -y wget
# install for testing and xrdcp
apt install -y ruby-full
gem install ansi
apt install -y xrootd-client

# Fetch and store the GPG key if it not exists
if [ ! -f /usr/share/keyrings/pgdg.gpg ]; then echo "Will get Postgresql ACCC4CF8.asc key"; wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/pgdg.gpg; fi

# Create the repository configuration file
sh -c 'echo "deb [arch=arm64 signed-by=/usr/share/keyrings/pgdg.gpg] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'

# Ensure necessary packages are installed
apt install -y curl ca-certificates

# Update the package lists
apt update

# Install the latest version of PostgreSQL (e.g., version 16)
apt install -y postgresql-16

# Install necessary packages based on distribution
case $DISTRO in
    raspbian|debian)
        apt update && apt install -y locales lynx apache2-utils openjdk-17-jdk rsyslog xmlstarlet
        ;;
    *)
        echo "Unsupported distribution: $DISTRO"
        exit 1
        ;;
esac

# Set locales for PostgreSQL
locale-gen en_US.UTF-8
update-locale LANG=en_GB.UTF-8
source /etc/default/locale

# Check if UFW or firewalld is running and apply rules accordingly
if systemctl is-active --quiet ufw; then
    ufw allow 2181/tcp
    ufw allow 22224/tcp
    ufw allow 2880/tcp
    ufw allow 20000:25000/tcp
    ufw allow 33115:33145/tcp
    ufw reload
elif systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --zone=public --add-port=2181/tcp
    firewall-cmd --permanent --zone=public --add-port=22224/tcp
    firewall-cmd --permanent --zone=public --add-port=2880/tcp
    firewall-cmd --permanent --zone=public --add-port=20000-25000/tcp
    firewall-cmd --permanent --zone=public --add-port=33115-33145/tcp
    firewall-cmd --reload
fi

# Fetch dCache download page and extract information
URL="https://www.dcache.org/old/downloads/1.9/index.shtml"
page_content=$(lynx -dump $URL)

# Extract the latest package link based on distribution
case $DISTRO in
    raspbian|debian)
        dcache_pkg=$(echo "$page_content" | grep -oP 'https://.*?\.deb' | sort --version-sort | tail -1)
        pkg_tool="dpkg -i"
        ;;
esac

# Download and install dCache package
dcache_basename=$(basename ${dcache_pkg})
if [ ! -f "$dcache_basename" ]; then
    curl -L $dcache_pkg -O
fi
$pkg_tool $dcache_basename

cat /etc/postgresql/16/main/pg_hba.conf | grep -E 'all\s+all' | sed -i 's/scram-sha-256/trust/' /etc/postgresql/16/main/pg_hba.conf

systemctl enable postgresql@16-main.service
systemctl start postgresql@16-main.service

# Configure PostgreSQL
#sudo -u postgres psql -c "CREATE USER dcache WITH PASSWORD '$PASSWD';"
#sudo -u postgres psql -c "CREATE DATABASE chimera OWNER dcache;"


# Check if the user exists
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='dcache'" | grep -q 1; then
    echo "User 'dcache' already exists."
else
    sudo -u postgres psql -c "CREATE USER dcache WITH PASSWORD '$PASSWD';"
    echo "User 'dcache' created successfully."
fi

# Check if the database exists
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='chimera'" | grep -q 1; then
    echo "Database 'chimera' already exists."
else
    sudo -u postgres psql -c "CREATE DATABASE chimera OWNER dcache;"
    echo "Database 'chimera' created successfully."
fi



systemctl restart postgresql@16-main.service


if [ ! -f /etc/dcache/dcache.conf ]; then
    echo "created dcache.conf"
    touch /etc/dcache/dcache.conf
fi

# Configure dCache
if [ -f /etc/dcache/dcache.conf ]; then
    not_edited=$(grep 'dcache.layout' /etc/dcache/dcache.conf >/dev/null 2>&1 ; echo $?)
    if [ "x$not_edited" == "x1" ]; then
        echo "dcache.layout=mylayout" >> /etc/dcache/dcache.conf
    fi
fi

cat <<'EOF' >/etc/dcache/layouts/mylayout.conf
dcache.enable.space-reservation = false

[dCacheDomain]
 dcache.broker.scheme = none
[dCacheDomain/zookeeper]
[dCacheDomain/admin]
[dCacheDomain/pnfsmanager]
 pnfsmanager.default-retention-policy = REPLICA
 pnfsmanager.default-access-latency = ONLINE

[dCacheDomain/cleaner-disk]
[dCacheDomain/poolmanager]
[dCacheDomain/billing]
[dCacheDomain/httpd]
[dCacheDomain/gplazma]
[dCacheDomain/webdav]
 webdav.authn.basic = true

[dCacheDomain/xrootd]
xrootd.cell.name=Xrootd-anonymous-operations-FULL
xrootd.net.port=1096
xrootd.security.tls.mode=OFF
xrootd.authz.anonymous-operations = FULL
xrootd.authz.read-paths = /
xrootd.authz.write-paths = /
EOF

cat <<'EOF' >/etc/dcache/gplazma.conf
auth     sufficient  htpasswd
map      sufficient  multimap
account  requisite   banfile
session  requisite   authzdb
EOF

touch /etc/dcache/htpasswd
htpasswd -bm /etc/dcache/htpasswd tester ${PASSWD}
htpasswd -bm /etc/dcache/htpasswd admin ${PASSWD}

cat <<'EOF' > /etc/dcache/multi-mapfile
username:tester uid:1000 gid:1000,true
username:admin uid:0 gid:0,true
EOF

touch /etc/dcache/ban.conf

# This is a bit peculiar. In order to start pools you need x509 certificates.
# Even though you don't use them.
mkdir -p /etc/grid-security
touch /etc/grid-security/hostkey.pem
touch /etc/grid-security/hostcert.pem
mkdir -p /etc/grid-security/certificates
mkdir -p /etc/grid-security/vomsdir

# Generate phony key and self-signed certificate to make pools start
openssl genrsa 2048 > /etc/grid-security/hostkey.pem
openssl req -x509 -days 1000 -new -subj "/C=NL/ST=Amsterdam/O=RPI/OU=NONE/CN=localhost" -key /etc/grid-security/hostkey.pem -out /etc/grid-security/hostcert.pem

cat <<'EOF' > /etc/grid-security/storage-authzdb
version 2.1

authorize tester read-write 1000 1000 /home/tester /
authorize admin read-write 0 0 / /
EOF

# Create pool
mkdir -p ${DATADIR}
dcache pool create ${DATADIR}/pool-1 pool1 dCacheDomain

# Update dCache databases
dcache database update

# Create directories
#chimera mkdir /home
#chimera mkdir /home/tester


# Create /home directory
if chimera ls /home >/dev/null 2>&1; then
    echo -e "\033[32mDirectory '/home' already exists.\033[0m"
else
    chimera mkdir /home
    echo "Directory '/home' created."
fi

# Create /home/tester directory
if chimera ls /home/tester >/dev/null 2>&1; then
    echo -e "\033[32mDirectory '/home/tester' already exists.\033[0m"
else
    chimera mkdir /home/tester
    echo "Directory '/home/tester' created."
fi



chimera chown 1000:1000 /home/tester

# Start dCache
systemctl daemon-reload
systemctl stop dcache.target
systemctl start dcache.target

# Move to a new line before checking the service
echo -ne "\rChecking if dCache service is started."

sleep 5

if systemctl is-active --quiet dcache.target; then
    total_time=120
    message="dCache service is running. Waiting for additional 120 seconds to finish startup sequence...."
    for ((j=1; j<=total_time; j++)); do
        num_stars=$((j * 60 / total_time))
        printf "\r%s [%-60s]" "$message" "$(printf '%*s' "$num_stars" | tr ' ' '*')"
        sleep 1
    done
    echo
    echo -ne "\rDone!                                     \n"
else
    echo -e "\rError: dCache service did not start within 5 seconds. Please check the service."
    exit 1
fi

echo -e '\033[32m      dCache is ready for use!\033[0m'
echo " "

echo "You can test uploading the README.md file with webdav now. Use localhost, hostname, or IP address"
echo "curl -v -u tester:$PASSWD -L -T README.md http://localhost:2880/home/tester/README.md"
echo " "

echo "You can check the upload with a curl PROPFIND command."
echo "curl -s -u tester:$PASSWD -X PROPFIND http://localhost:2880/home/tester/ | xmlstarlet sel -t -m \"//d:response\" -v \"concat(d:href, ' ', d:displayname, ' ', d:getlastmodified)\" -n"
echo " "

echo "You can test xrootd / xrdcp"
echo "xrdcp -f /bin/bash root://localhost:1096/home/tester/testfile # upload"
echo "xrdcp -f root://localhost:1096/home/tester/testfile /tmp/testfile # download"
echo " "

echo "You can also access the admin console with ssh."
echo "Admin console: ssh -p 22224 admin@localhost # with your provided password $PASSWD"

echo "You can also access the web interface"
echo "http://localhost:2288"

