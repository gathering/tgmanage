--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: nms; Type: DATABASE; Schema: -; Owner: nms
--

CREATE DATABASE nms WITH TEMPLATE = template0 ENCODING = 'UTF8' LC_COLLATE = 'en_US.UTF-8' LC_CTYPE = 'en_US.UTF-8';


ALTER DATABASE nms OWNER TO nms;

\connect nms

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET search_path = public, pg_catalog;

--
-- Name: datarate; Type: TYPE; Schema: public; Owner: nms
--

CREATE TYPE datarate AS (
	switch integer,
	ifname character varying(30),
	ifhcinoctets double precision,
	ifhcoutoctets double precision,
	last_poll_time timestamp with time zone
);


ALTER TYPE datarate OWNER TO nms;

--
-- Name: operstatuses; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE operstatuses AS (
	switch integer,
	ifdescr character(30),
	ifoperstatus integer,
	last_poll_time timestamp with time zone
);


ALTER TYPE operstatuses OWNER TO postgres;

--
-- Name: sample; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE sample AS (
	value bigint,
	polled timestamp with time zone
);


ALTER TYPE sample OWNER TO postgres;

--
-- Name: sample_state; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE sample_state AS (
	last sample,
	next_last sample
);


ALTER TYPE sample_state OWNER TO postgres;

--
-- Name: add_new_element(sample[], sample); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION add_new_element(sample[], sample) RETURNS sample[]
    LANGUAGE sql
    AS $_$ select ('{' || $1[1] || ', ' || $2 || '}')::sample[] $_$;


ALTER FUNCTION public.add_new_element(sample[], sample) OWNER TO postgres;

--
-- Name: add_new_element(sample_state, sample); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION add_new_element(sample_state, sample) RETURNS sample_state
    LANGUAGE sql
    AS $_$
        SELECT ($1.next_last, $2)::sample_state
$_$;


ALTER FUNCTION public.add_new_element(sample_state, sample) OWNER TO postgres;

--
-- Name: get_current_datarate(); Type: FUNCTION; Schema: public; Owner: nms
--

CREATE FUNCTION get_current_datarate() RETURNS SETOF datarate
    LANGUAGE sql
    AS $$
      SELECT switch,ifname,
      (ifhcoutoctets[1] - ifhcoutoctets[2]) / EXTRACT(EPOCH FROM (time[1] - time[2])) AS ifhcoutoctets,
      (ifhcinoctets[1] - ifhcinoctets[2]) / EXTRACT(EPOCH FROM (time[1] - time[2])) AS ifhcinoctets,
      time[1] AS last_poll_time
      FROM (
        SELECT switch,ifname,
        ARRAY_AGG(time) AS time,
        ARRAY_AGG(ifhcinoctets) AS ifhcinoctets,
        ARRAY_AGG(ifhcoutoctets) AS ifhcoutoctets
        FROM (
           SELECT *,rank() OVER (PARTITION BY switch,ifname ORDER BY time DESC) AS poll_num
           FROM polls WHERE time BETWEEN (now() - interval '11 minutes') AND now()
        ) t1
        WHERE poll_num <= 2
        GROUP BY switch,ifname
      ) t2
      WHERE
        time[2] IS NOT NULL
        AND ifhcinoctets[1] >= 0 AND ifhcoutoctets[1] >= 0
        AND ifhcinoctets[2] >= 0 AND ifhcoutoctets[2] >= 0
        AND ifhcoutoctets[1] >= ifhcoutoctets[2]
        AND ifhcinoctets[1] >= ifhcinoctets[2];
$$;


ALTER FUNCTION public.get_current_datarate() OWNER TO nms;

--
-- Name: get_datarate(); Type: FUNCTION; Schema: public; Owner: nms
--

CREATE FUNCTION get_datarate() RETURNS SETOF datarate
    LANGUAGE plpgsql
    AS $$
DECLARE
        num_entries INTEGER;
        poll polls;
        second_last_poll polls;
        last_poll polls;
        timediff float;
        ret datarate;
