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
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


SET search_path = public, pg_catalog;

--
-- Name: comment_state; Type: TYPE; Schema: public; Owner: nms
--

CREATE TYPE comment_state AS ENUM (
    'active',
    'inactive',
    'persist',
    'delete'
);


ALTER TYPE comment_state OWNER TO nms;

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
-- Name: sha1_hmac(bytea, bytea); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION sha1_hmac(bytea, bytea) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
      SELECT encode(hmac($1, $2, 'sha1'), 'hex')
    $_$;


ALTER FUNCTION public.sha1_hmac(bytea, bytea) OWNER TO postgres;

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
    "time" timestamp with time zone DEFAULT now() NOT NULL,
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
-- Name: ping; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE ping (
    switch integer NOT NULL,
    "time" timestamp with time zone DEFAULT now() NOT NULL,
    latency_ms double precision
);


ALTER TABLE ping OWNER TO nms;

--
-- Name: ping_secondary_ip; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE ping_secondary_ip (
    switch integer NOT NULL,
    "time" timestamp with time zone DEFAULT now() NOT NULL,
    latency_ms double precision
);


ALTER TABLE ping_secondary_ip OWNER TO nms;

--
-- Name: polls; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE polls (
    switch integer NOT NULL,
    "time" timestamp with time zone NOT NULL,
    ifname character varying(30) NOT NULL,
    ifhighspeed integer,
    ifhcoutoctets bigint,
    ifhcinoctets bigint
);


ALTER TABLE polls OWNER TO nms;

