#!/bin/bash

PASSWD="dcache123"
SLEEP=2
DEBUG=0

usage() {
  cat <<USAGE
dcache-test.sh - run basic dCache protocol checks

Options:
  -d        Enable debug output (print commands and show full stdout/stderr)
  -h        Show this help

Environment/variables you may tweak in the script:
  PASSWD    Password for users 'tester' (WebDAV) and 'admin' (FTP/admin ssh)
  SLEEP     Seconds to sleep between tests

The script tests:
  - WebDAV PUT and PROPFIND (basic and xmlstarlet parse)
  - Macaroon request + WebDAV PUT/GET and PROPFIND (Depth: 1)
  - XRootD upload/download
  - dcap/dccp upload/download
  - FTP list/upload/download on the FTP door
  - Admin console SSH login (EOF to close)
USAGE
}

while getopts ":dh" opt; do
  case "$opt" in
    d) DEBUG=1 ;;
    h) usage; exit 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage; exit 2 ;;
  esac
done

HOSTNAME=$(hostname)
ETH0_IP=$(ip -4 addr show dev eth0 | grep inet | awk '{print $2}' | cut -d/ -f1)
testfilestamp=$(date +%s)

green() { echo -e "\033[32m$1\033[0m"; }
red()   { echo -e "\033[31m$1\033[0m"; }

