# junos-bootstrap

Tools (DHCP daemon + HTTP daemon + DB) for managing provisioning towards a large number of factory default Juniper switches (EX2200) using ZTP (Zero Touch Protocol) over DHCP relays.

The project is built with Python (>3.4.0) and PostgreSQL (>9.3.5).

Licensed under the GNU GPL, version 2. See the included COPYING file.



## Usage
Launch the python scripts for junos-bootstrap from tgmanage directory.


### HTTPD
    j@lappie:~/git/tgmanage$ sudo python3 junos-bootstrap/httpd/server_http.py
    
Example: <a href="httpd/terminal.log">httpd/terminal.log</a>


### DHCPD
    j@lappie:~/git/tgmanage$ sudo python3 junos-bootstrap/dhcpd/server_dhcp.py
    
Example: <a href="dhcpd/terminal.log">dhcpd/terminal.log</a>
