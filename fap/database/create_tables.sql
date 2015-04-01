CREATE TABLE switches (
 id serial,
 hostname character varying(20),
 distro_name character varying(100),
 distro_phy_port character varying(100),
 mgmt_v4_addr character varying(15),
 mgmt_v4_cidr smallint,
 mgmt_v4_gw character varying(15),
 mgmt_v6_cidr smallint,
 mgmt_v6_addr character varying(35),
 mgmt_v6_gw character varying(35),
 mgmt_vlan smallint,
 last_config_fetch integer,
 current_mac character varying(17),
 model character varying(20),
 traffic_vlan integer
);
