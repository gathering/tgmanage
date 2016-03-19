#Instructions

## Installation
- fetch data from tg server: `scp ${USER}@wat.gathering.org:/root/nms-2015.sql.gz .`
- Rename the nms dump so we can use it later: `mv nms-2015.sql.gz nms-dump.sql.gz`

- Do the Debian install(or whatever OS you're on.): https://docs.docker.com/engine/installation/linux/debian/ And make sure that your user is in the docker group, so that you can run docker without sudo.  

- Clone repository: `git clone git@github.com:tech-server/tgmanage.git`


- run `./makedockerfiles.sh`, which creates the docker image files, and builds
  them. 

- Start database node: `docker run -v /sys/fs/cgroup:/sys/fs/cgroup:ro --privileged --rm -ti --name=db nms-db`
- Start front end node: ` docker run -v /sys/fs/cgroup:/sys/fs/cgroup:ro --privileged --rm -ti --name=front --link=db:db nms-front `
- Find IP's: `docker inspect front`, `docker inspect db`
- Start a shell in a container: `docker exec front /bin/bash`
- Open localhost:PORT in browser to start testing.



## TODO
- finish the installation guide above.
