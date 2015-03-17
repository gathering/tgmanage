# Database layout

PostgreSQL

**Tables**
```
bootstrap-> \dt
           List of relations
 Schema |   Name   | Type  |   Owner   
--------+----------+-------+-----------
 public | switches | table | bootstrap
```


**Table structure**
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
 current_mac       | character varying(17)  | 
 model             | character varying(20)  | 
 traffic_vlan      | integer                | 
 mgmt_v6_cidr      | smallint               | 
 mgmt_v6_addr      | character varying(35)  | 
 mgmt_v6_gw        | character varying(35)  | 
Indexes:
    "switches_pkey" PRIMARY KEY, btree (id)
```


**Sample content in DB**
```
bootstrap=> select * from switches order by hostname;
 id | hostname | distro_name | distro_phy_port | mgmt_addr | mgmt_cidr | mgmt_gw  | mgmt_vlan | last_config_fetch |    current_mac    | model | traffic_vlan | mgmt_v6_cidr |    mgmt_v6_addr     |    mgmt_v6_gw     
----+----------+-------------+-----------------+-----------+-----------+----------+-----------+-------------------+-------------------+-------+--------------+--------------+---------------------+-------------------
 21 | e-00-0   | rs1.sector0 | ge-0/0/0        | 10.0.0.10 |        24 | 10.0.0.1 |       666 |        1426608997 | 44:f4:77:69:51:41 |       |          100 |           64 | 2a02:ed02:0666::100 | 2a02:ed02:0666::1
 22 | e-00-1   | rs1.sector0 | ge-0/0/1        | 10.0.0.11 |        24 | 10.0.0.1 |       666 |        1426607722 | 44:f4:77:68:f7:c1 |       |          101 |           64 | 2a02:ed02:0666::101 | 2a02:ed02:0666::1
 23 | e-00-2   | rs1.sector0 | ge-0/0/2        | 10.0.0.12 |        24 | 10.0.0.1 |       666 |                   |                   |       |          102 |           64 | 2a02:ed02:0666::102 | 2a02:ed02:0666::1
 24 | e-00-3   | rs1.sector0 | ge-0/0/3        | 10.0.0.13 |        24 | 10.0.0.1 |       666 |        1426606900 | 44:f4:77:69:49:81 |       |          103 |           64 | 2a02:ed02:0666::103 | 2a02:ed02:0666::1
 25 | e-00-4   | rs1.sector0 | ge-0/0/4        | 10.0.0.14 |        24 | 10.0.0.1 |       666 |                   |                   |       |          104 |           64 | 2a02:ed02:0666::104 | 2a02:ed02:0666::1
 26 | e-00-5   | rs1.sector0 | ge-0/0/5        | 10.0.0.15 |        24 | 10.0.0.1 |       666 |        1426607987 | 44:f4:77:69:5e:c1 |       |          105 |           64 | 2a02:ed02:0666::105 | 2a02:ed02:0666::1
 27 | e-00-6   | rs1.sector0 | ge-0/0/6        | 10.0.0.16 |        24 | 10.0.0.1 |       666 |                   |                   |       |          106 |           64 | 2a02:ed02:0666::106 | 2a02:ed02:0666::1
 28 | e-00-7   | rs1.sector0 | ge-0/0/7        | 10.0.0.17 |        24 | 10.0.0.1 |       666 |        1426540295 | 44:f4:77:69:22:41 |       |          107 |           64 | 2a02:ed02:0666::107 | 2a02:ed02:0666::1
 29 | e-00-8   | rs1.sector0 | ge-0/0/8        | 10.0.0.18 |        24 | 10.0.0.1 |       666 |        1426608145 | 44:f4:77:69:4f:c1 |       |          108 |           64 | 2a02:ed02:0666::108 | 2a02:ed02:0666::1
 30 | e-00-9   | rs1.sector0 | ge-0/0/9        | 10.0.0.19 |        24 | 10.0.0.1 |       666 |        1426608293 | 44:f4:77:68:b5:01 |       |          109 |           64 | 2a02:ed02:0666::109 | 2a02:ed02:0666::1
(10 rows)

```


**Connect to DB from CLI**
```
j@lappie:~/git/tgmanage$ psql -U bootstrap -d bootstrap -W
Password for user bootstrap: 
psql (9.3.5)
Type "help" for help.

bootstrap=> 
```


**Sample procedure to insert content to DB**
```
insert into switches 
(hostname, distro_name, distro_phy_port, mgmt_addr, mgmt_cidr, mgmt_gw, mgmt_vlan, traffic_vlan)
values 
('e-00-0', 'rs1.sector0', 'ge-0/0/0', '10.0.0.10', '24', '10.0.0.1', '666', '100'),
('e-00-1', 'rs1.sector0', 'ge-0/0/1', '10.0.0.11', '24', '10.0.0.1', '666', '101'),
('e-00-2', 'rs1.sector0', 'ge-0/0/2', '10.0.0.12', '24', '10.0.0.1', '666', '102'),
('e-00-3', 'rs1.sector0', 'ge-0/0/3', '10.0.0.13', '24', '10.0.0.1', '666', '103'),
('e-00-4', 'rs1.sector0', 'ge-0/0/4', '10.0.0.14', '24', '10.0.0.1', '666', '104'),
('e-00-5', 'rs1.sector0', 'ge-0/0/5', '10.0.0.15', '24', '10.0.0.1', '666', '105'),
('e-00-6', 'rs1.sector0', 'ge-0/0/6', '10.0.0.16', '24', '10.0.0.1', '666', '106'),
('e-00-7', 'rs1.sector0', 'ge-0/0/7', '10.0.0.17', '24', '10.0.0.1', '666', '107'),
('e-00-8', 'rs1.sector0', 'ge-0/0/8', '10.0.0.18', '24', '10.0.0.1', '666', '108'),
('e-00-9', 'rs1.sector0', 'ge-0/0/9', '10.0.0.19', '24', '10.0.0.1', '666', '109');
```



## Detailed description of table "switches" fields:
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



## TODO
* Rename v4 column names to follow v6 scheme
