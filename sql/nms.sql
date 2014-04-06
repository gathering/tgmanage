--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
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
	port integer,
	bytes_in double precision,
	bytes_out double precision,
	last_poll_time timestamp with time zone
);


ALTER TYPE public.datarate OWNER TO nms;

--
-- Name: sample; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE sample AS (
	value bigint,
	polled timestamp with time zone
);


ALTER TYPE public.sample OWNER TO postgres;

--
-- Name: sample_state; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE sample_state AS (
	last sample,
	next_last sample
);


ALTER TYPE public.sample_state OWNER TO postgres;

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
    LANGUAGE plpgsql
    AS $$
DECLARE
        num_entries INTEGER;
        poll polls;
        first_poll polls;
        last_poll polls;
        timediff float;
        ret datarate;
BEGIN
        num_entries := 0;
        last_poll.switch := -1;

        FOR poll IN select * from polls where time >= now() - '15 minutes'::interval and time < now() order by switch,port,time LOOP
                IF poll.switch <> last_poll.switch OR poll.port <> last_poll.port THEN
                        IF num_entries >= 2 THEN
                                timediff := EXTRACT(epoch from last_poll.time - first_poll.time);
                                ret.switch := last_poll.switch;
                                ret.port := last_poll.port;

                                IF last_poll.bytes_in >= first_poll.bytes_in AND last_poll.bytes_out >= first_poll.bytes_out THEN
                                        ret.bytes_in := (last_poll.bytes_in - first_poll.bytes_in) / timediff;
                                        ret.bytes_out := (last_poll.bytes_out - first_poll.bytes_out) / timediff;
					ret.last_poll_time := last_poll.time;
                                        return next ret; 
                                END IF;
                        END IF;
                        num_entries := 0;
                ELSE
                        -- reset if we have wraparound
                        IF last_poll.bytes_in < first_poll.bytes_in OR
                           last_poll.bytes_out < first_poll.bytes_out THEN
                                num_entries := 0;
                        END IF;
                END IF;

                num_entries := num_entries + 1;
                IF num_entries = 1 THEN
                        first_poll.switch := poll.switch;
                        first_poll.port := poll.port;
                        first_poll.time := poll.time;
                        first_poll.bytes_in := poll.bytes_in;
                        first_poll.bytes_out := poll.bytes_out;
                END IF;

                last_poll.switch := poll.switch;
                last_poll.port := poll.port;
                last_poll.time := poll.time;
                last_poll.bytes_in := poll.bytes_in;
                last_poll.bytes_out := poll.bytes_out;
        END LOOP;

        -- last
        IF num_entries >= 2 THEN
                timediff := EXTRACT(epoch from last_poll.time - first_poll.time);
                ret.switch := last_poll.switch;
                ret.port := last_poll.port;

                IF last_poll.bytes_in >= first_poll.bytes_in AND
                   last_poll.bytes_out >= first_poll.bytes_out THEN
                        ret.bytes_in := (last_poll.bytes_in - first_poll.bytes_in) / timediff;
                        ret.bytes_out := (last_poll.bytes_out - first_poll.bytes_out) / timediff;
			ret.last_poll_time := last_poll.time;
                        return next ret; 
                END IF;
        END IF;

        RETURN;
END;
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

        FOR poll IN select * from polls where time >= now() - '15 minutes'::interval and time < now() order by switch,port,time LOOP
                IF poll.switch <> last_poll.switch OR poll.port <> last_poll.port THEN
                        IF num_entries >= 2 THEN
                                timediff := EXTRACT(epoch from last_poll.time - second_last_poll.time);
                                ret.switch := last_poll.switch;
                                ret.port := last_poll.port;
                                
                                IF last_poll.bytes_in < second_last_poll.bytes_in THEN
                                        second_last_poll.bytes_in = 0;
                                END IF;
                                IF last_poll.bytes_out < second_last_poll.bytes_out THEN
                                        second_last_poll.bytes_out = 0;
                                END IF;

                                ret.bytes_in := (last_poll.bytes_in - second_last_poll.bytes_in) / timediff;
                                ret.bytes_out := (last_poll.bytes_out - second_last_poll.bytes_out) / timediff;
                                ret.last_poll_time := last_poll.time;
                                return next ret;
                        ELSIF num_entries = 1 THEN
                                ret.switch := last_poll.switch;
                                ret.port := last_poll.port;
                                ret.bytes_in := -1;
                                ret.bytes_out := -1;
                                ret.last_poll_time := last_poll.time;
                                return next ret;
                        END IF;
                        num_entries := 1;
                ELSE
                        num_entries := num_entries + 1;
                END IF;
                second_last_poll.switch := last_poll.switch;
                second_last_poll.port := last_poll.port;
                second_last_poll.time := last_poll.time;
                second_last_poll.bytes_in := last_poll.bytes_in;
                second_last_poll.bytes_out := last_poll.bytes_out;
                last_poll.switch := poll.switch;
                last_poll.port := poll.port;
                last_poll.time := poll.time;
                last_poll.bytes_in := poll.bytes_in;
                last_poll.bytes_out := poll.bytes_out;
        END LOOP;
       -- pah, and once more, for the last switch/port...
        IF num_entries >= 2 THEN
                timediff := EXTRACT(epoch from last_poll.time - second_last_poll.time);
                ret.switch := last_poll.switch;
                ret.port := last_poll.port;
                
                IF last_poll.bytes_in < second_last_poll.bytes_in THEN
                        second_last_poll.bytes_in = 0;
                END IF;
                IF last_poll.bytes_out < second_last_poll.bytes_out THEN
                        second_last_poll.bytes_out = 0;
                END IF;

                ret.bytes_in := (last_poll.bytes_in - second_last_poll.bytes_in) / timediff;
                ret.bytes_out := (last_poll.bytes_out - second_last_poll.bytes_out) / timediff;
		ret.last_poll_time := last_poll.time;
                return next ret;
        ELSIF num_entries = 1 THEN
                ret.switch := last_poll.switch;
                ret.port := last_poll.port;
                ret.bytes_in := -1;
                ret.bytes_out := -1;
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


ALTER TABLE public.ap_poll OWNER TO nms;

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


ALTER TABLE public.backup_polls OWNER TO nms;

--
-- Name: cpuloadpoll_id_seq; Type: SEQUENCE; Schema: public; Owner: nms
--

CREATE SEQUENCE cpuloadpoll_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.cpuloadpoll_id_seq OWNER TO nms;

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


ALTER TABLE public.cpuloadpoll OWNER TO nms;

--
-- Name: dhcp; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE dhcp (
    switch integer NOT NULL,
    network cidr NOT NULL,
    last_ack timestamp without time zone,
    owner_color character varying
);


ALTER TABLE public.dhcp OWNER TO nms;

--
-- Name: ipv4; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE ipv4 (
    mac macaddr NOT NULL,
    address inet NOT NULL,
    "time" timestamp without time zone NOT NULL,
    age integer
);


ALTER TABLE public.ipv4 OWNER TO nms;

--
-- Name: ipv6; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE ipv6 (
    mac macaddr NOT NULL,
    address inet NOT NULL,
    "time" timestamp with time zone NOT NULL,
    age integer,
    vlan text
);


ALTER TABLE public.ipv6 OWNER TO nms;

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


ALTER TABLE public.mbd_log OWNER TO nms;

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


ALTER TABLE public.mldpolls OWNER TO postgres;

--
-- Name: placements; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE placements (
    switch integer NOT NULL,
    placement box NOT NULL,
    zorder integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.placements OWNER TO nms;

--
-- Name: polls; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE polls (
    "time" timestamp with time zone NOT NULL,
    switch integer NOT NULL,
    port integer NOT NULL,
    bytes_in bigint NOT NULL,
    bytes_out bigint NOT NULL,
    errors_in bigint NOT NULL,
    errors_out bigint NOT NULL,
    official_port boolean NOT NULL DEFAULT false
);
ALTER TABLE ONLY polls ALTER COLUMN "time" SET STATISTICS 100;


ALTER TABLE public.polls OWNER TO nms;

--
-- Name: polls_poll_seq; Type: SEQUENCE; Schema: public; Owner: nms
--

CREATE SEQUENCE polls_poll_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.polls_poll_seq OWNER TO nms;

--
-- Name: portnames; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE portnames (
    switchtype character varying NOT NULL,
    port integer NOT NULL,
    description character varying NOT NULL
);


ALTER TABLE public.portnames OWNER TO nms;

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


ALTER TABLE public.squeue OWNER TO nms;

--
-- Name: squeue_group_sequence; Type: SEQUENCE; Schema: public; Owner: nms
--

CREATE SEQUENCE squeue_group_sequence
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.squeue_group_sequence OWNER TO nms;

--
-- Name: squeue_sequence; Type: SEQUENCE; Schema: public; Owner: nms
--

CREATE SEQUENCE squeue_sequence
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.squeue_sequence OWNER TO nms;

--
-- Name: stemppoll_sequence; Type: SEQUENCE; Schema: public; Owner: nms
--

CREATE SEQUENCE stemppoll_sequence
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.stemppoll_sequence OWNER TO nms;

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
    poll_frequency interval DEFAULT '00:05:00'::interval NOT NULL,
    community character varying DEFAULT 'public'::character varying NOT NULL
);


ALTER TABLE public.switches OWNER TO nms;

--
-- Name: switches_switch_seq; Type: SEQUENCE; Schema: public; Owner: nms
--

CREATE SEQUENCE switches_switch_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.switches_switch_seq OWNER TO nms;

--
-- Name: switchtypes; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE switchtypes (
    switchtype character varying NOT NULL,
    ports character varying NOT NULL,
);


ALTER TABLE public.switchtypes OWNER TO nms;

--
-- Name: temppoll; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE temppoll (
    id integer DEFAULT nextval(('stemppoll_sequence'::text)::regclass) NOT NULL,
    "time" timestamp without time zone NOT NULL,
    switch integer NOT NULL,
    temp double precision
);


ALTER TABLE public.temppoll OWNER TO nms;

--
-- Name: uplinks; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE uplinks (
    switch integer NOT NULL,
    coreswitch integer NOT NULL,
    blade integer NOT NULL,
    port integer NOT NULL
);


ALTER TABLE public.uplinks OWNER TO nms;