BEGIN
        num_entries := 0;
        last_poll.switch = -1;

        FOR poll IN select * from polls where time >= now() - '15 minutes'::interval and time < now() order by switch,ifname,time LOOP
                IF poll.switch <> last_poll.switch OR poll.ifname <> last_poll.ifname THEN
                        IF num_entries >= 2 THEN
                                timediff := EXTRACT(epoch from last_poll.time - second_last_poll.time);
                                ret.switch := last_poll.switch;
                                ret.ifname := last_poll.ifname;
                                
                                IF last_poll.ifhcinoctets < second_last_poll.ifhcinoctets THEN
                                        second_last_poll.ifhcinoctets = 0;
                                END IF;
                                IF last_poll.ifhcoutoctets < second_last_poll.ifhcoutoctets THEN
                                        second_last_poll.ifhcoutoctets = 0;
                                END IF;

                                ret.ifhcinoctets := (last_poll.ifhcinoctets - second_last_poll.ifhcinoctets) / timediff;
                                ret.ifhcoutoctets := (last_poll.ifhcoutoctets - second_last_poll.ifhcoutoctets) / timediff;
                                ret.last_poll_time := last_poll.time;
                                return next ret;
                        ELSIF num_entries = 1 THEN
                                ret.switch := last_poll.switch;
                                ret.ifname := last_poll.ifname;
                                ret.ifhcinoctets := -1;
                                ret.ifhcoutoctets := -1;
                                ret.last_poll_time := last_poll.time;
                                return next ret;
                        END IF;
                        num_entries := 1;
                ELSE
                        num_entries := num_entries + 1;
                END IF;
                second_last_poll.switch := last_poll.switch;
                second_last_poll.ifname := last_poll.ifname;
                second_last_poll.time := last_poll.time;
                second_last_poll.ifhcinoctets := last_poll.ifhcinoctets;
                second_last_poll.ifhcoutoctets := last_poll.ifhcoutoctets;
                last_poll.switch := poll.switch;
                last_poll.ifname := poll.ifname;
                last_poll.time := poll.time;
                last_poll.ifhcinoctets := poll.ifhcinoctets;
                last_poll.ifhcoutoctets := poll.ifhcoutoctets;
        END LOOP;
       -- pah, and once more, for the last switch/ifname...
        IF num_entries >= 2 THEN
                timediff := EXTRACT(epoch from last_poll.time - second_last_poll.time);
                ret.switch := last_poll.switch;
                ret.ifname := last_poll.ifname;
                
                IF last_poll.ifhcinoctets < second_last_poll.ifhcinoctets THEN
                        second_last_poll.ifhcinoctets = 0;
                END IF;
                IF last_poll.ifhcoutoctets < second_last_poll.ifhcoutoctets THEN
                        second_last_poll.ifhcoutoctets = 0;
                END IF;

                ret.ifhcinoctets := (last_poll.ifhcinoctets - second_last_poll.ifhcinoctets) / timediff;
                ret.ifhcoutoctets := (last_poll.ifhcoutoctets - second_last_poll.ifhcoutoctets) / timediff;
		ret.last_poll_time := last_poll.time;
                return next ret;
        ELSIF num_entries = 1 THEN
                ret.switch := last_poll.switch;
                ret.ifname := last_poll.ifname;
                ret.ifhcinoctets := -1;
                ret.ifhcoutoctets := -1;
		ret.last_poll_time := last_poll.time;
                return next ret;
        END IF;
        
        RETURN;
END;
$$;


ALTER FUNCTION public.get_datarate() OWNER TO nms;

--
-- Name: current_change(sample); Type: AGGREGATE; Schema: public; Owner: postgres
--

CREATE AGGREGATE current_change(sample) (
    SFUNC = public.add_new_element,
    STYPE = sample_state
);


ALTER AGGREGATE public.current_change(sample) OWNER TO postgres;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: ap_poll; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE ap_poll (
    switch integer NOT NULL,
    model character varying DEFAULT ''::character varying NOT NULL,
    last_poll timestamp with time zone
);


ALTER TABLE ap_poll OWNER TO nms;

--
-- Name: backup_polls; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE backup_polls (
    "time" timestamp with time zone,
    switch integer,
    port integer,
    bytes_in bigint,
    bytes_out bigint,
    errors_in bigint,
    errors_out bigint
);


ALTER TABLE backup_polls OWNER TO nms;

--
-- Name: cpuloadpoll_id_seq; Type: SEQUENCE; Schema: public; Owner: nms
--

CREATE SEQUENCE cpuloadpoll_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE cpuloadpoll_id_seq OWNER TO nms;

--
-- Name: cpuloadpoll; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE cpuloadpoll (
    id integer DEFAULT nextval('cpuloadpoll_id_seq'::regclass) NOT NULL,
    "time" timestamp without time zone NOT NULL,
    switch integer NOT NULL,
    entity integer NOT NULL,
    value integer NOT NULL
);


