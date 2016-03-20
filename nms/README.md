#Instructions

## Installation
- fetch data from tg server: `scp ${USER}@wat.gathering.org:/root/nms-2015.sql.gz .`
- Rename the nms dump so we can use it later: `mv nms-2015.sql.gz nms-dump.sql.gz`

- Do the Debian install(or whatever OS you're on.): 
https://docs.docker.com/engine/installation/linux/debian/ 
And make sure that your user is in the docker group, so that you can run docker without sudo.  

- Clone repository: `git clone git@github.com:tech-server/tgmanage.git`

- run `./makedockerfiles.sh`, which creates the docker image files, and builds
  them. 

- Start database node: 
`docker run -v /sys/fs/cgroup:/sys/fs/cgroup:ro --privileged --rm -ti --name=db nms-db`

- Start front end node:
-- with cgroup: `docker run -v /sys/fs/cgroup:/sys/fs/cgroup:ro --privileged --rm -ti --name=front --link=db:db nms-front`

-- getting to prompt(without cgroup): 
`docker run -v "/home/kiro/repos/tgmanage:/srv/tgmanage" -v "/home/kiro/repos/tgmanage/nms/.bashrc:/root/.bashrc" -w "/srv/tgmanage/web/nms.gathering.org" \
-rm=true -ti --name=front --privileged nms-front /bin/bash`

- Find IP's:
`docker inspect nms-db | grep "IPAddress\":"`
`docker inspect nms-front | grep "IPAddress\":"`

- Open the nms-front ip in the web browser.
http://172.17.0.2:8080/