--
-- Data for Name: ap_poll; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY ap_poll (switch, model, last_poll) FROM stdin;
\.


--
-- Data for Name: backup_polls; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY backup_polls ("time", switch, port, bytes_in, bytes_out, errors_in, errors_out) FROM stdin;
\.


--
-- Data for Name: cpuloadpoll; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY cpuloadpoll (id, "time", switch, entity, value) FROM stdin;
\.


--
-- Name: cpuloadpoll_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nms
--

SELECT pg_catalog.setval('cpuloadpoll_id_seq', 1, false);


--
-- Data for Name: dhcp; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY dhcp (switch, network, last_ack, owner_color) FROM stdin;
106	151.216.27.64/26	2013-03-31 07:53:24	#000000
2	151.216.1.64/26	2013-03-31 07:54:48	#000000
91	151.216.23.128/26	2013-03-31 08:04:58	#000000
108	151.216.27.192/26	2013-03-31 08:17:17	#000000
79	151.216.20.128/26	2013-03-31 08:20:27	#000000
83	151.216.21.128/26	2013-03-31 08:24:38	#000000
107	151.216.27.128/26	2013-03-31 08:30:13	#000000
31	151.216.8.128/26	2013-03-31 08:44:47	#000000
104	151.216.26.192/26	2013-03-31 08:45:11	#000000
11	151.216.3.128/26	2013-03-31 08:52:07	#000000
102	151.216.26.64/26	2013-03-31 08:55:46	#000000
15	151.216.4.128/26	2013-03-31 08:58:05	#000000
26	151.216.7.64/26	2013-03-31 09:13:42	#000000
93	151.216.24.0/26	2013-03-31 09:14:03	#000000
57	151.216.15.0/26	2013-03-31 09:30:18	#000000
47	151.216.12.128/26	2013-03-31 09:31:12	#000000
103	151.216.26.128/26	2013-03-31 09:37:39	#000000
23	151.216.6.128/26	2013-03-31 09:45:17	#000000
113	151.216.29.0/26	2013-03-31 09:45:35	#000000
18	151.216.5.64/26	2013-03-31 09:45:49	#000000
89	151.216.23.0/26	2013-03-31 09:45:57	#000000
114	151.216.29.64/26	2013-03-31 09:46:29	#000000
87	151.216.22.128/26	2013-03-31 09:48:38	#000000
8	151.216.2.192/26	2013-03-31 09:53:10	#000000
46	151.216.12.64/26	2013-03-31 09:57:09	#000000
95	151.216.24.128/26	2013-03-31 09:58:08	#000000
72	151.216.18.192/26	2013-03-31 09:59:29	#000000
116	151.216.29.192/26	2013-03-31 10:01:14	#000000
17	151.216.5.0/26	2013-03-31 10:01:27	#000000
59	151.216.15.128/26	2013-03-31 10:12:07	#000000
68	151.216.17.192/26	2013-03-31 10:14:20	#000000
22	151.216.6.64/26	2013-03-31 10:14:22	#000000
90	151.216.23.64/26	2013-03-31 10:15:18	#000000
30	151.216.8.64/26	2013-03-31 10:15:46	#000000
56	151.216.14.192/26	2013-03-31 10:18:37	#000000
61	151.216.16.0/26	2013-03-31 10:21:12	#000000
126	151.216.32.64/26	2013-03-31 10:21:49	#000000
24	151.216.6.192/26	2013-03-31 10:22:31	#000000
43	151.216.11.128/26	2013-03-31 10:26:03	#000000
28	151.216.7.192/26	2013-03-31 10:26:04	#000000
71	151.216.18.128/26	2013-03-31 10:28:44	#000000
75	151.216.19.128/26	2013-03-31 10:29:05	#000000
101	151.216.26.0/26	2013-03-31 10:29:46	#000000
128	151.216.32.192/26	2013-03-31 10:30:46	#000000
55	151.216.14.128/26	2013-03-31 10:32:26	#000000
4	151.216.1.192/26	2013-03-31 10:33:55	#000000
99	151.216.25.128/26	2013-03-31 10:33:56	#000000
85	151.216.22.0/26	2013-03-31 10:34:46	#000000
67	151.216.17.128/26	2013-03-31 10:36:17	#000000
49	151.216.13.0/26	2013-03-31 10:36:21	#000000
44	151.216.11.192/26	2013-03-31 10:36:34	#000000
70	151.216.18.64/26	2013-03-31 10:37:05	#000000
94	151.216.24.64/26	2013-03-31 10:37:17	#000000
73	151.216.19.0/26	2013-03-31 10:37:28	#000000
10	151.216.3.64/26	2013-03-31 10:37:36	#000000
64	151.216.16.192/26	2013-03-31 10:37:39	#000000
119	151.216.30.128/26	2013-03-31 10:39:58	#000000
48	151.216.12.192/26	2013-03-31 10:40:55	#000000
33	151.216.9.0/26	2013-03-31 10:41:16	#000000
1	151.216.1.0/26	2013-03-31 10:42:04	#000000
32	151.216.8.192/26	2013-03-31 10:42:50	#000000
3	151.216.1.128/26	2013-03-31 10:43:20	#000000
84	151.216.21.192/26	2013-03-31 10:43:29	#000000
13	151.216.4.0/26	2013-03-31 10:43:35	#000000
105	151.216.27.0/26	2013-03-31 10:43:50	#000000
42	151.216.11.64/26	2013-03-31 10:44:06	#000000
21	151.216.6.0/26	2013-03-31 10:45:30	#000000
60	151.216.15.192/26	2013-03-31 10:46:00	#000000
82	151.216.21.64/26	2013-03-31 10:46:49	#000000
80	151.216.20.192/26	2013-03-31 10:48:02	#000000
9	151.216.3.0/26	2013-03-31 10:48:12	#000000
78	151.216.20.64/26	2013-03-31 10:49:10	#000000
40	151.216.10.192/26	2013-03-31 10:49:12	#000000
120	151.216.30.192/26	2013-03-31 10:49:56	#000000
51	151.216.13.128/26	2013-03-31 10:51:12	#000000
111	151.216.28.128/26	2013-03-31 10:51:49	#000000
36	151.216.9.192/26	2013-03-31 10:52:01	#000000
127	151.216.32.128/26	2013-03-31 10:52:05	#000000
98	151.216.25.64/26	2013-03-31 10:52:09	#000000
50	151.216.13.64/26	2013-03-31 10:52:31	#000000
20	151.216.5.192/26	2013-03-31 10:52:47	#000000
41	151.216.11.0/26	2013-03-31 10:53:03	#000000
58	151.216.15.64/26	2013-03-31 10:53:06	#000000
37	151.216.10.0/26	2013-03-31 10:53:13	#000000
76	151.216.19.192/26	2013-03-31 10:54:00	#000000
34	151.216.9.64/26	2013-03-31 10:54:04	#000000
45	151.216.12.0/26	2013-03-31 10:54:13	#000000
65	151.216.17.0/26	2013-03-31 10:54:45	#000000
96	151.216.24.192/26	2013-03-31 10:55:15	#000000
74	151.216.19.64/26	2013-03-31 10:55:25	#000000
6	151.216.2.64/26	2013-03-31 10:56:28	#000000
53	151.216.14.0/26	2013-03-31 10:56:42	#000000
63	151.216.16.128/26	2013-03-31 10:57:06	#000000
7	151.216.2.128/26	2013-03-31 10:57:08	#000000
122	151.216.31.64/26	2013-03-31 10:57:10	#000000
52	151.216.13.192/26	2013-03-31 10:57:23	#000000
19	151.216.5.128/26	2013-03-31 10:57:31	#000000
27	151.216.7.128/26	2013-03-31 10:57:52	#000000
124	151.216.31.192/26	2013-03-31 10:58:10	#000000
16	151.216.4.192/26	2013-03-31 10:58:22	#000000
62	151.216.16.64/26	2013-03-31 10:58:38	#000000
110	151.216.28.64/26	2013-03-31 10:58:42	#000000
5	151.216.2.0/26	2013-03-31 10:58:43	#000000
35	151.216.9.128/26	2013-03-31 10:58:43	#000000
81	151.216.21.0/26	2013-03-31 10:58:43	#000000
25	151.216.7.0/26	2013-03-31 10:58:51	#000000
117	151.216.30.0/26	2013-03-31 10:59:19	#000000
115	151.216.29.128/26	2013-03-31 10:59:53	#000000
14	151.216.4.64/26	2013-03-31 11:00:05	#000000
38	151.216.10.64/26	2013-03-31 11:00:19	#000000
77	151.216.20.0/26	2013-03-31 11:00:36	#000000
12	151.216.3.192/26	2013-03-31 11:01:02	#000000
109	151.216.28.0/26	2013-03-31 11:02:23	#000000
97	151.216.25.0/26	2013-03-31 11:02:25	#000000
123	151.216.31.128/26	2013-03-31 11:02:43	#000000
121	151.216.31.0/26	2013-03-31 11:02:52	#000000
88	151.216.22.192/26	2013-03-31 11:03:11	#000000
29	151.216.8.0/26	2013-03-31 11:03:45	#000000
86	151.216.22.64/26	2013-03-31 11:03:50	#000000
125	151.216.32.0/26	2013-03-31 11:04:08	#000000
118	151.216.30.64/26	2013-03-31 11:04:37	#000000
66	151.216.17.64/26	2013-03-31 11:05:14	#000000
112	151.216.28.192/26	2013-03-31 11:05:34	#000000
92	151.216.23.192/26	2013-03-31 11:06:12	#000000
69	151.216.18.0/26	2013-03-31 11:07:12	#000000
39	151.216.10.128/26	2013-03-31 11:07:35	#000000
54	151.216.14.64/26	2013-03-31 11:08:33	#000000
100	151.216.25.192/26	2013-03-31 11:08:35	#000000
\.


--
-- Data for Name: ipv4; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY ipv4 (mac, address, "time", age) FROM stdin;
\.


--
-- Data for Name: ipv6; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY ipv6 (mac, address, "time", age, vlan) FROM stdin;
\.


--
-- Data for Name: mbd_log; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY mbd_log (ts, game, port, description, active_servers) FROM stdin;
\.


--
-- Data for Name: mldpolls; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY mldpolls ("time", switch, mcast_group, count, raw_portlist) FROM stdin;
\.


