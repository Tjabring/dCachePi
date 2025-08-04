echo -e '\033[32m      dCache tests\033[0m'
echo " "

echo "You can test uploading the README.md file with webdav now. Use localhost, hostname or IP address."
echo "curl -v -u tester:$PASSWD -L -T README.md http://localhost:2880/home/tester/README.md"
echo " "

echo "You can check the upload with a curl PROPFIND command."
echo "curl -s -u tester:dcache123 -X PROPFIND http://localhost:2880/home/tester/ | xmlstarlet sel -N d=\"DAV:\" -t -m \"//d:response\" -v \"concat(d:href, ' ', d:propstat/d:prop/d:displayname, ' ', d:propstat/d:prop/d:getlastmodified)\" -n"
echo " "

echo "You can test xrootd / xrdcp."
echo "xrdcp -f /bin/bash root://localhost:1096/home/tester/testfile # upload"
echo "xrdcp -f root://localhost:1096/home/tester/testfile /tmp/testfile # download"
echo " "

testfilestamp=$(date +%s)
echo "You can test dcap / dccp."
echo "dccp -A /bin/bash dcap://localhost:22125/home/tester/testfile-$testfilestamp"
echo "dccp -A dcap://localhost:22125/home/tester/testfile-$testfilestamp /tmp/testfile-$testfilestamp"
echo " "

echo "You can test ftp."
echo "echo -e \"quote USER admin\\nquote PASS dcache123\\nbinary\\nls\\nbye\" | ftp -n -P 22126 localhost"
echo "echo -e \"quote USER admin\\nquote PASS dcache123\\nbinary\\nls\\nput README.md ftp-README.md\\nbye\" | ftp -n -P 22126 localhost"
echo "echo -e \"quote USER admin\\nquote PASS dcache123\\nbinary\\nls\\nget ftp-README.md /tmp/ftp-README.md\\nbye\" | ftp -n -P 22126 localhost"
echo " "

echo "You can also access the admin console with ssh."
echo "Admin console: ssh -p 22224 admin@localhost # with your provided password $PASSWD"
echo " "

ETH0_IP=$(ip -4 addr show dev eth0 | grep inet | awk '{print $2}' | cut -d/ -f1)
echo "You can also access the web interface - dCache service."
echo "http://${HOSTNAME}.local:2288 or http://${ETH0_IP}:2288"