ALTER TABLE cpuloadpoll OWNER TO nms;

--
-- Name: dhcp; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE dhcp (
    switch integer NOT NULL,
    network cidr NOT NULL,
    last_ack timestamp without time zone,
    owner_color character varying
);


ALTER TABLE dhcp OWNER TO nms;

--
-- Name: linknet_ping; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE linknet_ping (
    linknet integer NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL,
    latency1_ms double precision,
    latency2_ms double precision
);


ALTER TABLE linknet_ping OWNER TO nms;

--
-- Name: linknets; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE linknets (
    linknet integer NOT NULL,
    switch1 integer NOT NULL,
    addr1 inet NOT NULL,
    switch2 integer NOT NULL,
    addr2 inet NOT NULL
);


ALTER TABLE linknets OWNER TO nms;

--
-- Name: linknets_linknet_seq; Type: SEQUENCE; Schema: public; Owner: nms
--

CREATE SEQUENCE linknets_linknet_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE linknets_linknet_seq OWNER TO nms;

--
-- Name: linknets_linknet_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nms
--

ALTER SEQUENCE linknets_linknet_seq OWNED BY linknets.linknet;


--
-- Name: mbd_log; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE mbd_log (
    ts timestamp without time zone,
    game character varying,
    port integer,
    description character varying,
    active_servers integer
);


ALTER TABLE mbd_log OWNER TO nms;

--
-- Name: mldpolls; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE mldpolls (
    "time" timestamp with time zone NOT NULL,
    switch integer NOT NULL,
    mcast_group inet NOT NULL,
    count integer NOT NULL,
    raw_portlist character varying
);


ALTER TABLE mldpolls OWNER TO postgres;

--
-- Name: ping; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE ping (
    switch integer NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL,
    latency_ms double precision
);


ALTER TABLE ping OWNER TO nms;

--
-- Name: ping_secondary_ip; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE ping_secondary_ip (
    switch integer NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL,
    latency_ms double precision
);


ALTER TABLE ping_secondary_ip OWNER TO nms;

--
-- Name: placements; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE placements (
    switch integer NOT NULL,
    placement box NOT NULL,
    zorder integer DEFAULT 0 NOT NULL
);


ALTER TABLE placements OWNER TO nms;

--
-- Name: polls; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE polls (
    switch integer,
    "time" timestamp with time zone,
    ifname character varying(30),
    ifhighspeed bigint,
    ifhcoutoctets bigint,
    ifhcinoctets bigint
);


ALTER TABLE polls OWNER TO nms;

--
-- Name: polls_old; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE polls_old (
    "time" timestamp with time zone NOT NULL,
    switch integer NOT NULL,
    port integer NOT NULL,
    bytes_in bigint NOT NULL,
    bytes_out bigint NOT NULL,
    errors_in bigint NOT NULL,
    errors_out bigint NOT NULL,
    official_port boolean DEFAULT false NOT NULL,
    operstatus integer DEFAULT 2 NOT NULL,
    ifdescr character(16) DEFAULT NULL::bpchar
);
ALTER TABLE ONLY polls_old ALTER COLUMN "time" SET STATISTICS 100;


ALTER TABLE polls_old OWNER TO nms;

--
-- Name: polls_poll_seq; Type: SEQUENCE; Schema: public; Owner: nms
--

CREATE SEQUENCE polls_poll_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE polls_poll_seq OWNER TO nms;

--
-- Name: portnames; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE portnames (
    switchtype character varying NOT NULL,
    port integer NOT NULL,
    description character varying NOT NULL
);


ALTER TABLE portnames OWNER TO nms;