--
-- Data for Name: placements; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY placements (switch, placement, zorder) FROM stdin;
1	(234,310),(220,226)	0
2	(234,226),(220,184)	0
3	(255,310),(241,226)	0
4	(255,226),(241,170)	0
5	(277,310),(263,226)	0
6	(277,226),(263,156)	0
7	(298,310),(284,226)	0
8	(298,226),(284,142)	0
9	(320,310),(306,226)	0
10	(320,226),(306,142)	0
11	(351,507),(337,423)	0
12	(351,423),(337,339)	0
13	(351,310),(337,226)	0
14	(351,226),(337,142)	0
15	(373,507),(359,423)	0
16	(373,423),(359,339)	0
17	(373,310),(359,226)	0
18	(373,226),(359,142)	0
19	(394,507),(380,423)	0
20	(394,423),(380,339)	0
21	(394,310),(380,226)	0
22	(394,226),(380,142)	0
23	(416,507),(402,423)	0
24	(416,423),(402,339)	0
25	(416,310),(402,226)	0
26	(416,226),(402,142)	0
27	(437,507),(423,423)	0
28	(437,423),(423,339)	0
29	(437,310),(423,226)	0
30	(437,226),(423,142)	0
31	(459,507),(445,423)	0
32	(459,423),(445,339)	0
33	(459,310),(445,226)	0
34	(459,226),(445,142)	0
35	(480,507),(466,423)	0
36	(480,423),(466,339)	0
37	(480,310),(466,226)	0
38	(480,226),(466,142)	0
39	(502,507),(488,423)	0
40	(502,423),(488,339)	0
41	(502,310),(488,226)	0
42	(502,226),(488,142)	0
43	(533,507),(519,423)	0
44	(533,423),(519,339)	0
45	(555,507),(541,423)	0
46	(555,423),(541,339)	0
47	(576,507),(562,423)	0
48	(576,423),(562,339)	0
49	(598,507),(584,423)	0
50	(598,423),(584,339)	0
51	(619,507),(605,423)	0
52	(619,423),(605,339)	0
53	(641,507),(627,423)	0
54	(641,423),(627,339)	0
55	(662,507),(648,423)	0
56	(662,423),(648,339)	0
57	(684,507),(670,423)	0
58	(684,423),(670,339)	0
59	(715,507),(701,423)	0
60	(715,423),(701,339)	0
61	(715,310),(701,226)	0
62	(715,226),(701,142)	0
63	(737,507),(723,423)	0
64	(737,423),(723,339)	0
65	(737,310),(723,226)	0
66	(737,226),(723,142)	0
67	(758,507),(744,423)	0
68	(758,423),(744,339)	0
69	(758,310),(744,226)	0
70	(758,226),(744,142)	0
71	(780,507),(766,423)	0
72	(780,423),(766,339)	0
73	(780,310),(766,226)	0
74	(780,226),(766,142)	0
75	(801,507),(787,423)	0
76	(801,423),(787,339)	0
77	(801,310),(787,226)	0
78	(801,226),(787,142)	0
79	(823,507),(809,423)	0
80	(823,423),(809,339)	0
81	(823,310),(809,226)	0
82	(823,226),(809,142)	0
83	(844,507),(830,423)	0
84	(844,423),(830,339)	0
85	(844,310),(830,226)	0
86	(844,226),(830,142)	0
87	(866,507),(852,423)	0
88	(866,423),(852,339)	0
89	(866,310),(852,226)	0
90	(866,226),(852,142)	0
91	(897,507),(883,423)	0
92	(897,423),(883,339)	0
93	(897,310),(883,226)	0
94	(897,226),(883,142)	0
95	(919,507),(905,423)	0
96	(919,423),(905,339)	0
97	(919,310),(905,226)	0
98	(919,226),(905,142)	0
99	(940,507),(926,423)	0
100	(940,423),(926,339)	0
101	(940,310),(926,226)	0
102	(940,226),(926,142)	0
103	(962,507),(948,423)	0
104	(962,423),(948,339)	0
105	(962,310),(948,226)	0
106	(962,226),(948,142)	0
107	(983,507),(969,423)	0
108	(983,423),(969,339)	0
109	(983,310),(969,226)	0
110	(983,226),(969,142)	0
111	(1005,507),(991,423)	0
112	(1005,423),(991,339)	0
113	(1005,310),(991,226)	0
114	(1005,226),(991,142)	0
115	(1026,507),(1012,423)	0
116	(1026,423),(1012,339)	0
117	(1026,310),(1012,226)	0
118	(1026,226),(1012,142)	0
119	(1048,507),(1034,423)	0
120	(1048,423),(1034,339)	0
121	(1048,310),(1034,226)	0
122	(1048,226),(1034,142)	0
123	(1069,507),(1055,423)	0
124	(1069,423),(1055,339)	0
125	(1069,310),(1055,226)	0
126	(1069,226),(1055,142)	0
127	(1091,493),(1077,423)	0
128	(1091,423),(1077,339)	0
130	(1180,530),(1150,500)	1
131	(1280,330),(1250,300)	1
134	(830,130),(800,100)	1
135	(1130,340),(1100,310)	1
140	(360,340),(330,310)	1
141	(460,340),(430,310)	1
142	(730,340),(700,310)	1
143	(800,340),(770,310)	1
144	(1000,340),(970,310)	1
136	(160,340),(130,310)	1
132	(680,80),(650,50)	1
133	(680,130),(650,100)	1
137	(430,600),(400,570)	1
139	(730,600),(700,570)	1
138	(630,600),(600,570)	1
129	(780,600),(750,570)	1
360	(866,507),(852,423)	0
359	(844,226),(830,142)	0
361	(866,423),(852,339)	0
397	(1069,423),(1055,339)	0
379	(962,226),(948,142)	0
373	(940,423),(926,339)	0
297	(416,423),(402,339)	0
300	(437,507),(423,423)	0
321	(576,423),(562,339)	0
288	(373,507),(359,423)	0
332	(715,507),(701,423)	0
325	(619,423),(605,339)	0
326	(641,507),(627,423)	0
381	(983,423),(969,339)	0
335	(715,226),(701,142)	0
305	(459,423),(445,339)	0
368	(919,507),(905,423)	0
296	(416,507),(402,423)	0
316	(533,507),(519,423)	0
376	(962,507),(948,423)	0
357	(844,423),(830,339)	0
286	(351,310),(337,226)	0
327	(641,423),(627,339)	0
280	(298,310),(284,226)	0
369	(919,423),(905,339)	0
298	(416,310),(402,226)	0
307	(459,226),(445,142)	0
336	(737,507),(723,423)	0
328	(662,507),(648,423)	0
399	(1069,226),(1055,142)	0
378	(962,310),(948,226)	0
292	(394,507),(380,423)	0
314	(502,310),(488,226)	0
333	(715,423),(701,339)	0
275	(234,226),(220,184)	0
380	(983,507),(969,423)	0
363	(866,226),(852,142)	0
371	(919,226),(905,142)	0
295	(394,226),(380,142)	0
322	(598,507),(584,423)	0
313	(502,423),(488,339)	0
337	(737,423),(723,339)	0
329	(662,423),(648,339)	0
372	(940,507),(926,423)	0
370	(919,310),(905,226)	0
334	(715,310),(701,226)	0
277	(255,226),(241,170)	0
377	(962,423),(948,339)	0
382	(983,310),(969,226)	0
294	(394,310),(380,226)	0
338	(737,310),(723,226)	0
331	(684,423),(670,339)	0
276	(255,310),(241,226)	0
367	(897,226),(883,142)	0
365	(897,423),(883,339)	0
274	(234,310),(220,226)	0
278	(277,310),(263,226)	0
323	(598,423),(584,339)	0
315	(502,226),(488,142)	0
358	(844,310),(830,226)	0
383	(983,226),(969,142)	0
364	(897,507),(883,423)	0
289	(373,423),(359,339)	0
374	(940,310),(926,226)	0
339	(737,226),(723,142)	0
340	(758,507),(744,423)	0
320	(576,507),(562,423)	0
279	(277,226),(263,156)	0
400	(1091,493),(1077,423)	0
356	(844,507),(830,423)	0
285	(351,423),(337,339)	0
398	(1069,310),(1055,226)	0
384	(1005,507),(991,423)	0
302	(437,310),(423,226)	0
391	(1026,226),(1012,142)	0
394	(1048,310),(1034,226)	0
318	(555,507),(541,423)	0
341	(758,423),(744,339)	0
319	(555,423),(541,339)	0
342	(758,310),(744,226)	0
395	(1048,226),(1034,142)	0
304	(459,507),(445,423)	0
401	(1091,423),(1077,339)	0
343	(758,226),(744,142)	0
385	(1005,423),(991,339)	0
312	(502,507),(488,423)	0
392	(1048,507),(1034,423)	0
291	(373,226),(359,142)	0
344	(780,507),(766,423)	0
396	(1069,507),(1055,423)	0
345	(780,423),(766,339)	0
386	(1005,310),(991,226)	0
306	(459,310),(445,226)	0
355	(823,226),(809,142)	0
293	(394,423),(380,339)	0
346	(780,310),(766,226)	0
283	(320,226),(306,142)	0
347	(780,226),(766,142)	0
387	(1005,226),(991,142)	0
330	(684,507),(670,423)	0
290	(373,310),(359,226)	0
303	(437,226),(423,142)	0
317	(533,423),(519,339)	0
348	(801,507),(787,423)	0
366	(897,310),(883,226)	0
301	(437,423),(423,339)	0
362	(866,310),(852,226)	0
388	(1026,507),(1012,423)	0
281	(298,226),(284,142)	0
349	(801,423),(787,339)	0
393	(1048,423),(1034,339)	0
350	(801,310),(787,226)	0
308	(480,507),(466,423)	0
311	(480,226),(466,142)	0
351	(801,226),(787,142)	0
389	(1026,423),(1012,339)	0
375	(940,226),(926,142)	0
287	(351,226),(337,142)	0
310	(480,310),(466,226)	0
282	(320,310),(306,226)	0
352	(823,507),(809,423)	0
390	(1026,310),(1012,226)	0
353	(823,423),(809,339)	0
284	(351,507),(337,423)	0
324	(619,507),(605,423)	0
354	(823,310),(809,226)	0
299	(416,226),(402,142)	0
309	(480,423),(466,339)	0
402	(460,340),(430,310)	1
403	(730,340),(700,310)	1
404	(800,340),(770,310)	1
405	(360,340),(330,310)	1
406	(1000,340),(970,310)	1
407	(1130,310),(1076,296)	0
408	(1190,310),(1136,296)	0
409	(1130,290),(1076,276)	0
410	(1190,290),(1136,276)	0
411	(1130,270),(1076,256)	0
412	(1190,270),(1136,256)	0
413	(1130,250),(1076,236)	0
414	(1190,250),(1136,236)	0
415	(1164,230),(1076,216)	0
416	(1164,210),(1076,196)	0
417	(1164,190),(1076,176)	0
\.


