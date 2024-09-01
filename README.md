piCache - dCache All-In-One Setup Script for Raspberry Pi
--------------------------------------------------------

`piCache` is a bash script that automates the setup of a dCache all-in-one server on a Raspberry Pi. It installs dependencies, configures PostgreSQL, sets up dCache, and handles initial configurations. This script is intended for testing purposes only and should not be used on production systems.

Features:
- Auto-detects Linux distribution.
- Installs PostgreSQL and dCache.
- Configures PostgreSQL for dCache.
- Sets up firewall rules.
- Generates a self-signed certificate.
- Supports interactive mode for input if parameters aren't provided.

Prerequisites:
- Raspberry Pi with Raspbian or Debian.
- Root access.
- Internet connection.

Usage:

To run with parameters:

./picache --datadir=<directory> --passwd=<password>
If no parameters are provided, the script will prompt for them:
./picache

License:
This script is provided as-is, without warranty. Use at your own risk.

Based on: https://github.com/sara-nl/dcache_aio

Tested on a Raspberry Pi 4 Model B Rev 1.5. Four cores and 2GB memory.
Running on Raspberry Pi OS Debian GNU/Linux 12 (bookworm) 6.6.31+rpt-rpi-v8

For more information about dCache, visit: [dCache.org](https://www.dcache.org).
