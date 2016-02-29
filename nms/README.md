#Instructions

## Installation
- fetch data from tg server: `scp ${USER}@wat.gathering.org:/root/nms-2015.sql.gz .`

- Do the Debian install(or whatever OS you're on.): https://docs.docker.com/engine/installation/linux/debian/ And make sure that your user is in the docker group, so that you can run docker without sudo.  

- Clone repository: `git clone git@github.com:tech-server/tgmanage.git`

- run `./makedockerfiles.sh`, which creates the docker image files, and builds
  them. 

- Start database node: ` ... `
- Start front end node: ` ... `
- Open localhost:PORT in browser to start testing.

## TODO
- finish the installation guide above.