--
-- Data for Name: polls; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY polls ("time", switch, port, bytes_in, bytes_out, errors_in, errors_out) FROM stdin;
\.


--
-- Name: polls_poll_seq; Type: SEQUENCE SET; Schema: public; Owner: nms
--

SELECT pg_catalog.setval('polls_poll_seq', 1, false);


--
-- Data for Name: portnames; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY portnames (switchtype, port, description) FROM stdin;
dlink3100	1	Ethernet Interface (port 1)
dlink3100	2	Ethernet Interface (port 2)
dlink3100	3	Ethernet Interface (port 3)
dlink3100	4	Ethernet Interface (port 4)
dlink3100	5	Ethernet Interface (port 5)
dlink3100	6	Ethernet Interface (port 6)
dlink3100	7	Ethernet Interface (port 7)
dlink3100	8	Ethernet Interface (port 8)
dlink3100	9	Ethernet Interface (port 9)
dlink3100	10	Ethernet Interface (port 10)
dlink3100	11	Ethernet Interface (port 11)
dlink3100	12	Ethernet Interface (port 12)
dlink3100	13	Ethernet Interface (port 13)
dlink3100	14	Ethernet Interface (port 14)
dlink3100	15	Ethernet Interface (port 15)
dlink3100	16	Ethernet Interface (port 16)
dlink3100	17	Ethernet Interface (port 17)
dlink3100	18	Ethernet Interface (port 18)
dlink3100	19	Ethernet Interface (port 19)
dlink3100	20	Ethernet Interface (port 20)
dlink3100	21	Ethernet Interface (port 21)
dlink3100	22	Ethernet Interface (port 22)
dlink3100	23	Ethernet Interface (port 23)
dlink3100	24	Ethernet Interface (port 24)
dlink3100	25	Ethernet Interface (port 25)
dlink3100	26	Ethernet Interface (port 26)
dlink3100	27	Ethernet Interface (port 27)
dlink3100	28	Ethernet Interface (port 28)
dlink3100	29	Ethernet Interface (port 29)
dlink3100	30	Ethernet Interface (port 30)
dlink3100	31	Ethernet Interface (port 31)
dlink3100	32	Ethernet Interface (port 32)
dlink3100	33	Ethernet Interface (port 33)
dlink3100	34	Ethernet Interface (port 34)
dlink3100	35	Ethernet Interface (port 35)
dlink3100	36	Ethernet Interface (port 36)
dlink3100	37	Ethernet Interface (port 37)
dlink3100	38	Ethernet Interface (port 38)
dlink3100	39	Ethernet Interface (port 39)
dlink3100	40	Ethernet Interface (port 40)
dlink3100	41	Ethernet Interface (port 41)
dlink3100	42	Ethernet Interface (port 42)
dlink3100	43	Ethernet Interface (port 43)
dlink3100	44	Ethernet Interface (port 44)
dlink3100	45	Ethernet Interface (port 45)
dlink3100	46	Ethernet Interface (port 46)
dlink3100	47	Ethernet Interface (port 47)
dlink3100	48	Ethernet Interface (port 48)
dlink3100	301	Ethernet Interface (port 301)
dlink3100	302	Ethernet Interface (port 302)
dlink3100	303	Ethernet Interface (port 303)
dlink3100	304	Ethernet Interface (port 304)
dlink3100	305	Ethernet Interface (port 305)
dlink3100	306	Ethernet Interface (port 306)
dlink3100	307	Ethernet Interface (port 307)
dlink3100	308	Ethernet Interface (port 308)
dlink3100	309	Ethernet Interface (port 309)
dlink3100	310	Ethernet Interface (port 310)
dlink3100	311	Ethernet Interface (port 311)
dlink3100	312	Ethernet Interface (port 312)
dlink3100	313	Ethernet Interface (port 313)
dlink3100	314	Ethernet Interface (port 314)
dlink3100	315	Ethernet Interface (port 315)
dlink3100	316	Ethernet Interface (port 316)
dlink3100	317	Ethernet Interface (port 317)
dlink3100	318	Ethernet Interface (port 318)
dlink3100	319	Ethernet Interface (port 319)
dlink3100	320	Ethernet Interface (port 320)
dlink3100	321	Ethernet Interface (port 321)
dlink3100	322	Ethernet Interface (port 322)
dlink3100	323	Ethernet Interface (port 323)
dlink3100	324	Ethernet Interface (port 324)
dlink3100	325	Ethernet Interface (port 325)
dlink3100	326	Ethernet Interface (port 326)
dlink3100	327	Ethernet Interface (port 327)
dlink3100	328	Ethernet Interface (port 328)
dlink3100	329	Ethernet Interface (port 329)
dlink3100	330	Ethernet Interface (port 330)
dlink3100	331	Ethernet Interface (port 331)
dlink3100	332	Ethernet Interface (port 332)
dlink3100	9000	Internal Interface (port 9000)
dlink3100	100000	vlan (port 100000)
\.


--
-- Data for Name: squeue; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY squeue (id, gid, added, updated, addr, cmd, locked, processed, disabled, priority, sysname, author, result, delay, delaytime) FROM stdin;
\.


--
-- Name: squeue_group_sequence; Type: SEQUENCE SET; Schema: public; Owner: nms
--

SELECT pg_catalog.setval('squeue_group_sequence', 71, true);


--
-- Name: squeue_sequence; Type: SEQUENCE SET; Schema: public; Owner: nms
--

SELECT pg_catalog.setval('squeue_sequence', 3324, true);


--
-- Name: stemppoll_sequence; Type: SEQUENCE SET; Schema: public; Owner: nms
--

SELECT pg_catalog.setval('stemppoll_sequence', 1, false);


