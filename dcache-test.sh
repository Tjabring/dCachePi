#!/bin/bash

PASSWD="dcache123"
SLEEP=1  # seconds to sleep between tests
HOSTNAME=$(hostname)
ETH0_IP=$(ip -4 addr show dev eth0 | grep inet | awk '{print $2}' | cut -d/ -f1)
testfilestamp=$(date +%s)

green() { echo -e "\033[32m$1\033[0m"; }
red()   { echo -e "\033[31m$1\033[0m"; }

run_test() {
  DESC="$1"
  CMD="$2"

  echo "Running: $DESC"
  eval "$CMD" > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    green "✅ OK: $DESC"
  else
    red "❌ FAIL: $DESC"
  fi
  sleep $SLEEP
}

echo
green "      dCache tests"
echo

# WebDAV
run_test "WebDAV upload" \
  "curl -s -u tester:$PASSWD -L -T README.md http://localhost:2880/home/tester/README.md"

run_test "WebDAV PROPFIND check" \
  "curl -s -u tester:$PASSWD -X PROPFIND http://localhost:2880/home/tester/ | grep README.md"

echo
echo "This test uses xmlstarlet to parse the PROPFIND XML response from dCache WebDAV."
echo "It extracts href, filename and last-modified timestamp from the response."
echo

echo "Running: WebDAV PROPFIND XML parse"
PROPFIND_OUTPUT=$(curl -s -u tester:$PASSWD -X PROPFIND http://localhost:2880/home/tester/ | \
  xmlstarlet sel -N d='DAV:' -t -m '//d:response' -v 'concat(d:href, " ", d:propstat/d:prop/d:displayname, " ", d:propstat/d:prop/d:getlastmodified)' -n)

if echo "$PROPFIND_OUTPUT" | grep -q README.md; then
  green "✅ OK: WebDAV PROPFIND XML parse"
else
  red "❌ FAIL: WebDAV PROPFIND XML parse"
fi

echo "$PROPFIND_OUTPUT"
sleep $SLEEP

# xrootd (short explanation)
echo
echo "xrootd is a high-performance, scalable protocol for data access, commonly used in large scientific computing environments like CERN."
echo "It allows users to copy files to/from storage systems like dCache using the xrdcp client."
echo

run_test "xrootd upload" \
  "xrdcp -f /bin/bash root://localhost:1096/home/tester/testfile"

run_test "xrootd download" \
  "xrdcp -f root://localhost:1096/home/tester/testfile /tmp/testfile"

# dcap / dccp (short explanation)
echo
echo "dcap is dCache’s native protocol for fast data transfer, often used in high-throughput computing."
echo "dccp is the client tool used to copy files over dcap, similar to scp or xrdcp."
echo

run_test "dccp upload (dcap)" \
  "dccp -A /bin/bash dcap://localhost:22125/home/tester/testfile-$testfilestamp"

run_test "dccp download (dcap)" \
  "dccp -A dcap://localhost:22125/home/tester/testfile-$testfilestamp /tmp/testfile-$testfilestamp"

# FTP
run_test "FTP LIST" \
  "echo -e \"quote USER admin\nquote PASS $PASSWD\nbinary\nls\nbye\" | ftp -n -P 22126 localhost"

run_test "FTP UPLOAD" \
  "echo -e \"quote USER admin\nquote PASS $PASSWD\nbinary\nput README.md ftp-README.md\nbye\" | ftp -n -P 22126 localhost"

run_test "FTP DOWNLOAD" \
  "echo -e \"quote USER admin\nquote PASS $PASSWD\nbinary\nget ftp-README.md /tmp/ftp-README.md\nbye\" | ftp -n -P 22126 localhost"

# Admin console (via sshpass and EOF)
run_test "SSH admin console login" \
  "sshpass -p $PASSWD ssh -o StrictHostKeyChecking=no -p 22224 -o ConnectTimeout=5 admin@localhost <<EOF
EOF"

# Info
echo
green "Web interface:"
echo "  http://${HOSTNAME}.local:2288"
echo "  http://${ETH0_IP}:2288"
echo
