# Oxidized

Config backup used during TG23

Features

- Config diff upload to Slack
- Fetches devices from gondul
- Automatic reload of device list

## Tools

A few moving components

### monitor

This service monitors a syslog file for changes and then runs a REST api call to oxidized
to queue a new backup job.
Make sure to only send `UI_COMMIT_COMPLETED` to this. Or modify bash script to look for this message.

NB. Only use IP of syslog server. If you're using DNS, it will send the logg twice. [This is intended feature(tm) from Juniper](https://supportportal.juniper.net/s/article/Junos-Syslog-server-receives-duplicate-syslog-when-using-DNS-name-as-host?language=en_US)

Config example

```junos
system {
    syslog {
        /* Oxidized syslog */
        host <IP of Syslog server> {
            interactive-commands notice;
            match UI_COMMIT_COMPLETED;
            source-address <lo0>;
        }
    }
}
```

### refresh-oxidized

Supersimple service to refresh device database of oxidized every minute

### slack / yolo.sh

Uploads a diff of a git commit (in essence, the config of a single device) after every backup action.
Quite useful
![Odizied](img/slack.jpg?raw=true)

## References

- <https://codingpackets.com/blog/oxidized-getting-started/>
- <https://codingpackets.com/blog/oxidized-gitlab-storage-backend/>