--
-- Data for Name: switches; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY switches (switch, ip, sysname, switchtype, last_updated, locked, priority, poll_frequency, community) FROM stdin;
320	127.0.0.1	ap-e31-1	ciscoap	2013-03-31 14:03:35.163353+02	f	0	00:05:00	<removed>
380	127.0.0.1	ap-e67-1	ciscoap	2013-03-31 14:03:45.678972+02	f	0	00:05:00	<removed>
301	127.0.0.1	ap-e19-2	ciscoap	2013-03-31 14:04:15.974348+02	f	0	00:05:00	<removed>
89	151.216.23.2	e57-3	dlink3100	2013-03-31 14:09:08.899489+02	f	0	00:01:00	<removed>
32	151.216.8.194	e21-2	dlink3100	2013-03-31 14:09:19.750092+02	f	0	00:01:00	<removed>
407	151.216.50.2	creativiasw01	dlink3100	2013-03-31 14:09:29.799659+02	f	0	00:01:00	<removed>
121	151.216.31.2	e73-3	dlink3100	2013-03-31 14:09:39.03767+02	f	0	00:01:00	<removed>
3	151.216.1.130	e3-3	dlink3100	2013-03-31 14:10:38.32422+02	f	0	00:01:00	<removed>
57	151.216.15.2	e41-1	dlink3100	2013-03-31 14:10:46.324438+02	f	0	00:01:00	<removed>
97	151.216.25.2	e61-3	dlink3100	2013-03-31 14:10:56.366466+02	f	0	00:01:00	<removed>
108	151.216.27.194	e67-2	dlink3100	2013-03-31 14:11:06.409468+02	f	0	00:01:00	<removed>
65	151.216.17.2	e45-3	dlink3100	2013-03-31 14:11:16.450631+02	f	0	00:01:00	<removed>
416	151.216.50.11	creativiasw10	dlink3100	2013-03-31 14:11:29.776178+02	f	0	00:01:00	<removed>
22	151.216.6.66	e15-4	dlink3100	2013-03-31 14:11:40.601614+02	f	0	00:01:00	<removed>
30	151.216.8.66	e19-4	dlink3100	2013-03-31 14:11:49.857971+02	f	0	00:01:00	<removed>
18	151.216.5.66	e13-4	dlink3100	2013-03-31 14:12:00.689688+02	f	0	00:01:00	<removed>
43	151.216.11.130	e27-1	dlink3100	2013-03-31 14:12:10.733619+02	f	0	00:01:00	<removed>
24	151.216.6.194	e17-2	dlink3100	2013-03-31 14:12:19.983821+02	f	0	00:01:00	<removed>
4	151.216.1.194	e3-4	dlink3100	2013-03-31 14:12:30.025734+02	f	0	00:01:00	<removed>
31	151.216.8.130	e21-1	dlink3100	2013-03-31 14:09:05.474089+02	f	0	00:01:00	<removed>
47	151.216.12.130	e31-1	dlink3100	2013-03-31 14:12:40.068048+02	f	0	00:01:00	<removed>
92	151.216.23.194	e59-2	dlink3100	2013-03-31 14:09:15.523555+02	f	0	00:01:00	<removed>
33	151.216.9.2	e21-3	dlink3100	2013-03-31 14:09:25.573946+02	f	0	00:01:00	<removed>
20	151.216.5.194	e15-2	dlink3100	2013-03-31 14:09:35.626024+02	f	0	00:01:00	<removed>
133	151.216.127.5	wtfgw	wtfgw	2013-03-31 14:09:35.670908+02	f	0	00:01:00	<removed>
28	151.216.7.194	e19-2	dlink3100	2013-03-31 14:09:45.955527+02	f	0	00:01:00	<removed>
67	151.216.17.130	e47-1	dlink3100	2013-03-31 14:09:58.029684+02	f	0	00:01:00	<removed>
26	151.216.7.66	e17-4	dlink3100	2013-03-31 14:10:08.127872+02	f	0	00:01:00	<removed>
102	151.216.26.66	e63-4	dlink3100	2013-03-31 14:10:16.136217+02	f	0	00:01:00	<removed>
125	151.216.32.2	e75-3	dlink3100	2013-03-31 14:10:26.181503+02	f	0	00:01:00	<removed>
130	151.216.127.1	telegw	telegw	2013-03-31 14:07:58.60478+02	f	0	00:01:00	<removed>
412	151.216.50.7	creativiasw06	dlink3100	2013-03-31 14:09:09.699614+02	f	0	00:01:00	<removed>
128	151.216.32.194	e77-2	dlink3100	2013-03-31 14:09:27.615732+02	f	0	00:01:00	<removed>
408	151.216.50.3	creativiasw02	dlink3100	2013-03-31 14:09:37.667708+02	f	0	00:01:00	<removed>
417	151.216.50.12	creativiasw11	dlink3100	2013-03-31 14:09:47.935097+02	f	0	00:01:00	<removed>
127	151.216.32.130	e77-1	dlink3100	2013-03-31 14:09:56.039513+02	f	0	00:01:00	<removed>
376	127.0.0.1	ap-e65-1	ciscoap	2013-03-31 14:03:45.695637+02	f	0	00:05:00	<removed>
112	151.216.28.194	e69-2	dlink3100	2013-03-31 14:10:06.089831+02	f	0	00:01:00	<removed>
9	151.216.3.2	e9-3	dlink3100	2013-03-31 14:10:18.178421+02	f	0	00:01:00	<removed>
83	151.216.21.130	e55-1	dlink3100	2013-03-31 14:10:28.282289+02	f	0	00:01:00	<removed>
13	151.216.4.2	e11-3	dlink3100	2013-03-31 14:10:30.307108+02	f	0	00:01:00	<removed>
343	127.0.0.1	ap-e47-4	ciscoap	2013-03-31 14:04:46.367004+02	f	0	00:05:00	<removed>
45	151.216.12.2	e29-1	dlink3100	2013-03-31 14:10:39.315785+02	f	0	00:01:00	<removed>
297	127.0.0.1	ap-e17-2	ciscoap	2013-03-31 14:04:46.750319+02	f	0	00:05:00	<removed>
293	127.0.0.1	ap-e15-2	ciscoap	2013-03-31 14:05:06.492611+02	f	0	00:05:00	<removed>
350	127.0.0.1	ap-e51-3	ciscoap	2013-03-31 14:05:06.525983+02	f	0	00:05:00	<removed>
363	127.0.0.1	ap-e57-4	ciscoap	2013-03-31 14:05:16.625481+02	f	0	00:05:00	<removed>
368	127.0.0.1	ap-e61-1	ciscoap	2013-03-31 14:05:16.700464+02	f	0	00:05:00	<removed>
388	127.0.0.1	ap-e71-1	ciscoap	2013-03-31 14:05:26.787007+02	f	0	00:05:00	<removed>
304	127.0.0.1	ap-e21-1	ciscoap	2013-03-31 14:05:26.853688+02	f	0	00:05:00	<removed>
352	127.0.0.1	ap-e53-1	ciscoap	2013-03-31 14:05:26.887026+02	f	0	00:05:00	<removed>
323	127.0.0.1	ap-e33-2	ciscoap	2013-03-31 14:05:26.912028+02	f	0	00:05:00	<removed>
406	127.0.0.1	ap-distro4	ciscoap	2013-03-31 14:05:27.045455+02	f	0	00:05:00	<removed>
339	127.0.0.1	ap-e45-4	ciscoap	2013-03-31 14:05:27.053748+02	f	0	00:05:00	<removed>
393	127.0.0.1	ap-e73-2	ciscoap	2013-03-31 14:04:26.17466+02	f	0	00:05:00	<removed>
337	127.0.0.1	ap-e45-2	ciscoap	2013-03-31 14:04:26.191324+02	f	0	00:05:00	<removed>
384	127.0.0.1	ap-e69-1	ciscoap	2013-03-31 14:04:26.207988+02	f	0	00:05:00	<removed>
387	127.0.0.1	ap-e69-4	ciscoap	2013-03-31 14:04:26.224645+02	f	0	00:05:00	<removed>
371	127.0.0.1	ap-e61-4	ciscoap	2013-03-31 14:04:36.283297+02	f	0	00:05:00	<removed>
398	127.0.0.1	ap-e75-3	ciscoap	2013-03-31 14:04:46.333668+02	f	0	00:05:00	<removed>
351	127.0.0.1	ap-e51-4	ciscoap	2013-03-31 14:04:46.350332+02	f	0	00:05:00	<removed>
356	127.0.0.1	ap-e55-1	ciscoap	2013-03-31 14:04:46.383667+02	f	0	00:05:00	<removed>
389	127.0.0.1	ap-e71-2	ciscoap	2013-03-31 14:04:46.733636+02	f	0	00:05:00	<removed>
372	127.0.0.1	ap-e63-1	ciscoap	2013-03-31 14:05:06.509265+02	f	0	00:05:00	<removed>
328	127.0.0.1	ap-e39-1	ciscoap	2013-03-31 14:05:16.608766+02	f	0	00:05:00	<removed>
5	151.216.2.2	e5-3	dlink3100	2013-03-31 14:09:17.565638+02	f	0	00:01:00	<removed>
50	151.216.13.66	e33-2	dlink3100	2013-03-31 14:09:18.937921+02	f	0	00:01:00	<removed>
103	151.216.26.130	e65-1	dlink3100	2013-03-31 14:09:28.988094+02	f	0	00:01:00	<removed>
91	151.216.23.130	e59-1	dlink3100	2013-03-31 14:09:39.851074+02	f	0	00:01:00	<removed>
63	151.216.16.130	e45-1	dlink3100	2013-03-31 14:09:49.897376+02	f	0	00:01:00	<removed>
7	151.216.2.130	e7-3	dlink3100	2013-03-31 14:09:59.947741+02	f	0	00:01:00	<removed>
100	151.216.25.194	e63-2	dlink3100	2013-03-31 14:10:10.223204+02	f	0	00:01:00	<removed>
84	151.216.21.194	e55-2	dlink3100	2013-03-31 14:10:19.231795+02	f	0	00:01:00	<removed>
126	151.216.32.66	e75-4	dlink3100	2013-03-31 14:10:29.273823+02	f	0	00:01:00	<removed>
361	127.0.0.1	ap-e57-2	ciscoap	2013-03-31 14:04:16.074284+02	f	0	00:05:00	<removed>
312	127.0.0.1	ap-e25-1	ciscoap	2013-03-31 14:04:26.124587+02	f	0	00:05:00	<removed>
310	127.0.0.1	ap-e23-3	ciscoap	2013-03-31 14:04:26.141221+02	f	0	00:05:00	<removed>
308	127.0.0.1	ap-e23-1	ciscoap	2013-03-31 14:04:26.157994+02	f	0	00:05:00	<removed>
104	151.216.26.194	e65-2	dlink3100	2013-03-31 14:10:09.189552+02	f	0	00:01:00	<removed>
119	151.216.30.130	e73-1	dlink3100	2013-03-31 14:12:40.859661+02	f	0	00:01:00	<removed>
69	151.216.18.2	e47-3	dlink3100	2013-03-31 14:10:20.265181+02	f	0	00:01:00	<removed>
37	151.216.10.2	e23-3	dlink3100	2013-03-31 14:12:40.88249+02	t	0	00:01:00	<removed>
325	127.0.0.1	ap-e35-2	ciscoap	2013-03-31 14:06:47.598526+02	f	0	00:05:00	<removed>
52	151.216.13.194	e35-2	dlink3100	2013-03-31 14:10:36.22414+02	f	0	00:01:00	<removed>
399	127.0.0.1	ap-e75-4	ciscoap	2013-03-31 14:06:54.140511+02	f	0	00:05:00	<removed>
401	127.0.0.1	ap-e77-2	ciscoap	2013-03-31 14:05:06.475953+02	f	0	00:05:00	<removed>
109	151.216.28.2	e67-3	dlink3100	2013-03-31 14:10:40.349205+02	f	0	00:01:00	<removed>
123	151.216.31.130	e75-1	dlink3100	2013-03-31 14:10:49.357742+02	f	0	00:01:00	<removed>
332	127.0.0.1	ap-e43-1	ciscoap	2013-03-31 14:06:54.157133+02	f	0	00:05:00	<removed>
98	151.216.25.66	e61-4	dlink3100	2013-03-31 14:06:56.826042+02	f	0	00:01:00	<removed>
117	151.216.30.2	e71-3	dlink3100	2013-03-31 14:10:59.399785+02	f	0	00:01:00	<removed>
101	151.216.26.2	e63-3	dlink3100	2013-03-31 14:11:09.441726+02	f	0	00:01:00	<removed>
39	151.216.10.130	e25-1	dlink3100	2013-03-31 14:11:20.517295+02	f	0	00:01:00	<removed>
290	127.0.0.1	ap-e13-3	ciscoap	2013-03-31 14:05:16.592114+02	f	0	00:05:00	<removed>
345	127.0.0.1	ap-e49-2	ciscoap	2013-03-31 14:06:57.657385+02	f	0	00:05:00	<removed>
366	127.0.0.1	ap-e59-3	ciscoap	2013-03-31 14:06:57.665697+02	f	0	00:05:00	<removed>
392	127.0.0.1	ap-e73-1	ciscoap	2013-03-31 14:04:15.990948+02	f	0	00:05:00	<removed>
355	127.0.0.1	ap-e53-4	ciscoap	2013-03-31 14:05:16.658807+02	f	0	00:05:00	<removed>
86	151.216.22.66	e55-4	dlink3100	2013-03-31 14:11:30.559419+02	f	0	00:01:00	<removed>
277	127.0.0.1	ap-e3-4	ciscoap	2013-03-31 14:04:16.007613+02	f	0	00:05:00	<removed>
40	151.216.10.194	e25-2	dlink3100	2013-03-31 14:11:39.818373+02	f	0	00:01:00	<removed>
314	127.0.0.1	ap-e25-3	ciscoap	2013-03-31 14:04:16.024289+02	f	0	00:05:00	<removed>
289	127.0.0.1	ap-e13-2	ciscoap	2013-03-31 14:06:57.724049+02	f	0	00:05:00	<removed>
2	151.216.1.66	e1-4	dlink3100	2013-03-31 14:11:50.641091+02	f	0	00:01:00	<removed>
302	127.0.0.1	ap-e19-3	ciscoap	2013-03-31 14:06:57.732372+02	f	0	00:05:00	<removed>
99	151.216.25.130	e63-1	dlink3100	2013-03-31 14:11:59.899883+02	f	0	00:01:00	<removed>
344	127.0.0.1	ap-e49-1	ciscoap	2013-03-31 14:04:16.04092+02	f	0	00:05:00	<removed>
335	127.0.0.1	ap-e43-4	ciscoap	2013-03-31 14:06:57.799008+02	f	0	00:05:00	<removed>
279	127.0.0.1	ap-e5-4	ciscoap	2013-03-31 14:04:16.057621+02	f	0	00:05:00	<removed>
38	151.216.10.66	e23-4	dlink3100	2013-03-31 14:12:09.94159+02	f	0	00:01:00	<removed>
285	127.0.0.1	ap-e11-2	ciscoap	2013-03-31 14:06:57.824055+02	f	0	00:05:00	<removed>
404	127.0.0.1	ap-distro3	ciscoap	2013-03-31 14:06:57.832368+02	f	0	00:05:00	<removed>
21	151.216.6.2	e15-3	dlink3100	2013-03-31 14:12:20.775526+02	f	0	00:01:00	<removed>
131	151.216.127.3	camgw	camgw	2013-03-31 14:08:59.442796+02	f	0	00:01:00	<removed>
415	151.216.50.10	creativiasw09	dlink3100	2013-03-31 14:09:49.089144+02	f	0	00:01:00	<removed>
23	151.216.6.130	e17-1	dlink3100	2013-03-31 14:12:30.817401+02	f	0	00:01:00	<removed>
140	151.216.127.17	distro0	distro0	2013-03-31 14:09:59.139467+02	f	0	00:01:00	<removed>
303	127.0.0.1	ap-e19-4	ciscoap	2013-03-31 14:05:27.020371+02	f	0	00:05:00	<removed>
348	127.0.0.1	ap-e51-1	ciscoap	2013-03-31 14:07:14.399896+02	f	0	00:05:00	<removed>
46	151.216.12.66	e29-2	dlink3100	2013-03-31 14:11:58.658094+02	f	0	00:01:00	<removed>
311	127.0.0.1	ap-e23-4	ciscoap	2013-03-31 14:07:14.433216+02	f	0	00:05:00	<removed>
6	151.216.2.66	e5-4	dlink3100	2013-03-31 14:12:08.075251+02	f	0	00:01:00	<removed>
61	151.216.16.2	e43-3	dlink3100	2013-03-31 14:12:18.115548+02	f	0	00:01:00	<removed>
281	127.0.0.1	ap-e7-4	ciscoap	2013-03-31 14:07:14.449892+02	f	0	00:05:00	<removed>
42	151.216.11.66	e25-4	dlink3100	2013-03-31 14:12:28.78394+02	f	0	00:01:00	<removed>
124	151.216.31.194	e75-2	dlink3100	2013-03-31 14:12:38.82574+02	f	0	00:01:00	<removed>
341	127.0.0.1	ap-e47-2	ciscoap	2013-03-31 14:07:14.49997+02	f	0	00:05:00	<removed>
394	127.0.0.1	ap-e73-3	ciscoap	2013-03-31 14:07:18.250168+02	f	0	00:05:00	<removed>
134	151.216.127.6	logistikkgw	logistikkgw	2013-03-31 14:09:37.70706+02	f	0	00:01:00	<removed>
296	127.0.0.1	ap-e17-1	ciscoap	2013-03-31 14:05:16.642148+02	f	0	00:05:00	<removed>
342	127.0.0.1	ap-e47-3	ciscoap	2013-03-31 14:05:16.683807+02	f	0	00:05:00	<removed>
138	151.216.127.14	sponsorgw	sponsorgw	2013-03-31 14:10:36.296979+02	f	0	00:01:00	<removed>
300	127.0.0.1	ap-e19-1	ciscoap	2013-03-31 14:05:26.753695+02	f	0	00:05:00	<removed>
74	151.216.19.66	e49-4	dlink3100	2013-03-31 14:10:48.366303+02	f	0	00:01:00	<removed>
90	151.216.23.66	e57-4	dlink3100	2013-03-31 14:10:50.391178+02	f	0	00:01:00	<removed>
364	127.0.0.1	ap-e59-1	ciscoap	2013-03-31 14:06:57.699034+02	f	0	00:05:00	<removed>
14	151.216.4.66	e11-4	dlink3100	2013-03-31 14:11:00.431572+02	f	0	00:01:00	<removed>
280	127.0.0.1	ap-e7-3	ciscoap	2013-03-31 14:05:26.803681+02	f	0	00:05:00	<removed>
357	127.0.0.1	ap-e55-2	ciscoap	2013-03-31 14:06:57.757379+02	f	0	00:05:00	<removed>
144	151.216.127.21	distro4	distro4	2013-03-31 14:11:18.492445+02	f	0	00:01:00	<removed>
19	151.216.5.130	e15-1	dlink3100	2013-03-31 14:11:19.483883+02	f	0	00:01:00	<removed>
307	127.0.0.1	ap-e21-4	ciscoap	2013-03-31 14:06:57.790715+02	f	0	00:05:00	<removed>
85	151.216.22.2	e55-3	dlink3100	2013-03-31 14:11:38.576512+02	f	0	00:01:00	<removed>
286	127.0.0.1	ap-e11-3	ciscoap	2013-03-31 14:05:26.837029+02	f	0	00:05:00	<removed>
369	127.0.0.1	ap-e61-2	ciscoap	2013-03-31 14:06:57.857392+02	f	0	00:05:00	<removed>
10	151.216.3.66	e9-4	dlink3100	2013-03-31 14:11:48.616108+02	f	0	00:01:00	<removed>
385	127.0.0.1	ap-e69-2	ciscoap	2013-03-31 14:07:07.916359+02	f	0	00:05:00	<removed>
288	127.0.0.1	ap-e13-1	ciscoap	2013-03-31 14:05:26.945339+02	f	0	00:05:00	<removed>
282	127.0.0.1	ap-e9-3	ciscoap	2013-03-31 14:07:07.924585+02	f	0	00:05:00	<removed>
358	127.0.0.1	ap-e55-3	ciscoap	2013-03-31 14:05:26.953679+02	f	0	00:05:00	<removed>
396	127.0.0.1	ap-e75-1	ciscoap	2013-03-31 14:07:14.333223+02	f	0	00:05:00	<removed>
374	127.0.0.1	ap-e63-3	ciscoap	2013-03-31 14:07:14.349887+02	f	0	00:05:00	<removed>
365	127.0.0.1	ap-e59-2	ciscoap	2013-03-31 14:05:26.978658+02	f	0	00:05:00	<removed>
276	127.0.0.1	ap-e3-3	ciscoap	2013-03-31 14:05:26.987059+02	f	0	00:05:00	<removed>
334	127.0.0.1	ap-e43-3	ciscoap	2013-03-31 14:05:27.012008+02	f	0	00:05:00	<removed>
382	127.0.0.1	ap-e67-3	ciscoap	2013-03-31 14:07:14.466569+02	f	0	00:05:00	<removed>
62	151.216.16.66	e43-4	dlink3100	2013-03-31 14:12:08.699458+02	f	0	00:01:00	<removed>
275	127.0.0.1	ap-e1-4	ciscoap	2013-03-31 14:07:14.483301+02	f	0	00:05:00	<removed>
36	151.216.9.194	e23-2	dlink3100	2013-03-31 14:12:18.742024+02	f	0	00:01:00	<removed>
51	151.216.13.130	e35-1	dlink3100	2013-03-31 14:12:28.217471+02	f	0	00:01:00	<removed>
324	127.0.0.1	ap-e35-1	ciscoap	2013-03-31 14:07:14.516632+02	f	0	00:05:00	<removed>
1	151.216.1.2	e1-3	dlink3100	2013-03-31 14:12:38.299693+02	f	0	00:01:00	<removed>
291	127.0.0.1	ap-e13-4	ciscoap	2013-03-31 14:05:47.253657+02	f	0	00:05:00	<removed>
381	127.0.0.1	ap-e67-2	ciscoap	2013-03-31 14:07:14.533237+02	f	0	00:05:00	<removed>
395	127.0.0.1	ap-e73-4	ciscoap	2013-03-31 14:05:47.261963+02	f	0	00:05:00	<removed>
298	127.0.0.1	ap-e17-3	ciscoap	2013-03-31 14:07:18.24186+02	f	0	00:05:00	<removed>
375	127.0.0.1	ap-e63-4	ciscoap	2013-03-31 14:05:26.770358+02	f	0	00:05:00	<removed>
402	127.0.0.1	ap-distro1	ciscoap	2013-03-31 14:05:47.286984+02	f	0	00:05:00	<removed>
278	127.0.0.1	ap-e5-3	ciscoap	2013-03-31 14:07:18.275213+02	f	0	00:05:00	<removed>
349	127.0.0.1	ap-e51-2	ciscoap	2013-03-31 14:05:26.820365+02	f	0	00:05:00	<removed>
390	127.0.0.1	ap-e71-3	ciscoap	2013-03-31 14:05:26.870368+02	f	0	00:05:00	<removed>
135	151.216.127.9	crewgw	crewgw	2013-03-31 14:09:59.991016+02	f	0	00:01:00	<removed>
88	151.216.22.194	e57-2	dlink3100	2013-03-31 14:10:58.408324+02	f	0	00:01:00	<removed>
378	127.0.0.1	ap-e65-3	ciscoap	2013-03-31 14:05:26.920352+02	f	0	00:05:00	<removed>
64	151.216.16.194	e45-2	dlink3100	2013-03-31 14:11:08.451146+02	f	0	00:01:00	<removed>
141	151.216.127.18	distro1	distro1	2013-03-31 14:11:10.476036+02	f	0	00:01:00	<removed>
397	127.0.0.1	ap-e75-2	ciscoap	2013-03-31 14:06:57.690716+02	f	0	00:05:00	<removed>
142	151.216.127.19	distro2	distro2	2013-03-31 14:11:26.53242+02	f	0	00:01:00	<removed>
336	127.0.0.1	ap-e45-1	ciscoap	2013-03-31 14:05:37.128164+02	f	0	00:05:00	<removed>
370	127.0.0.1	ap-e61-3	ciscoap	2013-03-31 14:05:37.136492+02	f	0	00:05:00	<removed>
340	127.0.0.1	ap-e47-1	ciscoap	2013-03-31 14:06:57.765706+02	f	0	00:05:00	<removed>
137	151.216.127.12	resepsjongw	resepsjongw	2013-03-31 14:11:28.534488+02	f	0	00:01:00	<removed>
71	151.216.18.130	e49-1	dlink3100	2013-03-31 14:11:36.567717+02	f	0	00:01:00	<removed>
319	127.0.0.1	ap-e29-2	ciscoap	2013-03-31 14:07:07.949621+02	f	0	00:05:00	<removed>
82	151.216.21.66	e53-4	dlink3100	2013-03-31 14:11:47.281839+02	f	0	00:01:00	<removed>
403	127.0.0.1	ap-distro2	ciscoap	2013-03-31 14:07:14.316549+02	f	0	00:05:00	<removed>
333	127.0.0.1	ap-e43-2	ciscoap	2013-03-31 14:07:14.366567+02	f	0	00:05:00	<removed>
305	127.0.0.1	ap-e21-2	ciscoap	2013-03-31 14:05:37.161496+02	f	0	00:05:00	<removed>
383	127.0.0.1	ap-e67-4	ciscoap	2013-03-31 14:05:37.169782+02	f	0	00:05:00	<removed>
35	151.216.9.130	e23-1	dlink3100	2013-03-31 14:11:57.324788+02	f	0	00:01:00	<removed>
329	127.0.0.1	ap-e39-2	ciscoap	2013-03-31 14:07:14.383235+02	f	0	00:05:00	<removed>
295	127.0.0.1	ap-e15-4	ciscoap	2013-03-31 14:07:14.416546+02	f	0	00:05:00	<removed>
322	127.0.0.1	ap-e33-1	ciscoap	2013-03-31 14:05:37.194794+02	f	0	00:05:00	<removed>
316	127.0.0.1	ap-e27-1	ciscoap	2013-03-31 14:07:18.075143+02	f	0	00:05:00	<removed>
317	127.0.0.1	ap-e27-2	ciscoap	2013-03-31 14:07:18.083421+02	f	0	00:05:00	<removed>
410	151.216.50.5	creativiasw04	dlink3100	2013-03-31 14:08:38.747626+02	f	0	00:01:00	<removed>
54	151.216.14.66	e37-2	dlink3100	2013-03-31 14:08:48.798532+02	f	0	00:01:00	<removed>
346	127.0.0.1	ap-e49-3	ciscoap	2013-03-31 14:07:18.116747+02	f	0	00:05:00	<removed>
16	151.216.4.194	e13-2	dlink3100	2013-03-31 14:08:59.398994+02	f	0	00:01:00	<removed>
132	151.216.127.4	stageboh	stageboh	2013-03-31 14:11:19.519638+02	f	0	00:01:00	<removed>
353	127.0.0.1	ap-e53-2	ciscoap	2013-03-31 14:07:18.141775+02	f	0	00:05:00	<removed>
122	151.216.31.66	e73-4	dlink3100	2013-03-31 14:12:38.849023+02	t	0	00:01:00	<removed>
338	127.0.0.1	ap-e45-3	ciscoap	2013-03-31 14:07:18.175214+02	f	0	00:05:00	<removed>
327	127.0.0.1	ap-e37-2	ciscoap	2013-03-31 14:07:18.216828+02	f	0	00:05:00	<removed>
309	127.0.0.1	ap-e23-2	ciscoap	2013-03-31 14:07:24.68384+02	f	0	00:05:00	<removed>
330	127.0.0.1	ap-e41-1	ciscoap	2013-03-31 14:07:24.71716+02	f	0	00:05:00	<removed>
299	127.0.0.1	ap-e17-4	ciscoap	2013-03-31 14:07:24.733842+02	f	0	00:05:00	<removed>
379	127.0.0.1	ap-e65-4	ciscoap	2013-03-31 14:07:24.750498+02	f	0	00:05:00	<removed>
8	151.216.2.194	e7-4	dlink3100	2013-03-31 14:07:28.294572+02	f	0	00:01:00	<removed>
70	151.216.18.66	e47-4	dlink3100	2013-03-31 14:06:47.567226+02	f	0	00:01:00	<removed>
377	127.0.0.1	ap-e65-2	ciscoap	2013-03-31 14:07:28.367437+02	f	0	00:05:00	<removed>
60	151.216.15.194	e43-2	dlink3100	2013-03-31 14:06:57.634414+02	f	0	00:01:00	<removed>
292	127.0.0.1	ap-e15-1	ciscoap	2013-03-31 14:07:34.926035+02	f	0	00:05:00	<removed>
114	151.216.29.66	e69-4	dlink3100	2013-03-31 14:07:07.891609+02	f	0	00:01:00	<removed>
347	127.0.0.1	ap-e49-4	ciscoap	2013-03-31 14:07:34.959373+02	f	0	00:05:00	<removed>
116	151.216.29.194	e71-2	dlink3100	2013-03-31 14:07:38.453277+02	f	0	00:01:00	<removed>
411	151.216.50.6	creativiasw05	dlink3100	2013-03-31 14:07:17.968957+02	f	0	00:01:00	<removed>
87	151.216.22.130	e57-1	dlink3100	2013-03-31 14:07:48.503769+02	f	0	00:01:00	<removed>
113	151.216.29.2	e69-3	dlink3100	2013-03-31 14:07:58.545997+02	f	0	00:01:00	<removed>
287	127.0.0.1	ap-e11-4	ciscoap	2013-03-31 14:07:18.016788+02	f	0	00:05:00	<removed>
66	151.216.17.66	e45-4	dlink3100	2013-03-31 14:08:08.60963+02	f	0	00:01:00	<removed>
120	151.216.30.194	e73-2	dlink3100	2013-03-31 14:08:18.656104+02	f	0	00:01:00	<removed>
118	151.216.30.66	e71-4	dlink3100	2013-03-31 14:08:29.247615+02	f	0	00:01:00	<removed>
400	127.0.0.1	ap-e77-1	ciscoap	2013-03-31 14:07:34.859414+02	f	0	00:05:00	<removed>
139	151.216.127.16	eldregw	eldregw	2013-03-31 14:12:28.253362+02	f	0	00:01:00	<removed>
76	151.216.19.194	e51-2	dlink3100	2013-03-31 14:12:38.382364+02	t	0	00:01:00	<removed>
405	127.0.0.1	ap-distro0	ciscoap	2013-03-31 14:07:34.876034+02	f	0	00:05:00	<removed>
359	127.0.0.1	ap-e55-4	ciscoap	2013-03-31 14:07:18.041795+02	f	0	00:05:00	<removed>
373	127.0.0.1	ap-e63-2	ciscoap	2013-03-31 14:07:18.050126+02	f	0	00:05:00	<removed>
354	127.0.0.1	ap-e53-3	ciscoap	2013-03-31 14:07:34.892675+02	f	0	00:05:00	<removed>
386	127.0.0.1	ap-e69-3	ciscoap	2013-03-31 14:07:18.108439+02	f	0	00:05:00	<removed>
326	127.0.0.1	ap-e37-1	ciscoap	2013-03-31 14:07:34.909368+02	f	0	00:05:00	<removed>
284	127.0.0.1	ap-e11-1	ciscoap	2013-03-31 14:07:34.942715+02	f	0	00:05:00	<removed>
391	127.0.0.1	ap-e71-4	ciscoap	2013-03-31 14:07:18.150127+02	f	0	00:05:00	<removed>
362	127.0.0.1	ap-e57-3	ciscoap	2013-03-31 14:07:34.976095+02	f	0	00:05:00	<removed>
318	127.0.0.1	ap-e29-1	ciscoap	2013-03-31 14:07:18.183518+02	f	0	00:05:00	<removed>
110	151.216.28.66	e67-4	dlink3100	2013-03-31 14:07:38.444965+02	f	0	00:01:00	<removed>
274	127.0.0.1	ap-e1-3	ciscoap	2013-03-31 14:07:18.208538+02	f	0	00:05:00	<removed>
53	151.216.14.2	e37-1	dlink3100	2013-03-31 14:07:48.49557+02	f	0	00:01:00	<removed>
107	151.216.27.130	e67-1	dlink3100	2013-03-31 14:07:58.554186+02	f	0	00:01:00	<removed>
315	127.0.0.1	ap-e25-4	ciscoap	2013-03-31 14:07:24.650503+02	f	0	00:05:00	<removed>
360	127.0.0.1	ap-e57-1	ciscoap	2013-03-31 14:07:24.667163+02	f	0	00:05:00	<removed>
78	151.216.20.66	e51-4	dlink3100	2013-03-31 14:08:09.146709+02	f	0	00:01:00	<removed>
414	151.216.50.9	creativiasw08	dlink3100	2013-03-31 14:06:47.558957+02	f	0	00:01:00	<removed>
294	127.0.0.1	ap-e15-3	ciscoap	2013-03-31 14:07:24.700488+02	f	0	00:05:00	<removed>
25	151.216.7.2	e17-3	dlink3100	2013-03-31 14:07:28.311147+02	f	0	00:01:00	<removed>
75	151.216.19.130	e51-1	dlink3100	2013-03-31 14:06:57.617774+02	f	0	00:01:00	<removed>
93	151.216.24.2	e59-3	dlink3100	2013-03-31 14:08:19.189476+02	f	0	00:01:00	<removed>
11	151.216.3.130	e11-1	dlink3100	2013-03-31 14:08:28.698108+02	f	0	00:01:00	<removed>
55	151.216.14.130	e39-1	dlink3100	2013-03-31 14:08:39.297705+02	f	0	00:01:00	<removed>
367	127.0.0.1	ap-e59-4	ciscoap	2013-03-31 14:07:28.334102+02	f	0	00:05:00	<removed>
80	151.216.20.194	e53-2	dlink3100	2013-03-31 14:07:07.875693+02	f	0	00:01:00	<removed>
321	127.0.0.1	ap-e31-2	ciscoap	2013-03-31 14:07:28.342401+02	f	0	00:05:00	<removed>
94	151.216.24.66	e59-4	dlink3100	2013-03-31 14:07:17.985368+02	f	0	00:01:00	<removed>
283	127.0.0.1	ap-e9-4	ciscoap	2013-03-31 14:07:28.375765+02	f	0	00:05:00	<removed>
48	151.216.12.194	e31-2	dlink3100	2013-03-31 14:08:49.348586+02	f	0	00:01:00	<removed>
68	151.216.17.194	e47-2	dlink3100	2013-03-31 14:08:58.847409+02	f	0	00:01:00	<removed>
331	127.0.0.1	ap-e41-2	ciscoap	2013-03-31 14:07:18.008451+02	f	0	00:05:00	<removed>
129	151.216.127.2	nocgw	nocgw	2013-03-31 14:11:36.609335+02	f	0	00:01:00	<removed>
306	127.0.0.1	ap-e21-3	ciscoap	2013-03-31 14:07:28.400753+02	f	0	00:05:00	<removed>
313	127.0.0.1	ap-e25-2	ciscoap	2013-03-31 14:07:28.409069+02	f	0	00:05:00	<removed>
136	151.216.127.11	gamegw	gamegw	2013-03-31 14:06:54.076054+02	f	0	00:01:00	<removed>
81	151.216.21.2	e53-3	dlink3100	2013-03-31 14:07:04.184831+02	f	0	00:01:00	<removed>
105	151.216.27.2	e65-3	dlink3100	2013-03-31 14:07:14.28811+02	f	0	00:01:00	<removed>
56	151.216.14.194	e39-2	dlink3100	2013-03-31 14:07:26.952794+02	f	0	00:01:00	<removed>
72	151.216.18.194	e49-2	dlink3100	2013-03-31 14:07:36.993533+02	f	0	00:01:00	<removed>
27	151.216.7.130	e19-1	dlink3100	2013-03-31 14:07:45.003682+02	f	0	00:01:00	<removed>
17	151.216.5.2	e13-3	dlink3100	2013-03-31 14:07:57.079313+02	f	0	00:01:00	<removed>
59	151.216.15.130	e43-1	dlink3100	2013-03-31 14:08:07.12975+02	f	0	00:01:00	<removed>
79	151.216.20.130	e53-1	dlink3100	2013-03-31 14:08:15.230508+02	f	0	00:01:00	<removed>
12	151.216.3.194	e11-2	dlink3100	2013-03-31 14:08:25.273211+02	f	0	00:01:00	<removed>
413	151.216.50.8	creativiasw07	dlink3100	2013-03-31 14:08:35.321636+02	f	0	00:01:00	<removed>
15	151.216.4.130	e13-1	dlink3100	2013-03-31 14:08:45.372088+02	f	0	00:01:00	<removed>
106	151.216.27.66	e65-4	dlink3100	2013-03-31 14:08:57.465785+02	f	0	00:01:00	<removed>
29	151.216.8.2	e19-3	dlink3100	2013-03-31 14:09:07.516177+02	f	0	00:01:00	<removed>
34	151.216.9.66	e21-4	dlink3100	2013-03-31 14:12:40.090712+02	t	0	00:01:00	<removed>
49	151.216.13.2	e33-1	dlink3100	2013-03-31 14:07:06.867675+02	f	0	00:01:00	<removed>
44	151.216.11.194	e27-2	dlink3100	2013-03-31 14:07:16.909469+02	f	0	00:01:00	<removed>
96	151.216.24.194	e61-2	dlink3100	2013-03-31 14:07:24.56102+02	f	0	00:01:00	<removed>
73	151.216.19.2	e49-3	dlink3100	2013-03-31 14:07:34.777763+02	f	0	00:01:00	<removed>
115	151.216.29.130	e71-1	dlink3100	2013-03-31 14:07:47.037305+02	f	0	00:01:00	<removed>
95	151.216.24.130	e61-1	dlink3100	2013-03-31 14:07:55.137659+02	f	0	00:01:00	<removed>
409	151.216.50.4	creativiasw03	dlink3100	2013-03-31 14:08:05.18812+02	f	0	00:01:00	<removed>
111	151.216.28.130	e69-1	dlink3100	2013-03-31 14:08:17.239454+02	f	0	00:01:00	<removed>
77	151.216.20.2	e51-3	dlink3100	2013-03-31 14:08:27.313458+02	f	0	00:01:00	<removed>
58	151.216.15.66	e41-2	dlink3100	2013-03-31 14:08:37.363767+02	f	0	00:01:00	<removed>
41	151.216.11.2	e25-3	dlink3100	2013-03-31 14:08:47.415311+02	f	0	00:01:00	<removed>
143	151.216.127.20	distro3	distro3	2013-03-31 14:08:55.423637+02	f	0	00:01:00	<removed>
\.


