# Database layout

PostgreSQL

```
bootstrap-> \dt
           List of relations
 Schema |   Name   | Type  |   Owner   
--------+----------+-------+-----------
 public | switches | table | bootstrap
```


```
bootstrap=> \d switches
                                      Table "public.switches"
      Column       |          Type          |                       Modifiers                       
-------------------+------------------------+-------------------------------------------------------
 id                | integer                | not null default nextval('switches_id_seq'::regclass)
 hostname          | character varying(20)  | not null
 distro_name       | character varying(100) | not null
 distro_phy_port   | character varying(100) | not null
 mgmt_addr         | character varying(15)  | not null
 mgmt_cidr         | smallint               | not null
 mgmt_gw           | character varying(15)  | not null
 mgmt_vlan         | smallint               | not null
 last_config_fetch | integer                | 
 current_mac       | character varying(17)  | default NULL::character varying
 model             | character varying(20)  | 
Indexes:
    "switches_pkey" PRIMARY KEY, btree (id)
```

## Detailed description of table fields:
* id: autoincreasing integer used to identify the database row
* hostname: the unique edge switchs hostname - example: edge01
* distro_name: the distro switch hostname - example: distro01
* distro_phy_port: The distro switch's physical port - example: ge-3/1/0
* mgmt_addr: The management IP - will be configured under vlan set in "mgmt_vlan" - example: 10.20.30.40
* mgmt_cidr: CIDR mask on management subnet - example: 28
* mgmt_vlan: VLAN id at the management VLAN - example: 100
* last_config_fetch: unix timestamp of the last time the config were fetched by the switch - example: 11041551
* current_mac: MAC address of the edge switch - example: 0f:1f:2f:3f:4f:5f
* model: edge switch model - used to select template - example: ex2200