--
-- Name: seen_mac; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE seen_mac (
    mac macaddr NOT NULL,
    address inet NOT NULL,
    seen timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE seen_mac OWNER TO nms;

--
-- Name: snmp; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE snmp (
    "time" timestamp without time zone DEFAULT now() NOT NULL,
    switch integer NOT NULL,
    data jsonb,
    id integer NOT NULL
);


ALTER TABLE snmp OWNER TO postgres;

--
-- Name: snmp_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE snmp_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE snmp_id_seq OWNER TO postgres;

--
-- Name: snmp_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE snmp_id_seq OWNED BY snmp.id;


--
-- Name: switch_comments; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE switch_comments (
    switch integer NOT NULL,
    "time" timestamp with time zone,
    comment text,
    state comment_state DEFAULT 'active'::comment_state,
    username character varying(32),
    id integer NOT NULL
);


ALTER TABLE switch_comments OWNER TO nms;

--
-- Name: switch_comments_id_seq; Type: SEQUENCE; Schema: public; Owner: nms
--

CREATE SEQUENCE switch_comments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE switch_comments_id_seq OWNER TO nms;

--
-- Name: switch_comments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nms
--

ALTER SEQUENCE switch_comments_id_seq OWNED BY switch_comments.id;


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
    ip inet,
    sysname character varying NOT NULL,
    switchtype character varying DEFAULT 'ex2200'::character varying NOT NULL,
    last_updated timestamp with time zone,
    locked boolean DEFAULT false NOT NULL,
    poll_frequency interval DEFAULT '00:01:00'::interval NOT NULL,
    community character varying DEFAULT 'public'::character varying NOT NULL,
    lldp_chassis_id character varying,
    secondary_ip inet,
    placement box,
    subnet4 cidr,
    subnet6 cidr
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
-- Name: linknet; Type: DEFAULT; Schema: public; Owner: nms
--

ALTER TABLE ONLY linknets ALTER COLUMN linknet SET DEFAULT nextval('linknets_linknet_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY snmp ALTER COLUMN id SET DEFAULT nextval('snmp_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: nms
--

ALTER TABLE ONLY switch_comments ALTER COLUMN id SET DEFAULT nextval('switch_comments_id_seq'::regclass);


--
-- Name: polls_time_switch_ifname_key; Type: CONSTRAINT; Schema: public; Owner: nms; Tablespace: 
--

ALTER TABLE ONLY polls
    ADD CONSTRAINT polls_time_switch_ifname_key UNIQUE ("time", switch, ifname);


--
-- Name: seen_mac_pkey; Type: CONSTRAINT; Schema: public; Owner: nms; Tablespace: 
--

ALTER TABLE ONLY seen_mac
    ADD CONSTRAINT seen_mac_pkey PRIMARY KEY (mac, address, seen);


--
-- Name: switch_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: nms; Tablespace: 
--

ALTER TABLE ONLY switch_comments
    ADD CONSTRAINT switch_comments_pkey PRIMARY KEY (id);


--
-- Name: switches_pkey; Type: CONSTRAINT; Schema: public; Owner: nms; Tablespace: 
--

ALTER TABLE ONLY switches
    ADD CONSTRAINT switches_pkey PRIMARY KEY (switch);


--
-- Name: switches_sysname_key; Type: CONSTRAINT; Schema: public; Owner: nms; Tablespace: 
--

ALTER TABLE ONLY switches
    ADD CONSTRAINT switches_sysname_key UNIQUE (sysname);


--
-- Name: switches_sysname_key1; Type: CONSTRAINT; Schema: public; Owner: nms; Tablespace: 
--

ALTER TABLE ONLY switches
    ADD CONSTRAINT switches_sysname_key1 UNIQUE (sysname);


--
-- Name: ping_index; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX ping_index ON ping USING btree ("time");


--
-- Name: polls_ifname; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX polls_ifname ON polls USING btree (ifname);


--
-- Name: polls_switch; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX polls_switch ON polls USING btree (switch);


--
-- Name: polls_switch_ifname; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX polls_switch_ifname ON polls USING btree (switch, ifname);


--
-- Name: polls_time; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX polls_time ON polls USING btree ("time");


--
-- Name: seen_mac_addr_family; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX seen_mac_addr_family ON seen_mac USING btree (family(address));


--
-- Name: seen_mac_seen; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX seen_mac_seen ON seen_mac USING btree (seen);


--
-- Name: snmp_time; Type: INDEX; Schema: public; Owner: postgres; Tablespace: 
--

CREATE INDEX snmp_time ON snmp USING btree ("time");


--
-- Name: snmp_time15; Type: INDEX; Schema: public; Owner: postgres; Tablespace: 
--

CREATE INDEX snmp_time15 ON snmp USING btree (id, switch);


--
-- Name: snmp_time6; Type: INDEX; Schema: public; Owner: postgres; Tablespace: 
--

CREATE INDEX snmp_time6 ON snmp USING btree ("time" DESC, switch);


--
-- Name: switch_temp_index; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX switch_temp_index ON switch_temp USING btree (switch);


--
-- Name: switches_dhcp; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE UNIQUE INDEX switches_dhcp ON dhcp USING btree (switch);


--
-- Name: switches_switch; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX switches_switch ON switches USING hash (switch);


--
-- Name: updated_index2; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX updated_index2 ON linknet_ping USING btree ("time");


--
-- Name: updated_index3; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX updated_index3 ON ping_secondary_ip USING btree ("time");


--
-- Name: snmp_switch_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY snmp
    ADD CONSTRAINT snmp_switch_fkey FOREIGN KEY (switch) REFERENCES switches(switch);


--
-- Name: switchname; Type: FK CONSTRAINT; Schema: public; Owner: nms
--

ALTER TABLE ONLY polls
    ADD CONSTRAINT switchname FOREIGN KEY (switch) REFERENCES switches(switch);


--
-- Name: switchname; Type: FK CONSTRAINT; Schema: public; Owner: nms
--

ALTER TABLE ONLY ping
    ADD CONSTRAINT switchname FOREIGN KEY (switch) REFERENCES switches(switch);


--
-- Name: switchname; Type: FK CONSTRAINT; Schema: public; Owner: nms
--

ALTER TABLE ONLY switch_comments
    ADD CONSTRAINT switchname FOREIGN KEY (switch) REFERENCES switches(switch);


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
-- Name: seen_mac; Type: ACL; Schema: public; Owner: nms
--

REVOKE ALL ON TABLE seen_mac FROM PUBLIC;
REVOKE ALL ON TABLE seen_mac FROM nms;
GRANT ALL ON TABLE seen_mac TO nms;


--
-- Name: snmp; Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON TABLE snmp FROM PUBLIC;
REVOKE ALL ON TABLE snmp FROM postgres;
GRANT ALL ON TABLE snmp TO postgres;
GRANT ALL ON TABLE snmp TO nms;


--
-- Name: snmp_id_seq; Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON SEQUENCE snmp_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE snmp_id_seq FROM postgres;
GRANT ALL ON SEQUENCE snmp_id_seq TO postgres;
GRANT ALL ON SEQUENCE snmp_id_seq TO nms;


--
-- Name: switches; Type: ACL; Schema: public; Owner: nms
--

REVOKE ALL ON TABLE switches FROM PUBLIC;
REVOKE ALL ON TABLE switches FROM nms;
GRANT ALL ON TABLE switches TO nms;


--
-- PostgreSQL database dump complete
--