--
-- Name: switches_switch_seq; Type: SEQUENCE SET; Schema: public; Owner: nms
--

SELECT pg_catalog.setval('switches_switch_seq', 417, true);


--
-- Data for Name: switchtypes; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY switchtypes (switchtype, ports) FROM stdin;
dlink3100	1-44,46-48
dlink3100full	1-48
ciscoap	
nocgw	1-114
telegw	1-94,99-102
camgw	1-52,55
stageboh	1-52,55
wtfgw	1-52,55
logistikkgw	1-52,55
crewgw	1-52,55
gamegw	1-52,55
resepsjongw	10101-10110
sponsorgw	
eldregw	1-5
distro0	1-201
distro1	1-201
distro2	1-201
distro3	1-201
distro4	1-201
\.


--
-- Data for Name: temppoll; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY temppoll (id, "time", switch, temp) FROM stdin;
\.


--
-- Data for Name: uplinks; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY uplinks (switch, coreswitch, blade, port) FROM stdin;
274	140	6	1
275	140	6	2
276	140	6	3
277	140	6	4
278	140	6	5
279	140	6	6
280	140	6	7
281	140	6	8
282	140	6	9
283	140	6	10
284	141	6	1
285	141	6	2
286	140	6	11
287	140	6	12
288	141	6	3
289	141	6	4
290	140	6	13
291	140	6	14
292	141	6	5
293	141	6	6
294	140	6	15
295	140	6	16
296	141	6	7
297	141	6	8
298	140	6	17
299	140	6	18
300	141	6	9
301	141	6	10
302	140	6	19
303	140	6	20
304	141	6	11
305	141	6	12
306	140	6	21
307	140	6	22
308	141	6	13
309	141	6	14
310	140	6	23
311	140	6	24
312	141	6	15
313	141	6	16
314	140	6	25
315	140	6	26
316	141	6	17
317	141	6	18
318	141	6	19
319	141	6	20
320	141	6	21
321	141	6	22
322	142	6	1
323	141	6	23
324	142	6	2
325	142	6	3
326	142	6	4
327	142	6	5
328	142	6	6
329	142	6	7
330	142	6	8
331	142	6	9
332	142	6	10
333	142	6	11
334	143	6	1
335	143	6	2
336	142	6	12
337	142	6	13
338	143	6	3
339	143	6	4
340	142	6	14
341	142	6	15
342	143	6	5
343	143	6	6
344	142	6	16
345	142	6	17
346	143	6	7
347	143	6	8
348	142	6	18
349	142	6	19
350	143	6	9
351	143	6	10
352	142	6	20
353	142	6	21
354	143	6	11
355	143	6	12
356	142	6	22
357	142	6	23
358	143	6	13
359	143	6	14
360	142	6	24
361	142	6	25
362	143	6	15
363	143	6	16
364	144	6	1
365	144	6	2
366	143	6	17
367	143	6	18
368	144	6	3
369	144	6	4
370	143	6	19
371	143	6	20
372	144	6	5
373	144	6	6
374	144	6	7
375	144	6	8
376	144	6	9
377	144	6	10
378	144	6	11
379	144	6	12
380	144	6	13
381	144	6	14
382	144	6	15
383	144	6	16
384	144	6	17
385	144	6	18
386	144	6	19
387	144	6	20
388	144	6	21
389	144	6	22
390	144	6	23
391	144	6	24
392	144	6	25
393	144	6	26
394	144	6	27
395	144	6	28
396	144	6	29
397	144	6	30
398	144	6	31
399	144	6	32
400	144	6	33
401	144	6	34
402	141	6	48
403	142	6	47
404	143	6	48
405	140	6	48
406	144	6	48
\.