--
-- Name: seen_mac; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE seen_mac (
    mac macaddr NOT NULL,
    address inet NOT NULL,
    seen timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE seen_mac OWNER TO postgres;

--
-- Name: squeue; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE squeue (
    id integer DEFAULT nextval(('squeue_sequence'::text)::regclass) NOT NULL,
    gid integer NOT NULL,
    added timestamp with time zone NOT NULL,
    updated timestamp with time zone,
    addr inet,
    cmd character varying NOT NULL,
    locked boolean DEFAULT false NOT NULL,
    processed boolean DEFAULT false NOT NULL,
    disabled boolean DEFAULT false NOT NULL,
    priority integer DEFAULT 3,
    sysname character varying NOT NULL,
    author character varying NOT NULL,
    result character varying,
    delay timestamp with time zone,
    delaytime interval DEFAULT '00:01:00'::interval
);


ALTER TABLE squeue OWNER TO nms;

--
-- Name: squeue_group_sequence; Type: SEQUENCE; Schema: public; Owner: nms
--

CREATE SEQUENCE squeue_group_sequence
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE squeue_group_sequence OWNER TO nms;

--
-- Name: squeue_sequence; Type: SEQUENCE; Schema: public; Owner: nms
--

CREATE SEQUENCE squeue_sequence
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE squeue_sequence OWNER TO nms;

--
-- Name: stemppoll_sequence; Type: SEQUENCE; Schema: public; Owner: nms
--

CREATE SEQUENCE stemppoll_sequence
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE stemppoll_sequence OWNER TO nms;

--
-- Name: switch_temp; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE switch_temp (
    switch integer,
    temp integer,
    "time" timestamp with time zone
);


ALTER TABLE switch_temp OWNER TO nms;

--
-- Name: switches; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE switches (
    switch integer DEFAULT nextval(('"switches_switch_seq"'::text)::regclass) NOT NULL,
    ip inet NOT NULL,
    sysname character varying NOT NULL,
    switchtype character varying NOT NULL,
    last_updated timestamp with time zone,
    locked boolean DEFAULT false NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    poll_frequency interval DEFAULT '00:01:00'::interval NOT NULL,
    community character varying DEFAULT 'public'::character varying NOT NULL,
    lldp_chassis_id character varying,
    secondary_ip inet
);


ALTER TABLE switches OWNER TO nms;

--
-- Name: switches_switch_seq; Type: SEQUENCE; Schema: public; Owner: nms
--

CREATE SEQUENCE switches_switch_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE switches_switch_seq OWNER TO nms;

--
-- Name: switchtypes; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE switchtypes (
    switchtype character varying NOT NULL,
    ports character varying NOT NULL
);


ALTER TABLE switchtypes OWNER TO nms;

--
-- Name: temppoll; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE temppoll (
    id integer DEFAULT nextval(('stemppoll_sequence'::text)::regclass) NOT NULL,
    "time" timestamp without time zone NOT NULL,
    switch integer NOT NULL,
    temp double precision
);


ALTER TABLE temppoll OWNER TO nms;

--
-- Name: uplinks; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE uplinks (
    switch integer NOT NULL,
    coreswitch integer NOT NULL,
    blade integer NOT NULL,
    port integer NOT NULL
);


ALTER TABLE uplinks OWNER TO nms;

--
-- Name: linknet; Type: DEFAULT; Schema: public; Owner: nms
--

ALTER TABLE ONLY linknets ALTER COLUMN linknet SET DEFAULT nextval('linknets_linknet_seq'::regclass);


--
-- Name: cpuloadpoll_pkey; Type: CONSTRAINT; Schema: public; Owner: nms; Tablespace: 
--

ALTER TABLE ONLY cpuloadpoll
    ADD CONSTRAINT cpuloadpoll_pkey PRIMARY KEY (id);


--
-- Name: seen_mac_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres; Tablespace: 
--

ALTER TABLE ONLY seen_mac
    ADD CONSTRAINT seen_mac_pkey PRIMARY KEY (mac, address, seen);


--
-- Name: switches_pkey; Type: CONSTRAINT; Schema: public; Owner: nms; Tablespace: 
--

ALTER TABLE ONLY switches
    ADD CONSTRAINT switches_pkey PRIMARY KEY (switch);


--
-- Name: switchtypes_pkey; Type: CONSTRAINT; Schema: public; Owner: nms; Tablespace: 
--

ALTER TABLE ONLY switchtypes
    ADD CONSTRAINT switchtypes_pkey PRIMARY KEY (switchtype);


--
-- Name: polls2_time_ifname_switch_idx; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX polls2_time_ifname_switch_idx ON polls USING btree ("time", ifname, switch);


--
-- Name: polls_switchporttime; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX polls_switchporttime ON polls_old USING btree (switch, port, "time");


--
-- Name: polls_time; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX polls_time ON polls_old USING btree ("time");


--
-- Name: seen_mac_addr_family; Type: INDEX; Schema: public; Owner: postgres; Tablespace: 
--

CREATE INDEX seen_mac_addr_family ON seen_mac USING btree (family(address));


--
-- Name: seen_mac_seen; Type: INDEX; Schema: public; Owner: postgres; Tablespace: 
--

CREATE INDEX seen_mac_seen ON seen_mac USING btree (seen);


--
-- Name: switch_temp_index; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX switch_temp_index ON switch_temp USING btree (switch);


--
-- Name: switches_ap_poll; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE UNIQUE INDEX switches_ap_poll ON ap_poll USING btree (switch);


--
-- Name: switches_dhcp; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE UNIQUE INDEX switches_dhcp ON dhcp USING btree (switch);


--
-- Name: switches_placement; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE UNIQUE INDEX switches_placement ON placements USING btree (switch);


--
-- Name: switches_switch; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE UNIQUE INDEX switches_switch ON switches USING btree (switch);


--
-- Name: temppoll_search; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX temppoll_search ON temppoll USING btree (switch, id);


--
-- Name: test2_mm_idx; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE UNIQUE INDEX test2_mm_idx ON polls_old USING btree ("time", switch, ifdescr);


--
-- Name: updated_index; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX updated_index ON ping USING btree (updated);


--
-- Name: updated_index2; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX updated_index2 ON linknet_ping USING btree (updated);


--
-- Name: updated_index3; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX updated_index3 ON ping_secondary_ip USING btree (updated);


--
-- Name: ap_poll_switch_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nms
--

ALTER TABLE ONLY ap_poll
    ADD CONSTRAINT ap_poll_switch_fkey FOREIGN KEY (switch) REFERENCES switches(switch);


--
-- Name: switches_switchtype_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nms
--

ALTER TABLE ONLY switches
    ADD CONSTRAINT switches_switchtype_fkey FOREIGN KEY (switchtype) REFERENCES switchtypes(switchtype);


--
-- Name: temppoll_switch_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nms
--

ALTER TABLE ONLY temppoll
    ADD CONSTRAINT temppoll_switch_fkey FOREIGN KEY (switch) REFERENCES switches(switch);


--
-- Name: uplinks_coreswitch_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nms
--

ALTER TABLE ONLY uplinks
    ADD CONSTRAINT uplinks_coreswitch_fkey FOREIGN KEY (coreswitch) REFERENCES switches(switch);


--
-- Name: uplinks_switch_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nms
--

ALTER TABLE ONLY uplinks
    ADD CONSTRAINT uplinks_switch_fkey FOREIGN KEY (switch) REFERENCES switches(switch);


--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- Name: dhcp; Type: ACL; Schema: public; Owner: nms
--

REVOKE ALL ON TABLE dhcp FROM PUBLIC;
REVOKE ALL ON TABLE dhcp FROM nms;
GRANT ALL ON TABLE dhcp TO nms;


--
-- Name: mbd_log; Type: ACL; Schema: public; Owner: nms
--

REVOKE ALL ON TABLE mbd_log FROM PUBLIC;
REVOKE ALL ON TABLE mbd_log FROM nms;
GRANT ALL ON TABLE mbd_log TO nms;


--
-- Name: mldpolls; Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON TABLE mldpolls FROM PUBLIC;
REVOKE ALL ON TABLE mldpolls FROM postgres;
GRANT ALL ON TABLE mldpolls TO postgres;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE mldpolls TO nms;


--
-- Name: placements; Type: ACL; Schema: public; Owner: nms
--

REVOKE ALL ON TABLE placements FROM PUBLIC;
REVOKE ALL ON TABLE placements FROM nms;
GRANT ALL ON TABLE placements TO nms;


--
-- Name: seen_mac; Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON TABLE seen_mac FROM PUBLIC;
REVOKE ALL ON TABLE seen_mac FROM postgres;
GRANT ALL ON TABLE seen_mac TO postgres;
GRANT SELECT,INSERT ON TABLE seen_mac TO nms;


--
-- Name: squeue; Type: ACL; Schema: public; Owner: nms
--

REVOKE ALL ON TABLE squeue FROM PUBLIC;
REVOKE ALL ON TABLE squeue FROM nms;
GRANT ALL ON TABLE squeue TO nms;


--
-- Name: switches; Type: ACL; Schema: public; Owner: nms
--

REVOKE ALL ON TABLE switches FROM PUBLIC;
REVOKE ALL ON TABLE switches FROM nms;
GRANT ALL ON TABLE switches TO nms;


--
-- PostgreSQL database dump complete
--