run_test() {
  DESC="$1"
  CMD="$2"

  echo "Running: $DESC"
  if [ "$DEBUG" -eq 1 ]; then
    echo "DEBUG: $CMD"
    bash -c "$CMD"
    rc=$?
  else
    bash -c "$CMD" >/dev/null 2>&1
    rc=$?
  fi

  if [ $rc -eq 0 ]; then
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

# WebDAV PROPFIND XML parse with visible output
echo
echo "This test uses xmlstarlet to parse the PROPFIND XML response from dCache WebDAV."
echo "It extracts href, filename and last-modified timestamp from the response."
echo

echo "Running: WebDAV PROPFIND XML parse"
if [ "$DEBUG" -eq 1 ]; then
  echo "DEBUG: curl -s -u tester:***** -X PROPFIND http://localhost:2880/home/tester/ | xmlstarlet sel -N d='DAV:' -t -m '//d:response' -v 'concat(d:href, \" \", d:propstat/d:prop/d:displayname, \" \", d:propstat/d:prop/d:getlastmodified)' -n"
fi
PROPFIND_OUTPUT=$(curl -s -u tester:$PASSWD -X PROPFIND http://localhost:2880/home/tester/ | \
  xmlstarlet sel -N d='DAV:' -t -m '//d:response' -v 'concat(d:href, " ", d:propstat/d:prop/d:displayname, " ", d:propstat/d:prop/d:getlastmodified)' -n)
if echo "$PROPFIND_OUTPUT" | grep -q README.md; then
  green "✅ OK: WebDAV PROPFIND XML parse"
else
  red "❌ FAIL: WebDAV PROPFIND XML parse"
fi
echo "$PROPFIND_OUTPUT"



# HTTP-aware helper for curl tests (expects HTTP code on last line)
run_http() {
  DESC="$1"
  CMD="$2"
  WANT="$3"   # space-separated expected codes, e.g. "200 201 204 207"

  echo "Running: $DESC"
  [ "$DEBUG" -eq 1 ] && echo "DEBUG: $CMD"
  out=$(bash -c "$CMD" 2>&1)
  rc=$?
  code=$(echo "$out" | tail -n1)

  if [ $rc -eq 0 ] && echo " $WANT " | grep -q " $code "; then
    green "✅ OK: $DESC (HTTP $code)"
  else
    red "❌ FAIL: $DESC (HTTP ${code:-?})"
    [ "$DEBUG" -eq 1 ] && echo "$out"
  fi
  sleep $SLEEP
}


echo
echo "Requesting macaroon..."
macaroon=$(curl -s -k -u admin:$PASSWD \
  -X POST -H 'Content-Type: application/macaroon-request' \
  https://localhost:2881 | grep -o '"macaroon": *"[^"]*"' | sed 's/.*"macaroon": *"\([^"]*\)".*/\1/')

if [ -z "$macaroon" ]; then
  red "❌ FAIL: could not get macaroon"
  exit 1
fi
green "Macaroon acquired: $macaroon"
sleep $SLEEP

# Create a test file
ts=$(date +%s)
testname="macaroon-test-$ts.txt"
src="/tmp/$testname"
dst="/tmp/download-$testname"
echo "This is the test content of the macaroon-test file: $ts" > "$src"

# Upload
run_test "Macaroon PUT $testname" \
  "curl -fsSk -H \"Authorization: Bearer $macaroon\" -T \"$src\" https://localhost:2881/home/tester/$testname"

# Download
run_test "Macaroon GET $testname" \
  "curl -fsSk -H \"Authorization: Bearer $macaroon\" -o \"$dst\" https://localhost:2881/home/tester/$testname"

# Show downloaded content
echo "Downloaded file content of file ($dst):"
file "$dst"
cat "$dst"

# Delete
run_test "Macaroon DELETE $testname" \
  "curl -fsSk -H \"Authorization: Bearer $macaroon\" -X DELETE https://localhost:2881/home/tester/$testname"

# Final listing
echo
echo "Final PROPFIND listing via macaroon"
curl -s -k -X PROPFIND -H "Authorization: Bearer $macaroon" -H "Depth: 1" \
  https://localhost:2881/home/tester/ | \
  xmlstarlet sel -N d='DAV:' \
    -t -m '//d:response' \
    -v 'concat(d:href, " ", d:propstat/d:prop/d:displayname, " ", d:propstat/d:prop/d:getlastmodified)' -n

sleep $SLEEP
sleep $SLEEP





# xrootd
echo
green "XROOTD"
echo "xrootd is a high-performance, scalable protocol for data access, commonly used in large scientific computing environments like CERN."
echo "It allows users to copy files to/from storage systems like dCache using the xrdcp client."
echo

run_test "xrootd upload" \
  "xrdcp -f /bin/bash root://localhost:1096/home/tester/testfile"

run_test "xrootd download" \
  "xrdcp -f root://localhost:1096/home/tester/testfile /tmp/testfile"

# dcap / dccp
echo
green "DCAP"
echo "dcap is dCache’s native protocol for fast data transfer, often used in high-throughput computing."
echo "dccp is the client tool used to copy files over dcap, similar to scp or xrdcp."
echo

run_test "dccp upload (dcap)" \
  "dccp -A /bin/bash dcap://localhost:22125/home/tester/testfile-$testfilestamp"

run_test "dccp download (dcap)" \
  "dccp -A dcap://localhost:22125/home/tester/testfile-$testfilestamp /tmp/testfile-$testfilestamp"

# FTP
echo
green "FTP"
echo
run_test "FTP LIST" \
  "echo -e \"quote USER admin\nquote PASS $PASSWD\nbinary\nls\nbye\" | ftp -n -P 22126 localhost"

run_test "FTP UPLOAD" \
  "echo -e \"quote USER admin\nquote PASS $PASSWD\nbinary\nput README.md ftp-README.md\nbye\" | ftp -n -P 22126 localhost"

run_test "FTP DOWNLOAD" \
  "echo -e \"quote USER admin\nquote PASS $PASSWD\nbinary\nget ftp-README.md /tmp/ftp-README.md\nbye\" | ftp -n -P 22126 localhost"

# Admin console (send EOF via stdin redirection)
run_test "SSH admin console login" \
  "sshpass -p $PASSWD ssh -o StrictHostKeyChecking=no -p 22224 -o ConnectTimeout=5 admin@localhost </dev/null"

# Info
echo
green " You can also check the web interface on:"
echo "  http://${HOSTNAME}.local:2288"
echo "  http://${ETH0_IP}:2288"
echo

