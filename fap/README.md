# FAP - Fast and Agile Provisioning

Tools (DHCP daemon + HTTP daemon + DB) for managing provisioning towards a large number of factory default Juniper switches (EX2200) using ZTP (Zero Touch Protocol) over DHCP relays.

The project is built with Python (>3.4.0) and PostgreSQL (>9.3.5).

Licensed under the GNU GPL, version 2. See the included COPYING file.



## Usage

### Installation/configuration
* Install apache2, postgresql, php, php-cli, python3, python-psycopg2
* Configure Postgresql with user + db name "fap", and password to your liking
* Create DB tables from database/create_tables.sql
* Configure Apache, necessary config in fap/httpd/apache_base_config
* Enable mod_rewrite in Apache - "a2enmod rewrite"
* Start/restart Apache

### FAP workflow
* planning.cpp generates switches.txt and patchlist.txt
* "php -f fap/tools/create_queries/create_queries.php" generates SQL queries
* Manually insert queries from create_queries.php into DB
* "php -f fap/tools/generate_distro_config_ae_event-options/generate.php" generates distroconfig into generated_configs/<distro>
* Copy distro config from generated_configs/* to HTTPD (fap/httpd/files/), and load them from the distros (load merge <ip>/files/<distro>.conf in configure mode)
* Start FAP DHCPD (sudo python3 fap/dhcpd/server_dhcp.py)


# TODO
* DONE: Support for IPv6 management
* DONE: Process multiple HTTP request simultaneously
* Support for only pushing JunOS image to switch - no config (for backup switches)
* Try/catch on whole ethernet frame in DHCPD
* Timestamps on each line in log both from DHCPD and HTTPD