--
-- Name: cpuloadpoll_pkey; Type: CONSTRAINT; Schema: public; Owner: nms; Tablespace: 
--

ALTER TABLE ONLY cpuloadpoll
    ADD CONSTRAINT cpuloadpoll_pkey PRIMARY KEY (id);


--
-- Name: ipv4_pkey; Type: CONSTRAINT; Schema: public; Owner: nms; Tablespace: 
--

ALTER TABLE ONLY ipv4
    ADD CONSTRAINT ipv4_pkey PRIMARY KEY (mac, address, "time");


--
-- Name: ipv6_pkey; Type: CONSTRAINT; Schema: public; Owner: nms; Tablespace: 
--

ALTER TABLE ONLY ipv6
    ADD CONSTRAINT ipv6_pkey PRIMARY KEY (mac, address, "time");


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
-- Name: polls_switchporttime; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX polls_switchporttime ON polls USING btree (switch, port, "time");


--
-- Name: polls_time; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX polls_time ON polls USING btree ("time");


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
-- Name: time_idx; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX time_idx ON ipv6 USING btree ("time");


--
-- Name: timev4_idx; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX timev4_idx ON ipv4 USING btree ("time");


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
-- Name: ipv4; Type: ACL; Schema: public; Owner: nms
--

REVOKE ALL ON TABLE ipv4 FROM PUBLIC;
REVOKE ALL ON TABLE ipv4 FROM nms;
GRANT ALL ON TABLE ipv4 TO nms;


--
-- Name: ipv6; Type: ACL; Schema: public; Owner: nms
--

REVOKE ALL ON TABLE ipv6 FROM PUBLIC;
REVOKE ALL ON TABLE ipv6 FROM nms;
GRANT ALL ON TABLE ipv6 TO nms;


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
-- PostgreSQL database dump complete
--

\connect postgres

--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: postgres; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON DATABASE postgres IS 'default administrative connection database';


--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--

\connect template1

--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: template1; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON DATABASE template1 IS 'default template for new databases';


--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--

--
-- PostgreSQL database cluster dump complete
--

