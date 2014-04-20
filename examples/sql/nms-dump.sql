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
-- Name: nms; Type: DATABASE; Schema: -; Owner: postgres
--

CREATE DATABASE nms WITH TEMPLATE = template0 ENCODING = 'UTF8' LC_COLLATE = 'en_US.UTF-8' LC_CTYPE = 'en_US.UTF-8';


ALTER DATABASE nms OWNER TO postgres;

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
    LANGUAGE sql
    AS $$
      SELECT switch,port,
      (bytes_out[1] - bytes_out[2]) / EXTRACT(EPOCH FROM (time[1] - time[2])) AS bytes_out,
      (bytes_in[1] - bytes_in[2]) / EXTRACT(EPOCH FROM (time[1] - time[2])) AS bytes_in,
      time[1] AS last_poll_time
      FROM (
        SELECT switch,port,
        ARRAY_AGG(time) AS time,
        ARRAY_AGG(bytes_in) AS bytes_in,
        ARRAY_AGG(bytes_out) AS bytes_out
        FROM (
           SELECT *,rank() OVER (PARTITION BY switch,port ORDER BY time DESC) AS poll_num
           FROM polls WHERE time BETWEEN (now() - interval '5 minutes') AND now()
           AND official_port
        ) t1
        WHERE poll_num <= 2
        GROUP BY switch,port
      ) t2
      WHERE
        time[2] IS NOT NULL
        AND bytes_in[1] >= 0 AND bytes_out[1] >= 0
        AND bytes_in[2] >= 0 AND bytes_out[2] >= 0
        AND bytes_out[1] >= bytes_out[2]
        AND bytes_in[1] >= bytes_in[2];
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
-- Name: linknet_ping; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE linknet_ping (
    linknet integer NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL,
    latency1_ms double precision,
    latency2_ms double precision
);


ALTER TABLE public.linknet_ping OWNER TO nms;

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


ALTER TABLE public.linknets OWNER TO nms;

--
-- Name: linknets_linknet_seq; Type: SEQUENCE; Schema: public; Owner: nms
--

CREATE SEQUENCE linknets_linknet_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.linknets_linknet_seq OWNER TO nms;

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
-- Name: ping; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE ping (
    switch integer NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL,
    latency_ms double precision
);


ALTER TABLE public.ping OWNER TO nms;

--
-- Name: ping_secondary_ip; Type: TABLE; Schema: public; Owner: nms; Tablespace: 
--

CREATE TABLE ping_secondary_ip (
    switch integer NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL,
    latency_ms double precision
);


ALTER TABLE public.ping_secondary_ip OWNER TO nms;

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
    official_port boolean DEFAULT false NOT NULL
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
-- Name: seen_mac; Type: TABLE; Schema: public; Owner: postgres; Tablespace: 
--

CREATE TABLE seen_mac (
    mac macaddr NOT NULL,
    address inet NOT NULL,
    seen timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.seen_mac OWNER TO postgres;

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
    poll_frequency interval DEFAULT '00:01:00'::interval NOT NULL,
    community character varying DEFAULT 'public'::character varying NOT NULL,
    lldp_chassis_id character varying,
    secondary_ip inet
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
    ports character varying NOT NULL
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
-- Name: linknet; Type: DEFAULT; Schema: public; Owner: nms
--

ALTER TABLE ONLY linknets ALTER COLUMN linknet SET DEFAULT nextval('linknets_linknet_seq'::regclass);


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
\.


--
-- Data for Name: linknet_ping; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY linknet_ping (linknet, updated, latency1_ms, latency2_ms) FROM stdin;
\.


--
-- Data for Name: linknets; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY linknets (linknet, switch1, addr1, switch2, addr2) FROM stdin;
242	419	151.216.128.4	420	151.216.128.5
243	430	151.216.128.72	615	151.216.128.73
244	421	151.216.128.18	423	151.216.128.19
245	429	151.216.128.60	418	151.216.128.61
246	429	151.216.128.59	423	151.216.128.58
247	622	151.216.128.49	420	151.216.128.48
248	613	151.216.128.33	418	151.216.128.32
249	418	151.216.128.32	613	151.216.128.33
250	421	151.216.128.47	420	151.216.128.46
251	418	151.216.227.1	431	151.216.227.3
252	622	151.216.128.75	430	151.216.128.74
253	591	151.216.128.65	430	151.216.128.64
254	612	151.216.128.69	430	151.216.128.68
255	617	151.216.128.63	430	151.216.128.62
256	418	151.216.128.79	430	151.216.128.78
257	618	151.216.128.77	430	151.216.128.76
258	418	151.216.128.3	419	151.216.128.2
259	419	151.216.128.81	430	151.216.128.80
260	614	151.216.128.71	430	151.216.128.70
261	588	151.216.128.67	430	151.216.128.66
\.


--
-- Name: linknets_linknet_seq; Type: SEQUENCE SET; Schema: public; Owner: nms
--

SELECT pg_catalog.setval('linknets_linknet_seq', 261, true);


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
-- Data for Name: ping; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY ping (switch, updated, latency_ms) FROM stdin;
\.


--
-- Data for Name: ping_secondary_ip; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY ping_secondary_ip (switch, updated, latency_ms) FROM stdin;
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
425	(206,476),(166,436)	0
426	(316,544),(276,504)	0
427	(655,43),(615,3)	0
423	(531,115),(491,75)	0
592	(1077,174),(1025,160)	0
421	(814,115),(774,75)	0
424	(525,617),(485,577)	0
593	(1087,196),(1025,182)	0
420	(1183,313),(1143,273)	0
431	(884,639),(844,599)	0
594	(1097,218),(1025,204)	0
430	(669,361),(629,321)	0
595	(1077,240),(1025,226)	0
418	(480,617),(440,577)	0
596	(1129,240),(1077,226)	0
597	(1077,263),(1025,249)	0
605	(1136,365),(1066,351)	0
428	(630,617),(530,601)	0
598	(1129,263),(1077,249)	0
599	(1077,285),(1025,271)	0
600	(1129,285),(1077,271)	0
601	(1077,307),(1025,293)	0
602	(1129,307),(1077,293)	0
603	(1077,329),(1025,315)	0
604	(1129,329),(1077,315)	0
606	(1168,385),(1068,369)	0
434	(219,244),(205,205)	-1
432	(631,593),(531,577)	0
586	(1047,613),(1007,573)	0
607	(1158,384),(1113,370)	0
609	(1158,404),(1113,390)	0
611	(1158,425),(1113,411)	0
591	(406,348),(366,308)	0
623	(261,434),(247,350)	0
608	(1168,405),(1068,389)	0
610	(1168,425),(1068,409)	0
628	(432,566),(392,526)	0
617	(279,353),(239,313)	0
435	(239,328),(225,244)	-1
436	(239,244),(225,180)	-1
437	(259,328),(245,244)	-1
438	(259,244),(245,175)	-1
439	(279,328),(265,244)	-1
440	(279,244),(265,160)	-1
441	(299,328),(285,244)	-1
442	(299,244),(285,160)	-1
443	(328,519),(314,435)	-1
444	(328,435),(314,351)	-1
445	(328,328),(314,244)	-1
446	(328,244),(314,160)	-1
447	(348,519),(334,435)	-1
448	(348,435),(334,351)	-1
449	(348,328),(334,244)	-1
613	(479,566),(439,526)	0
455	(388,519),(374,435)	-1
612	(728,382),(688,342)	0
618	(1048,274),(1008,234)	0
629	(989,657),(889,641)	0
429	(108,113),(68,73)	0
579	(1138,363),(1068,349)	0
580	(1113,384),(1068,370)	0
581	(1158,384),(1113,370)	0
582	(1113,404),(1068,390)	0
583	(1158,404),(1113,390)	0
584	(1113,425),(1068,411)	0
585	(1158,425),(1113,411)	0
567	(1077,174),(1025,160)	0
568	(1087,196),(1025,182)	0
569	(1097,218),(1025,204)	0
571	(1077,240),(1025,226)	0
572	(1129,240),(1077,226)	0
573	(1077,263),(1025,249)	0
574	(1129,263),(1077,249)	0
450	(348,244),(334,160)	-1
451	(368,519),(354,435)	-1
452	(368,435),(354,351)	-1
453	(368,328),(354,244)	-1
454	(368,244),(354,160)	-1
456	(388,435),(374,351)	-1
457	(388,328),(374,244)	-1
458	(388,244),(374,160)	-1
459	(408,519),(394,435)	-1
460	(408,435),(394,351)	-1
461	(408,328),(394,244)	-1
575	(1077,285),(1025,271)	0
576	(1129,285),(1077,271)	0
577	(1077,307),(1025,293)	0
578	(1129,307),(1077,293)	0
462	(408,244),(394,160)	-1
463	(429,519),(415,435)	-1
464	(429,435),(415,351)	-1
465	(429,328),(415,244)	-1
466	(429,244),(415,160)	-1
467	(449,519),(435,435)	-1
468	(449,435),(435,351)	-1
469	(449,328),(435,244)	-1
470	(449,244),(435,160)	-1
471	(469,519),(455,435)	-1
472	(469,435),(455,351)	-1
473	(469,328),(455,244)	-1
474	(469,244),(455,160)	-1
475	(495,519),(481,435)	-1
477	(515,519),(501,435)	-1
478	(515,435),(501,351)	-1
479	(536,519),(522,435)	-1
481	(556,519),(542,435)	-1
482	(556,435),(542,351)	-1
483	(576,519),(562,435)	-1
484	(576,435),(562,351)	-1
485	(596,519),(582,435)	-1
486	(596,435),(582,351)	-1
487	(616,519),(602,435)	-1
488	(616,435),(602,351)	-1
489	(637,519),(623,435)	-1
490	(637,435),(623,351)	-1
491	(669,519),(655,435)	-1
492	(669,435),(655,351)	-1
493	(669,328),(655,244)	-1
494	(669,244),(655,160)	-1
495	(689,519),(675,435)	-1
496	(689,435),(675,351)	-1
497	(689,328),(675,244)	-1
498	(689,244),(675,160)	-1
500	(709,435),(695,351)	-1
501	(709,328),(695,244)	-1
502	(709,244),(695,160)	-1
503	(729,519),(715,435)	-1
504	(729,435),(715,351)	-1
505	(729,328),(715,244)	-1
506	(729,244),(715,160)	-1
507	(750,519),(736,435)	-1
508	(750,435),(736,351)	-1
509	(750,328),(736,244)	-1
510	(750,244),(736,160)	-1
511	(770,519),(756,435)	-1
512	(770,435),(756,351)	-1
513	(770,328),(756,244)	-1
514	(770,244),(756,160)	-1
515	(790,519),(776,435)	-1
516	(790,435),(776,351)	-1
517	(790,328),(776,244)	-1
518	(790,244),(776,160)	-1
519	(810,519),(796,435)	-1
520	(810,435),(796,351)	-1
521	(810,328),(796,244)	-1
522	(810,244),(796,160)	-1
523	(830,519),(816,435)	-1
524	(830,435),(816,351)	-1
525	(830,328),(816,244)	-1
526	(830,244),(816,160)	-1
527	(858,519),(844,435)	-1
530	(858,244),(844,160)	-1
531	(878,519),(864,435)	-1
533	(878,328),(864,244)	-1
534	(878,244),(864,160)	-1
535	(898,519),(884,435)	-1
536	(898,435),(884,351)	-1
537	(898,328),(884,244)	-1
538	(898,244),(884,160)	-1
539	(918,519),(904,435)	-1
566	(1060,435),(1046,351)	-1
587	(645,544),(605,504)	0
625	(556,289),(516,249)	0
528	(858,435),(844,351)	-1
529	(858,329),(844,245)	-1
624	(480,92),(380,76)	0
619	(461,113),(421,73)	0
480	(536,435),(522,351)	-1
476	(495,435),(481,351)	-1
614	(797,366),(757,326)	0
422	(634,154),(594,114)	0
532	(878,435),(864,351)	-1
499	(709,519),(695,435)	-1
588	(463,377),(423,337)	0
620	(414,113),(374,73)	0
626	(432,658),(332,642)	0
419	(1092,624),(1052,584)	0
615	(964,377),(924,337)	0
627	(480,112),(380,96)	0
621	(702,55),(602,39)	0
589	(988,582),(888,566)	0
565	(1060,504),(1046,435)	-1
433	(219,328),(205,244)	-1
590	(989,638),(889,622)	0
622	(1203,479),(1163,439)	0
547	(959,520),(945,436)	-1
616	(1256,347),(1156,331)	0
540	(918,435),(904,351)	-1
541	(918,328),(904,244)	-1
542	(918,244),(904,160)	-1
543	(938,519),(924,435)	-1
544	(938,435),(924,351)	-1
545	(938,328),(924,244)	-1
546	(938,244),(924,160)	-1
548	(959,435),(945,351)	-1
549	(959,328),(945,244)	-1
550	(959,244),(945,160)	-1
551	(979,519),(965,435)	-1
552	(979,435),(965,351)	-1
553	(979,328),(965,244)	-1
554	(979,244),(965,160)	-1
555	(999,519),(985,435)	-1
556	(999,435),(985,351)	-1
557	(999,328),(985,244)	-1
558	(999,244),(985,160)	-1
559	(1019,519),(1005,435)	-1
560	(1019,435),(1005,351)	-1
561	(1019,328),(1005,244)	-1
562	(1019,244),(1005,160)	-1
563	(1039,519),(1025,435)	-1
564	(1039,435),(1025,351)	-1
\.


--
-- Data for Name: polls; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY polls ("time", switch, port, bytes_in, bytes_out, errors_in, errors_out, official_port) FROM stdin;
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
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	127	Vlan1
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	32	GigabitEthernet4/20
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	90	GigabitEthernet9/12
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	118	GigabitEthernet9/40
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	71	TenGigabitEthernet7/1
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	102	GigabitEthernet9/24
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	18	GigabitEthernet4/6
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	125	GigabitEthernet9/47
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	16	GigabitEthernet4/4
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	44	GigabitEthernet4/32
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	55	GigabitEthernet4/43
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	84	GigabitEthernet9/6
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	27	GigabitEthernet4/15
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	161	unrouted VLAN 2272
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	95	GigabitEthernet9/17
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	57	GigabitEthernet4/45
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	20	GigabitEthernet4/8
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	163	Vlan3000
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	109	GigabitEthernet9/31
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	151	Vlan192
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	89	GigabitEthernet9/11
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	148	Port-channel22
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	31	GigabitEthernet4/19
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	35	GigabitEthernet4/23
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	11	TenGigabitEthernet3/3
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	78	TenGigabitEthernet8/4
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	93	GigabitEthernet9/15
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	106	GigabitEthernet9/28
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	157	unrouted VLAN 2500
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	65	TenGigabitEthernet5/5
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	29	GigabitEthernet4/17
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	138	Port-channel1
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	114	GigabitEthernet9/36
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	58	GigabitEthernet4/46
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	153	Tunnel4
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	15	GigabitEthernet4/3
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	137	Loopback0
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	81	GigabitEthernet9/3
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	60	GigabitEthernet4/48
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	101	GigabitEthernet9/23
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	73	TenGigabitEthernet7/3
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	86	GigabitEthernet9/8
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	76	TenGigabitEthernet8/2
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	62	GigabitEthernet5/2
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	67	GigabitEthernet6/2
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	165	Loopback3000
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	139	Port-channel11
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	129	Null0
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	2	TenGigabitEthernet1/2
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	17	GigabitEthernet4/5
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	110	GigabitEthernet9/32
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	82	GigabitEthernet9/4
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	147	Port-channel21
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	135	unrouted VLAN 1005
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	14	GigabitEthernet4/2
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	112	GigabitEthernet9/34
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	69	TenGigabitEthernet6/4
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	145	Tunnel2
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	49	GigabitEthernet4/37
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	24	GigabitEthernet4/12
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	140	Port-channel12
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	124	GigabitEthernet9/46
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	104	GigabitEthernet9/26
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	131	Control Plane Interface
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	121	GigabitEthernet9/43
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	79	GigabitEthernet9/1
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	154	Port-channel3
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	23	GigabitEthernet4/11
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	96	GigabitEthernet9/18
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	126	GigabitEthernet9/48
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	159	unrouted VLAN 2271
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	160	Vlan2271
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	47	GigabitEthernet4/35
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	8	TenGigabitEthernet2/4
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	98	GigabitEthernet9/20
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	37	GigabitEthernet4/25
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	117	GigabitEthernet9/39
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	43	GigabitEthernet4/31
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	5	TenGigabitEthernet2/1
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	33	GigabitEthernet4/21
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	21	GigabitEthernet4/9
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	63	GigabitEthernet5/3
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	7	TenGigabitEthernet2/3
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	26	GigabitEthernet4/14
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	80	GigabitEthernet9/2
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	119	GigabitEthernet9/41
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	99	GigabitEthernet9/21
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	162	Vlan2272
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	72	TenGigabitEthernet7/2
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	74	TenGigabitEthernet7/4
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	61	GigabitEthernet5/1
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	108	GigabitEthernet9/30
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	115	GigabitEthernet9/37
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	92	GigabitEthernet9/14
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	103	GigabitEthernet9/25
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	10	TenGigabitEthernet3/2
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	113	GigabitEthernet9/35
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	152	Tunnel3
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	142	Tunnel0
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	91	GigabitEthernet9/13
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	48	GigabitEthernet4/36
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	107	GigabitEthernet9/29
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	87	GigabitEthernet9/9
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	77	TenGigabitEthernet8/3
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	133	unrouted VLAN 1002
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	149	Vlan253
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	123	GigabitEthernet9/45
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	50	GigabitEthernet4/38
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	39	GigabitEthernet4/27
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	64	TenGigabitEthernet5/4
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	97	GigabitEthernet9/19
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	12	TenGigabitEthernet3/4
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	41	GigabitEthernet4/29
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	52	GigabitEthernet4/40
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	56	GigabitEthernet4/44
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	45	GigabitEthernet4/33
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	66	GigabitEthernet6/1
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	19	GigabitEthernet4/7
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	54	GigabitEthernet4/42
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	70	TenGigabitEthernet6/5
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	68	GigabitEthernet6/3
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	166	Loopback3001
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	1	TenGigabitEthernet1/1
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	136	unrouted VLAN 1003
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	88	GigabitEthernet9/10
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	116	GigabitEthernet9/38
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	144	unrouted VLAN 252
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	141	Vlan252
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	30	GigabitEthernet4/18
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	100	GigabitEthernet9/22
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	25	GigabitEthernet4/13
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	128	EOBC0/2
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	28	GigabitEthernet4/16
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	120	GigabitEthernet9/42
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	156	Port-channel1-mpls layer
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	134	unrouted VLAN 1004
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	40	GigabitEthernet4/28
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	75	TenGigabitEthernet8/1
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	83	GigabitEthernet9/5
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	59	GigabitEthernet4/47
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	150	unrouted VLAN 192
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	155	Port-channel13
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	130	SPAN RP Interface
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	53	GigabitEthernet4/41
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	122	GigabitEthernet9/44
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	143	Tunnel1
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	158	Vlan2500
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	42	GigabitEthernet4/30
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	22	GigabitEthernet4/10
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	46	GigabitEthernet4/34
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	13	GigabitEthernet4/1
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	105	GigabitEthernet9/27
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	6	TenGigabitEthernet2/2
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	85	GigabitEthernet9/7
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	36	GigabitEthernet4/24
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	3	TenGigabitEthernet1/3
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	94	GigabitEthernet9/16
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	146	unrouted VLAN 253
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	51	GigabitEthernet4/39
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	9	TenGigabitEthernet3/1
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	111	GigabitEthernet9/33
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	38	GigabitEthernet4/26
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	4	TenGigabitEthernet1/4
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	34	GigabitEthernet4/22
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	164	unrouted VLAN 3000
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	132	unrouted VLAN 1
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	127	unrouted VLAN 3000
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	33	GigabitEthernet2/29
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	32	GigabitEthernet2/28
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	63	GigabitEthernet5/3
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	21	GigabitEthernet2/17
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	118	Vlan254
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	71	TenGigabitEthernet7/1
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	7	GigabitEthernet2/3
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	80	EOBC0/2
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	26	GigabitEthernet2/22
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	119	Loopback0
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	18	GigabitEthernet2/14
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	72	TenGigabitEthernet7/2
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	125	Port-channel2-mpls layer
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	16	GigabitEthernet2/12
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	44	GigabitEthernet2/40
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	55	TenGigabitEthernet3/3
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	84	unrouted VLAN 1
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	74	TenGigabitEthernet7/4
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	27	GigabitEthernet2/23
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	57	TenGigabitEthernet4/1
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	61	GigabitEthernet5/1
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	115	Port-channel1
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	20	GigabitEthernet2/16
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	10	GigabitEthernet2/6
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	31	GigabitEthernet2/27
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	35	GigabitEthernet2/31
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	11	GigabitEthernet2/7
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	78	TenGigabitEthernet8/4
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	48	GigabitEthernet2/44
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	87	unrouted VLAN 1005
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	77	TenGigabitEthernet8/3
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	65	TenGigabitEthernet5/5
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	29	GigabitEthernet2/25
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	50	GigabitEthernet2/46
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	39	GigabitEthernet2/35
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	64	TenGigabitEthernet5/4
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	58	TenGigabitEthernet4/2
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	41	GigabitEthernet2/37
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	12	GigabitEthernet2/8
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	15	GigabitEthernet2/11
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	81	Null0
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	52	GigabitEthernet2/48
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	60	TenGigabitEthernet4/4
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	56	TenGigabitEthernet3/4
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	73	TenGigabitEthernet7/3
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	66	GigabitEthernet6/1
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	45	GigabitEthernet2/41
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	86	unrouted VLAN 1004
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	76	TenGigabitEthernet8/2
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	19	GigabitEthernet2/15
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	62	GigabitEthernet5/2
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	54	TenGigabitEthernet3/2
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	67	GigabitEthernet6/2
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	70	TenGigabitEthernet6/5
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	129	Loopback3001
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	68	GigabitEthernet6/3
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	2	TenGigabitEthernet1/2
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	17	GigabitEthernet2/13
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	1	TenGigabitEthernet1/1
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	88	unrouted VLAN 1003
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	30	GigabitEthernet2/26
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	82	SPAN RP Interface
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	128	Loopback3000
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	25	GigabitEthernet2/21
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	120	Tunnel0
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	28	GigabitEthernet2/24
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	83	Control Plane Interface
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	75	TenGigabitEthernet8/1
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	40	GigabitEthernet2/36
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	14	GigabitEthernet2/10
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	69	TenGigabitEthernet6/4
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	59	TenGigabitEthernet4/3
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	49	GigabitEthernet2/45
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	24	GigabitEthernet2/20
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	124	Tunnel2
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	53	TenGigabitEthernet3/1
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	122	Port-channel2
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	121	Tunnel1
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	79	Vlan1
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	22	GigabitEthernet2/18
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	42	GigabitEthernet2/38
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	46	GigabitEthernet2/42
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	23	GigabitEthernet2/19
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	13	GigabitEthernet2/9
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	126	Vlan3000
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	6	GigabitEthernet2/2
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	85	unrouted VLAN 1002
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	3	TenGigabitEthernet1/3
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	36	GigabitEthernet2/32
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	9	GigabitEthernet2/5
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	51	GigabitEthernet2/47
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	47	GigabitEthernet2/43
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	8	GigabitEthernet2/4
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	38	GigabitEthernet2/34
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	4	TenGigabitEthernet1/4
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	34	GigabitEthernet2/30
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	37	GigabitEthernet2/33
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	117	unrouted VLAN 254
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	43	GigabitEthernet2/39
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	5	GigabitEthernet2/1
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	33	GigabitEthernet1/33
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	32	GigabitEthernet1/32
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	63	Tunnel1
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	21	GigabitEthernet1/21
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	7	GigabitEthernet1/7
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	26	GigabitEthernet1/26
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	18	GigabitEthernet1/18
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	72	Vlan183
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	16	GigabitEthernet1/16
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	44	GigabitEthernet1/44
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	55	FastEthernet1
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	27	GigabitEthernet1/27
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	57	unrouted VLAN 1
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	61	unrouted VLAN 1003
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	20	GigabitEthernet1/20
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	10	GigabitEthernet1/10
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	31	GigabitEthernet1/31
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	35	GigabitEthernet1/35
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	11	GigabitEthernet1/11
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	48	GigabitEthernet1/48
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	29	GigabitEthernet1/29
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	50	TenGigabitEthernet1/50
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	39	GigabitEthernet1/39
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	64	Loopback0
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	58	unrouted VLAN 1002
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	41	GigabitEthernet1/41
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	12	GigabitEthernet1/12
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	15	GigabitEthernet1/15
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	52	TenGigabitEthernet1/52
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	60	unrouted VLAN 1005
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	56	Vlan1
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	45	GigabitEthernet1/45
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	19	GigabitEthernet1/19
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	62	Tunnel0
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	54	Null0
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	67	Vlan234
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	70	Tunnel2
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	68	unrouted VLAN 234
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	2	GigabitEthernet1/2
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	17	GigabitEthernet1/17
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	1	GigabitEthernet1/1
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	30	GigabitEthernet1/30
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	25	GigabitEthernet1/25
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	28	GigabitEthernet1/28
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	40	GigabitEthernet1/40
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	14	GigabitEthernet1/14
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	69	unrouted VLAN 183
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	59	unrouted VLAN 1004
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	49	TenGigabitEthernet1/49
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	24	GigabitEthernet1/24
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	22	GigabitEthernet1/22
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	42	GigabitEthernet1/42
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	46	GigabitEthernet1/46
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	23	GigabitEthernet1/23
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	13	GigabitEthernet1/13
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	6	GigabitEthernet1/6
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	3	GigabitEthernet1/3
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	36	GigabitEthernet1/36
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	9	GigabitEthernet1/9
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	51	TenGigabitEthernet1/51
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	47	GigabitEthernet1/47
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	8	GigabitEthernet1/8
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	38	GigabitEthernet1/38
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	4	GigabitEthernet1/4
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	34	GigabitEthernet1/34
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	37	GigabitEthernet1/37
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	43	GigabitEthernet1/43
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	5	GigabitEthernet1/5
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	33	GigabitEthernet1/33
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	32	GigabitEthernet1/32
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	63	Tunnel0
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	21	GigabitEthernet1/21
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	7	GigabitEthernet1/7
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	26	GigabitEthernet1/26
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	18	GigabitEthernet1/18
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	16	GigabitEthernet1/16
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	44	GigabitEthernet1/44
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	55	FastEthernet1
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	27	GigabitEthernet1/27
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	57	unrouted VLAN 1
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	61	unrouted VLAN 1003
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	20	GigabitEthernet1/20
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	10	GigabitEthernet1/10
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	31	GigabitEthernet1/31
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	35	GigabitEthernet1/35
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	11	GigabitEthernet1/11
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	48	GigabitEthernet1/48
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	65	Loopback0
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	29	GigabitEthernet1/29
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	50	TenGigabitEthernet1/50
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	39	GigabitEthernet1/39
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	64	Tunnel1
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	58	unrouted VLAN 1002
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	41	GigabitEthernet1/41
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	12	GigabitEthernet1/12
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	15	GigabitEthernet1/15
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	52	TenGigabitEthernet1/52
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	60	unrouted VLAN 1005
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	56	Vlan1
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	66	unrouted VLAN 224
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	45	GigabitEthernet1/45
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	19	GigabitEthernet1/19
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	62	unrouted VLAN 899
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	54	Null0
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	67	Vlan224
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	68	Tunnel2
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	2	GigabitEthernet1/2
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	17	GigabitEthernet1/17
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	1	GigabitEthernet1/1
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	30	GigabitEthernet1/30
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	25	GigabitEthernet1/25
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	28	GigabitEthernet1/28
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	40	GigabitEthernet1/40
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	14	GigabitEthernet1/14
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	59	unrouted VLAN 1004
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	49	TenGigabitEthernet1/49
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	24	GigabitEthernet1/24
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	22	GigabitEthernet1/22
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	42	GigabitEthernet1/42
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	46	GigabitEthernet1/46
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	23	GigabitEthernet1/23
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	13	GigabitEthernet1/13
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	6	GigabitEthernet1/6
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	3	GigabitEthernet1/3
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	36	GigabitEthernet1/36
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	9	GigabitEthernet1/9
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	51	TenGigabitEthernet1/51
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	47	GigabitEthernet1/47
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	8	GigabitEthernet1/8
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	38	GigabitEthernet1/38
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	4	GigabitEthernet1/4
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	34	GigabitEthernet1/34
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	37	GigabitEthernet1/37
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	43	GigabitEthernet1/43
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	5	GigabitEthernet1/5
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	33	GigabitEthernet1/33
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	32	GigabitEthernet1/32
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	21	GigabitEthernet1/21
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	7	GigabitEthernet1/7
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	26	GigabitEthernet1/26
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	18	GigabitEthernet1/18
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	16	GigabitEthernet1/16
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	44	GigabitEthernet1/44
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	55	FastEthernet1
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	27	GigabitEthernet1/27
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	57	unrouted VLAN 1
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	61	unrouted VLAN 1003
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	20	GigabitEthernet1/20
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	10	GigabitEthernet1/10
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	31	GigabitEthernet1/31
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	35	GigabitEthernet1/35
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	11	GigabitEthernet1/11
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	48	GigabitEthernet1/48
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	65	Tunnel0
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	29	GigabitEthernet1/29
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	50	TenGigabitEthernet1/50
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	39	GigabitEthernet1/39
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	58	unrouted VLAN 1002
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	41	GigabitEthernet1/41
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	12	GigabitEthernet1/12
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	15	GigabitEthernet1/15
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	52	TenGigabitEthernet1/52
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	60	unrouted VLAN 1005
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	56	Vlan1
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	66	Tunnel1
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	45	GigabitEthernet1/45
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	19	GigabitEthernet1/19
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	54	Null0
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	67	Loopback0
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	70	unrouted VLAN 235
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	68	Tunnel2
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	2	GigabitEthernet1/2
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	17	GigabitEthernet1/17
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	1	GigabitEthernet1/1
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	30	GigabitEthernet1/30
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	25	GigabitEthernet1/25
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	28	GigabitEthernet1/28
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	40	GigabitEthernet1/40
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	14	GigabitEthernet1/14
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	69	Vlan235
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	59	unrouted VLAN 1004
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	49	TenGigabitEthernet1/49
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	24	GigabitEthernet1/24
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	22	GigabitEthernet1/22
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	42	GigabitEthernet1/42
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	46	GigabitEthernet1/46
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	23	GigabitEthernet1/23
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	13	GigabitEthernet1/13
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	6	GigabitEthernet1/6
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	3	GigabitEthernet1/3
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	36	GigabitEthernet1/36
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	9	GigabitEthernet1/9
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	51	TenGigabitEthernet1/51
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	47	GigabitEthernet1/47
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	8	GigabitEthernet1/8
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	38	GigabitEthernet1/38
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	4	GigabitEthernet1/4
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	34	GigabitEthernet1/34
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	37	GigabitEthernet1/37
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	43	GigabitEthernet1/43
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	5	GigabitEthernet1/5
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	33	GigabitEthernet1/33
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	32	GigabitEthernet1/32
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	21	GigabitEthernet1/21
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	7	GigabitEthernet1/7
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	26	GigabitEthernet1/26
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	18	GigabitEthernet1/18
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	16	GigabitEthernet1/16
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	44	GigabitEthernet1/44
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	55	FastEthernet1
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	27	GigabitEthernet1/27
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	57	unrouted VLAN 1
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	61	unrouted VLAN 1003
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	20	GigabitEthernet1/20
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	10	GigabitEthernet1/10
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	31	GigabitEthernet1/31
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	35	GigabitEthernet1/35
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	11	GigabitEthernet1/11
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	48	GigabitEthernet1/48
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	87	Loopback0
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	29	GigabitEthernet1/29
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	50	TenGigabitEthernet1/50
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	39	GigabitEthernet1/39
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	58	unrouted VLAN 1002
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	41	GigabitEthernet1/41
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	12	GigabitEthernet1/12
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	15	GigabitEthernet1/15
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	52	TenGigabitEthernet1/52
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	60	unrouted VLAN 1005
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	56	Vlan1
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	45	GigabitEthernet1/45
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	86	Tunnel1
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	19	GigabitEthernet1/19
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	54	Null0
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	2	GigabitEthernet1/2
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	17	GigabitEthernet1/17
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	1	GigabitEthernet1/1
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	88	Tunnel2
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	30	GigabitEthernet1/30
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	25	GigabitEthernet1/25
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	28	GigabitEthernet1/28
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	40	GigabitEthernet1/40
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	14	GigabitEthernet1/14
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	59	unrouted VLAN 1004
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	49	TenGigabitEthernet1/49
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	24	GigabitEthernet1/24
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	22	GigabitEthernet1/22
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	42	GigabitEthernet1/42
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	46	GigabitEthernet1/46
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	23	GigabitEthernet1/23
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	13	GigabitEthernet1/13
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	6	GigabitEthernet1/6
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	85	Tunnel0
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	3	GigabitEthernet1/3
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	36	GigabitEthernet1/36
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	9	GigabitEthernet1/9
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	51	TenGigabitEthernet1/51
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	47	GigabitEthernet1/47
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	8	GigabitEthernet1/8
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	38	GigabitEthernet1/38
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	4	GigabitEthernet1/4
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	34	GigabitEthernet1/34
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	37	GigabitEthernet1/37
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	43	GigabitEthernet1/43
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	5	GigabitEthernet1/5
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	436248576	Ethernet1/11
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	436224000	Ethernet1/5
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	436240384	Ethernet1/9
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	369098765	port-channel14
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	436244480	Ethernet1/10
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	436277248	Ethernet1/18
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	436273152	Ethernet1/17
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	436252672	Ethernet1/12
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	436232192	Ethernet1/7
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	151060733	Vlan253
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	436215808	Ethernet1/3
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	436269056	Ethernet1/16
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	436224000	Ethernet1/5
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	436240384	Ethernet1/9
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	436211712	Ethernet1/2
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	436211712	Ethernet1/2
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	369098763	port-channel12
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	436264960	Ethernet1/15
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	436281344	Ethernet1/19
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	369098762	port-channel11
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	369098763	port-channel12
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	436264960	Ethernet1/15
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	436281344	Ethernet1/19
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	369098762	port-channel11
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	436219904	Ethernet1/4
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	436256768	Ethernet1/13
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	436260864	Ethernet1/14
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	83886080	mgmt0
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	436236288	Ethernet1/8
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	436207616	Ethernet1/1
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	151060481	Vlan1
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	436228096	Ethernet1/6
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	436219904	Ethernet1/4
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	436256768	Ethernet1/13
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	436260864	Ethernet1/14
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	83886080	mgmt0
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	436236288	Ethernet1/8
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	436285440	Ethernet1/20
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	369098754	port-channel3
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	436248576	Ethernet1/11
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	369098765	port-channel14
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	436244480	Ethernet1/10
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	436277248	Ethernet1/18
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	436273152	Ethernet1/17
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	436252672	Ethernet1/12
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	436232192	Ethernet1/7
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	151060733	Vlan253
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	436215808	Ethernet1/3
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	436269056	Ethernet1/16
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	436224000	Ethernet1/5
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	436240384	Ethernet1/9
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	436211712	Ethernet1/2
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	369098763	port-channel12
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	436264960	Ethernet1/15
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	436281344	Ethernet1/19
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	369098762	port-channel11
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	436219904	Ethernet1/4
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	436256768	Ethernet1/13
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	436260864	Ethernet1/14
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	83886080	mgmt0
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	436236288	Ethernet1/8
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	436207616	Ethernet1/1
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	151060481	Vlan1
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	436228096	Ethernet1/6
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	436285440	Ethernet1/20
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	369098754	port-channel3
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	436248576	Ethernet1/11
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	369098765	port-channel14
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	436244480	Ethernet1/10
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	436277248	Ethernet1/18
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	436273152	Ethernet1/17
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	436252672	Ethernet1/12
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	436232192	Ethernet1/7
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	151060733	Vlan253
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	436215808	Ethernet1/3
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	436269056	Ethernet1/16
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	436224000	Ethernet1/5
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	436240384	Ethernet1/9
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	436211712	Ethernet1/2
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	369098763	port-channel12
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	436264960	Ethernet1/15
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	436281344	Ethernet1/19
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	369098762	port-channel11
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	436219904	Ethernet1/4
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	436256768	Ethernet1/13
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	436260864	Ethernet1/14
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	83886080	mgmt0
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	436236288	Ethernet1/8
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	436207616	Ethernet1/1
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	151060481	Vlan1
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	436228096	Ethernet1/6
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	436285440	Ethernet1/20
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	369098754	port-channel3
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	436248576	Ethernet1/11
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	369098765	port-channel14
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	436244480	Ethernet1/10
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	436277248	Ethernet1/18
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	436273152	Ethernet1/17
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	436252672	Ethernet1/12
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	436232192	Ethernet1/7
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	151060733	Vlan253
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	436215808	Ethernet1/3
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	436269056	Ethernet1/16
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	436207616	Ethernet1/1
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	151060481	Vlan1
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	436228096	Ethernet1/6
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	436285440	Ethernet1/20
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	369098754	port-channel3
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10107	GigabitEthernet1/0/7
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10142	GigabitEthernet1/0/42
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10141	GigabitEthernet1/0/41
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10132	GigabitEthernet1/0/32
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10136	GigabitEthernet1/0/36
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10120	GigabitEthernet1/0/20
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10115	GigabitEthernet1/0/15
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10108	GigabitEthernet1/0/8
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10102	GigabitEthernet1/0/2
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10123	GigabitEthernet1/0/23
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	14001	Null0
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10122	GigabitEthernet1/0/22
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	1	Vlan1
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10144	GigabitEthernet1/0/44
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10121	GigabitEthernet1/0/21
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10134	GigabitEthernet1/0/34
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10135	GigabitEthernet1/0/35
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10148	GigabitEthernet1/0/48
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	252	Vlan252
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10129	GigabitEthernet1/0/29
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	5180	StackSub-St1-1
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10137	GigabitEthernet1/0/37
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10116	GigabitEthernet1/0/16
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10138	GigabitEthernet1/0/38
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10103	GigabitEthernet1/0/3
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10143	GigabitEthernet1/0/43
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10130	GigabitEthernet1/0/30
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10104	GigabitEthernet1/0/4
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10106	GigabitEthernet1/0/6
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10126	GigabitEthernet1/0/26
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10125	GigabitEthernet1/0/25
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10113	GigabitEthernet1/0/13
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10105	GigabitEthernet1/0/5
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10117	GigabitEthernet1/0/17
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10201	TenGigabitEthernet1/0/1
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10112	GigabitEthernet1/0/12
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	5181	StackSub-St1-2
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10147	GigabitEthernet1/0/47
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10139	GigabitEthernet1/0/39
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	5179	StackPort1
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10110	GigabitEthernet1/0/10
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	14002	FastEthernet0
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10150	GigabitEthernet1/0/50
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10149	GigabitEthernet1/0/49
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10133	GigabitEthernet1/0/33
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10118	GigabitEthernet1/0/18
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10131	GigabitEthernet1/0/31
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10127	GigabitEthernet1/0/27
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10202	TenGigabitEthernet1/0/2
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10124	GigabitEthernet1/0/24
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	5001	Port-channel1
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10111	GigabitEthernet1/0/11
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10145	GigabitEthernet1/0/45
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10128	GigabitEthernet1/0/28
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10109	GigabitEthernet1/0/9
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10119	GigabitEthernet1/0/19
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10146	GigabitEthernet1/0/46
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10140	GigabitEthernet1/0/40
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10114	GigabitEthernet1/0/14
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10101	GigabitEthernet1/0/1
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	384	TenGigabitEthernet2/2/7
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	276	TenGigabitEthernet2/1/3
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	206	TenGigabitEthernet1/1/4--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	386	TenGigabitEthernet2/2/7--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	358	TenGigabitEthernet2/1/30--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	331	TenGigabitEthernet2/1/21--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	200	TenGigabitEthernet1/1/1--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	376	TenGigabitEthernet2/2/4--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	366	TenGigabitEthernet2/2/1
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	329	TenGigabitEthernet2/1/20--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	44	unrouted VLAN 1
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	272	TenGigabitEthernet2/1/1--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	233	TenGigabitEthernet1/1/17--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	190	TenGigabitEthernet1/2/1--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	161	TenGigabitEthernet1/1/12
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	298	TenGigabitEthernet2/1/10--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	259	TenGigabitEthernet1/1/30--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	194	TenGigabitEthernet1/2/4--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	368	TenGigabitEthernet2/2/1--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	220	TenGigabitEthernet1/1/11--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	316	TenGigabitEthernet2/1/16--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	313	TenGigabitEthernet2/1/15--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	243	TenGigabitEthernet1/1/22--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	231	TenGigabitEthernet1/1/16--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	163	TenGigabitEthernet1/1/14
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	151	TenGigabitEthernet1/1/2
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	175	TenGigabitEthernet1/1/26
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	148	Loopback0
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	343	TenGigabitEthernet2/1/25--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	347	TenGigabitEthernet2/1/26--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	287	TenGigabitEthernet2/1/6--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	208	TenGigabitEthernet1/1/5--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	294	TenGigabitEthernet2/1/9
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	349	TenGigabitEthernet2/1/27--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	292	TenGigabitEthernet2/1/8--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	275	TenGigabitEthernet2/1/2--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	157	TenGigabitEthernet1/1/8
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	378	TenGigabitEthernet2/2/5
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	325	TenGigabitEthernet2/1/19--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	350	TenGigabitEthernet2/1/27--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	197	TenGigabitEthernet1/2/5--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	203	TenGigabitEthernet1/1/2--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	261	TenGigabitEthernet1/1/31--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	291	TenGigabitEthernet2/1/8
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	374	TenGigabitEthernet2/2/3--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	199	TenGigabitEthernet1/2/6--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	226	TenGigabitEthernet1/1/14--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	211	TenGigabitEthernet1/1/6--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	153	TenGigabitEthernet1/1/4
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	382	TenGigabitEthernet2/2/6--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	337	TenGigabitEthernet2/1/23--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	321	TenGigabitEthernet2/1/18
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	340	TenGigabitEthernet2/1/24--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	284	TenGigabitEthernet2/1/5--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	311	TenGigabitEthernet2/1/14--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	247	TenGigabitEthernet1/1/24--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	371	TenGigabitEthernet2/2/2--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	204	TenGigabitEthernet1/1/3--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	289	TenGigabitEthernet2/1/7--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	241	TenGigabitEthernet1/1/21--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	165	TenGigabitEthernet1/1/16
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	198	TenGigabitEthernet1/2/6--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	389	TenGigabitEthernet2/2/8--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	346	TenGigabitEthernet2/1/26--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	327	TenGigabitEthernet2/1/20
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	320	TenGigabitEthernet2/1/17--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	186	TenGigabitEthernet1/2/5
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	147	Tunnel0
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	333	TenGigabitEthernet2/1/22
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	623	Tunnel0
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	339	TenGigabitEthernet2/1/24
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	280	TenGigabitEthernet2/1/4--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	228	TenGigabitEthernet1/1/15--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	273	TenGigabitEthernet2/1/2
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	323	TenGigabitEthernet2/1/18--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	236	TenGigabitEthernet1/1/19--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	361	TenGigabitEthernet2/1/31--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	268	TenGigabitEthernet1/2/8--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	249	TenGigabitEthernet1/1/25--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	218	TenGigabitEthernet1/1/10--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	168	TenGigabitEthernet1/1/19
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	202	TenGigabitEthernet1/1/2--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	184	TenGigabitEthernet1/2/3
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	348	TenGigabitEthernet2/1/27
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	345	TenGigabitEthernet2/1/26
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	319	TenGigabitEthernet2/1/17--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	172	TenGigabitEthernet1/1/23
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	191	TenGigabitEthernet1/2/1--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	178	TenGigabitEthernet1/1/29
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	224	TenGigabitEthernet1/1/13--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	285	TenGigabitEthernet2/1/6
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	187	TenGigabitEthernet1/2/6
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	223	TenGigabitEthernet1/1/12--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	181	TenGigabitEthernet1/1/32
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	385	TenGigabitEthernet2/2/7--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	234	TenGigabitEthernet1/1/18--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	282	TenGigabitEthernet2/1/5
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	314	TenGigabitEthernet2/1/15--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	307	TenGigabitEthernet2/1/13--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	262	TenGigabitEthernet1/1/32--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	212	TenGigabitEthernet1/1/7--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	154	TenGigabitEthernet1/1/5
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	352	TenGigabitEthernet2/1/28--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	344	TenGigabitEthernet2/1/25--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	388	TenGigabitEthernet2/2/8--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	364	TenGigabitEthernet2/1/32--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	355	TenGigabitEthernet2/1/29--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	238	TenGigabitEthernet1/1/20--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	159	TenGigabitEthernet1/1/10
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	251	TenGigabitEthernet1/1/26--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	369	TenGigabitEthernet2/2/2
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	326	TenGigabitEthernet2/1/19--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	253	TenGigabitEthernet1/1/27--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	160	TenGigabitEthernet1/1/11
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	279	TenGigabitEthernet2/1/4
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	47	unrouted VLAN 1005
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	176	TenGigabitEthernet1/1/27
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	367	TenGigabitEthernet2/2/1--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	209	TenGigabitEthernet1/1/5--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	357	TenGigabitEthernet2/1/30
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	335	TenGigabitEthernet2/1/22--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	256	TenGigabitEthernet1/1/29--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	216	TenGigabitEthernet1/1/9--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	372	TenGigabitEthernet2/2/3
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	43	Vlan1
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	270	TenGigabitEthernet2/1/1
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	195	TenGigabitEthernet1/2/4--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	391	Port-channel20
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	170	TenGigabitEthernet1/1/21
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	227	TenGigabitEthernet1/1/14--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	288	TenGigabitEthernet2/1/7
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	193	TenGigabitEthernet1/2/3--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	336	TenGigabitEthernet2/1/23
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	324	TenGigabitEthernet2/1/19
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	180	TenGigabitEthernet1/1/31
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	244	TenGigabitEthernet1/1/23--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	162	TenGigabitEthernet1/1/13
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	179	TenGigabitEthernet1/1/30
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	383	TenGigabitEthernet2/2/6--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	351	TenGigabitEthernet2/1/28
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	255	TenGigabitEthernet1/1/28--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	264	TenGigabitEthernet1/2/2--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	297	TenGigabitEthernet2/1/10
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	240	TenGigabitEthernet1/1/21--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	246	TenGigabitEthernet1/1/24--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	359	TenGigabitEthernet2/1/30--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	334	TenGigabitEthernet2/1/22--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	182	TenGigabitEthernet1/2/1
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	230	TenGigabitEthernet1/1/16--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	299	TenGigabitEthernet2/1/10--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	377	TenGigabitEthernet2/2/4--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	277	TenGigabitEthernet2/1/3--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	201	TenGigabitEthernet1/1/1--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	379	TenGigabitEthernet2/2/5--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	232	TenGigabitEthernet1/1/17--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	152	TenGigabitEthernet1/1/3
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	189	TenGigabitEthernet1/2/8
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	225	TenGigabitEthernet1/1/13--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	342	TenGigabitEthernet2/1/25
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	330	TenGigabitEthernet2/1/21
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	207	TenGigabitEthernet1/1/4--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	295	TenGigabitEthernet2/1/9--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	263	TenGigabitEthernet1/1/32--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	266	TenGigabitEthernet1/2/7--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	341	TenGigabitEthernet2/1/24--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	167	TenGigabitEthernet1/1/18
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	48	unrouted VLAN 1003
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	360	TenGigabitEthernet2/1/31
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	174	TenGigabitEthernet1/1/25
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	214	TenGigabitEthernet1/1/8--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	290	TenGigabitEthernet2/1/7--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	149	Port-channel1
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	304	TenGigabitEthernet2/1/12--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	221	TenGigabitEthernet1/1/11--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	210	TenGigabitEthernet1/1/6--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	258	TenGigabitEthernet1/1/30--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	312	TenGigabitEthernet2/1/15
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	302	TenGigabitEthernet2/1/11--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	173	TenGigabitEthernet1/1/24
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	45	unrouted VLAN 1002
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	229	TenGigabitEthernet1/1/15--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	260	TenGigabitEthernet1/1/31--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	293	TenGigabitEthernet2/1/8--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	365	TenGigabitEthernet2/1/32--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	274	TenGigabitEthernet2/1/2--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	237	TenGigabitEthernet1/1/19--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	306	TenGigabitEthernet2/1/13
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	370	TenGigabitEthernet2/2/2--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	309	TenGigabitEthernet2/1/14
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	188	TenGigabitEthernet1/2/7
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	322	TenGigabitEthernet2/1/18--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	315	TenGigabitEthernet2/1/16
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	353	TenGigabitEthernet2/1/28--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	166	TenGigabitEthernet1/1/17
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	1	FastEthernet1
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	375	TenGigabitEthernet2/2/4
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	338	TenGigabitEthernet2/1/23--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	380	TenGigabitEthernet2/2/5--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	300	TenGigabitEthernet2/1/11
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	222	TenGigabitEthernet1/1/12--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	252	TenGigabitEthernet1/1/27--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	286	TenGigabitEthernet2/1/6--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	310	TenGigabitEthernet2/1/14--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	283	TenGigabitEthernet2/1/5--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	156	TenGigabitEthernet1/1/7
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	303	TenGigabitEthernet2/1/12
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	192	TenGigabitEthernet1/2/3--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	250	TenGigabitEthernet1/1/26--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	381	TenGigabitEthernet2/2/6
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	305	TenGigabitEthernet2/1/12--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	308	TenGigabitEthernet2/1/13--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	392	Port-channel21
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	215	TenGigabitEthernet1/1/8--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	254	TenGigabitEthernet1/1/28--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	278	TenGigabitEthernet2/1/3--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	177	TenGigabitEthernet1/1/28
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	150	TenGigabitEthernet1/1/1
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	271	TenGigabitEthernet2/1/1--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	373	TenGigabitEthernet2/2/3--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	155	TenGigabitEthernet1/1/6
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	387	TenGigabitEthernet2/2/8
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	217	TenGigabitEthernet1/1/9--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	328	TenGigabitEthernet2/1/20--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	239	TenGigabitEthernet1/1/20--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	245	TenGigabitEthernet1/1/23--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	267	TenGigabitEthernet1/2/7--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	281	TenGigabitEthernet2/1/4--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	269	TenGigabitEthernet1/2/8--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	42	Null0
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	158	TenGigabitEthernet1/1/9
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	205	TenGigabitEthernet1/1/3--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	363	TenGigabitEthernet2/1/32
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	354	TenGigabitEthernet2/1/29
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	46	unrouted VLAN 1004
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	219	TenGigabitEthernet1/1/10--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	318	TenGigabitEthernet2/1/17
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	235	TenGigabitEthernet1/1/18--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	257	TenGigabitEthernet1/1/29--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	301	TenGigabitEthernet2/1/11--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	185	TenGigabitEthernet1/2/4
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	390	Port-channel2
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	332	TenGigabitEthernet2/1/21--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	183	TenGigabitEthernet1/2/2
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	213	TenGigabitEthernet1/1/7--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	248	TenGigabitEthernet1/1/25--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	356	TenGigabitEthernet2/1/29--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	362	TenGigabitEthernet2/1/31--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	317	TenGigabitEthernet2/1/16--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	296	TenGigabitEthernet2/1/9--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	265	TenGigabitEthernet1/2/2--Controlled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	164	TenGigabitEthernet1/1/15
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	169	TenGigabitEthernet1/1/20
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	196	TenGigabitEthernet1/2/5--Uncontrolled
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	171	TenGigabitEthernet1/1/22
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	242	TenGigabitEthernet1/1/22--Uncontrolled
auto-FuglebergDistro.infra.tg14.gathering.org-2c:36:f8:88:48:00	10107	GigabitEthernet0/7
auto-FuglebergDistro.infra.tg14.gathering.org-2c:36:f8:88:48:00	10105	GigabitEthernet0/5
auto-FuglebergDistro.infra.tg14.gathering.org-2c:36:f8:88:48:00	10501	Null0
auto-FuglebergDistro.infra.tg14.gathering.org-2c:36:f8:88:48:00	10108	GigabitEthernet0/8
auto-FuglebergDistro.infra.tg14.gathering.org-2c:36:f8:88:48:00	10102	GigabitEthernet0/2
auto-FuglebergDistro.infra.tg14.gathering.org-2c:36:f8:88:48:00	20567	Loopback0
auto-FuglebergDistro.infra.tg14.gathering.org-2c:36:f8:88:48:00	2271	Vlan2271
auto-FuglebergDistro.infra.tg14.gathering.org-2c:36:f8:88:48:00	1	Vlan1
auto-FuglebergDistro.infra.tg14.gathering.org-2c:36:f8:88:48:00	10110	GigabitEthernet0/10
auto-FuglebergDistro.infra.tg14.gathering.org-2c:36:f8:88:48:00	10109	GigabitEthernet0/9
auto-FuglebergDistro.infra.tg14.gathering.org-2c:36:f8:88:48:00	10103	GigabitEthernet0/3
auto-FuglebergDistro.infra.tg14.gathering.org-2c:36:f8:88:48:00	10104	GigabitEthernet0/4
auto-FuglebergDistro.infra.tg14.gathering.org-2c:36:f8:88:48:00	10106	GigabitEthernet0/6
auto-FuglebergDistro.infra.tg14.gathering.org-2c:36:f8:88:48:00	10101	GigabitEthernet0/1
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10107	GigabitEthernet1/0/7
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10142	GigabitEthernet1/0/42
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10141	GigabitEthernet1/0/41
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10132	GigabitEthernet1/0/32
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10136	GigabitEthernet1/0/36
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10120	GigabitEthernet1/0/20
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10115	GigabitEthernet1/0/15
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10108	GigabitEthernet1/0/8
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10102	GigabitEthernet1/0/2
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10123	GigabitEthernet1/0/23
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	14001	Null0
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10122	GigabitEthernet1/0/22
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	1	Vlan1
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10144	GigabitEthernet1/0/44
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10121	GigabitEthernet1/0/21
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10134	GigabitEthernet1/0/34
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10135	GigabitEthernet1/0/35
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10148	GigabitEthernet1/0/48
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	252	Vlan252
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10129	GigabitEthernet1/0/29
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	5180	StackSub-St1-1
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10137	GigabitEthernet1/0/37
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10116	GigabitEthernet1/0/16
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10138	GigabitEthernet1/0/38
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10103	GigabitEthernet1/0/3
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10143	GigabitEthernet1/0/43
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10130	GigabitEthernet1/0/30
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10104	GigabitEthernet1/0/4
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10106	GigabitEthernet1/0/6
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10126	GigabitEthernet1/0/26
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10125	GigabitEthernet1/0/25
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10113	GigabitEthernet1/0/13
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10105	GigabitEthernet1/0/5
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10117	GigabitEthernet1/0/17
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10201	TenGigabitEthernet1/0/1
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10112	GigabitEthernet1/0/12
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	5181	StackSub-St1-2
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10147	GigabitEthernet1/0/47
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10139	GigabitEthernet1/0/39
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	5179	StackPort1
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10110	GigabitEthernet1/0/10
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	14002	FastEthernet0
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10150	GigabitEthernet1/0/50
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10149	GigabitEthernet1/0/49
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	24067	Loopback0
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10133	GigabitEthernet1/0/33
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10118	GigabitEthernet1/0/18
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10131	GigabitEthernet1/0/31
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10127	GigabitEthernet1/0/27
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10202	TenGigabitEthernet1/0/2
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10124	GigabitEthernet1/0/24
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	5001	Port-channel1
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10111	GigabitEthernet1/0/11
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10145	GigabitEthernet1/0/45
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10128	GigabitEthernet1/0/28
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10109	GigabitEthernet1/0/9
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10119	GigabitEthernet1/0/19
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10146	GigabitEthernet1/0/46
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10140	GigabitEthernet1/0/40
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10114	GigabitEthernet1/0/14
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10101	GigabitEthernet1/0/1
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	559	GigabitEthernet6/24--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	127	GigabitEthernet5/22
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	32	GigabitEthernet1/31
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	443	GigabitEthernet5/14--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	206	unrouted VLAN 1004
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	118	GigabitEthernet5/13
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	71	GigabitEthernet2/22
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	358	GigabitEthernet2/27--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	331	GigabitEthernet2/14--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	560	GigabitEthernet6/24--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	580	GigabitEthernet6/34--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	84	GigabitEthernet2/35
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	512	GigabitEthernet5/48--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	437	GigabitEthernet5/11--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	463	GigabitEthernet5/24--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	194	GigabitEthernet6/41
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	517	GigabitEthernet6/3--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	458	GigabitEthernet5/21--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	451	GigabitEthernet5/18--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	220	GigabitEthernet1/6--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	454	GigabitEthernet5/19--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	31	GigabitEthernet1/30
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	578	GigabitEthernet6/33--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	378	GigabitEthernet2/37--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	325	GigabitEthernet2/11--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	29	GigabitEthernet1/28
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	572	GigabitEthernet6/30--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	350	GigabitEthernet2/23--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	540	GigabitEthernet6/14--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	226	GigabitEthernet1/9--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	58	GigabitEthernet2/9
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	211	GigabitEthernet1/2--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	153	GigabitEthernet5/48
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	15	GigabitEthernet1/14
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	527	GigabitEthernet6/8--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	431	GigabitEthernet5/8--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	382	GigabitEthernet2/39--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	337	GigabitEthernet2/17--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	101	TenGigabitEthernet3/4
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	340	GigabitEthernet2/18--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	76	GigabitEthernet2/27
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	311	GigabitEthernet2/4--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	62	GigabitEthernet2/13
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	571	GigabitEthernet6/30--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	139	GigabitEthernet5/34
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	389	GigabitEthernet2/43--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	129	GigabitEthernet5/24
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	548	GigabitEthernet6/18--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	495	GigabitEthernet5/40--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	418	GigabitEthernet5/1--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	236	GigabitEthernet1/14--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	218	GigabitEthernet1/5--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	168	GigabitEthernet6/15
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	135	GigabitEthernet5/30
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	14	GigabitEthernet1/13
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	348	GigabitEthernet2/22--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	145	GigabitEthernet5/40
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	49	GigabitEthernet1/48
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	178	GigabitEthernet6/25
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	285	GigabitEthernet1/39--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	124	GigabitEthernet5/19
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	234	GigabitEthernet1/13--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	594	GigabitEthernet6/41--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	23	GigabitEthernet1/22
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	388	GigabitEthernet2/42--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	364	GigabitEthernet2/30--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	96	GigabitEthernet2/47
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	486	GigabitEthernet5/35--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	509	GigabitEthernet5/47--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	160	GigabitEthernet6/7
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	569	GigabitEthernet6/29--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	367	GigabitEthernet2/32--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	8	GigabitEthernet1/7
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	98	TenGigabitEthernet3/1
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	43	GigabitEthernet1/42
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	485	GigabitEthernet5/35--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	391	GigabitEthernet2/44--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	21	GigabitEthernet1/20
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	523	GigabitEthernet6/6--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	288	GigabitEthernet1/40--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	193	GigabitEthernet6/40
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	460	GigabitEthernet5/22--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	119	GigabitEthernet5/14
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	586	GigabitEthernet6/37--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	453	GigabitEthernet5/19--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	324	GigabitEthernet2/10--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	180	GigabitEthernet6/27
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	244	GigabitEthernet1/18--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	351	GigabitEthernet2/24--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	410	TenGigabitEthernet4/1--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	595	GigabitEthernet6/42--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	246	GigabitEthernet1/19--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	488	GigabitEthernet5/36--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	61	GigabitEthernet2/12
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	430	GigabitEthernet5/7--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	447	GigabitEthernet5/16--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	536	GigabitEthernet6/12--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	379	GigabitEthernet2/38--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	415	TenGigabitEthernet4/4--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	113	GigabitEthernet5/8
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	152	GigabitEthernet5/47
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	189	GigabitEthernet6/36
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	452	GigabitEthernet5/18--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	342	GigabitEthernet2/19--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	579	GigabitEthernet6/34--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	295	GigabitEthernet1/44--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	480	GigabitEthernet5/32--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	341	GigabitEthernet2/19--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	438	GigabitEthernet5/11--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	107	GigabitEthernet5/2
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	535	GigabitEthernet6/12--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	87	GigabitEthernet2/38
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	77	GigabitEthernet2/28
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	444	GigabitEthernet5/14--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	541	GigabitEthernet6/15--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	508	GigabitEthernet5/46--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	221	GigabitEthernet1/7--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	39	GigabitEthernet1/38
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	64	GigabitEthernet2/15
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	558	GigabitEthernet6/23--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	417	GigabitEthernet5/1--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	12	GigabitEthernet1/11
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	312	GigabitEthernet2/4--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	45	GigabitEthernet1/44
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	507	GigabitEthernet5/46--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	405	TenGigabitEthernet3/3--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	260	GigabitEthernet1/26--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	573	GigabitEthernet6/31--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	237	GigabitEthernet1/15--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	370	GigabitEthernet2/33--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	309	GigabitEthernet2/3--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	567	GigabitEthernet6/28--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	1	FastEthernet1
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	506	GigabitEthernet5/45--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	136	GigabitEthernet5/31
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	116	GigabitEthernet5/11
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	416	TenGigabitEthernet4/4--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	144	GigabitEthernet5/39
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	380	GigabitEthernet2/38--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	100	TenGigabitEthernet3/3
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	300	GigabitEthernet1/46--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	286	GigabitEthernet1/39--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	120	GigabitEthernet5/15
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	381	GigabitEthernet2/39--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	581	GigabitEthernet6/35--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	308	GigabitEthernet2/2--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	392	GigabitEthernet2/44--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	254	GigabitEthernet1/23--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	177	GigabitEthernet6/24
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	496	GigabitEthernet5/40--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	605	GigabitEthernet6/47--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	373	GigabitEthernet2/35--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	607	GigabitEthernet6/48--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	205	unrouted VLAN 1002
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	42	GigabitEthernet1/41
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	22	GigabitEthernet1/21
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	399	GigabitEthernet2/48--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	235	GigabitEthernet1/14--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	301	GigabitEthernet1/47--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	436	GigabitEthernet5/10--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	213	GigabitEthernet1/3--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	94	GigabitEthernet2/45
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	51	GigabitEthernet2/2
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	456	GigabitEthernet5/20--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	568	GigabitEthernet6/28--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	296	GigabitEthernet1/44--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	265	GigabitEthernet1/29--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	493	GigabitEthernet5/39--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	171	GigabitEthernet6/18
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	386	GigabitEthernet2/41--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	445	GigabitEthernet5/15--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	200	GigabitEthernet6/47
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	366	GigabitEthernet2/31--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	329	GigabitEthernet2/13--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	525	GigabitEthernet6/7--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	27	GigabitEthernet1/26
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	272	GigabitEthernet1/32--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	161	GigabitEthernet6/8
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	582	GigabitEthernet6/35--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	534	GigabitEthernet6/11--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	400	GigabitEthernet2/48--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	20	GigabitEthernet1/19
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	109	GigabitEthernet5/4
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	151	GigabitEthernet5/46
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	557	GigabitEthernet6/23--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	468	GigabitEthernet5/26--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	287	GigabitEthernet1/40--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	475	GigabitEthernet5/30--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	441	GigabitEthernet5/13--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	78	GigabitEthernet2/29
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	413	TenGigabitEthernet4/3--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	294	GigabitEthernet1/43--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	349	GigabitEthernet2/23--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	275	GigabitEthernet1/34--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	515	GigabitEthernet6/2--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	197	GigabitEthernet6/44
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	138	GigabitEthernet5/33
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	606	GigabitEthernet6/47--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	137	GigabitEthernet5/32
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	60	GigabitEthernet2/11
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	432	GigabitEthernet5/8--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	519	GigabitEthernet6/4--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	346	GigabitEthernet2/21--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	17	GigabitEthernet1/16
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	427	GigabitEthernet5/6--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	82	GigabitEthernet2/33
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	110	GigabitEthernet5/5
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	333	GigabitEthernet2/15--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	590	GigabitEthernet6/39--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	323	GigabitEthernet2/10--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	69	GigabitEthernet2/20
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	112	GigabitEthernet5/7
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	545	GigabitEthernet6/17--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	191	GigabitEthernet6/38
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	224	GigabitEthernet1/8--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	187	GigabitEthernet6/34
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	588	GigabitEthernet6/38--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	446	GigabitEthernet5/15--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	262	GigabitEthernet1/27--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	79	GigabitEthernet2/30
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	212	GigabitEthernet1/2--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	352	GigabitEthernet2/24--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	126	GigabitEthernet5/21
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	426	GigabitEthernet5/5--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	251	GigabitEthernet1/22--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	542	GigabitEthernet6/15--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	369	GigabitEthernet2/33--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	279	GigabitEthernet1/36--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	176	GigabitEthernet6/23
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	498	GigabitEthernet5/41--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	483	GigabitEthernet5/34--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	256	GigabitEthernet1/24--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	372	GigabitEthernet2/34--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	574	GigabitEthernet6/31--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	170	GigabitEthernet6/17
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	33	GigabitEthernet1/32
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	428	GigabitEthernet5/6--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	7	GigabitEthernet1/6
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	26	GigabitEthernet1/25
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	227	GigabitEthernet1/10--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	99	TenGigabitEthernet3/2
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	566	GigabitEthernet6/27--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	526	GigabitEthernet6/7--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	72	GigabitEthernet2/23
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	500	GigabitEthernet5/42--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	264	GigabitEthernet1/28--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	255	GigabitEthernet1/24--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	533	GigabitEthernet6/11--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	359	GigabitEthernet2/28--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	182	GigabitEthernet6/29
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	108	GigabitEthernet5/3
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	604	GigabitEthernet6/46--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	556	GigabitEthernet6/22--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	462	GigabitEthernet5/23--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	414	TenGigabitEthernet4/3--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	232	GigabitEthernet1/12--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	477	GigabitEthernet5/31--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	225	GigabitEthernet1/9--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	330	GigabitEthernet2/13--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	142	GigabitEthernet5/37
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	207	unrouted VLAN 1005
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	263	GigabitEthernet1/28--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	394	GigabitEthernet2/45--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	167	GigabitEthernet6/14
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	48	GigabitEthernet1/47
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	360	GigabitEthernet2/28--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	610	Tunnel0
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	514	GigabitEthernet6/1--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	513	GigabitEthernet6/1--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	50	GigabitEthernet2/1
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	476	GigabitEthernet5/30--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	510	GigabitEthernet5/47--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	393	GigabitEthernet2/45--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	449	GigabitEthernet5/17--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	293	GigabitEthernet1/43--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	274	GigabitEthernet1/33--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	549	GigabitEthernet6/19--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	322	GigabitEthernet2/9--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	469	GigabitEthernet5/27--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	353	GigabitEthernet2/25--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	575	GigabitEthernet6/32--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	375	GigabitEthernet2/36--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	128	GigabitEthernet5/23
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	28	GigabitEthernet1/27
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	310	GigabitEthernet2/3--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	40	GigabitEthernet1/39
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	589	GigabitEthernet6/39--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	303	GigabitEthernet1/48--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	192	GigabitEthernet6/39
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	250	GigabitEthernet1/21--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	501	GigabitEthernet5/43--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	215	GigabitEthernet1/4--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	278	GigabitEthernet1/35--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	490	GigabitEthernet5/37--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	150	GigabitEthernet5/45
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	130	GigabitEthernet5/25
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	155	GigabitEthernet6/2
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	387	GigabitEthernet2/42--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	53	GigabitEthernet2/4
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	245	GigabitEthernet1/19--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	543	GigabitEthernet6/16--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	267	GigabitEthernet1/30--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	354	GigabitEthernet2/25--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	461	GigabitEthernet5/23--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	583	GigabitEthernet6/36--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	257	GigabitEthernet1/25--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	85	GigabitEthernet2/36
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	332	GigabitEthernet2/14--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	9	GigabitEthernet1/8
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	425	GigabitEthernet5/5--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	591	GigabitEthernet6/40--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	34	GigabitEthernet1/33
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	539	GigabitEthernet6/14--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	603	GigabitEthernet6/46--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	90	GigabitEthernet2/41
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	276	GigabitEthernet1/34--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	565	GigabitEthernet6/27--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	102	TenGigabitEthernet4/1
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	520	GigabitEthernet6/4--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	532	GigabitEthernet6/10--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	16	GigabitEthernet1/15
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	55	GigabitEthernet2/6
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	233	GigabitEthernet1/13--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	57	GigabitEthernet2/8
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	259	GigabitEthernet1/26--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	368	GigabitEthernet2/32--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	424	GigabitEthernet5/4--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	316	GigabitEthernet2/6--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	163	GigabitEthernet6/10
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	395	GigabitEthernet2/46--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	89	GigabitEthernet2/40
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	611	Loopback0
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	175	GigabitEthernet6/22
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	584	GigabitEthernet6/36--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	35	GigabitEthernet1/34
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	11	GigabitEthernet1/10
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	492	GigabitEthernet5/38--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	208	unrouted VLAN 1003
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	347	GigabitEthernet2/22--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	511	GigabitEthernet5/48--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	434	GigabitEthernet5/9--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	93	GigabitEthernet2/44
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	292	GigabitEthernet1/42--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	291	GigabitEthernet1/42--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	374	GigabitEthernet2/35--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	114	GigabitEthernet5/9
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	199	GigabitEthernet6/46
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	442	GigabitEthernet5/13--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	429	GigabitEthernet5/7--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	73	GigabitEthernet2/24
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	409	TenGigabitEthernet4/1--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	67	GigabitEthernet2/18
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	241	GigabitEthernet1/17--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	198	GigabitEthernet6/45
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	489	GigabitEthernet5/37--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	585	GigabitEthernet6/37--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	327	GigabitEthernet2/12--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	320	GigabitEthernet2/8--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	280	GigabitEthernet1/36--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	273	GigabitEthernet1/33--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	471	GigabitEthernet5/28--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	202	Null0
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	249	GigabitEthernet1/21--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	361	GigabitEthernet2/29--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	465	GigabitEthernet5/25--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	184	GigabitEthernet6/31
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	24	GigabitEthernet1/23
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	140	GigabitEthernet5/35
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	104	TenGigabitEthernet4/3
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	131	GigabitEthernet5/26
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	181	GigabitEthernet6/28
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	412	TenGigabitEthernet4/2--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	385	GigabitEthernet2/41--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	502	GigabitEthernet5/43--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	307	GigabitEthernet2/2--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	314	GigabitEthernet2/5--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	154	GigabitEthernet6/1
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	355	GigabitEthernet2/26--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	553	GigabitEthernet6/21--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	159	GigabitEthernet6/6
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	479	GigabitEthernet5/32--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	326	GigabitEthernet2/11--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	555	GigabitEthernet6/22--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	47	GigabitEthernet1/46
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	37	GigabitEthernet1/36
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	335	GigabitEthernet2/16--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	270	GigabitEthernet1/31--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	5	GigabitEthernet1/4
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	195	GigabitEthernet6/42
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	538	GigabitEthernet6/13--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	524	GigabitEthernet6/6--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	554	GigabitEthernet6/21--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	552	GigabitEthernet6/20--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	521	GigabitEthernet6/5--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	598	GigabitEthernet6/43--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	162	GigabitEthernet6/9
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	433	GigabitEthernet5/9--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	74	GigabitEthernet2/25
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	240	GigabitEthernet1/16--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	334	GigabitEthernet2/15--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	440	GigabitEthernet5/12--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	230	GigabitEthernet1/11--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	115	GigabitEthernet5/10
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	299	GigabitEthernet1/46--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	377	GigabitEthernet2/37--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	103	TenGigabitEthernet4/2
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	602	GigabitEthernet6/45--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	201	GigabitEthernet6/48
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	423	GigabitEthernet5/4--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	91	GigabitEthernet2/42
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	266	GigabitEthernet1/29--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	467	GigabitEthernet5/26--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	174	GigabitEthernet6/21
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	474	GigabitEthernet5/29--Controlled
auto-GameHQSW2-00:26:5a:e4:9e:e4	129	Null0
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	481	GigabitEthernet5/33--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	214	GigabitEthernet1/3--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	422	GigabitEthernet5/3--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	564	GigabitEthernet6/26--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	563	GigabitEthernet6/26--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	97	GigabitEthernet2/48
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	41	GigabitEthernet1/40
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	52	GigabitEthernet2/3
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	302	GigabitEthernet1/47--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	229	GigabitEthernet1/11--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	503	GigabitEthernet5/44--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	593	GigabitEthernet6/41--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	68	GigabitEthernet2/19
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	188	GigabitEthernet6/35
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	315	GigabitEthernet2/6--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	402	TenGigabitEthernet3/1--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	338	GigabitEthernet2/17--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	576	GigabitEthernet6/32--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	222	GigabitEthernet1/7--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	25	GigabitEthernet1/24
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	83	GigabitEthernet2/34
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	484	GigabitEthernet5/34--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	305	GigabitEthernet2/1--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	544	GigabitEthernet6/16--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	217	GigabitEthernet1/5--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	328	GigabitEthernet2/12--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	239	GigabitEthernet1/16--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	122	GigabitEthernet5/17
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	143	GigabitEthernet5/38
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	158	GigabitEthernet6/5
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	269	GigabitEthernet1/31--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	281	GigabitEthernet1/37--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	464	GigabitEthernet5/24--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	363	GigabitEthernet2/30--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	46	GigabitEthernet1/45
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	6	GigabitEthernet1/5
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	562	GigabitEthernet6/25--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	36	GigabitEthernet1/35
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	518	GigabitEthernet6/3--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	183	GigabitEthernet6/30
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	497	GigabitEthernet5/41--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	472	GigabitEthernet5/28--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	362	GigabitEthernet2/29--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	439	GigabitEthernet5/12--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	317	GigabitEthernet2/7--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	608	GigabitEthernet6/48--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	132	GigabitEthernet5/27
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	169	GigabitEthernet6/16
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	411	TenGigabitEthernet4/2--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	478	GigabitEthernet5/31--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	384	GigabitEthernet2/40--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	398	GigabitEthernet2/47--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	546	GigabitEthernet6/17--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	537	GigabitEthernet6/13--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	407	TenGigabitEthernet3/4--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	18	GigabitEthernet1/17
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	376	GigabitEthernet2/36--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	522	GigabitEthernet6/5--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	125	GigabitEthernet5/20
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	599	GigabitEthernet6/44--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	44	GigabitEthernet1/43
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	609	Port-channel12
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	587	GigabitEthernet6/38--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	190	GigabitEthernet6/37
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	95	GigabitEthernet2/46
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	298	GigabitEthernet1/45--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	601	GigabitEthernet6/45--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	313	GigabitEthernet2/5--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	243	GigabitEthernet1/18--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	231	GigabitEthernet1/12--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	551	GigabitEthernet6/20--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	529	GigabitEthernet6/9--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	148	GigabitEthernet5/43
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	343	GigabitEthernet2/20--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	504	GigabitEthernet5/44--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	397	GigabitEthernet2/47--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	106	GigabitEthernet5/1
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	157	GigabitEthernet6/4
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	65	GigabitEthernet2/16
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	203	Vlan1
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	261	GigabitEthernet1/27--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	81	GigabitEthernet2/32
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	321	GigabitEthernet2/9--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	459	GigabitEthernet5/22--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	86	GigabitEthernet2/37
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	284	GigabitEthernet1/38--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	247	GigabitEthernet1/20--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	371	GigabitEthernet2/34--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	204	unrouted VLAN 1
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	165	GigabitEthernet6/12
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	289	GigabitEthernet1/41--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	2	GigabitEthernet1/1
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	435	GigabitEthernet5/10--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	401	TenGigabitEthernet3/1--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	186	GigabitEthernet6/33
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	147	GigabitEthernet5/42
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	339	GigabitEthernet2/18--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	228	GigabitEthernet1/10--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	531	GigabitEthernet6/10--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	268	GigabitEthernet1/30--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	345	GigabitEthernet2/21--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	596	GigabitEthernet6/42--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	172	GigabitEthernet6/19
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	319	GigabitEthernet2/8--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	223	GigabitEthernet1/8--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	404	TenGigabitEthernet3/2--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	516	GigabitEthernet6/2--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	282	GigabitEthernet1/37--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	420	GigabitEthernet5/2--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	121	GigabitEthernet5/16
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	344	GigabitEthernet2/20--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	487	GigabitEthernet5/36--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	494	GigabitEthernet5/39--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	238	GigabitEthernet1/15--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	577	GigabitEthernet6/33--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	253	GigabitEthernet1/23--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	561	GigabitEthernet6/25--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	448	GigabitEthernet5/16--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	209	GigabitEthernet1/1--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	216	GigabitEthernet1/4--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	357	GigabitEthernet2/27--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	117	GigabitEthernet5/12
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	63	GigabitEthernet2/14
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	455	GigabitEthernet5/20--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	600	GigabitEthernet6/44--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	80	GigabitEthernet2/31
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	336	GigabitEthernet2/16--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	457	GigabitEthernet5/21--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	179	GigabitEthernet6/26
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	383	GigabitEthernet2/40--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	297	GigabitEthernet1/45--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	277	GigabitEthernet1/35--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	92	GigabitEthernet2/43
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	10	GigabitEthernet1/9
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	550	GigabitEthernet6/19--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	505	GigabitEthernet5/45--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	419	GigabitEthernet5/2--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	133	GigabitEthernet5/28
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	290	GigabitEthernet1/41--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	592	GigabitEthernet6/40--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	149	GigabitEthernet5/44
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	123	GigabitEthernet5/18
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	304	GigabitEthernet1/48--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	547	GigabitEthernet6/18--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	210	GigabitEthernet1/1--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	406	TenGigabitEthernet3/3--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	258	GigabitEthernet1/25--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	396	GigabitEthernet2/46--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	482	GigabitEthernet5/33--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	173	GigabitEthernet6/20
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	530	GigabitEthernet6/9--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	56	GigabitEthernet2/7
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	499	GigabitEthernet5/42--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	66	GigabitEthernet2/17
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	19	GigabitEthernet1/18
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	54	GigabitEthernet2/5
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	365	GigabitEthernet2/31--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	306	GigabitEthernet2/1--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	70	GigabitEthernet2/21
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	470	GigabitEthernet5/27--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	166	GigabitEthernet6/13
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	88	GigabitEthernet2/39
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	141	GigabitEthernet5/36
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	30	GigabitEthernet1/29
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	570	GigabitEthernet6/29--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	403	TenGigabitEthernet3/2--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	252	GigabitEthernet1/22--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	466	GigabitEthernet5/25--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	156	GigabitEthernet6/3
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	134	GigabitEthernet5/29
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	75	GigabitEthernet2/26
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	283	GigabitEthernet1/38--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	59	GigabitEthernet2/10
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	421	GigabitEthernet5/3--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	450	GigabitEthernet5/17--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	271	GigabitEthernet1/32--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	491	GigabitEthernet5/38--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	219	GigabitEthernet1/6--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	318	GigabitEthernet2/7--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	13	GigabitEthernet1/12
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	105	TenGigabitEthernet4/4
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	473	GigabitEthernet5/29--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	185	GigabitEthernet6/32
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	3	GigabitEthernet1/2
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	597	GigabitEthernet6/43--Uncontrolled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	248	GigabitEthernet1/20--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	390	GigabitEthernet2/43--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	146	GigabitEthernet5/41
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	111	GigabitEthernet5/6
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	38	GigabitEthernet1/37
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	356	GigabitEthernet2/26--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	408	TenGigabitEthernet3/4--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	4	GigabitEthernet1/3
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	528	GigabitEthernet6/8--Controlled
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	164	GigabitEthernet6/11
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	196	GigabitEthernet6/43
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	242	GigabitEthernet1/17--Controlled
auto-secbua-lowersw.infra.tg14.gathering.org-6c:9c:ed:82:6b:00	10107	GigabitEthernet0/7
auto-secbua-lowersw.infra.tg14.gathering.org-6c:9c:ed:82:6b:00	10105	GigabitEthernet0/5
auto-secbua-lowersw.infra.tg14.gathering.org-6c:9c:ed:82:6b:00	10501	Null0
auto-secbua-lowersw.infra.tg14.gathering.org-6c:9c:ed:82:6b:00	10108	GigabitEthernet0/8
auto-secbua-lowersw.infra.tg14.gathering.org-6c:9c:ed:82:6b:00	10102	GigabitEthernet0/2
auto-secbua-lowersw.infra.tg14.gathering.org-6c:9c:ed:82:6b:00	20567	Loopback0
auto-secbua-lowersw.infra.tg14.gathering.org-6c:9c:ed:82:6b:00	2271	Vlan2271
auto-secbua-lowersw.infra.tg14.gathering.org-6c:9c:ed:82:6b:00	1	Vlan1
auto-secbua-lowersw.infra.tg14.gathering.org-6c:9c:ed:82:6b:00	10110	GigabitEthernet0/10
auto-secbua-lowersw.infra.tg14.gathering.org-6c:9c:ed:82:6b:00	10109	GigabitEthernet0/9
auto-secbua-lowersw.infra.tg14.gathering.org-6c:9c:ed:82:6b:00	10103	GigabitEthernet0/3
auto-secbua-lowersw.infra.tg14.gathering.org-6c:9c:ed:82:6b:00	10104	GigabitEthernet0/4
auto-secbua-lowersw.infra.tg14.gathering.org-6c:9c:ed:82:6b:00	10106	GigabitEthernet0/6
auto-secbua-lowersw.infra.tg14.gathering.org-6c:9c:ed:82:6b:00	10101	GigabitEthernet0/1
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	33	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	32	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	21	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	7	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	26	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	17	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	2	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	1	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	18	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	30	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	16	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	27	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	25	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	28	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	20	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	14	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	24	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	10	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	31	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	35	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	11	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	22	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	13	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	23	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	29	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	6	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	39	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	36	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	3	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	9	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	12	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	15	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	38	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	8	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	4	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	34	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	37	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	19	Ethernet Interface
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	5	Ethernet Interface
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	559	GigabitEthernet6/19--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	127	GigabitEthernet5/22
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	32	GigabitEthernet1/31
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	443	GigabitEthernet5/9--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	206	unrouted VLAN 1004
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	118	GigabitEthernet5/13
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	71	GigabitEthernet2/22
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	358	GigabitEthernet2/23--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	331	GigabitEthernet2/9--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	560	GigabitEthernet6/20--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	580	GigabitEthernet6/30--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	84	GigabitEthernet2/35
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	512	GigabitEthernet5/44--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	437	GigabitEthernet5/6--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	463	GigabitEthernet5/19--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	194	GigabitEthernet6/41
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	517	GigabitEthernet5/46--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	458	GigabitEthernet5/17--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	451	GigabitEthernet5/13--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	220	GigabitEthernet1/2--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	454	GigabitEthernet5/15--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	31	GigabitEthernet1/30
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	578	GigabitEthernet6/29--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	378	GigabitEthernet2/33--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	325	GigabitEthernet2/6--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	29	GigabitEthernet1/28
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	572	GigabitEthernet6/26--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	350	GigabitEthernet2/19--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	540	GigabitEthernet6/10--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	226	GigabitEthernet1/5--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	58	GigabitEthernet2/9
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	211	unrouted VLAN 4
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	153	GigabitEthernet5/48
auto-GameHQSW2-00:26:5a:e4:9e:e4	2	TenGigabitEthernet1/2
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	15	GigabitEthernet1/14
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	527	GigabitEthernet6/3--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	431	GigabitEthernet5/3--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	382	GigabitEthernet2/35--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	337	GigabitEthernet2/12--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	101	TenGigabitEthernet3/4
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	340	GigabitEthernet2/14--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	76	GigabitEthernet2/27
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	311	GigabitEthernet1/47--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	62	GigabitEthernet2/13
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	571	GigabitEthernet6/25--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	139	GigabitEthernet5/34
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	389	GigabitEthernet2/38--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	129	GigabitEthernet5/24
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	548	GigabitEthernet6/14--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	495	GigabitEthernet5/35--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	418	TenGigabitEthernet4/1--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	236	GigabitEthernet1/10--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	218	GigabitEthernet1/1--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	168	GigabitEthernet6/15
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	135	GigabitEthernet5/30
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	14	GigabitEthernet1/13
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	348	GigabitEthernet2/18--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	145	GigabitEthernet5/40
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	49	GigabitEthernet1/48
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	178	GigabitEthernet6/25
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	285	GigabitEthernet1/34--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	124	GigabitEthernet5/19
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	234	GigabitEthernet1/9--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	594	GigabitEthernet6/37--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	23	GigabitEthernet1/22
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	388	GigabitEthernet2/38--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	364	GigabitEthernet2/26--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	96	GigabitEthernet2/47
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	486	GigabitEthernet5/31--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	509	GigabitEthernet5/42--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	160	GigabitEthernet6/7
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	569	GigabitEthernet6/24--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	367	GigabitEthernet2/27--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	8	GigabitEthernet1/7
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	98	TenGigabitEthernet3/1
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	43	GigabitEthernet1/42
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	485	GigabitEthernet5/30--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	391	GigabitEthernet2/39--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	21	GigabitEthernet1/20
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	523	GigabitEthernet6/1--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	288	GigabitEthernet1/36--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	193	GigabitEthernet6/40
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	460	GigabitEthernet5/18--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	119	GigabitEthernet5/14
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	586	GigabitEthernet6/33--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	453	GigabitEthernet5/14--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	324	GigabitEthernet2/6--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	180	GigabitEthernet6/27
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	244	GigabitEthernet1/14--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	351	GigabitEthernet2/19--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	410	TenGigabitEthernet3/1--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	595	GigabitEthernet6/37--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	246	GigabitEthernet1/15--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	488	GigabitEthernet5/32--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	61	GigabitEthernet2/12
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	430	GigabitEthernet5/3--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	447	GigabitEthernet5/11--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	536	GigabitEthernet6/8--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	379	GigabitEthernet2/33--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	415	TenGigabitEthernet3/3--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	113	GigabitEthernet5/8
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	152	GigabitEthernet5/47
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	189	GigabitEthernet6/36
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	452	GigabitEthernet5/14--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	342	GigabitEthernet2/15--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	579	GigabitEthernet6/29--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	295	GigabitEthernet1/39--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	480	GigabitEthernet5/28--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	341	GigabitEthernet2/14--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	438	GigabitEthernet5/7--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	107	GigabitEthernet5/2
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	535	GigabitEthernet6/7--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	87	GigabitEthernet2/38
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	77	GigabitEthernet2/28
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	444	GigabitEthernet5/10--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	541	GigabitEthernet6/10--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	508	GigabitEthernet5/42--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	221	GigabitEthernet1/2--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	39	GigabitEthernet1/38
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	64	GigabitEthernet2/15
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	558	GigabitEthernet6/19--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	417	TenGigabitEthernet3/4--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	12	GigabitEthernet1/11
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	312	GigabitEthernet1/48--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	45	GigabitEthernet1/44
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	507	GigabitEthernet5/41--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	405	GigabitEthernet2/46--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	260	GigabitEthernet1/22--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	573	GigabitEthernet6/26--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	237	GigabitEthernet1/10--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	370	GigabitEthernet2/29--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	309	GigabitEthernet1/46--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	567	GigabitEthernet6/23--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	1	FastEthernet1
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	506	GigabitEthernet5/41--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	136	GigabitEthernet5/31
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	116	GigabitEthernet5/11
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	416	TenGigabitEthernet3/4--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	144	GigabitEthernet5/39
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	380	GigabitEthernet2/34--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	100	TenGigabitEthernet3/3
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	300	GigabitEthernet1/42--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	286	GigabitEthernet1/35--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	120	GigabitEthernet5/15
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	381	GigabitEthernet2/34--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	581	GigabitEthernet6/30--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	308	GigabitEthernet1/46--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	392	GigabitEthernet2/40--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	254	GigabitEthernet1/19--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	177	GigabitEthernet6/24
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	496	GigabitEthernet5/36--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	605	GigabitEthernet6/42--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	373	GigabitEthernet2/30--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	607	GigabitEthernet6/43--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	205	unrouted VLAN 1002
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	42	GigabitEthernet1/41
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	22	GigabitEthernet1/21
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	399	GigabitEthernet2/43--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	235	GigabitEthernet1/9--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	301	GigabitEthernet1/42--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	436	GigabitEthernet5/6--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	213	unrouted VLAN 31
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	94	GigabitEthernet2/45
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	51	GigabitEthernet2/2
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	456	GigabitEthernet5/16--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	568	GigabitEthernet6/24--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	296	GigabitEthernet1/40--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	265	GigabitEthernet1/24--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	493	GigabitEthernet5/34--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	171	GigabitEthernet6/18
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	386	GigabitEthernet2/37--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	445	GigabitEthernet5/10--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	200	GigabitEthernet6/47
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	366	GigabitEthernet2/27--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	329	GigabitEthernet2/8--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	525	GigabitEthernet6/2--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	27	GigabitEthernet1/26
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	272	GigabitEthernet1/28--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	161	GigabitEthernet6/8
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	582	GigabitEthernet6/31--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	534	GigabitEthernet6/7--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	400	GigabitEthernet2/44--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	20	GigabitEthernet1/19
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	109	GigabitEthernet5/4
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	151	GigabitEthernet5/46
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	557	GigabitEthernet6/18--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	468	GigabitEthernet5/22--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	287	GigabitEthernet1/35--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	475	GigabitEthernet5/25--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	441	GigabitEthernet5/8--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	78	GigabitEthernet2/29
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	413	TenGigabitEthernet3/2--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	294	GigabitEthernet1/39--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	349	GigabitEthernet2/18--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	275	GigabitEthernet1/29--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	515	GigabitEthernet5/45--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	197	GigabitEthernet6/44
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	138	GigabitEthernet5/33
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	606	GigabitEthernet6/43--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	137	GigabitEthernet5/32
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	60	GigabitEthernet2/11
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	432	GigabitEthernet5/4--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	519	GigabitEthernet5/47--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	346	GigabitEthernet2/17--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	17	GigabitEthernet1/16
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	427	GigabitEthernet5/1--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	82	GigabitEthernet2/33
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	110	GigabitEthernet5/5
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	333	GigabitEthernet2/10--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	590	GigabitEthernet6/35--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	323	GigabitEthernet2/5--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	69	GigabitEthernet2/20
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	112	GigabitEthernet5/7
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	545	GigabitEthernet6/12--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	191	GigabitEthernet6/38
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	224	GigabitEthernet1/4--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	187	GigabitEthernet6/34
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	588	GigabitEthernet6/34--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	446	GigabitEthernet5/11--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	262	GigabitEthernet1/23--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	617	GigabitEthernet6/48--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	79	GigabitEthernet2/30
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	212	unrouted VLAN 128
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	352	GigabitEthernet2/20--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	126	GigabitEthernet5/21
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	426	GigabitEthernet5/1--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	251	GigabitEthernet1/17--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	542	GigabitEthernet6/11--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	369	GigabitEthernet2/28--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	279	GigabitEthernet1/31--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	176	GigabitEthernet6/23
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	498	GigabitEthernet5/37--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	483	GigabitEthernet5/29--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	256	GigabitEthernet1/20--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	372	GigabitEthernet2/30--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	574	GigabitEthernet6/27--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	170	GigabitEthernet6/17
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	33	GigabitEthernet1/32
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	428	GigabitEthernet5/2--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	7	GigabitEthernet1/6
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	26	GigabitEthernet1/25
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	227	GigabitEthernet1/5--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	99	TenGigabitEthernet3/2
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	566	GigabitEthernet6/23--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	526	GigabitEthernet6/3--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	72	GigabitEthernet2/23
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	500	GigabitEthernet5/38--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	264	GigabitEthernet1/24--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	255	GigabitEthernet1/19--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	533	GigabitEthernet6/6--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	359	GigabitEthernet2/23--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	182	GigabitEthernet6/29
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	108	GigabitEthernet5/3
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	604	GigabitEthernet6/42--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	556	GigabitEthernet6/18--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	462	GigabitEthernet5/19--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	414	TenGigabitEthernet3/3--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	232	GigabitEthernet1/8--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	477	GigabitEthernet5/26--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	225	GigabitEthernet1/4--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	330	GigabitEthernet2/9--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	142	GigabitEthernet5/37
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	207	unrouted VLAN 1005
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	263	GigabitEthernet1/23--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	394	GigabitEthernet2/41--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	167	GigabitEthernet6/14
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	48	GigabitEthernet1/47
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	360	GigabitEthernet2/24--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	610	GigabitEthernet6/45--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	514	GigabitEthernet5/45--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	513	GigabitEthernet5/44--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	615	GigabitEthernet6/47--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	50	GigabitEthernet2/1
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	476	GigabitEthernet5/26--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	510	GigabitEthernet5/43--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	393	GigabitEthernet2/40--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	449	GigabitEthernet5/12--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	293	GigabitEthernet1/38--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	274	GigabitEthernet1/29--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	549	GigabitEthernet6/14--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	322	GigabitEthernet2/5--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	469	GigabitEthernet5/22--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	353	GigabitEthernet2/20--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	575	GigabitEthernet6/27--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	375	GigabitEthernet2/31--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	128	GigabitEthernet5/23
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	28	GigabitEthernet1/27
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	310	GigabitEthernet1/47--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	40	GigabitEthernet1/39
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	589	GigabitEthernet6/34--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	303	GigabitEthernet1/43--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	192	GigabitEthernet6/39
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	250	GigabitEthernet1/17--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	614	GigabitEthernet6/47--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	501	GigabitEthernet5/38--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	215	unrouted VLAN 100
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	278	GigabitEthernet1/31--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	490	GigabitEthernet5/33--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	150	GigabitEthernet5/45
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	130	GigabitEthernet5/25
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	155	GigabitEthernet6/2
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	387	GigabitEthernet2/37--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	53	GigabitEthernet2/4
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	245	GigabitEthernet1/14--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	543	GigabitEthernet6/11--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	267	GigabitEthernet1/25--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	354	GigabitEthernet2/21--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	461	GigabitEthernet5/18--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	583	GigabitEthernet6/31--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	257	GigabitEthernet1/20--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	85	GigabitEthernet2/36
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	332	GigabitEthernet2/10--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	9	GigabitEthernet1/8
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	425	TenGigabitEthernet4/4--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	591	GigabitEthernet6/35--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	34	GigabitEthernet1/33
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	539	GigabitEthernet6/9--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	603	GigabitEthernet6/41--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	90	GigabitEthernet2/41
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	276	GigabitEthernet1/30--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	565	GigabitEthernet6/22--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	102	TenGigabitEthernet4/1
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	520	GigabitEthernet5/48--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	532	GigabitEthernet6/6--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	16	GigabitEthernet1/15
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	55	GigabitEthernet2/6
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	233	GigabitEthernet1/8--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	57	GigabitEthernet2/8
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	259	GigabitEthernet1/21--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	368	GigabitEthernet2/28--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	424	TenGigabitEthernet4/4--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	316	GigabitEthernet2/2--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	163	GigabitEthernet6/10
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	395	GigabitEthernet2/41--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	89	GigabitEthernet2/40
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	611	GigabitEthernet6/45--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	175	GigabitEthernet6/22
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	584	GigabitEthernet6/32--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	35	GigabitEthernet1/34
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	11	GigabitEthernet1/10
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	492	GigabitEthernet5/34--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	208	unrouted VLAN 1003
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	347	GigabitEthernet2/17--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	511	GigabitEthernet5/43--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	434	GigabitEthernet5/5--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	93	GigabitEthernet2/44
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	292	GigabitEthernet1/38--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	291	GigabitEthernet1/37--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	374	GigabitEthernet2/31--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	114	GigabitEthernet5/9
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	199	GigabitEthernet6/46
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	442	GigabitEthernet5/9--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	429	GigabitEthernet5/2--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	73	GigabitEthernet2/24
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	409	GigabitEthernet2/48--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	67	GigabitEthernet2/18
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	241	GigabitEthernet1/12--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	198	GigabitEthernet6/45
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	489	GigabitEthernet5/32--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	585	GigabitEthernet6/32--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	327	GigabitEthernet2/7--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	320	GigabitEthernet2/4--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	280	GigabitEthernet1/32--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	273	GigabitEthernet1/28--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	471	GigabitEthernet5/23--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	202	Null0
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	249	GigabitEthernet1/16--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	361	GigabitEthernet2/24--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	465	GigabitEthernet5/20--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	184	GigabitEthernet6/31
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	24	GigabitEthernet1/23
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	140	GigabitEthernet5/35
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	104	TenGigabitEthernet4/3
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	131	GigabitEthernet5/26
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	181	GigabitEthernet6/28
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	412	TenGigabitEthernet3/2--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	385	GigabitEthernet2/36--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	502	GigabitEthernet5/39--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	307	GigabitEthernet1/45--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	314	GigabitEthernet2/1--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	154	GigabitEthernet6/1
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	355	GigabitEthernet2/21--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	553	GigabitEthernet6/16--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	159	GigabitEthernet6/6
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	479	GigabitEthernet5/27--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	326	GigabitEthernet2/7--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	555	GigabitEthernet6/17--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	47	GigabitEthernet1/46
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	619	Loopback0
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	37	GigabitEthernet1/36
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	335	GigabitEthernet2/11--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	270	GigabitEthernet1/27--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	5	GigabitEthernet1/4
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	195	GigabitEthernet6/42
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	538	GigabitEthernet6/9--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	524	GigabitEthernet6/2--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	554	GigabitEthernet6/17--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	552	GigabitEthernet6/16--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	521	GigabitEthernet5/48--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	598	GigabitEthernet6/39--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	162	GigabitEthernet6/9
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	433	GigabitEthernet5/4--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	74	GigabitEthernet2/25
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	240	GigabitEthernet1/12--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	334	GigabitEthernet2/11--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	440	GigabitEthernet5/8--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	230	GigabitEthernet1/7--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	115	GigabitEthernet5/10
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	299	GigabitEthernet1/41--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	377	GigabitEthernet2/32--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	103	TenGigabitEthernet4/2
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	602	GigabitEthernet6/41--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	201	GigabitEthernet6/48
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	423	TenGigabitEthernet4/3--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	612	GigabitEthernet6/46--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	91	GigabitEthernet2/42
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	266	GigabitEthernet1/25--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	467	GigabitEthernet5/21--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	174	GigabitEthernet6/21
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	474	GigabitEthernet5/25--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	481	GigabitEthernet5/28--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	214	unrouted VLAN 32
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	422	TenGigabitEthernet4/3--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	564	GigabitEthernet6/22--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	563	GigabitEthernet6/21--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	97	GigabitEthernet2/48
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	41	GigabitEthernet1/40
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	52	GigabitEthernet2/3
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	302	GigabitEthernet1/43--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	229	GigabitEthernet1/6--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	503	GigabitEthernet5/39--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	593	GigabitEthernet6/36--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	68	GigabitEthernet2/19
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	188	GigabitEthernet6/35
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	315	GigabitEthernet2/1--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	402	GigabitEthernet2/45--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	338	GigabitEthernet2/13--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	576	GigabitEthernet6/28--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	616	GigabitEthernet6/48--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	222	GigabitEthernet1/3--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	25	GigabitEthernet1/24
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	83	GigabitEthernet2/34
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	484	GigabitEthernet5/30--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	305	GigabitEthernet1/44--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	623	Port-channel1
auto-GameHQSW2-00:26:5a:e4:9e:e4	17	GigabitEthernet4/5
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	544	GigabitEthernet6/12--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	217	unrouted VLAN 103
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	328	GigabitEthernet2/8--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	239	GigabitEthernet1/11--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	122	GigabitEthernet5/17
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	143	GigabitEthernet5/38
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	158	GigabitEthernet6/5
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	269	GigabitEthernet1/26--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	281	GigabitEthernet1/32--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	464	GigabitEthernet5/20--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	363	GigabitEthernet2/25--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	46	GigabitEthernet1/45
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	6	GigabitEthernet1/5
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	562	GigabitEthernet6/21--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	36	GigabitEthernet1/35
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	518	GigabitEthernet5/47--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	183	GigabitEthernet6/30
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	497	GigabitEthernet5/36--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	472	GigabitEthernet5/24--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	362	GigabitEthernet2/25--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	439	GigabitEthernet5/7--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	317	GigabitEthernet2/2--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	608	GigabitEthernet6/44--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	132	GigabitEthernet5/27
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	169	GigabitEthernet6/16
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	411	TenGigabitEthernet3/1--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	478	GigabitEthernet5/27--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	384	GigabitEthernet2/36--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	398	GigabitEthernet2/43--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	546	GigabitEthernet6/13--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	537	GigabitEthernet6/8--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	407	GigabitEthernet2/47--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	18	GigabitEthernet1/17
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	376	GigabitEthernet2/32--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	522	GigabitEthernet6/1--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	125	GigabitEthernet5/20
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	599	GigabitEthernet6/39--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	44	GigabitEthernet1/43
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	609	GigabitEthernet6/44--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	587	GigabitEthernet6/33--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	190	GigabitEthernet6/37
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	95	GigabitEthernet2/46
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	298	GigabitEthernet1/41--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	601	GigabitEthernet6/40--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	313	GigabitEthernet1/48--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	243	GigabitEthernet1/13--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	231	GigabitEthernet1/7--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	551	GigabitEthernet6/15--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	529	GigabitEthernet6/4--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	148	GigabitEthernet5/43
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	343	GigabitEthernet2/15--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	504	GigabitEthernet5/40--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	397	GigabitEthernet2/42--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	106	GigabitEthernet5/1
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	157	GigabitEthernet6/4
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	65	GigabitEthernet2/16
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	203	Vlan1
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	261	GigabitEthernet1/22--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	81	GigabitEthernet2/32
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	321	GigabitEthernet2/4--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	459	GigabitEthernet5/17--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	86	GigabitEthernet2/37
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	284	GigabitEthernet1/34--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	247	GigabitEthernet1/15--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	371	GigabitEthernet2/29--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	204	unrouted VLAN 1
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	165	GigabitEthernet6/12
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	289	GigabitEthernet1/36--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	2	GigabitEthernet1/1
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	435	GigabitEthernet5/5--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	401	GigabitEthernet2/44--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	186	GigabitEthernet6/33
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	147	GigabitEthernet5/42
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	339	GigabitEthernet2/13--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	228	GigabitEthernet1/6--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	531	GigabitEthernet6/5--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	268	GigabitEthernet1/26--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	345	GigabitEthernet2/16--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	596	GigabitEthernet6/38--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	172	GigabitEthernet6/19
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	319	GigabitEthernet2/3--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	223	GigabitEthernet1/3--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	404	GigabitEthernet2/46--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	613	GigabitEthernet6/46--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	516	GigabitEthernet5/46--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	282	GigabitEthernet1/33--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	420	TenGigabitEthernet4/2--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	121	GigabitEthernet5/16
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	344	GigabitEthernet2/16--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	487	GigabitEthernet5/31--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	494	GigabitEthernet5/35--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	238	GigabitEthernet1/11--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	577	GigabitEthernet6/28--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	253	GigabitEthernet1/18--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	561	GigabitEthernet6/20--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	448	GigabitEthernet5/12--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	209	unrouted VLAN 2
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	216	unrouted VLAN 102
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	357	GigabitEthernet2/22--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	117	GigabitEthernet5/12
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	63	GigabitEthernet2/14
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	455	GigabitEthernet5/15--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	600	GigabitEthernet6/40--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	80	GigabitEthernet2/31
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	336	GigabitEthernet2/12--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	457	GigabitEthernet5/16--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	179	GigabitEthernet6/26
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	383	GigabitEthernet2/35--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	297	GigabitEthernet1/40--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	277	GigabitEthernet1/30--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	92	GigabitEthernet2/43
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	10	GigabitEthernet1/9
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	550	GigabitEthernet6/15--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	505	GigabitEthernet5/40--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	419	TenGigabitEthernet4/1--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	133	GigabitEthernet5/28
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	290	GigabitEthernet1/37--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	592	GigabitEthernet6/36--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	149	GigabitEthernet5/44
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	123	GigabitEthernet5/18
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	304	GigabitEthernet1/44--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	547	GigabitEthernet6/13--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	210	unrouted VLAN 3
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	406	GigabitEthernet2/47--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	258	GigabitEthernet1/21--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	396	GigabitEthernet2/42--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	482	GigabitEthernet5/29--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	173	GigabitEthernet6/20
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	530	GigabitEthernet6/5--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	56	GigabitEthernet2/7
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	499	GigabitEthernet5/37--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	66	GigabitEthernet2/17
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	19	GigabitEthernet1/18
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	54	GigabitEthernet2/5
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	365	GigabitEthernet2/26--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	306	GigabitEthernet1/45--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	70	GigabitEthernet2/21
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	470	GigabitEthernet5/23--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	166	GigabitEthernet6/13
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	88	GigabitEthernet2/39
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	141	GigabitEthernet5/36
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	30	GigabitEthernet1/29
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	570	GigabitEthernet6/25--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	403	GigabitEthernet2/45--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	252	GigabitEthernet1/18--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	466	GigabitEthernet5/21--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	156	GigabitEthernet6/3
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	134	GigabitEthernet5/29
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	75	GigabitEthernet2/26
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	283	GigabitEthernet1/33--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	618	Tunnel0
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	59	GigabitEthernet2/10
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	421	TenGigabitEthernet4/2--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	450	GigabitEthernet5/13--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	271	GigabitEthernet1/27--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	491	GigabitEthernet5/33--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	219	GigabitEthernet1/1--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	318	GigabitEthernet2/3--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	13	GigabitEthernet1/12
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	105	TenGigabitEthernet4/4
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	473	GigabitEthernet5/24--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	185	GigabitEthernet6/32
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	3	GigabitEthernet1/2
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	597	GigabitEthernet6/38--Controlled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	248	GigabitEthernet1/16--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	390	GigabitEthernet2/39--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	146	GigabitEthernet5/41
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	111	GigabitEthernet5/6
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	38	GigabitEthernet1/37
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	356	GigabitEthernet2/22--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	408	GigabitEthernet2/48--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	4	GigabitEthernet1/3
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	528	GigabitEthernet6/4--Uncontrolled
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	164	GigabitEthernet6/11
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	196	GigabitEthernet6/43
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	242	GigabitEthernet1/13--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	559	GigabitEthernet6/23--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	127	GigabitEthernet5/22
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	32	GigabitEthernet1/31
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	443	GigabitEthernet5/13--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	206	unrouted VLAN 1004
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	118	GigabitEthernet5/13
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	71	GigabitEthernet2/22
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	358	GigabitEthernet2/26--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	331	GigabitEthernet2/13--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	560	GigabitEthernet6/23--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	580	GigabitEthernet6/33--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	84	GigabitEthernet2/35
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	512	GigabitEthernet5/47--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	437	GigabitEthernet5/10--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	463	GigabitEthernet5/23--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	194	GigabitEthernet6/41
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	517	GigabitEthernet6/2--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	458	GigabitEthernet5/20--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	451	GigabitEthernet5/17--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	220	GigabitEthernet1/5--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	454	GigabitEthernet5/18--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	31	GigabitEthernet1/30
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	578	GigabitEthernet6/32--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	378	GigabitEthernet2/36--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	325	GigabitEthernet2/10--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	29	GigabitEthernet1/28
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	572	GigabitEthernet6/29--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	350	GigabitEthernet2/22--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	540	GigabitEthernet6/13--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	226	GigabitEthernet1/8--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	58	GigabitEthernet2/9
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	211	GigabitEthernet1/1--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	153	GigabitEthernet5/48
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	15	GigabitEthernet1/14
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	527	GigabitEthernet6/7--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	431	GigabitEthernet5/7--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	382	GigabitEthernet2/38--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	337	GigabitEthernet2/16--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	101	TenGigabitEthernet3/4
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	340	GigabitEthernet2/17--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	76	GigabitEthernet2/27
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	311	GigabitEthernet2/3--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	62	GigabitEthernet2/13
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	571	GigabitEthernet6/29--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	139	GigabitEthernet5/34
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	389	GigabitEthernet2/42--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	129	GigabitEthernet5/24
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	548	GigabitEthernet6/17--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	495	GigabitEthernet5/39--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	418	TenGigabitEthernet4/4--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	236	GigabitEthernet1/13--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	218	GigabitEthernet1/4--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	168	GigabitEthernet6/15
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	135	GigabitEthernet5/30
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	14	GigabitEthernet1/13
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	348	GigabitEthernet2/21--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	145	GigabitEthernet5/40
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	49	GigabitEthernet1/48
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	178	GigabitEthernet6/25
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	285	GigabitEthernet1/38--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	124	GigabitEthernet5/19
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	234	GigabitEthernet1/12--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	594	GigabitEthernet6/40--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	23	GigabitEthernet1/22
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	388	GigabitEthernet2/41--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	364	GigabitEthernet2/29--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	96	GigabitEthernet2/47
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	486	GigabitEthernet5/34--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	509	GigabitEthernet5/46--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	160	GigabitEthernet6/7
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	569	GigabitEthernet6/28--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	367	GigabitEthernet2/31--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	8	GigabitEthernet1/7
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	98	TenGigabitEthernet3/1
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	43	GigabitEthernet1/42
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	485	GigabitEthernet5/34--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	391	GigabitEthernet2/43--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	21	GigabitEthernet1/20
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	523	GigabitEthernet6/5--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	288	GigabitEthernet1/39--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	193	GigabitEthernet6/40
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	460	GigabitEthernet5/21--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	119	GigabitEthernet5/14
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	586	GigabitEthernet6/36--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	453	GigabitEthernet5/18--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	324	GigabitEthernet2/9--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	180	GigabitEthernet6/27
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	244	GigabitEthernet1/17--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	351	GigabitEthernet2/23--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	410	TenGigabitEthernet3/4--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	595	GigabitEthernet6/41--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	246	GigabitEthernet1/18--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	488	GigabitEthernet5/35--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	61	GigabitEthernet2/12
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	430	GigabitEthernet5/6--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	447	GigabitEthernet5/15--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	536	GigabitEthernet6/11--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	379	GigabitEthernet2/37--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	415	TenGigabitEthernet4/3--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	113	GigabitEthernet5/8
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	152	GigabitEthernet5/47
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	189	GigabitEthernet6/36
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	452	GigabitEthernet5/17--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	342	GigabitEthernet2/18--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	579	GigabitEthernet6/33--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	295	GigabitEthernet1/43--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	480	GigabitEthernet5/31--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	341	GigabitEthernet2/18--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	438	GigabitEthernet5/10--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	107	GigabitEthernet5/2
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	535	GigabitEthernet6/11--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	87	GigabitEthernet2/38
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	77	GigabitEthernet2/28
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	444	GigabitEthernet5/13--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	541	GigabitEthernet6/14--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	508	GigabitEthernet5/45--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	221	GigabitEthernet1/6--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	39	GigabitEthernet1/38
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	64	GigabitEthernet2/15
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	558	GigabitEthernet6/22--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	417	TenGigabitEthernet4/4--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	12	GigabitEthernet1/11
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	312	GigabitEthernet2/3--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	45	GigabitEthernet1/44
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	507	GigabitEthernet5/45--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	405	TenGigabitEthernet3/2--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	260	GigabitEthernet1/25--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	573	GigabitEthernet6/30--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	237	GigabitEthernet1/14--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	370	GigabitEthernet2/32--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	309	GigabitEthernet2/2--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	567	GigabitEthernet6/27--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	1	FastEthernet1
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	506	GigabitEthernet5/44--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	136	GigabitEthernet5/31
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	116	GigabitEthernet5/11
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	416	TenGigabitEthernet4/3--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	144	GigabitEthernet5/39
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	380	GigabitEthernet2/37--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	100	TenGigabitEthernet3/3
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	300	GigabitEthernet1/45--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	286	GigabitEthernet1/38--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	120	GigabitEthernet5/15
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	381	GigabitEthernet2/38--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	581	GigabitEthernet6/34--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	308	GigabitEthernet2/1--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	392	GigabitEthernet2/43--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	254	GigabitEthernet1/22--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	177	GigabitEthernet6/24
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	496	GigabitEthernet5/39--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	605	GigabitEthernet6/46--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	373	GigabitEthernet2/34--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	607	GigabitEthernet6/47--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	205	unrouted VLAN 1002
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	42	GigabitEthernet1/41
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	22	GigabitEthernet1/21
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	399	GigabitEthernet2/47--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	235	GigabitEthernet1/13--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	301	GigabitEthernet1/46--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	436	GigabitEthernet5/9--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	213	GigabitEthernet1/2--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	94	GigabitEthernet2/45
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	51	GigabitEthernet2/2
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	456	GigabitEthernet5/19--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	568	GigabitEthernet6/27--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	296	GigabitEthernet1/43--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	265	GigabitEthernet1/28--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	493	GigabitEthernet5/38--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	171	GigabitEthernet6/18
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	386	GigabitEthernet2/40--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	445	GigabitEthernet5/14--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	200	GigabitEthernet6/47
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	366	GigabitEthernet2/30--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	329	GigabitEthernet2/12--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	525	GigabitEthernet6/6--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	27	GigabitEthernet1/26
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	272	GigabitEthernet1/31--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	161	GigabitEthernet6/8
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	582	GigabitEthernet6/34--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	534	GigabitEthernet6/10--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	400	GigabitEthernet2/47--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	20	GigabitEthernet1/19
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	109	GigabitEthernet5/4
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	151	GigabitEthernet5/46
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	557	GigabitEthernet6/22--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	468	GigabitEthernet5/25--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	287	GigabitEthernet1/39--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	475	GigabitEthernet5/29--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	441	GigabitEthernet5/12--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	78	GigabitEthernet2/29
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	413	TenGigabitEthernet4/2--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	294	GigabitEthernet1/42--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	349	GigabitEthernet2/22--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	275	GigabitEthernet1/33--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	515	GigabitEthernet6/1--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	197	GigabitEthernet6/44
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	138	GigabitEthernet5/33
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	606	GigabitEthernet6/46--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	137	GigabitEthernet5/32
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	60	GigabitEthernet2/11
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	432	GigabitEthernet5/7--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	519	GigabitEthernet6/3--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	346	GigabitEthernet2/20--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	17	GigabitEthernet1/16
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	427	GigabitEthernet5/5--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	82	GigabitEthernet2/33
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	110	GigabitEthernet5/5
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	333	GigabitEthernet2/14--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	590	GigabitEthernet6/38--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	323	GigabitEthernet2/9--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	69	GigabitEthernet2/20
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	112	GigabitEthernet5/7
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	545	GigabitEthernet6/16--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	191	GigabitEthernet6/38
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	224	GigabitEthernet1/7--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	187	GigabitEthernet6/34
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	588	GigabitEthernet6/37--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	446	GigabitEthernet5/14--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	262	GigabitEthernet1/26--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	79	GigabitEthernet2/30
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	212	GigabitEthernet1/1--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	352	GigabitEthernet2/23--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	126	GigabitEthernet5/21
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	426	GigabitEthernet5/4--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	251	GigabitEthernet1/21--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	542	GigabitEthernet6/14--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	369	GigabitEthernet2/32--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	279	GigabitEthernet1/35--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	176	GigabitEthernet6/23
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	498	GigabitEthernet5/40--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	483	GigabitEthernet5/33--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	256	GigabitEthernet1/23--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	372	GigabitEthernet2/33--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	574	GigabitEthernet6/30--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	170	GigabitEthernet6/17
auto-GameHQSW2-00:26:5a:e4:9e:e4	110	GigabitEthernet9/32
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	33	GigabitEthernet1/32
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	428	GigabitEthernet5/5--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	7	GigabitEthernet1/6
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	26	GigabitEthernet1/25
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	227	GigabitEthernet1/9--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	99	TenGigabitEthernet3/2
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	566	GigabitEthernet6/26--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	526	GigabitEthernet6/6--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	72	GigabitEthernet2/23
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	500	GigabitEthernet5/41--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	264	GigabitEthernet1/27--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	255	GigabitEthernet1/23--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	533	GigabitEthernet6/10--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	359	GigabitEthernet2/27--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	182	GigabitEthernet6/29
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	108	GigabitEthernet5/3
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	604	GigabitEthernet6/45--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	556	GigabitEthernet6/21--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	462	GigabitEthernet5/22--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	414	TenGigabitEthernet4/2--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	232	GigabitEthernet1/11--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	477	GigabitEthernet5/30--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	225	GigabitEthernet1/8--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	330	GigabitEthernet2/12--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	142	GigabitEthernet5/37
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	207	unrouted VLAN 1005
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	263	GigabitEthernet1/27--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	394	GigabitEthernet2/44--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	167	GigabitEthernet6/14
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	48	GigabitEthernet1/47
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	360	GigabitEthernet2/27--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	610	GigabitEthernet6/48--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	514	GigabitEthernet5/48--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	513	GigabitEthernet5/48--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	50	GigabitEthernet2/1
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	476	GigabitEthernet5/29--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	510	GigabitEthernet5/46--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	393	GigabitEthernet2/44--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	449	GigabitEthernet5/16--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	293	GigabitEthernet1/42--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	274	GigabitEthernet1/32--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	549	GigabitEthernet6/18--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	322	GigabitEthernet2/8--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	469	GigabitEthernet5/26--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	353	GigabitEthernet2/24--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	575	GigabitEthernet6/31--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	375	GigabitEthernet2/35--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	128	GigabitEthernet5/23
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	28	GigabitEthernet1/27
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	310	GigabitEthernet2/2--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	40	GigabitEthernet1/39
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	589	GigabitEthernet6/38--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	303	GigabitEthernet1/47--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	192	GigabitEthernet6/39
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	250	GigabitEthernet1/20--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	614	Port-channel1
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	501	GigabitEthernet5/42--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	215	GigabitEthernet1/3--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	278	GigabitEthernet1/34--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	490	GigabitEthernet5/36--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	150	GigabitEthernet5/45
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	130	GigabitEthernet5/25
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	155	GigabitEthernet6/2
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	387	GigabitEthernet2/41--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	53	GigabitEthernet2/4
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	245	GigabitEthernet1/18--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	543	GigabitEthernet6/15--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	267	GigabitEthernet1/29--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	354	GigabitEthernet2/24--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	461	GigabitEthernet5/22--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	583	GigabitEthernet6/35--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	257	GigabitEthernet1/24--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	85	GigabitEthernet2/36
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	332	GigabitEthernet2/13--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	9	GigabitEthernet1/8
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	425	GigabitEthernet5/4--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	591	GigabitEthernet6/39--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	34	GigabitEthernet1/33
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	539	GigabitEthernet6/13--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	603	GigabitEthernet6/45--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	90	GigabitEthernet2/41
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	276	GigabitEthernet1/33--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	565	GigabitEthernet6/26--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	102	TenGigabitEthernet4/1
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	520	GigabitEthernet6/3--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	532	GigabitEthernet6/9--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	16	GigabitEthernet1/15
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	55	GigabitEthernet2/6
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	233	GigabitEthernet1/12--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	57	GigabitEthernet2/8
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	259	GigabitEthernet1/25--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	368	GigabitEthernet2/31--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	424	GigabitEthernet5/3--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	316	GigabitEthernet2/5--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	163	GigabitEthernet6/10
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	395	GigabitEthernet2/45--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	89	GigabitEthernet2/40
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	611	Tunnel0
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	175	GigabitEthernet6/22
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	584	GigabitEthernet6/35--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	35	GigabitEthernet1/34
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	11	GigabitEthernet1/10
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	492	GigabitEthernet5/37--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	208	unrouted VLAN 1003
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	347	GigabitEthernet2/21--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	511	GigabitEthernet5/47--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	434	GigabitEthernet5/8--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	93	GigabitEthernet2/44
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	292	GigabitEthernet1/41--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	291	GigabitEthernet1/41--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	374	GigabitEthernet2/34--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	114	GigabitEthernet5/9
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	199	GigabitEthernet6/46
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	442	GigabitEthernet5/12--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	429	GigabitEthernet5/6--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	73	GigabitEthernet2/24
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	409	TenGigabitEthernet3/4--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	67	GigabitEthernet2/18
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	241	GigabitEthernet1/16--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	198	GigabitEthernet6/45
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	489	GigabitEthernet5/36--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	585	GigabitEthernet6/36--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	327	GigabitEthernet2/11--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	320	GigabitEthernet2/7--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	280	GigabitEthernet1/35--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	273	GigabitEthernet1/32--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	471	GigabitEthernet5/27--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	202	Null0
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	249	GigabitEthernet1/20--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	361	GigabitEthernet2/28--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	465	GigabitEthernet5/24--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	184	GigabitEthernet6/31
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	24	GigabitEthernet1/23
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	140	GigabitEthernet5/35
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	104	TenGigabitEthernet4/3
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	131	GigabitEthernet5/26
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	181	GigabitEthernet6/28
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	412	TenGigabitEthernet4/1--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	385	GigabitEthernet2/40--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	502	GigabitEthernet5/42--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	307	GigabitEthernet2/1--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	314	GigabitEthernet2/4--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	154	GigabitEthernet6/1
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	355	GigabitEthernet2/25--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	553	GigabitEthernet6/20--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	159	GigabitEthernet6/6
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	479	GigabitEthernet5/31--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	326	GigabitEthernet2/10--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	555	GigabitEthernet6/21--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	47	GigabitEthernet1/46
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	37	GigabitEthernet1/36
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	335	GigabitEthernet2/15--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	270	GigabitEthernet1/30--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	5	GigabitEthernet1/4
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	195	GigabitEthernet6/42
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	538	GigabitEthernet6/12--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	524	GigabitEthernet6/5--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	554	GigabitEthernet6/20--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	552	GigabitEthernet6/19--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	521	GigabitEthernet6/4--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	598	GigabitEthernet6/42--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	162	GigabitEthernet6/9
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	433	GigabitEthernet5/8--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	74	GigabitEthernet2/25
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	240	GigabitEthernet1/15--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	334	GigabitEthernet2/14--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	440	GigabitEthernet5/11--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	230	GigabitEthernet1/10--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	115	GigabitEthernet5/10
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	299	GigabitEthernet1/45--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	377	GigabitEthernet2/36--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	103	TenGigabitEthernet4/2
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	602	GigabitEthernet6/44--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	201	GigabitEthernet6/48
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	423	GigabitEthernet5/3--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	612	Loopback0
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	91	GigabitEthernet2/42
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	266	GigabitEthernet1/28--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	467	GigabitEthernet5/25--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	174	GigabitEthernet6/21
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	474	GigabitEthernet5/28--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	481	GigabitEthernet5/32--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	214	GigabitEthernet1/2--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	422	GigabitEthernet5/2--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	564	GigabitEthernet6/25--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	563	GigabitEthernet6/25--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	97	GigabitEthernet2/48
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	41	GigabitEthernet1/40
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	52	GigabitEthernet2/3
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	302	GigabitEthernet1/46--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	229	GigabitEthernet1/10--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	503	GigabitEthernet5/43--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	593	GigabitEthernet6/40--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	68	GigabitEthernet2/19
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	188	GigabitEthernet6/35
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	315	GigabitEthernet2/5--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	402	GigabitEthernet2/48--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	338	GigabitEthernet2/16--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	576	GigabitEthernet6/31--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	222	GigabitEthernet1/6--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	25	GigabitEthernet1/24
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	83	GigabitEthernet2/34
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	484	GigabitEthernet5/33--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	305	GigabitEthernet1/48--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	544	GigabitEthernet6/15--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	217	GigabitEthernet1/4--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	328	GigabitEthernet2/11--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	239	GigabitEthernet1/15--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	122	GigabitEthernet5/17
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	143	GigabitEthernet5/38
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	158	GigabitEthernet6/5
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	269	GigabitEthernet1/30--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	281	GigabitEthernet1/36--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	464	GigabitEthernet5/23--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	363	GigabitEthernet2/29--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	46	GigabitEthernet1/45
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	6	GigabitEthernet1/5
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	562	GigabitEthernet6/24--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	36	GigabitEthernet1/35
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	518	GigabitEthernet6/2--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	183	GigabitEthernet6/30
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	497	GigabitEthernet5/40--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	472	GigabitEthernet5/27--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	362	GigabitEthernet2/28--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	439	GigabitEthernet5/11--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	317	GigabitEthernet2/6--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	608	GigabitEthernet6/47--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	132	GigabitEthernet5/27
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	169	GigabitEthernet6/16
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	411	TenGigabitEthernet4/1--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	478	GigabitEthernet5/30--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	384	GigabitEthernet2/39--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	398	GigabitEthernet2/46--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	546	GigabitEthernet6/16--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	537	GigabitEthernet6/12--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	407	TenGigabitEthernet3/3--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	18	GigabitEthernet1/17
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	376	GigabitEthernet2/35--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	522	GigabitEthernet6/4--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	125	GigabitEthernet5/20
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	599	GigabitEthernet6/43--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	44	GigabitEthernet1/43
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	609	GigabitEthernet6/48--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	587	GigabitEthernet6/37--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	190	GigabitEthernet6/37
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	95	GigabitEthernet2/46
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	298	GigabitEthernet1/44--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	601	GigabitEthernet6/44--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	313	GigabitEthernet2/4--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	243	GigabitEthernet1/17--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	231	GigabitEthernet1/11--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	551	GigabitEthernet6/19--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	529	GigabitEthernet6/8--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	148	GigabitEthernet5/43
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	343	GigabitEthernet2/19--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	504	GigabitEthernet5/43--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	397	GigabitEthernet2/46--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	106	GigabitEthernet5/1
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	157	GigabitEthernet6/4
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	65	GigabitEthernet2/16
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	203	Vlan1
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	261	GigabitEthernet1/26--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	81	GigabitEthernet2/32
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	321	GigabitEthernet2/8--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	459	GigabitEthernet5/21--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	86	GigabitEthernet2/37
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	284	GigabitEthernet1/37--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	247	GigabitEthernet1/19--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	371	GigabitEthernet2/33--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	204	unrouted VLAN 1
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	165	GigabitEthernet6/12
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	289	GigabitEthernet1/40--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	2	GigabitEthernet1/1
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	435	GigabitEthernet5/9--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	401	GigabitEthernet2/48--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	186	GigabitEthernet6/33
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	147	GigabitEthernet5/42
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	339	GigabitEthernet2/17--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	228	GigabitEthernet1/9--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	531	GigabitEthernet6/9--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	268	GigabitEthernet1/29--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	345	GigabitEthernet2/20--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	596	GigabitEthernet6/41--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	172	GigabitEthernet6/19
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	319	GigabitEthernet2/7--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	223	GigabitEthernet1/7--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	404	TenGigabitEthernet3/1--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	516	GigabitEthernet6/1--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	282	GigabitEthernet1/36--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	420	GigabitEthernet5/1--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	121	GigabitEthernet5/16
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	344	GigabitEthernet2/19--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	487	GigabitEthernet5/35--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	494	GigabitEthernet5/38--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	238	GigabitEthernet1/14--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	577	GigabitEthernet6/32--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	253	GigabitEthernet1/22--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	561	GigabitEthernet6/24--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	448	GigabitEthernet5/15--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	209	unrouted VLAN 158
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	216	GigabitEthernet1/3--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	357	GigabitEthernet2/26--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	117	GigabitEthernet5/12
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	63	GigabitEthernet2/14
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	455	GigabitEthernet5/19--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	600	GigabitEthernet6/43--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	80	GigabitEthernet2/31
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	336	GigabitEthernet2/15--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	457	GigabitEthernet5/20--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	179	GigabitEthernet6/26
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	383	GigabitEthernet2/39--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	297	GigabitEthernet1/44--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	277	GigabitEthernet1/34--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	92	GigabitEthernet2/43
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	10	GigabitEthernet1/9
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	550	GigabitEthernet6/18--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	505	GigabitEthernet5/44--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	419	GigabitEthernet5/1--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	133	GigabitEthernet5/28
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	290	GigabitEthernet1/40--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	592	GigabitEthernet6/39--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	149	GigabitEthernet5/44
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	123	GigabitEthernet5/18
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	304	GigabitEthernet1/47--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	547	GigabitEthernet6/17--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	210	unrouted VLAN 901
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	406	TenGigabitEthernet3/2--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	258	GigabitEthernet1/24--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	396	GigabitEthernet2/45--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	482	GigabitEthernet5/32--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	173	GigabitEthernet6/20
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	530	GigabitEthernet6/8--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	56	GigabitEthernet2/7
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	499	GigabitEthernet5/41--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	66	GigabitEthernet2/17
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	19	GigabitEthernet1/18
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	54	GigabitEthernet2/5
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	365	GigabitEthernet2/30--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	306	GigabitEthernet1/48--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	70	GigabitEthernet2/21
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	470	GigabitEthernet5/26--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	166	GigabitEthernet6/13
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	88	GigabitEthernet2/39
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	141	GigabitEthernet5/36
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	30	GigabitEthernet1/29
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	570	GigabitEthernet6/28--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	403	TenGigabitEthernet3/1--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	252	GigabitEthernet1/21--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	466	GigabitEthernet5/24--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	156	GigabitEthernet6/3
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	134	GigabitEthernet5/29
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	75	GigabitEthernet2/26
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	283	GigabitEthernet1/37--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	59	GigabitEthernet2/10
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	421	GigabitEthernet5/2--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	450	GigabitEthernet5/16--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	271	GigabitEthernet1/31--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	491	GigabitEthernet5/37--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	219	GigabitEthernet1/5--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	318	GigabitEthernet2/6--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	13	GigabitEthernet1/12
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	105	TenGigabitEthernet4/4
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	473	GigabitEthernet5/28--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	185	GigabitEthernet6/32
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	3	GigabitEthernet1/2
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	597	GigabitEthernet6/42--Uncontrolled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	248	GigabitEthernet1/19--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	390	GigabitEthernet2/42--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	146	GigabitEthernet5/41
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	111	GigabitEthernet5/6
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	38	GigabitEthernet1/37
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	356	GigabitEthernet2/25--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	408	TenGigabitEthernet3/3--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	4	GigabitEthernet1/3
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	528	GigabitEthernet6/7--Controlled
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	164	GigabitEthernet6/11
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	196	GigabitEthernet6/43
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	242	GigabitEthernet1/16--Controlled
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	33	GigabitEthernet1/33
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	32	GigabitEthernet1/32
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	63	Tunnel0
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	21	GigabitEthernet1/21
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	7	GigabitEthernet1/7
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	26	GigabitEthernet1/26
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	18	GigabitEthernet1/18
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	16	GigabitEthernet1/16
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	44	GigabitEthernet1/44
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	55	FastEthernet1
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	27	GigabitEthernet1/27
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	57	unrouted VLAN 1
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	61	unrouted VLAN 1003
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	20	GigabitEthernet1/20
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	10	GigabitEthernet1/10
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	31	GigabitEthernet1/31
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	35	GigabitEthernet1/35
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	11	GigabitEthernet1/11
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	48	GigabitEthernet1/48
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	65	Port-channel1
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	29	GigabitEthernet1/29
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	50	TenGigabitEthernet1/50
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	39	GigabitEthernet1/39
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	64	Loopback0
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	58	unrouted VLAN 1002
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	41	GigabitEthernet1/41
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	12	GigabitEthernet1/12
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	15	GigabitEthernet1/15
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	52	TenGigabitEthernet1/52
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	60	unrouted VLAN 1005
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	56	Vlan1
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	66	unrouted VLAN 233
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	45	GigabitEthernet1/45
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	19	GigabitEthernet1/19
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	62	unrouted VLAN 146
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	54	Null0
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	67	Vlan233
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	70	unrouted VLAN 225
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	68	Tunnel1
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	2	GigabitEthernet1/2
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	17	GigabitEthernet1/17
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	1	GigabitEthernet1/1
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	30	GigabitEthernet1/30
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	25	GigabitEthernet1/25
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	28	GigabitEthernet1/28
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	40	GigabitEthernet1/40
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	14	GigabitEthernet1/14
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	69	Vlan225
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	59	unrouted VLAN 1004
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	49	TenGigabitEthernet1/49
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	24	GigabitEthernet1/24
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	22	GigabitEthernet1/22
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	42	GigabitEthernet1/42
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	46	GigabitEthernet1/46
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	23	GigabitEthernet1/23
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	13	GigabitEthernet1/13
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	6	GigabitEthernet1/6
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	3	GigabitEthernet1/3
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	36	GigabitEthernet1/36
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	9	GigabitEthernet1/9
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	51	TenGigabitEthernet1/51
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	47	GigabitEthernet1/47
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	8	GigabitEthernet1/8
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	38	GigabitEthernet1/38
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	4	GigabitEthernet1/4
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	34	GigabitEthernet1/34
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	37	GigabitEthernet1/37
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	43	GigabitEthernet1/43
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	5	GigabitEthernet1/5
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	559	GigabitEthernet6/23--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	127	GigabitEthernet5/22
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	32	GigabitEthernet1/31
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	443	GigabitEthernet5/13--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	206	unrouted VLAN 1004
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	118	GigabitEthernet5/13
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	71	GigabitEthernet2/22
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	358	GigabitEthernet2/20--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	331	GigabitEthernet2/7--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	560	GigabitEthernet6/23--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	580	GigabitEthernet6/33--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	84	GigabitEthernet2/35
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	512	GigabitEthernet5/47--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	437	GigabitEthernet5/10--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	463	GigabitEthernet5/23--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	194	GigabitEthernet6/41
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	517	GigabitEthernet6/2--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	458	GigabitEthernet5/20--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	451	GigabitEthernet5/17--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	220	unrouted VLAN 213
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	454	GigabitEthernet5/18--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	31	GigabitEthernet1/30
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	578	GigabitEthernet6/32--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	378	GigabitEthernet2/30--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	325	GigabitEthernet2/4--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	29	GigabitEthernet1/28
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	572	GigabitEthernet6/29--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	350	GigabitEthernet2/16--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	540	GigabitEthernet6/13--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	226	GigabitEthernet1/2--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	58	GigabitEthernet2/9
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	211	unrouted VLAN 10
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	153	GigabitEthernet5/48
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	15	GigabitEthernet1/14
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	527	GigabitEthernet6/7--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	431	GigabitEthernet5/7--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	382	GigabitEthernet2/32--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	337	GigabitEthernet2/10--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	101	TenGigabitEthernet3/4
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	340	GigabitEthernet2/11--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	76	GigabitEthernet2/27
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	311	GigabitEthernet1/45--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	62	GigabitEthernet2/13
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	571	GigabitEthernet6/29--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	139	GigabitEthernet5/34
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	389	GigabitEthernet2/36--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	129	GigabitEthernet5/24
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	548	GigabitEthernet6/17--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	495	GigabitEthernet5/39--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	418	TenGigabitEthernet4/1--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	236	GigabitEthernet1/7--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	218	unrouted VLAN 214
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	168	GigabitEthernet6/15
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	135	GigabitEthernet5/30
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	14	GigabitEthernet1/13
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	348	GigabitEthernet2/15--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	145	GigabitEthernet5/40
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	49	GigabitEthernet1/48
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	178	GigabitEthernet6/25
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	285	GigabitEthernet1/32--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	124	GigabitEthernet5/19
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	234	GigabitEthernet1/6--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	594	GigabitEthernet6/40--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	23	GigabitEthernet1/22
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	388	GigabitEthernet2/35--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	364	GigabitEthernet2/23--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	96	GigabitEthernet2/47
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	486	GigabitEthernet5/34--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	509	GigabitEthernet5/46--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	160	GigabitEthernet6/7
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	569	GigabitEthernet6/28--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	367	GigabitEthernet2/25--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	8	GigabitEthernet1/7
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	98	TenGigabitEthernet3/1
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	43	GigabitEthernet1/42
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	485	GigabitEthernet5/34--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	391	GigabitEthernet2/37--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	21	GigabitEthernet1/20
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	523	GigabitEthernet6/5--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	288	GigabitEthernet1/33--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	193	GigabitEthernet6/40
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	460	GigabitEthernet5/21--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	119	GigabitEthernet5/14
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	586	GigabitEthernet6/36--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	453	GigabitEthernet5/18--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	324	GigabitEthernet2/3--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	180	GigabitEthernet6/27
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	244	GigabitEthernet1/11--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	351	GigabitEthernet2/17--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	410	GigabitEthernet2/46--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	595	GigabitEthernet6/41--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	246	GigabitEthernet1/12--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	488	GigabitEthernet5/35--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	61	GigabitEthernet2/12
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	430	GigabitEthernet5/6--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	447	GigabitEthernet5/15--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	536	GigabitEthernet6/11--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	379	GigabitEthernet2/31--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	415	TenGigabitEthernet3/1--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	113	GigabitEthernet5/8
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	152	GigabitEthernet5/47
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	189	GigabitEthernet6/36
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	452	GigabitEthernet5/17--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	342	GigabitEthernet2/12--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	579	GigabitEthernet6/33--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	295	GigabitEthernet1/37--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	480	GigabitEthernet5/31--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	341	GigabitEthernet2/12--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	438	GigabitEthernet5/10--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	107	GigabitEthernet5/2
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	535	GigabitEthernet6/11--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	87	GigabitEthernet2/38
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	77	GigabitEthernet2/28
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	444	GigabitEthernet5/13--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	541	GigabitEthernet6/14--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	508	GigabitEthernet5/45--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	221	Port-channel1
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	39	GigabitEthernet1/38
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	64	GigabitEthernet2/15
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	558	GigabitEthernet6/22--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	417	TenGigabitEthernet4/1--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	12	GigabitEthernet1/11
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	312	GigabitEthernet1/45--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	45	GigabitEthernet1/44
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	507	GigabitEthernet5/45--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	405	GigabitEthernet2/44--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	260	GigabitEthernet1/19--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	573	GigabitEthernet6/30--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	237	GigabitEthernet1/8--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	370	GigabitEthernet2/26--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	309	GigabitEthernet1/44--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	567	GigabitEthernet6/27--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	1	FastEthernet1
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	506	GigabitEthernet5/44--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	136	GigabitEthernet5/31
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	116	GigabitEthernet5/11
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	416	TenGigabitEthernet3/1--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	144	GigabitEthernet5/39
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	380	GigabitEthernet2/31--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	100	TenGigabitEthernet3/3
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	300	GigabitEthernet1/39--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	286	GigabitEthernet1/32--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	120	GigabitEthernet5/15
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	381	GigabitEthernet2/32--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	581	GigabitEthernet6/34--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	308	GigabitEthernet1/43--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	392	GigabitEthernet2/37--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	254	GigabitEthernet1/16--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	177	GigabitEthernet6/24
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	496	GigabitEthernet5/39--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	605	GigabitEthernet6/46--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	373	GigabitEthernet2/28--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	607	GigabitEthernet6/47--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	205	unrouted VLAN 1002
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	42	GigabitEthernet1/41
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	22	GigabitEthernet1/21
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	399	GigabitEthernet2/41--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	235	GigabitEthernet1/7--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	301	GigabitEthernet1/40--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	436	GigabitEthernet5/9--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	213	unrouted VLAN 14
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	94	GigabitEthernet2/45
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	51	GigabitEthernet2/2
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	456	GigabitEthernet5/19--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	568	GigabitEthernet6/27--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	296	GigabitEthernet1/37--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	265	GigabitEthernet1/22--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	493	GigabitEthernet5/38--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	171	GigabitEthernet6/18
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	386	GigabitEthernet2/34--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	445	GigabitEthernet5/14--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	200	GigabitEthernet6/47
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	366	GigabitEthernet2/24--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	329	GigabitEthernet2/6--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	525	GigabitEthernet6/6--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	27	GigabitEthernet1/26
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	272	GigabitEthernet1/25--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	161	GigabitEthernet6/8
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	582	GigabitEthernet6/34--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	534	GigabitEthernet6/10--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	400	GigabitEthernet2/41--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	20	GigabitEthernet1/19
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	109	GigabitEthernet5/4
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	151	GigabitEthernet5/46
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	557	GigabitEthernet6/22--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	468	GigabitEthernet5/25--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	287	GigabitEthernet1/33--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	475	GigabitEthernet5/29--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	441	GigabitEthernet5/12--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	78	GigabitEthernet2/29
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	413	GigabitEthernet2/48--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	294	GigabitEthernet1/36--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	349	GigabitEthernet2/16--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	275	GigabitEthernet1/27--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	515	GigabitEthernet6/1--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	197	GigabitEthernet6/44
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	138	GigabitEthernet5/33
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	606	GigabitEthernet6/46--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	137	GigabitEthernet5/32
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	60	GigabitEthernet2/11
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	432	GigabitEthernet5/7--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	519	GigabitEthernet6/3--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	346	GigabitEthernet2/14--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	17	GigabitEthernet1/16
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	427	GigabitEthernet5/5--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	82	GigabitEthernet2/33
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	110	GigabitEthernet5/5
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	333	GigabitEthernet2/8--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	590	GigabitEthernet6/38--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	323	GigabitEthernet2/3--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	69	GigabitEthernet2/20
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	112	GigabitEthernet5/7
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	545	GigabitEthernet6/16--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	191	GigabitEthernet6/38
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	224	GigabitEthernet1/1--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	187	GigabitEthernet6/34
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	588	GigabitEthernet6/37--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	446	GigabitEthernet5/14--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	262	GigabitEthernet1/20--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	617	TenGigabitEthernet4/2--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	79	GigabitEthernet2/30
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	212	unrouted VLAN 11
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	352	GigabitEthernet2/17--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	126	GigabitEthernet5/21
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	426	GigabitEthernet5/4--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	251	GigabitEthernet1/15--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	542	GigabitEthernet6/14--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	369	GigabitEthernet2/26--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	279	GigabitEthernet1/29--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	176	GigabitEthernet6/23
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	498	GigabitEthernet5/40--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	483	GigabitEthernet5/33--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	256	GigabitEthernet1/17--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	372	GigabitEthernet2/27--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	574	GigabitEthernet6/30--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	170	GigabitEthernet6/17
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	33	GigabitEthernet1/32
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	428	GigabitEthernet5/5--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	7	GigabitEthernet1/6
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	26	GigabitEthernet1/25
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	227	GigabitEthernet1/3--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	99	TenGigabitEthernet3/2
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	566	GigabitEthernet6/26--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	526	GigabitEthernet6/6--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	72	GigabitEthernet2/23
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	500	GigabitEthernet5/41--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	264	GigabitEthernet1/21--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	255	GigabitEthernet1/17--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	533	GigabitEthernet6/10--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	359	GigabitEthernet2/21--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	182	GigabitEthernet6/29
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	108	GigabitEthernet5/3
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	604	GigabitEthernet6/45--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	556	GigabitEthernet6/21--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	462	GigabitEthernet5/22--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	414	GigabitEthernet2/48--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	232	GigabitEthernet1/5--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	477	GigabitEthernet5/30--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	225	GigabitEthernet1/2--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	330	GigabitEthernet2/6--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	142	GigabitEthernet5/37
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	207	unrouted VLAN 1005
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	263	GigabitEthernet1/21--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	394	GigabitEthernet2/38--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	167	GigabitEthernet6/14
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	48	GigabitEthernet1/47
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	360	GigabitEthernet2/21--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	610	GigabitEthernet6/48--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	514	GigabitEthernet5/48--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	513	GigabitEthernet5/48--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	615	TenGigabitEthernet3/4--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	50	GigabitEthernet2/1
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	476	GigabitEthernet5/29--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	510	GigabitEthernet5/46--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	393	GigabitEthernet2/38--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	449	GigabitEthernet5/16--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	293	GigabitEthernet1/36--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	274	GigabitEthernet1/26--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	549	GigabitEthernet6/18--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	322	GigabitEthernet2/2--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	469	GigabitEthernet5/26--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	353	GigabitEthernet2/18--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	575	GigabitEthernet6/31--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	375	GigabitEthernet2/29--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	128	GigabitEthernet5/23
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	28	GigabitEthernet1/27
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	310	GigabitEthernet1/44--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	40	GigabitEthernet1/39
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	589	GigabitEthernet6/38--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	303	GigabitEthernet1/41--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	192	GigabitEthernet6/39
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	250	GigabitEthernet1/14--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	614	TenGigabitEthernet3/3--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	501	GigabitEthernet5/42--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	215	unrouted VLAN 100
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	278	GigabitEthernet1/28--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	490	GigabitEthernet5/36--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	150	GigabitEthernet5/45
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	130	GigabitEthernet5/25
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	155	GigabitEthernet6/2
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	387	GigabitEthernet2/35--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	53	GigabitEthernet2/4
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	245	GigabitEthernet1/12--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	543	GigabitEthernet6/15--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	267	GigabitEthernet1/23--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	354	GigabitEthernet2/18--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	461	GigabitEthernet5/22--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	583	GigabitEthernet6/35--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	257	GigabitEthernet1/18--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	85	GigabitEthernet2/36
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	332	GigabitEthernet2/7--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	9	GigabitEthernet1/8
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	425	GigabitEthernet5/4--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	591	GigabitEthernet6/39--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	34	GigabitEthernet1/33
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	539	GigabitEthernet6/13--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	603	GigabitEthernet6/45--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	90	GigabitEthernet2/41
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	276	GigabitEthernet1/27--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	620	TenGigabitEthernet4/3--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	565	GigabitEthernet6/26--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	102	TenGigabitEthernet4/1
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	520	GigabitEthernet6/3--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	532	GigabitEthernet6/9--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	16	GigabitEthernet1/15
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	55	GigabitEthernet2/6
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	233	GigabitEthernet1/6--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	57	GigabitEthernet2/8
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	259	GigabitEthernet1/19--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	368	GigabitEthernet2/25--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	424	GigabitEthernet5/3--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	316	GigabitEthernet1/47--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	163	GigabitEthernet6/10
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	395	GigabitEthernet2/39--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	89	GigabitEthernet2/40
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	611	TenGigabitEthernet3/2--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	175	GigabitEthernet6/22
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	584	GigabitEthernet6/35--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	35	GigabitEthernet1/34
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	11	GigabitEthernet1/10
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	492	GigabitEthernet5/37--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	208	unrouted VLAN 1003
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	347	GigabitEthernet2/15--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	511	GigabitEthernet5/47--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	434	GigabitEthernet5/8--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	93	GigabitEthernet2/44
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	292	GigabitEthernet1/35--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	291	GigabitEthernet1/35--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	374	GigabitEthernet2/28--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	114	GigabitEthernet5/9
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	199	GigabitEthernet6/46
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	442	GigabitEthernet5/12--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	429	GigabitEthernet5/6--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	73	GigabitEthernet2/24
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	409	GigabitEthernet2/46--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	67	GigabitEthernet2/18
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	241	GigabitEthernet1/10--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	198	GigabitEthernet6/45
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	489	GigabitEthernet5/36--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	585	GigabitEthernet6/36--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	327	GigabitEthernet2/5--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	320	GigabitEthernet2/1--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	280	GigabitEthernet1/29--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	273	GigabitEthernet1/26--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	471	GigabitEthernet5/27--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	622	TenGigabitEthernet4/4--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	202	Null0
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	249	GigabitEthernet1/14--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	361	GigabitEthernet2/22--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	465	GigabitEthernet5/24--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	184	GigabitEthernet6/31
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	24	GigabitEthernet1/23
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	140	GigabitEthernet5/35
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	104	TenGigabitEthernet4/3
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	131	GigabitEthernet5/26
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	181	GigabitEthernet6/28
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	412	GigabitEthernet2/47--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	385	GigabitEthernet2/34--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	502	GigabitEthernet5/42--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	307	GigabitEthernet1/43--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	314	GigabitEthernet1/46--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	154	GigabitEthernet6/1
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	355	GigabitEthernet2/19--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	553	GigabitEthernet6/20--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	159	GigabitEthernet6/6
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	479	GigabitEthernet5/31--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	326	GigabitEthernet2/4--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	555	GigabitEthernet6/21--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	47	GigabitEthernet1/46
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	619	TenGigabitEthernet4/3--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	37	GigabitEthernet1/36
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	335	GigabitEthernet2/9--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	270	GigabitEthernet1/24--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	5	GigabitEthernet1/4
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	195	GigabitEthernet6/42
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	621	TenGigabitEthernet4/4--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	538	GigabitEthernet6/12--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	524	GigabitEthernet6/5--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	554	GigabitEthernet6/20--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	552	GigabitEthernet6/19--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	521	GigabitEthernet6/4--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	598	GigabitEthernet6/42--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	162	GigabitEthernet6/9
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	433	GigabitEthernet5/8--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	74	GigabitEthernet2/25
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	240	GigabitEthernet1/9--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	334	GigabitEthernet2/8--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	440	GigabitEthernet5/11--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	230	GigabitEthernet1/4--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	115	GigabitEthernet5/10
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	299	GigabitEthernet1/39--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	377	GigabitEthernet2/30--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	103	TenGigabitEthernet4/2
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	602	GigabitEthernet6/44--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	201	GigabitEthernet6/48
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	423	GigabitEthernet5/3--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	612	TenGigabitEthernet3/2--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	91	GigabitEthernet2/42
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	266	GigabitEthernet1/22--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	467	GigabitEthernet5/25--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	174	GigabitEthernet6/21
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	474	GigabitEthernet5/28--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	481	GigabitEthernet5/32--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	214	unrouted VLAN 60
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	422	GigabitEthernet5/2--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	564	GigabitEthernet6/25--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	563	GigabitEthernet6/25--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	97	GigabitEthernet2/48
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	41	GigabitEthernet1/40
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	52	GigabitEthernet2/3
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	302	GigabitEthernet1/40--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	229	GigabitEthernet1/4--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	503	GigabitEthernet5/43--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	593	GigabitEthernet6/40--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	68	GigabitEthernet2/19
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	188	GigabitEthernet6/35
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	315	GigabitEthernet1/47--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	402	GigabitEthernet2/42--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	338	GigabitEthernet2/10--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	576	GigabitEthernet6/31--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	616	TenGigabitEthernet3/4--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	222	Loopback0
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	25	GigabitEthernet1/24
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	83	GigabitEthernet2/34
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	484	GigabitEthernet5/33--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	305	GigabitEthernet1/42--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	544	GigabitEthernet6/15--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	217	unrouted VLAN 199
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	328	GigabitEthernet2/5--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	239	GigabitEthernet1/9--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	122	GigabitEthernet5/17
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	143	GigabitEthernet5/38
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	158	GigabitEthernet6/5
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	269	GigabitEthernet1/24--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	281	GigabitEthernet1/30--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	464	GigabitEthernet5/23--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	363	GigabitEthernet2/23--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	46	GigabitEthernet1/45
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	6	GigabitEthernet1/5
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	562	GigabitEthernet6/24--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	36	GigabitEthernet1/35
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	518	GigabitEthernet6/2--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	183	GigabitEthernet6/30
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	497	GigabitEthernet5/40--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	472	GigabitEthernet5/27--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	362	GigabitEthernet2/22--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	439	GigabitEthernet5/11--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	317	GigabitEthernet1/48--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	608	GigabitEthernet6/47--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	132	GigabitEthernet5/27
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	169	GigabitEthernet6/16
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	411	GigabitEthernet2/47--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	478	GigabitEthernet5/30--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	384	GigabitEthernet2/33--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	398	GigabitEthernet2/40--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	546	GigabitEthernet6/16--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	537	GigabitEthernet6/12--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	407	GigabitEthernet2/45--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	18	GigabitEthernet1/17
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	376	GigabitEthernet2/29--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	522	GigabitEthernet6/4--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	125	GigabitEthernet5/20
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	599	GigabitEthernet6/43--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	44	GigabitEthernet1/43
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	609	GigabitEthernet6/48--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	587	GigabitEthernet6/37--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	190	GigabitEthernet6/37
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	95	GigabitEthernet2/46
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	298	GigabitEthernet1/38--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	601	GigabitEthernet6/44--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	313	GigabitEthernet1/46--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	243	GigabitEthernet1/11--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	231	GigabitEthernet1/5--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	551	GigabitEthernet6/19--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	529	GigabitEthernet6/8--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	148	GigabitEthernet5/43
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	343	GigabitEthernet2/13--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	504	GigabitEthernet5/43--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	397	GigabitEthernet2/40--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	106	GigabitEthernet5/1
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	157	GigabitEthernet6/4
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	65	GigabitEthernet2/16
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	203	Vlan1
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	261	GigabitEthernet1/20--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	81	GigabitEthernet2/32
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	321	GigabitEthernet2/2--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	459	GigabitEthernet5/21--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	86	GigabitEthernet2/37
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	284	GigabitEthernet1/31--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	247	GigabitEthernet1/13--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	371	GigabitEthernet2/27--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	204	unrouted VLAN 1
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	165	GigabitEthernet6/12
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	289	GigabitEthernet1/34--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	2	GigabitEthernet1/1
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	435	GigabitEthernet5/9--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	401	GigabitEthernet2/42--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	186	GigabitEthernet6/33
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	147	GigabitEthernet5/42
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	339	GigabitEthernet2/11--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	228	GigabitEthernet1/3--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	531	GigabitEthernet6/9--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	268	GigabitEthernet1/23--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	345	GigabitEthernet2/14--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	596	GigabitEthernet6/41--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	172	GigabitEthernet6/19
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	319	GigabitEthernet2/1--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	223	GigabitEthernet1/1--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	404	GigabitEthernet2/43--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	613	TenGigabitEthernet3/3--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	516	GigabitEthernet6/1--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	282	GigabitEthernet1/30--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	420	GigabitEthernet5/1--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	121	GigabitEthernet5/16
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	344	GigabitEthernet2/13--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	487	GigabitEthernet5/35--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	494	GigabitEthernet5/38--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	238	GigabitEthernet1/8--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	577	GigabitEthernet6/32--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	253	GigabitEthernet1/16--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	561	GigabitEthernet6/24--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	448	GigabitEthernet5/15--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	209	unrouted VLAN 2
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	216	unrouted VLAN 111
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	357	GigabitEthernet2/20--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	117	GigabitEthernet5/12
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	63	GigabitEthernet2/14
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	455	GigabitEthernet5/19--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	600	GigabitEthernet6/43--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	80	GigabitEthernet2/31
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	336	GigabitEthernet2/9--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	457	GigabitEthernet5/20--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	179	GigabitEthernet6/26
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	383	GigabitEthernet2/33--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	297	GigabitEthernet1/38--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	277	GigabitEthernet1/28--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	92	GigabitEthernet2/43
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	10	GigabitEthernet1/9
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	550	GigabitEthernet6/18--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	505	GigabitEthernet5/44--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	419	GigabitEthernet5/1--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	133	GigabitEthernet5/28
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	290	GigabitEthernet1/34--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	592	GigabitEthernet6/39--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	149	GigabitEthernet5/44
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	123	GigabitEthernet5/18
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	304	GigabitEthernet1/41--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	547	GigabitEthernet6/17--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	210	unrouted VLAN 4
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	406	GigabitEthernet2/44--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	258	GigabitEthernet1/18--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	396	GigabitEthernet2/39--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	482	GigabitEthernet5/32--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	173	GigabitEthernet6/20
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	530	GigabitEthernet6/8--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	56	GigabitEthernet2/7
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	499	GigabitEthernet5/41--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	66	GigabitEthernet2/17
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	19	GigabitEthernet1/18
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	54	GigabitEthernet2/5
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	365	GigabitEthernet2/24--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	306	GigabitEthernet1/42--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	70	GigabitEthernet2/21
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	470	GigabitEthernet5/26--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	166	GigabitEthernet6/13
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	88	GigabitEthernet2/39
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	141	GigabitEthernet5/36
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	30	GigabitEthernet1/29
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	570	GigabitEthernet6/28--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	403	GigabitEthernet2/43--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	252	GigabitEthernet1/15--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	466	GigabitEthernet5/24--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	156	GigabitEthernet6/3
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	134	GigabitEthernet5/29
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	75	GigabitEthernet2/26
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	283	GigabitEthernet1/31--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	618	TenGigabitEthernet4/2--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	59	GigabitEthernet2/10
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	421	GigabitEthernet5/2--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	450	GigabitEthernet5/16--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	271	GigabitEthernet1/25--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	491	GigabitEthernet5/37--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	219	unrouted VLAN 110
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	318	GigabitEthernet1/48--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	13	GigabitEthernet1/12
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	105	TenGigabitEthernet4/4
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	473	GigabitEthernet5/28--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	185	GigabitEthernet6/32
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	3	GigabitEthernet1/2
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	597	GigabitEthernet6/42--Uncontrolled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	248	GigabitEthernet1/13--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	390	GigabitEthernet2/36--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	146	GigabitEthernet5/41
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	111	GigabitEthernet5/6
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	38	GigabitEthernet1/37
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	356	GigabitEthernet2/19--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	408	GigabitEthernet2/45--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	4	GigabitEthernet1/3
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	528	GigabitEthernet6/7--Controlled
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	164	GigabitEthernet6/11
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	196	GigabitEthernet6/43
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	242	GigabitEthernet1/10--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	559	GigabitEthernet6/24--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	127	GigabitEthernet5/22
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	32	GigabitEthernet1/31
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	443	GigabitEthernet5/14--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	206	unrouted VLAN 1004
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	118	GigabitEthernet5/13
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	71	GigabitEthernet2/22
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	358	GigabitEthernet2/27--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	331	GigabitEthernet2/14--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	560	GigabitEthernet6/24--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	580	GigabitEthernet6/34--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	84	GigabitEthernet2/35
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	512	GigabitEthernet5/48--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	437	GigabitEthernet5/11--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	463	GigabitEthernet5/24--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	194	GigabitEthernet6/41
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	517	GigabitEthernet6/3--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	458	GigabitEthernet5/21--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	451	GigabitEthernet5/18--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	220	GigabitEthernet1/6--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	454	GigabitEthernet5/19--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	31	GigabitEthernet1/30
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	578	GigabitEthernet6/33--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	378	GigabitEthernet2/37--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	325	GigabitEthernet2/11--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	29	GigabitEthernet1/28
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	572	GigabitEthernet6/30--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	350	GigabitEthernet2/23--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	540	GigabitEthernet6/14--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	226	GigabitEthernet1/9--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	58	GigabitEthernet2/9
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	211	GigabitEthernet1/2--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	153	GigabitEthernet5/48
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	15	GigabitEthernet1/14
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	527	GigabitEthernet6/8--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	431	GigabitEthernet5/8--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	382	GigabitEthernet2/39--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	337	GigabitEthernet2/17--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	101	TenGigabitEthernet3/4
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	340	GigabitEthernet2/18--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	76	GigabitEthernet2/27
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	311	GigabitEthernet2/4--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	62	GigabitEthernet2/13
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	571	GigabitEthernet6/30--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	139	GigabitEthernet5/34
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	389	GigabitEthernet2/43--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	129	GigabitEthernet5/24
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	548	GigabitEthernet6/18--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	495	GigabitEthernet5/40--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	418	GigabitEthernet5/1--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	236	GigabitEthernet1/14--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	218	GigabitEthernet1/5--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	168	GigabitEthernet6/15
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	135	GigabitEthernet5/30
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	14	GigabitEthernet1/13
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	348	GigabitEthernet2/22--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	145	GigabitEthernet5/40
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	49	GigabitEthernet1/48
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	178	GigabitEthernet6/25
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	285	GigabitEthernet1/39--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	124	GigabitEthernet5/19
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	234	GigabitEthernet1/13--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	594	GigabitEthernet6/41--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	23	GigabitEthernet1/22
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	388	GigabitEthernet2/42--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	364	GigabitEthernet2/30--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	96	GigabitEthernet2/47
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	486	GigabitEthernet5/35--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	509	GigabitEthernet5/47--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	160	GigabitEthernet6/7
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	569	GigabitEthernet6/29--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	367	GigabitEthernet2/32--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	8	GigabitEthernet1/7
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	98	TenGigabitEthernet3/1
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	43	GigabitEthernet1/42
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	485	GigabitEthernet5/35--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	391	GigabitEthernet2/44--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	21	GigabitEthernet1/20
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	523	GigabitEthernet6/6--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	288	GigabitEthernet1/40--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	193	GigabitEthernet6/40
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	460	GigabitEthernet5/22--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	119	GigabitEthernet5/14
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	586	GigabitEthernet6/37--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	453	GigabitEthernet5/19--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	324	GigabitEthernet2/10--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	180	GigabitEthernet6/27
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	244	GigabitEthernet1/18--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	351	GigabitEthernet2/24--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	410	TenGigabitEthernet4/1--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	595	GigabitEthernet6/42--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	246	GigabitEthernet1/19--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	488	GigabitEthernet5/36--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	61	GigabitEthernet2/12
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	430	GigabitEthernet5/7--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	447	GigabitEthernet5/16--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	536	GigabitEthernet6/12--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	379	GigabitEthernet2/38--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	415	TenGigabitEthernet4/4--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	113	GigabitEthernet5/8
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	152	GigabitEthernet5/47
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	189	GigabitEthernet6/36
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	452	GigabitEthernet5/18--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	342	GigabitEthernet2/19--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	579	GigabitEthernet6/34--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	295	GigabitEthernet1/44--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	480	GigabitEthernet5/32--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	341	GigabitEthernet2/19--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	438	GigabitEthernet5/11--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	107	GigabitEthernet5/2
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	535	GigabitEthernet6/12--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	87	GigabitEthernet2/38
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	77	GigabitEthernet2/28
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	444	GigabitEthernet5/14--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	541	GigabitEthernet6/15--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	508	GigabitEthernet5/46--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	221	GigabitEthernet1/7--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	39	GigabitEthernet1/38
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	64	GigabitEthernet2/15
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	558	GigabitEthernet6/23--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	417	GigabitEthernet5/1--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	12	GigabitEthernet1/11
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	312	GigabitEthernet2/4--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	45	GigabitEthernet1/44
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	507	GigabitEthernet5/46--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	405	TenGigabitEthernet3/3--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	260	GigabitEthernet1/26--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	573	GigabitEthernet6/31--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	237	GigabitEthernet1/15--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	370	GigabitEthernet2/33--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	309	GigabitEthernet2/3--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	567	GigabitEthernet6/28--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	1	FastEthernet1
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	506	GigabitEthernet5/45--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	136	GigabitEthernet5/31
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	116	GigabitEthernet5/11
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	416	TenGigabitEthernet4/4--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	144	GigabitEthernet5/39
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	380	GigabitEthernet2/38--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	100	TenGigabitEthernet3/3
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	300	GigabitEthernet1/46--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	286	GigabitEthernet1/39--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	120	GigabitEthernet5/15
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	381	GigabitEthernet2/39--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	581	GigabitEthernet6/35--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	308	GigabitEthernet2/2--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	392	GigabitEthernet2/44--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	254	GigabitEthernet1/23--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	177	GigabitEthernet6/24
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	496	GigabitEthernet5/40--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	605	GigabitEthernet6/47--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	373	GigabitEthernet2/35--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	607	GigabitEthernet6/48--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	205	unrouted VLAN 1002
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	42	GigabitEthernet1/41
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	22	GigabitEthernet1/21
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	399	GigabitEthernet2/48--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	235	GigabitEthernet1/14--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	301	GigabitEthernet1/47--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	436	GigabitEthernet5/10--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	213	GigabitEthernet1/3--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	94	GigabitEthernet2/45
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	51	GigabitEthernet2/2
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	456	GigabitEthernet5/20--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	568	GigabitEthernet6/28--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	296	GigabitEthernet1/44--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	265	GigabitEthernet1/29--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	493	GigabitEthernet5/39--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	171	GigabitEthernet6/18
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	386	GigabitEthernet2/41--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	445	GigabitEthernet5/15--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	200	GigabitEthernet6/47
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	366	GigabitEthernet2/31--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	329	GigabitEthernet2/13--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	525	GigabitEthernet6/7--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	27	GigabitEthernet1/26
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	272	GigabitEthernet1/32--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	161	GigabitEthernet6/8
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	582	GigabitEthernet6/35--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	534	GigabitEthernet6/11--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	400	GigabitEthernet2/48--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	20	GigabitEthernet1/19
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	109	GigabitEthernet5/4
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	151	GigabitEthernet5/46
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	557	GigabitEthernet6/23--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	468	GigabitEthernet5/26--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	287	GigabitEthernet1/40--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	475	GigabitEthernet5/30--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	441	GigabitEthernet5/13--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	78	GigabitEthernet2/29
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	413	TenGigabitEthernet4/3--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	294	GigabitEthernet1/43--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	349	GigabitEthernet2/23--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	275	GigabitEthernet1/34--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	515	GigabitEthernet6/2--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	197	GigabitEthernet6/44
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	138	GigabitEthernet5/33
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	606	GigabitEthernet6/47--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	137	GigabitEthernet5/32
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	60	GigabitEthernet2/11
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	432	GigabitEthernet5/8--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	519	GigabitEthernet6/4--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	346	GigabitEthernet2/21--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	17	GigabitEthernet1/16
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	427	GigabitEthernet5/6--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	82	GigabitEthernet2/33
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	110	GigabitEthernet5/5
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	333	GigabitEthernet2/15--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	590	GigabitEthernet6/39--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	323	GigabitEthernet2/10--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	69	GigabitEthernet2/20
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	112	GigabitEthernet5/7
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	545	GigabitEthernet6/17--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	191	GigabitEthernet6/38
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	224	GigabitEthernet1/8--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	187	GigabitEthernet6/34
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	588	GigabitEthernet6/38--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	446	GigabitEthernet5/15--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	262	GigabitEthernet1/27--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	79	GigabitEthernet2/30
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	212	GigabitEthernet1/2--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	352	GigabitEthernet2/24--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	126	GigabitEthernet5/21
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	426	GigabitEthernet5/5--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	251	GigabitEthernet1/22--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	542	GigabitEthernet6/15--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	369	GigabitEthernet2/33--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	279	GigabitEthernet1/36--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	176	GigabitEthernet6/23
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	498	GigabitEthernet5/41--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	483	GigabitEthernet5/34--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	256	GigabitEthernet1/24--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	372	GigabitEthernet2/34--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	574	GigabitEthernet6/31--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	170	GigabitEthernet6/17
auto-GameHQSW2-00:26:5a:e4:9e:e4	82	GigabitEthernet9/4
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	33	GigabitEthernet1/32
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	428	GigabitEthernet5/6--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	7	GigabitEthernet1/6
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	26	GigabitEthernet1/25
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	227	GigabitEthernet1/10--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	99	TenGigabitEthernet3/2
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	566	GigabitEthernet6/27--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	526	GigabitEthernet6/7--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	72	GigabitEthernet2/23
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	500	GigabitEthernet5/42--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	264	GigabitEthernet1/28--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	255	GigabitEthernet1/24--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	533	GigabitEthernet6/11--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	359	GigabitEthernet2/28--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	182	GigabitEthernet6/29
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	108	GigabitEthernet5/3
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	604	GigabitEthernet6/46--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	556	GigabitEthernet6/22--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	462	GigabitEthernet5/23--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	414	TenGigabitEthernet4/3--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	232	GigabitEthernet1/12--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	477	GigabitEthernet5/31--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	225	GigabitEthernet1/9--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	330	GigabitEthernet2/13--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	142	GigabitEthernet5/37
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	207	unrouted VLAN 1005
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	263	GigabitEthernet1/28--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	394	GigabitEthernet2/45--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	167	GigabitEthernet6/14
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	48	GigabitEthernet1/47
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	360	GigabitEthernet2/28--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	610	Loopback0
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	514	GigabitEthernet6/1--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	513	GigabitEthernet6/1--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	50	GigabitEthernet2/1
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	476	GigabitEthernet5/30--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	510	GigabitEthernet5/47--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	393	GigabitEthernet2/45--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	449	GigabitEthernet5/17--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	293	GigabitEthernet1/43--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	274	GigabitEthernet1/33--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	549	GigabitEthernet6/19--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	322	GigabitEthernet2/9--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	469	GigabitEthernet5/27--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	353	GigabitEthernet2/25--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	575	GigabitEthernet6/32--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	375	GigabitEthernet2/36--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	128	GigabitEthernet5/23
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	28	GigabitEthernet1/27
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	310	GigabitEthernet2/3--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	40	GigabitEthernet1/39
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	589	GigabitEthernet6/39--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	303	GigabitEthernet1/48--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	192	GigabitEthernet6/39
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	250	GigabitEthernet1/21--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	501	GigabitEthernet5/43--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	215	GigabitEthernet1/4--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	278	GigabitEthernet1/35--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	490	GigabitEthernet5/37--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	150	GigabitEthernet5/45
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	130	GigabitEthernet5/25
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	155	GigabitEthernet6/2
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	387	GigabitEthernet2/42--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	53	GigabitEthernet2/4
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	245	GigabitEthernet1/19--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	543	GigabitEthernet6/16--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	267	GigabitEthernet1/30--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	354	GigabitEthernet2/25--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	461	GigabitEthernet5/23--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	583	GigabitEthernet6/36--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	257	GigabitEthernet1/25--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	85	GigabitEthernet2/36
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	332	GigabitEthernet2/14--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	9	GigabitEthernet1/8
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	425	GigabitEthernet5/5--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	591	GigabitEthernet6/40--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	34	GigabitEthernet1/33
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	539	GigabitEthernet6/14--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	603	GigabitEthernet6/46--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	90	GigabitEthernet2/41
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	276	GigabitEthernet1/34--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	565	GigabitEthernet6/27--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	102	TenGigabitEthernet4/1
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	520	GigabitEthernet6/4--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	532	GigabitEthernet6/10--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	16	GigabitEthernet1/15
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	55	GigabitEthernet2/6
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	233	GigabitEthernet1/13--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	57	GigabitEthernet2/8
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	259	GigabitEthernet1/26--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	368	GigabitEthernet2/32--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	424	GigabitEthernet5/4--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	316	GigabitEthernet2/6--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	163	GigabitEthernet6/10
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	395	GigabitEthernet2/46--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	89	GigabitEthernet2/40
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	611	Port-channel1
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	175	GigabitEthernet6/22
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	584	GigabitEthernet6/36--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	35	GigabitEthernet1/34
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	11	GigabitEthernet1/10
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	492	GigabitEthernet5/38--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	208	unrouted VLAN 1003
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	347	GigabitEthernet2/22--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	511	GigabitEthernet5/48--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	434	GigabitEthernet5/9--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	93	GigabitEthernet2/44
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	292	GigabitEthernet1/42--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	291	GigabitEthernet1/42--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	374	GigabitEthernet2/35--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	114	GigabitEthernet5/9
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	199	GigabitEthernet6/46
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	442	GigabitEthernet5/13--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	429	GigabitEthernet5/7--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	73	GigabitEthernet2/24
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	409	TenGigabitEthernet4/1--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	67	GigabitEthernet2/18
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	241	GigabitEthernet1/17--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	198	GigabitEthernet6/45
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	489	GigabitEthernet5/37--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	585	GigabitEthernet6/37--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	327	GigabitEthernet2/12--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	320	GigabitEthernet2/8--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	280	GigabitEthernet1/36--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	273	GigabitEthernet1/33--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	471	GigabitEthernet5/28--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	202	Null0
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	249	GigabitEthernet1/21--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	361	GigabitEthernet2/29--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	465	GigabitEthernet5/25--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	184	GigabitEthernet6/31
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	24	GigabitEthernet1/23
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	140	GigabitEthernet5/35
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	104	TenGigabitEthernet4/3
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	131	GigabitEthernet5/26
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	181	GigabitEthernet6/28
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	412	TenGigabitEthernet4/2--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	385	GigabitEthernet2/41--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	502	GigabitEthernet5/43--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	307	GigabitEthernet2/2--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	314	GigabitEthernet2/5--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	154	GigabitEthernet6/1
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	355	GigabitEthernet2/26--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	553	GigabitEthernet6/21--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	159	GigabitEthernet6/6
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	479	GigabitEthernet5/32--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	326	GigabitEthernet2/11--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	555	GigabitEthernet6/22--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	47	GigabitEthernet1/46
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	37	GigabitEthernet1/36
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	335	GigabitEthernet2/16--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	270	GigabitEthernet1/31--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	5	GigabitEthernet1/4
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	195	GigabitEthernet6/42
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	538	GigabitEthernet6/13--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	524	GigabitEthernet6/6--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	554	GigabitEthernet6/21--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	552	GigabitEthernet6/20--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	521	GigabitEthernet6/5--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	598	GigabitEthernet6/43--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	162	GigabitEthernet6/9
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	433	GigabitEthernet5/9--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	74	GigabitEthernet2/25
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	240	GigabitEthernet1/16--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	334	GigabitEthernet2/15--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	440	GigabitEthernet5/12--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	230	GigabitEthernet1/11--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	115	GigabitEthernet5/10
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	299	GigabitEthernet1/46--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	377	GigabitEthernet2/37--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	103	TenGigabitEthernet4/2
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	602	GigabitEthernet6/45--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	201	GigabitEthernet6/48
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	423	GigabitEthernet5/4--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	91	GigabitEthernet2/42
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	266	GigabitEthernet1/29--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	467	GigabitEthernet5/26--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	174	GigabitEthernet6/21
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	474	GigabitEthernet5/29--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	481	GigabitEthernet5/33--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	214	GigabitEthernet1/3--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	422	GigabitEthernet5/3--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	564	GigabitEthernet6/26--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	563	GigabitEthernet6/26--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	97	GigabitEthernet2/48
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	41	GigabitEthernet1/40
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	52	GigabitEthernet2/3
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	302	GigabitEthernet1/47--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	229	GigabitEthernet1/11--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	503	GigabitEthernet5/44--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	593	GigabitEthernet6/41--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	68	GigabitEthernet2/19
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	188	GigabitEthernet6/35
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	315	GigabitEthernet2/6--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	402	TenGigabitEthernet3/1--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	338	GigabitEthernet2/17--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	576	GigabitEthernet6/32--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	222	GigabitEthernet1/7--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	25	GigabitEthernet1/24
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	83	GigabitEthernet2/34
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	484	GigabitEthernet5/34--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	305	GigabitEthernet2/1--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	544	GigabitEthernet6/16--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	217	GigabitEthernet1/5--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	328	GigabitEthernet2/12--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	239	GigabitEthernet1/16--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	122	GigabitEthernet5/17
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	143	GigabitEthernet5/38
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	158	GigabitEthernet6/5
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	269	GigabitEthernet1/31--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	281	GigabitEthernet1/37--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	464	GigabitEthernet5/24--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	363	GigabitEthernet2/30--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	46	GigabitEthernet1/45
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	6	GigabitEthernet1/5
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	562	GigabitEthernet6/25--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	36	GigabitEthernet1/35
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	518	GigabitEthernet6/3--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	183	GigabitEthernet6/30
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	497	GigabitEthernet5/41--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	472	GigabitEthernet5/28--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	362	GigabitEthernet2/29--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	439	GigabitEthernet5/12--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	317	GigabitEthernet2/7--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	608	GigabitEthernet6/48--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	132	GigabitEthernet5/27
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	169	GigabitEthernet6/16
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	411	TenGigabitEthernet4/2--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	478	GigabitEthernet5/31--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	384	GigabitEthernet2/40--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	398	GigabitEthernet2/47--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	546	GigabitEthernet6/17--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	537	GigabitEthernet6/13--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	407	TenGigabitEthernet3/4--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	18	GigabitEthernet1/17
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	376	GigabitEthernet2/36--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	522	GigabitEthernet6/5--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	125	GigabitEthernet5/20
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	599	GigabitEthernet6/44--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	44	GigabitEthernet1/43
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	609	Tunnel0
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	587	GigabitEthernet6/38--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	190	GigabitEthernet6/37
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	95	GigabitEthernet2/46
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	298	GigabitEthernet1/45--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	601	GigabitEthernet6/45--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	313	GigabitEthernet2/5--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	243	GigabitEthernet1/18--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	231	GigabitEthernet1/12--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	551	GigabitEthernet6/20--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	529	GigabitEthernet6/9--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	148	GigabitEthernet5/43
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	343	GigabitEthernet2/20--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	504	GigabitEthernet5/44--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	397	GigabitEthernet2/47--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	106	GigabitEthernet5/1
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	157	GigabitEthernet6/4
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	65	GigabitEthernet2/16
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	203	Vlan1
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	261	GigabitEthernet1/27--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	81	GigabitEthernet2/32
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	321	GigabitEthernet2/9--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	459	GigabitEthernet5/22--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	86	GigabitEthernet2/37
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	284	GigabitEthernet1/38--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	247	GigabitEthernet1/20--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	371	GigabitEthernet2/34--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	204	unrouted VLAN 1
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	165	GigabitEthernet6/12
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	289	GigabitEthernet1/41--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	2	GigabitEthernet1/1
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	435	GigabitEthernet5/10--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	401	TenGigabitEthernet3/1--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	186	GigabitEthernet6/33
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	147	GigabitEthernet5/42
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	339	GigabitEthernet2/18--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	228	GigabitEthernet1/10--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	531	GigabitEthernet6/10--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	268	GigabitEthernet1/30--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	345	GigabitEthernet2/21--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	596	GigabitEthernet6/42--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	172	GigabitEthernet6/19
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	319	GigabitEthernet2/8--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	223	GigabitEthernet1/8--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	404	TenGigabitEthernet3/2--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	516	GigabitEthernet6/2--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	282	GigabitEthernet1/37--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	420	GigabitEthernet5/2--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	121	GigabitEthernet5/16
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	344	GigabitEthernet2/20--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	487	GigabitEthernet5/36--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	494	GigabitEthernet5/39--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	238	GigabitEthernet1/15--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	577	GigabitEthernet6/33--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	253	GigabitEthernet1/23--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	561	GigabitEthernet6/25--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	448	GigabitEthernet5/16--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	209	GigabitEthernet1/1--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	216	GigabitEthernet1/4--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	357	GigabitEthernet2/27--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	117	GigabitEthernet5/12
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	63	GigabitEthernet2/14
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	455	GigabitEthernet5/20--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	600	GigabitEthernet6/44--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	80	GigabitEthernet2/31
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	336	GigabitEthernet2/16--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	457	GigabitEthernet5/21--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	179	GigabitEthernet6/26
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	383	GigabitEthernet2/40--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	297	GigabitEthernet1/45--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	277	GigabitEthernet1/35--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	92	GigabitEthernet2/43
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	10	GigabitEthernet1/9
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	550	GigabitEthernet6/19--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	505	GigabitEthernet5/45--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	419	GigabitEthernet5/2--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	133	GigabitEthernet5/28
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	290	GigabitEthernet1/41--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	592	GigabitEthernet6/40--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	149	GigabitEthernet5/44
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	123	GigabitEthernet5/18
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	304	GigabitEthernet1/48--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	547	GigabitEthernet6/18--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	210	GigabitEthernet1/1--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	406	TenGigabitEthernet3/3--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	258	GigabitEthernet1/25--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	396	GigabitEthernet2/46--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	482	GigabitEthernet5/33--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	173	GigabitEthernet6/20
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	530	GigabitEthernet6/9--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	56	GigabitEthernet2/7
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	499	GigabitEthernet5/42--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	66	GigabitEthernet2/17
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	19	GigabitEthernet1/18
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	54	GigabitEthernet2/5
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	365	GigabitEthernet2/31--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	306	GigabitEthernet2/1--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	70	GigabitEthernet2/21
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	470	GigabitEthernet5/27--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	166	GigabitEthernet6/13
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	88	GigabitEthernet2/39
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	141	GigabitEthernet5/36
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	30	GigabitEthernet1/29
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	570	GigabitEthernet6/29--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	403	TenGigabitEthernet3/2--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	252	GigabitEthernet1/22--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	466	GigabitEthernet5/25--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	156	GigabitEthernet6/3
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	134	GigabitEthernet5/29
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	75	GigabitEthernet2/26
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	283	GigabitEthernet1/38--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	59	GigabitEthernet2/10
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	421	GigabitEthernet5/3--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	450	GigabitEthernet5/17--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	271	GigabitEthernet1/32--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	491	GigabitEthernet5/38--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	219	GigabitEthernet1/6--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	318	GigabitEthernet2/7--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	13	GigabitEthernet1/12
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	105	TenGigabitEthernet4/4
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	473	GigabitEthernet5/29--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	185	GigabitEthernet6/32
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	3	GigabitEthernet1/2
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	597	GigabitEthernet6/43--Uncontrolled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	248	GigabitEthernet1/20--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	390	GigabitEthernet2/43--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	146	GigabitEthernet5/41
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	111	GigabitEthernet5/6
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	38	GigabitEthernet1/37
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	356	GigabitEthernet2/26--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	408	TenGigabitEthernet3/4--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	4	GigabitEthernet1/3
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	528	GigabitEthernet6/8--Controlled
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	164	GigabitEthernet6/11
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	196	GigabitEthernet6/43
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	242	GigabitEthernet1/17--Controlled
auto-medicsw.infra.tg14.gathering.org-6c:9c:ed:82:34:00	10107	GigabitEthernet0/7
auto-medicsw.infra.tg14.gathering.org-6c:9c:ed:82:34:00	10105	GigabitEthernet0/5
auto-medicsw.infra.tg14.gathering.org-6c:9c:ed:82:34:00	240	Vlan240
auto-medicsw.infra.tg14.gathering.org-6c:9c:ed:82:34:00	10501	Null0
auto-medicsw.infra.tg14.gathering.org-6c:9c:ed:82:34:00	10108	GigabitEthernet0/8
auto-medicsw.infra.tg14.gathering.org-6c:9c:ed:82:34:00	10102	GigabitEthernet0/2
auto-medicsw.infra.tg14.gathering.org-6c:9c:ed:82:34:00	20567	Loopback0
auto-medicsw.infra.tg14.gathering.org-6c:9c:ed:82:34:00	1	Vlan1
auto-medicsw.infra.tg14.gathering.org-6c:9c:ed:82:34:00	10110	GigabitEthernet0/10
auto-medicsw.infra.tg14.gathering.org-6c:9c:ed:82:34:00	10109	GigabitEthernet0/9
auto-medicsw.infra.tg14.gathering.org-6c:9c:ed:82:34:00	10103	GigabitEthernet0/3
auto-medicsw.infra.tg14.gathering.org-6c:9c:ed:82:34:00	10104	GigabitEthernet0/4
auto-medicsw.infra.tg14.gathering.org-6c:9c:ed:82:34:00	10106	GigabitEthernet0/6
auto-medicsw.infra.tg14.gathering.org-6c:9c:ed:82:34:00	10101	GigabitEthernet0/1
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	33	GigabitEthernet1/33
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	32	GigabitEthernet1/32
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	63	unrouted VLAN 423
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	21	GigabitEthernet1/21
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	71	Vlan228
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	7	GigabitEthernet1/7
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	26	GigabitEthernet1/26
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	18	GigabitEthernet1/18
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	16	GigabitEthernet1/16
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	44	GigabitEthernet1/44
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	55	FastEthernet1
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	27	GigabitEthernet1/27
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	57	unrouted VLAN 1
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	61	unrouted VLAN 1003
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	20	GigabitEthernet1/20
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	10	GigabitEthernet1/10
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	31	GigabitEthernet1/31
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	35	GigabitEthernet1/35
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	11	GigabitEthernet1/11
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	48	GigabitEthernet1/48
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	65	unrouted VLAN 623
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	29	GigabitEthernet1/29
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	50	TenGigabitEthernet1/50
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	39	GigabitEthernet1/39
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	64	unrouted VLAN 613
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	58	unrouted VLAN 1002
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	41	GigabitEthernet1/41
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	12	GigabitEthernet1/12
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	15	GigabitEthernet1/15
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	52	TenGigabitEthernet1/52
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	60	unrouted VLAN 1005
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	56	Vlan1
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	66	Tunnel0
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	45	GigabitEthernet1/45
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	19	GigabitEthernet1/19
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	62	unrouted VLAN 413
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	54	Null0
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	68	Loopback0
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	2	GigabitEthernet1/2
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	17	GigabitEthernet1/17
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	1	GigabitEthernet1/1
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	30	GigabitEthernet1/30
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	25	GigabitEthernet1/25
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	28	GigabitEthernet1/28
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	40	GigabitEthernet1/40
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	14	GigabitEthernet1/14
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	69	Port-channel10
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	59	unrouted VLAN 1004
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	49	TenGigabitEthernet1/49
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	24	GigabitEthernet1/24
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	22	GigabitEthernet1/22
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	42	GigabitEthernet1/42
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	46	GigabitEthernet1/46
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	23	GigabitEthernet1/23
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	13	GigabitEthernet1/13
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	6	GigabitEthernet1/6
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	3	GigabitEthernet1/3
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	36	GigabitEthernet1/36
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	9	GigabitEthernet1/9
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	51	TenGigabitEthernet1/51
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	47	GigabitEthernet1/47
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	8	GigabitEthernet1/8
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	38	GigabitEthernet1/38
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	4	GigabitEthernet1/4
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	34	GigabitEthernet1/34
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	37	GigabitEthernet1/37
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	43	GigabitEthernet1/43
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	5	GigabitEthernet1/5
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	33	GigabitEthernet1/33
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	32	GigabitEthernet1/32
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	21	GigabitEthernet1/21
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	7	GigabitEthernet1/7
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	26	GigabitEthernet1/26
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	18	GigabitEthernet1/18
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	16	GigabitEthernet1/16
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	44	GigabitEthernet1/44
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	55	FastEthernet1
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	27	GigabitEthernet1/27
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	57	unrouted VLAN 1
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	61	unrouted VLAN 1003
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	20	GigabitEthernet1/20
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	10	GigabitEthernet1/10
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	31	GigabitEthernet1/31
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	35	GigabitEthernet1/35
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	11	GigabitEthernet1/11
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	48	GigabitEthernet1/48
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	29	GigabitEthernet1/29
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	50	TenGigabitEthernet1/50
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	39	GigabitEthernet1/39
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	58	unrouted VLAN 1002
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	41	GigabitEthernet1/41
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	12	GigabitEthernet1/12
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	15	GigabitEthernet1/15
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	52	TenGigabitEthernet1/52
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	60	unrouted VLAN 1005
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	56	Vlan1
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	66	Tunnel0
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	45	GigabitEthernet1/45
auto-GameHQSW2-00:26:5a:e4:9e:e4	147	Port-channel21
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	19	GigabitEthernet1/19
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	54	Null0
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	67	Loopback0
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	68	unrouted VLAN 178
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	2	GigabitEthernet1/2
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	17	GigabitEthernet1/17
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	1	GigabitEthernet1/1
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	30	GigabitEthernet1/30
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	25	GigabitEthernet1/25
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	28	GigabitEthernet1/28
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	40	GigabitEthernet1/40
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	14	GigabitEthernet1/14
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	59	unrouted VLAN 1004
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	69	Port-channel16
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	49	TenGigabitEthernet1/49
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	24	GigabitEthernet1/24
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	22	GigabitEthernet1/22
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	42	GigabitEthernet1/42
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	46	GigabitEthernet1/46
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	23	GigabitEthernet1/23
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	13	GigabitEthernet1/13
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	6	GigabitEthernet1/6
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	3	GigabitEthernet1/3
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	36	GigabitEthernet1/36
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	9	GigabitEthernet1/9
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	51	TenGigabitEthernet1/51
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	47	GigabitEthernet1/47
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	8	GigabitEthernet1/8
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	38	GigabitEthernet1/38
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	4	GigabitEthernet1/4
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	34	GigabitEthernet1/34
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	37	GigabitEthernet1/37
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	43	GigabitEthernet1/43
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	5	GigabitEthernet1/5
auto-GameHQSW2-00:26:5a:e4:9e:e4	127	Vlan1
auto-GameHQSW2-00:26:5a:e4:9e:e4	32	GigabitEthernet4/20
auto-GameHQSW2-00:26:5a:e4:9e:e4	90	GigabitEthernet9/12
auto-GameHQSW2-00:26:5a:e4:9e:e4	118	GigabitEthernet9/40
auto-GameHQSW2-00:26:5a:e4:9e:e4	71	TenGigabitEthernet7/1
auto-GameHQSW2-00:26:5a:e4:9e:e4	102	GigabitEthernet9/24
auto-GameHQSW2-00:26:5a:e4:9e:e4	18	GigabitEthernet4/6
auto-GameHQSW2-00:26:5a:e4:9e:e4	125	GigabitEthernet9/47
auto-GameHQSW2-00:26:5a:e4:9e:e4	16	GigabitEthernet4/4
auto-GameHQSW2-00:26:5a:e4:9e:e4	44	GigabitEthernet4/32
auto-GameHQSW2-00:26:5a:e4:9e:e4	55	GigabitEthernet4/43
auto-GameHQSW2-00:26:5a:e4:9e:e4	84	GigabitEthernet9/6
auto-GameHQSW2-00:26:5a:e4:9e:e4	27	GigabitEthernet4/15
auto-GameHQSW2-00:26:5a:e4:9e:e4	161	unrouted VLAN 2272
auto-GameHQSW2-00:26:5a:e4:9e:e4	95	GigabitEthernet9/17
auto-GameHQSW2-00:26:5a:e4:9e:e4	57	GigabitEthernet4/45
auto-GameHQSW2-00:26:5a:e4:9e:e4	20	GigabitEthernet4/8
auto-GameHQSW2-00:26:5a:e4:9e:e4	163	Vlan3000
auto-GameHQSW2-00:26:5a:e4:9e:e4	109	GigabitEthernet9/31
auto-GameHQSW2-00:26:5a:e4:9e:e4	151	Vlan192
auto-GameHQSW2-00:26:5a:e4:9e:e4	89	GigabitEthernet9/11
auto-GameHQSW2-00:26:5a:e4:9e:e4	175	Vlan1282
auto-GameHQSW2-00:26:5a:e4:9e:e4	148	Port-channel22
auto-GameHQSW2-00:26:5a:e4:9e:e4	31	GigabitEthernet4/19
auto-GameHQSW2-00:26:5a:e4:9e:e4	35	GigabitEthernet4/23
auto-GameHQSW2-00:26:5a:e4:9e:e4	11	TenGigabitEthernet3/3
auto-GameHQSW2-00:26:5a:e4:9e:e4	78	TenGigabitEthernet8/4
auto-GameHQSW2-00:26:5a:e4:9e:e4	93	GigabitEthernet9/15
auto-GameHQSW2-00:26:5a:e4:9e:e4	106	GigabitEthernet9/28
auto-GameHQSW2-00:26:5a:e4:9e:e4	157	unrouted VLAN 2500
auto-GameHQSW2-00:26:5a:e4:9e:e4	65	TenGigabitEthernet5/5
auto-GameHQSW2-00:26:5a:e4:9e:e4	29	GigabitEthernet4/17
auto-GameHQSW2-00:26:5a:e4:9e:e4	138	Port-channel1
auto-GameHQSW2-00:26:5a:e4:9e:e4	114	GigabitEthernet9/36
auto-GameHQSW2-00:26:5a:e4:9e:e4	58	GigabitEthernet4/46
auto-GameHQSW2-00:26:5a:e4:9e:e4	153	Tunnel4
auto-GameHQSW2-00:26:5a:e4:9e:e4	15	GigabitEthernet4/3
auto-GameHQSW2-00:26:5a:e4:9e:e4	137	Loopback0
auto-GameHQSW2-00:26:5a:e4:9e:e4	81	GigabitEthernet9/3
auto-GameHQSW2-00:26:5a:e4:9e:e4	60	GigabitEthernet4/48
auto-GameHQSW2-00:26:5a:e4:9e:e4	101	GigabitEthernet9/23
auto-GameHQSW2-00:26:5a:e4:9e:e4	73	TenGigabitEthernet7/3
auto-GameHQSW2-00:26:5a:e4:9e:e4	86	GigabitEthernet9/8
auto-GameHQSW2-00:26:5a:e4:9e:e4	76	TenGigabitEthernet8/2
auto-GameHQSW2-00:26:5a:e4:9e:e4	62	GigabitEthernet5/2
auto-GameHQSW2-00:26:5a:e4:9e:e4	67	GigabitEthernet6/2
auto-GameHQSW2-00:26:5a:e4:9e:e4	139	Port-channel11
auto-GameHQSW2-00:26:5a:e4:9e:e4	135	unrouted VLAN 1005
auto-GameHQSW2-00:26:5a:e4:9e:e4	14	GigabitEthernet4/2
auto-GameHQSW2-00:26:5a:e4:9e:e4	112	GigabitEthernet9/34
auto-GameHQSW2-00:26:5a:e4:9e:e4	69	TenGigabitEthernet6/4
auto-GameHQSW2-00:26:5a:e4:9e:e4	172	Port-channel31
auto-GameHQSW2-00:26:5a:e4:9e:e4	145	Tunnel2
auto-GameHQSW2-00:26:5a:e4:9e:e4	49	GigabitEthernet4/37
auto-GameHQSW2-00:26:5a:e4:9e:e4	178	unrouted VLAN 1284
auto-GameHQSW2-00:26:5a:e4:9e:e4	24	GigabitEthernet4/12
auto-GameHQSW2-00:26:5a:e4:9e:e4	140	Port-channel12
auto-GameHQSW2-00:26:5a:e4:9e:e4	124	GigabitEthernet9/46
auto-GameHQSW2-00:26:5a:e4:9e:e4	104	GigabitEthernet9/26
auto-GameHQSW2-00:26:5a:e4:9e:e4	131	Control Plane Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	181	unrouted VLAN 2010
auto-GameHQSW2-00:26:5a:e4:9e:e4	121	GigabitEthernet9/43
auto-GameHQSW2-00:26:5a:e4:9e:e4	79	GigabitEthernet9/1
auto-GameHQSW2-00:26:5a:e4:9e:e4	154	Port-channel3
auto-GameHQSW2-00:26:5a:e4:9e:e4	23	GigabitEthernet4/11
auto-GameHQSW2-00:26:5a:e4:9e:e4	96	GigabitEthernet9/18
auto-GameHQSW2-00:26:5a:e4:9e:e4	126	GigabitEthernet9/48
auto-GameHQSW2-00:26:5a:e4:9e:e4	159	unrouted VLAN 2271
auto-GameHQSW2-00:26:5a:e4:9e:e4	160	Vlan2271
auto-GameHQSW2-00:26:5a:e4:9e:e4	176	unrouted VLAN 1283
auto-GameHQSW2-00:26:5a:e4:9e:e4	47	GigabitEthernet4/35
auto-GameHQSW2-00:26:5a:e4:9e:e4	8	TenGigabitEthernet2/4
auto-GameHQSW2-00:26:5a:e4:9e:e4	98	GigabitEthernet9/20
auto-GameHQSW2-00:26:5a:e4:9e:e4	37	GigabitEthernet4/25
auto-GameHQSW2-00:26:5a:e4:9e:e4	117	GigabitEthernet9/39
auto-GameHQSW2-00:26:5a:e4:9e:e4	43	GigabitEthernet4/31
auto-GameHQSW2-00:26:5a:e4:9e:e4	5	TenGigabitEthernet2/1
auto-GameHQSW2-00:26:5a:e4:9e:e4	170	unrouted VLAN 128
auto-GameHQSW2-00:26:5a:e4:9e:e4	33	GigabitEthernet4/21
auto-GameHQSW2-00:26:5a:e4:9e:e4	21	GigabitEthernet4/9
auto-GameHQSW2-00:26:5a:e4:9e:e4	63	GigabitEthernet5/3
auto-GameHQSW2-00:26:5a:e4:9e:e4	7	TenGigabitEthernet2/3
auto-GameHQSW2-00:26:5a:e4:9e:e4	26	GigabitEthernet4/14
auto-GameHQSW2-00:26:5a:e4:9e:e4	80	GigabitEthernet9/2
auto-GameHQSW2-00:26:5a:e4:9e:e4	119	GigabitEthernet9/41
auto-GameHQSW2-00:26:5a:e4:9e:e4	180	Vlan2010
auto-GameHQSW2-00:26:5a:e4:9e:e4	99	GigabitEthernet9/21
auto-GameHQSW2-00:26:5a:e4:9e:e4	179	Vlan1284
auto-GameHQSW2-00:26:5a:e4:9e:e4	162	Vlan2272
auto-GameHQSW2-00:26:5a:e4:9e:e4	72	TenGigabitEthernet7/2
auto-GameHQSW2-00:26:5a:e4:9e:e4	74	TenGigabitEthernet7/4
auto-GameHQSW2-00:26:5a:e4:9e:e4	61	GigabitEthernet5/1
auto-GameHQSW2-00:26:5a:e4:9e:e4	108	GigabitEthernet9/30
auto-GameHQSW2-00:26:5a:e4:9e:e4	115	GigabitEthernet9/37
auto-GameHQSW2-00:26:5a:e4:9e:e4	92	GigabitEthernet9/14
auto-GameHQSW2-00:26:5a:e4:9e:e4	103	GigabitEthernet9/25
auto-GameHQSW2-00:26:5a:e4:9e:e4	10	TenGigabitEthernet3/2
auto-GameHQSW2-00:26:5a:e4:9e:e4	113	GigabitEthernet9/35
auto-GameHQSW2-00:26:5a:e4:9e:e4	152	Tunnel3
auto-GameHQSW2-00:26:5a:e4:9e:e4	142	Tunnel0
auto-GameHQSW2-00:26:5a:e4:9e:e4	91	GigabitEthernet9/13
auto-GameHQSW2-00:26:5a:e4:9e:e4	167	Port-channel23
auto-GameHQSW2-00:26:5a:e4:9e:e4	48	GigabitEthernet4/36
auto-GameHQSW2-00:26:5a:e4:9e:e4	107	GigabitEthernet9/29
auto-GameHQSW2-00:26:5a:e4:9e:e4	87	GigabitEthernet9/9
auto-GameHQSW2-00:26:5a:e4:9e:e4	174	unrouted VLAN 1282
auto-GameHQSW2-00:26:5a:e4:9e:e4	77	TenGigabitEthernet8/3
auto-GameHQSW2-00:26:5a:e4:9e:e4	133	unrouted VLAN 1002
auto-GameHQSW2-00:26:5a:e4:9e:e4	149	Vlan253
auto-GameHQSW2-00:26:5a:e4:9e:e4	123	GigabitEthernet9/45
auto-GameHQSW2-00:26:5a:e4:9e:e4	50	GigabitEthernet4/38
auto-GameHQSW2-00:26:5a:e4:9e:e4	39	GigabitEthernet4/27
auto-GameHQSW2-00:26:5a:e4:9e:e4	64	TenGigabitEthernet5/4
auto-GameHQSW2-00:26:5a:e4:9e:e4	97	GigabitEthernet9/19
auto-GameHQSW2-00:26:5a:e4:9e:e4	12	TenGigabitEthernet3/4
auto-GameHQSW2-00:26:5a:e4:9e:e4	41	GigabitEthernet4/29
auto-GameHQSW2-00:26:5a:e4:9e:e4	52	GigabitEthernet4/40
auto-GameHQSW2-00:26:5a:e4:9e:e4	173	Port-channel32
auto-GameHQSW2-00:26:5a:e4:9e:e4	56	GigabitEthernet4/44
auto-GameHQSW2-00:26:5a:e4:9e:e4	45	GigabitEthernet4/33
auto-GameHQSW2-00:26:5a:e4:9e:e4	66	GigabitEthernet6/1
auto-GameHQSW2-00:26:5a:e4:9e:e4	19	GigabitEthernet4/7
auto-GameHQSW2-00:26:5a:e4:9e:e4	54	GigabitEthernet4/42
auto-GameHQSW2-00:26:5a:e4:9e:e4	70	TenGigabitEthernet6/5
auto-GameHQSW2-00:26:5a:e4:9e:e4	68	GigabitEthernet6/3
auto-GameHQSW2-00:26:5a:e4:9e:e4	1	TenGigabitEthernet1/1
auto-GameHQSW2-00:26:5a:e4:9e:e4	136	unrouted VLAN 1003
auto-GameHQSW2-00:26:5a:e4:9e:e4	88	GigabitEthernet9/10
auto-GameHQSW2-00:26:5a:e4:9e:e4	116	GigabitEthernet9/38
auto-GameHQSW2-00:26:5a:e4:9e:e4	144	unrouted VLAN 252
auto-GameHQSW2-00:26:5a:e4:9e:e4	141	Vlan252
auto-GameHQSW2-00:26:5a:e4:9e:e4	30	GigabitEthernet4/18
auto-GameHQSW2-00:26:5a:e4:9e:e4	100	GigabitEthernet9/22
auto-GameHQSW2-00:26:5a:e4:9e:e4	25	GigabitEthernet4/13
auto-GameHQSW2-00:26:5a:e4:9e:e4	128	EOBC0/2
auto-GameHQSW2-00:26:5a:e4:9e:e4	28	GigabitEthernet4/16
auto-GameHQSW2-00:26:5a:e4:9e:e4	120	GigabitEthernet9/42
auto-GameHQSW2-00:26:5a:e4:9e:e4	156	Port-channel1-mpls layer
auto-GameHQSW2-00:26:5a:e4:9e:e4	134	unrouted VLAN 1004
auto-GameHQSW2-00:26:5a:e4:9e:e4	40	GigabitEthernet4/28
auto-GameHQSW2-00:26:5a:e4:9e:e4	75	TenGigabitEthernet8/1
auto-GameHQSW2-00:26:5a:e4:9e:e4	83	GigabitEthernet9/5
auto-GameHQSW2-00:26:5a:e4:9e:e4	59	GigabitEthernet4/47
auto-GameHQSW2-00:26:5a:e4:9e:e4	177	Vlan1283
auto-GameHQSW2-00:26:5a:e4:9e:e4	150	unrouted VLAN 192
auto-GameHQSW2-00:26:5a:e4:9e:e4	155	Port-channel13
auto-GameHQSW2-00:26:5a:e4:9e:e4	130	SPAN RP Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	53	GigabitEthernet4/41
auto-GameHQSW2-00:26:5a:e4:9e:e4	122	GigabitEthernet9/44
auto-GameHQSW2-00:26:5a:e4:9e:e4	143	Tunnel1
auto-GameHQSW2-00:26:5a:e4:9e:e4	158	Vlan2500
auto-GameHQSW2-00:26:5a:e4:9e:e4	42	GigabitEthernet4/30
auto-GameHQSW2-00:26:5a:e4:9e:e4	22	GigabitEthernet4/10
auto-GameHQSW2-00:26:5a:e4:9e:e4	46	GigabitEthernet4/34
auto-GameHQSW2-00:26:5a:e4:9e:e4	13	GigabitEthernet4/1
auto-GameHQSW2-00:26:5a:e4:9e:e4	105	GigabitEthernet9/27
auto-GameHQSW2-00:26:5a:e4:9e:e4	6	TenGigabitEthernet2/2
auto-GameHQSW2-00:26:5a:e4:9e:e4	85	GigabitEthernet9/7
auto-GameHQSW2-00:26:5a:e4:9e:e4	36	GigabitEthernet4/24
auto-GameHQSW2-00:26:5a:e4:9e:e4	3	TenGigabitEthernet1/3
auto-GameHQSW2-00:26:5a:e4:9e:e4	94	GigabitEthernet9/16
auto-GameHQSW2-00:26:5a:e4:9e:e4	146	unrouted VLAN 253
auto-GameHQSW2-00:26:5a:e4:9e:e4	51	GigabitEthernet4/39
auto-GameHQSW2-00:26:5a:e4:9e:e4	9	TenGigabitEthernet3/1
auto-GameHQSW2-00:26:5a:e4:9e:e4	111	GigabitEthernet9/33
auto-GameHQSW2-00:26:5a:e4:9e:e4	38	GigabitEthernet4/26
auto-GameHQSW2-00:26:5a:e4:9e:e4	4	TenGigabitEthernet1/4
auto-GameHQSW2-00:26:5a:e4:9e:e4	34	GigabitEthernet4/22
auto-GameHQSW2-00:26:5a:e4:9e:e4	169	Vlan128
auto-GameHQSW2-00:26:5a:e4:9e:e4	164	unrouted VLAN 3000
auto-GameHQSW2-00:26:5a:e4:9e:e4	132	unrouted VLAN 1
auto-GameHQSW2-00:26:5a:e4:9e:e4	171	Port-channel30
auto-GameHQSW1-00:26:5a:e9:4b:21	127	unrouted VLAN 3000
auto-GameHQSW1-00:26:5a:e9:4b:21	33	GigabitEthernet2/29
auto-GameHQSW1-00:26:5a:e9:4b:21	32	GigabitEthernet2/28
auto-GameHQSW1-00:26:5a:e9:4b:21	63	GigabitEthernet5/3
auto-GameHQSW1-00:26:5a:e9:4b:21	21	GigabitEthernet2/17
auto-GameHQSW1-00:26:5a:e9:4b:21	118	Vlan254
auto-GameHQSW1-00:26:5a:e9:4b:21	71	TenGigabitEthernet7/1
auto-GameHQSW1-00:26:5a:e9:4b:21	7	GigabitEthernet2/3
auto-GameHQSW1-00:26:5a:e9:4b:21	80	EOBC0/2
auto-GameHQSW1-00:26:5a:e9:4b:21	26	GigabitEthernet2/22
auto-GameHQSW1-00:26:5a:e9:4b:21	119	Loopback0
auto-GameHQSW1-00:26:5a:e9:4b:21	18	GigabitEthernet2/14
auto-GameHQSW1-00:26:5a:e9:4b:21	72	TenGigabitEthernet7/2
auto-GameHQSW1-00:26:5a:e9:4b:21	125	Port-channel2-mpls layer
auto-GameHQSW1-00:26:5a:e9:4b:21	16	GigabitEthernet2/12
auto-GameHQSW1-00:26:5a:e9:4b:21	44	GigabitEthernet2/40
auto-GameHQSW1-00:26:5a:e9:4b:21	55	TenGigabitEthernet3/3
auto-GameHQSW1-00:26:5a:e9:4b:21	84	unrouted VLAN 1
auto-GameHQSW1-00:26:5a:e9:4b:21	74	TenGigabitEthernet7/4
auto-GameHQSW1-00:26:5a:e9:4b:21	27	GigabitEthernet2/23
auto-GameHQSW1-00:26:5a:e9:4b:21	57	TenGigabitEthernet4/1
auto-GameHQSW1-00:26:5a:e9:4b:21	61	GigabitEthernet5/1
auto-GameHQSW1-00:26:5a:e9:4b:21	115	Port-channel1
auto-GameHQSW1-00:26:5a:e9:4b:21	20	GigabitEthernet2/16
auto-GameHQSW1-00:26:5a:e9:4b:21	10	GigabitEthernet2/6
auto-GameHQSW1-00:26:5a:e9:4b:21	31	GigabitEthernet2/27
auto-GameHQSW1-00:26:5a:e9:4b:21	35	GigabitEthernet2/31
auto-GameHQSW1-00:26:5a:e9:4b:21	11	GigabitEthernet2/7
auto-GameHQSW1-00:26:5a:e9:4b:21	78	TenGigabitEthernet8/4
auto-GameHQSW1-00:26:5a:e9:4b:21	48	GigabitEthernet2/44
auto-GameHQSW1-00:26:5a:e9:4b:21	87	unrouted VLAN 1005
auto-GameHQSW1-00:26:5a:e9:4b:21	77	TenGigabitEthernet8/3
auto-GameHQSW1-00:26:5a:e9:4b:21	65	TenGigabitEthernet5/5
auto-GameHQSW1-00:26:5a:e9:4b:21	29	GigabitEthernet2/25
auto-GameHQSW1-00:26:5a:e9:4b:21	50	GigabitEthernet2/46
auto-GameHQSW1-00:26:5a:e9:4b:21	39	GigabitEthernet2/35
auto-GameHQSW1-00:26:5a:e9:4b:21	64	TenGigabitEthernet5/4
auto-GameHQSW1-00:26:5a:e9:4b:21	58	TenGigabitEthernet4/2
auto-GameHQSW1-00:26:5a:e9:4b:21	41	GigabitEthernet2/37
auto-GameHQSW1-00:26:5a:e9:4b:21	12	GigabitEthernet2/8
auto-GameHQSW1-00:26:5a:e9:4b:21	15	GigabitEthernet2/11
auto-GameHQSW1-00:26:5a:e9:4b:21	81	Null0
auto-GameHQSW1-00:26:5a:e9:4b:21	52	GigabitEthernet2/48
auto-GameHQSW1-00:26:5a:e9:4b:21	60	TenGigabitEthernet4/4
auto-GameHQSW1-00:26:5a:e9:4b:21	56	TenGigabitEthernet3/4
auto-GameHQSW1-00:26:5a:e9:4b:21	73	TenGigabitEthernet7/3
auto-GameHQSW1-00:26:5a:e9:4b:21	66	GigabitEthernet6/1
auto-GameHQSW1-00:26:5a:e9:4b:21	45	GigabitEthernet2/41
auto-GameHQSW1-00:26:5a:e9:4b:21	86	unrouted VLAN 1004
auto-GameHQSW1-00:26:5a:e9:4b:21	76	TenGigabitEthernet8/2
auto-GameHQSW1-00:26:5a:e9:4b:21	19	GigabitEthernet2/15
auto-GameHQSW1-00:26:5a:e9:4b:21	62	GigabitEthernet5/2
auto-GameHQSW1-00:26:5a:e9:4b:21	54	TenGigabitEthernet3/2
auto-GameHQSW1-00:26:5a:e9:4b:21	67	GigabitEthernet6/2
auto-GameHQSW1-00:26:5a:e9:4b:21	70	TenGigabitEthernet6/5
auto-GameHQSW1-00:26:5a:e9:4b:21	68	GigabitEthernet6/3
auto-GameHQSW1-00:26:5a:e9:4b:21	2	TenGigabitEthernet1/2
auto-GameHQSW1-00:26:5a:e9:4b:21	17	GigabitEthernet2/13
auto-GameHQSW1-00:26:5a:e9:4b:21	1	TenGigabitEthernet1/1
auto-GameHQSW1-00:26:5a:e9:4b:21	88	unrouted VLAN 1003
auto-GameHQSW1-00:26:5a:e9:4b:21	30	GigabitEthernet2/26
auto-GameHQSW1-00:26:5a:e9:4b:21	82	SPAN RP Interface
auto-GameHQSW1-00:26:5a:e9:4b:21	25	GigabitEthernet2/21
auto-GameHQSW1-00:26:5a:e9:4b:21	120	Tunnel0
auto-GameHQSW1-00:26:5a:e9:4b:21	28	GigabitEthernet2/24
auto-GameHQSW1-00:26:5a:e9:4b:21	134	unrouted VLAN 240
auto-GameHQSW1-00:26:5a:e9:4b:21	83	Control Plane Interface
auto-GameHQSW1-00:26:5a:e9:4b:21	75	TenGigabitEthernet8/1
auto-GameHQSW1-00:26:5a:e9:4b:21	40	GigabitEthernet2/36
auto-GameHQSW1-00:26:5a:e9:4b:21	135	Vlan240
auto-GameHQSW1-00:26:5a:e9:4b:21	14	GigabitEthernet2/10
auto-GameHQSW1-00:26:5a:e9:4b:21	69	TenGigabitEthernet6/4
auto-GameHQSW1-00:26:5a:e9:4b:21	59	TenGigabitEthernet4/3
auto-GameHQSW1-00:26:5a:e9:4b:21	49	GigabitEthernet2/45
auto-GameHQSW1-00:26:5a:e9:4b:21	24	GigabitEthernet2/20
auto-GameHQSW1-00:26:5a:e9:4b:21	124	Tunnel2
auto-GameHQSW1-00:26:5a:e9:4b:21	131	Port-channel99
auto-GameHQSW1-00:26:5a:e9:4b:21	130	Port-channel20
auto-GameHQSW1-00:26:5a:e9:4b:21	53	TenGigabitEthernet3/1
auto-GameHQSW1-00:26:5a:e9:4b:21	122	Port-channel2
auto-GameHQSW1-00:26:5a:e9:4b:21	121	Tunnel1
auto-GameHQSW1-00:26:5a:e9:4b:21	79	Vlan1
auto-GameHQSW1-00:26:5a:e9:4b:21	22	GigabitEthernet2/18
auto-GameHQSW1-00:26:5a:e9:4b:21	42	GigabitEthernet2/38
auto-GameHQSW1-00:26:5a:e9:4b:21	46	GigabitEthernet2/42
auto-GameHQSW1-00:26:5a:e9:4b:21	23	GigabitEthernet2/19
auto-GameHQSW1-00:26:5a:e9:4b:21	13	GigabitEthernet2/9
auto-GameHQSW1-00:26:5a:e9:4b:21	126	Vlan3000
auto-GameHQSW1-00:26:5a:e9:4b:21	6	GigabitEthernet2/2
auto-GameHQSW1-00:26:5a:e9:4b:21	85	unrouted VLAN 1002
auto-GameHQSW1-00:26:5a:e9:4b:21	3	TenGigabitEthernet1/3
auto-GameHQSW1-00:26:5a:e9:4b:21	36	GigabitEthernet2/32
auto-GameHQSW1-00:26:5a:e9:4b:21	9	GigabitEthernet2/5
auto-GameHQSW1-00:26:5a:e9:4b:21	51	GigabitEthernet2/47
auto-GameHQSW1-00:26:5a:e9:4b:21	47	GigabitEthernet2/43
auto-GameHQSW1-00:26:5a:e9:4b:21	8	GigabitEthernet2/4
auto-GameHQSW1-00:26:5a:e9:4b:21	38	GigabitEthernet2/34
auto-GameHQSW1-00:26:5a:e9:4b:21	4	TenGigabitEthernet1/4
auto-GameHQSW1-00:26:5a:e9:4b:21	34	GigabitEthernet2/30
auto-GameHQSW1-00:26:5a:e9:4b:21	37	GigabitEthernet2/33
auto-GameHQSW1-00:26:5a:e9:4b:21	117	unrouted VLAN 254
auto-GameHQSW1-00:26:5a:e9:4b:21	43	GigabitEthernet2/39
auto-GameHQSW1-00:26:5a:e9:4b:21	5	GigabitEthernet2/1
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10107	GigabitEthernet1/0/7
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10142	GigabitEthernet1/0/42
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10141	GigabitEthernet1/0/41
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10132	GigabitEthernet1/0/32
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10136	GigabitEthernet1/0/36
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10120	GigabitEthernet1/0/20
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10115	GigabitEthernet1/0/15
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10108	GigabitEthernet1/0/8
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10102	GigabitEthernet1/0/2
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10123	GigabitEthernet1/0/23
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	14001	Null0
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10122	GigabitEthernet1/0/22
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	1	Vlan1
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10144	GigabitEthernet1/0/44
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10121	GigabitEthernet1/0/21
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10134	GigabitEthernet1/0/34
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10135	GigabitEthernet1/0/35
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10148	GigabitEthernet1/0/48
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10129	GigabitEthernet1/0/29
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	5180	StackSub-St1-1
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10137	GigabitEthernet1/0/37
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10116	GigabitEthernet1/0/16
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10138	GigabitEthernet1/0/38
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10103	GigabitEthernet1/0/3
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10143	GigabitEthernet1/0/43
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10130	GigabitEthernet1/0/30
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10104	GigabitEthernet1/0/4
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10106	GigabitEthernet1/0/6
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10126	GigabitEthernet1/0/26
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10125	GigabitEthernet1/0/25
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10113	GigabitEthernet1/0/13
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10105	GigabitEthernet1/0/5
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10117	GigabitEthernet1/0/17
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10201	TenGigabitEthernet1/0/1
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10112	GigabitEthernet1/0/12
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	5181	StackSub-St1-2
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10147	GigabitEthernet1/0/47
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10139	GigabitEthernet1/0/39
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	5179	StackPort1
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10110	GigabitEthernet1/0/10
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	14002	FastEthernet0
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10150	GigabitEthernet1/0/50
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10149	GigabitEthernet1/0/49
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	24067	Loopback0
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10133	GigabitEthernet1/0/33
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10118	GigabitEthernet1/0/18
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10131	GigabitEthernet1/0/31
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10127	GigabitEthernet1/0/27
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10202	TenGigabitEthernet1/0/2
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10124	GigabitEthernet1/0/24
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	5001	Port-channel1
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10111	GigabitEthernet1/0/11
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10145	GigabitEthernet1/0/45
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10128	GigabitEthernet1/0/28
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10109	GigabitEthernet1/0/9
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10119	GigabitEthernet1/0/19
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10146	GigabitEthernet1/0/46
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10140	GigabitEthernet1/0/40
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10114	GigabitEthernet1/0/14
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10101	GigabitEthernet1/0/1
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	242	Vlan242
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	33	GigabitEthernet1/33
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	32	GigabitEthernet1/32
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	63	Tunnel0
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	21	GigabitEthernet1/21
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	7	GigabitEthernet1/7
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	26	GigabitEthernet1/26
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	18	GigabitEthernet1/18
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	16	GigabitEthernet1/16
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	44	GigabitEthernet1/44
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	55	FastEthernet1
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	27	GigabitEthernet1/27
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	57	unrouted VLAN 1
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	61	unrouted VLAN 1003
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	20	GigabitEthernet1/20
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	10	GigabitEthernet1/10
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	31	GigabitEthernet1/31
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	35	GigabitEthernet1/35
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	11	GigabitEthernet1/11
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	48	GigabitEthernet1/48
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	65	Port-channel1
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	29	GigabitEthernet1/29
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	50	TenGigabitEthernet1/50
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	39	GigabitEthernet1/39
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	64	Loopback0
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	58	unrouted VLAN 1002
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	41	GigabitEthernet1/41
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	12	GigabitEthernet1/12
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	15	GigabitEthernet1/15
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	52	TenGigabitEthernet1/52
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	60	unrouted VLAN 1005
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	56	Vlan1
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	45	GigabitEthernet1/45
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	19	GigabitEthernet1/19
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	62	unrouted VLAN 253
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	54	Null0
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	2	GigabitEthernet1/2
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	17	GigabitEthernet1/17
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	1	GigabitEthernet1/1
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	30	GigabitEthernet1/30
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	25	GigabitEthernet1/25
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	28	GigabitEthernet1/28
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	40	GigabitEthernet1/40
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	14	GigabitEthernet1/14
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	59	unrouted VLAN 1004
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	49	TenGigabitEthernet1/49
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	24	GigabitEthernet1/24
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	22	GigabitEthernet1/22
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	42	GigabitEthernet1/42
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	46	GigabitEthernet1/46
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	23	GigabitEthernet1/23
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	13	GigabitEthernet1/13
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	6	GigabitEthernet1/6
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	3	GigabitEthernet1/3
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	36	GigabitEthernet1/36
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	9	GigabitEthernet1/9
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	51	TenGigabitEthernet1/51
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	47	GigabitEthernet1/47
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	8	GigabitEthernet1/8
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	38	GigabitEthernet1/38
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	4	GigabitEthernet1/4
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	34	GigabitEthernet1/34
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	37	GigabitEthernet1/37
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	43	GigabitEthernet1/43
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	5	GigabitEthernet1/5
auto-GameHQSw1-00:26:5a:e9:4b:21	33	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	32	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	21	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	7	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	26	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	331	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	324	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	18	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	329	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	16	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	44	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	27	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	316	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	313	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	20	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	10	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	31	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	35	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	11	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	330	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	48	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	325	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	29	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	100000	vlan
auto-GameHQSw1-00:26:5a:e9:4b:21	304	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	39	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	41	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	12	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	15	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	312	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	302	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	321	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	45	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	19	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	311	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	306	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	309	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	322	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	2	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	17	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	327	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	315	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	1	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	320	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	30	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	25	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	28	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	40	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	310	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	303	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	323	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	305	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	9000	Internal Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	14	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	308	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	319	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	24	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	328	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	307	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	314	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	22	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	42	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	46	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	318	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	23	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	13	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	301	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	6	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	3	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	36	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	332	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	326	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	9	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	47	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	8	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	38	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	4	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	317	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	34	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	37	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	43	Ethernet Interface
auto-GameHQSw1-00:26:5a:e9:4b:21	5	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	33	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	32	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	21	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	7	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	26	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	17	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	2	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	1	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	18	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	30	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	16	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	27	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	25	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	28	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	20	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	14	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	24	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	10	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	31	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	35	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	11	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	22	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	13	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	23	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	29	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	6	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	39	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	36	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	3	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	9	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	12	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	15	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	38	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	8	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	4	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	34	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	37	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	19	Ethernet Interface
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	5	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	33	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	32	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	21	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	7	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	26	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	17	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	2	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	1	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	18	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	30	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	16	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	27	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	25	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	28	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	20	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	14	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	24	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	10	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	31	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	35	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	11	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	22	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	13	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	23	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	29	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	6	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	39	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	36	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	3	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	9	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	12	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	15	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	38	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	8	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	4	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	34	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	37	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	19	Ethernet Interface
auto-resepsjonssw-00:26:5a:e4:ac:24	5	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	33	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	32	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	21	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	7	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	26	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	17	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	2	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	1	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	18	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	30	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	16	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	27	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	25	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	28	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	20	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	14	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	24	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	10	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	31	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	35	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	11	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	22	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	13	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	23	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	29	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	6	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	39	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	36	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	3	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	9	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	12	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	15	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	38	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	8	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	4	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	34	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	37	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	19	Ethernet Interface
auto-GameHQSW2-00:26:5a:e4:9e:e4	5	Ethernet Interface
auto-sponsorgw.infra.tg14.gathering.org-	33	GigabitEthernet1/33
auto-sponsorgw.infra.tg14.gathering.org-	32	GigabitEthernet1/32
auto-sponsorgw.infra.tg14.gathering.org-	63	Tunnel0
auto-sponsorgw.infra.tg14.gathering.org-	21	GigabitEthernet1/21
auto-sponsorgw.infra.tg14.gathering.org-	7	GigabitEthernet1/7
auto-sponsorgw.infra.tg14.gathering.org-	26	GigabitEthernet1/26
auto-sponsorgw.infra.tg14.gathering.org-	18	GigabitEthernet1/18
auto-sponsorgw.infra.tg14.gathering.org-	16	GigabitEthernet1/16
auto-sponsorgw.infra.tg14.gathering.org-	44	GigabitEthernet1/44
auto-sponsorgw.infra.tg14.gathering.org-	55	FastEthernet1
auto-sponsorgw.infra.tg14.gathering.org-	27	GigabitEthernet1/27
auto-sponsorgw.infra.tg14.gathering.org-	57	unrouted VLAN 1
auto-sponsorgw.infra.tg14.gathering.org-	61	unrouted VLAN 1003
auto-sponsorgw.infra.tg14.gathering.org-	20	GigabitEthernet1/20
auto-sponsorgw.infra.tg14.gathering.org-	10	GigabitEthernet1/10
auto-sponsorgw.infra.tg14.gathering.org-	31	GigabitEthernet1/31
auto-sponsorgw.infra.tg14.gathering.org-	35	GigabitEthernet1/35
auto-sponsorgw.infra.tg14.gathering.org-	11	GigabitEthernet1/11
auto-sponsorgw.infra.tg14.gathering.org-	48	GigabitEthernet1/48
auto-sponsorgw.infra.tg14.gathering.org-	65	Port-channel1
auto-sponsorgw.infra.tg14.gathering.org-	29	GigabitEthernet1/29
auto-sponsorgw.infra.tg14.gathering.org-	50	TenGigabitEthernet1/50
auto-sponsorgw.infra.tg14.gathering.org-	39	GigabitEthernet1/39
auto-sponsorgw.infra.tg14.gathering.org-	64	Loopback0
auto-sponsorgw.infra.tg14.gathering.org-	58	unrouted VLAN 1002
auto-sponsorgw.infra.tg14.gathering.org-	41	GigabitEthernet1/41
auto-sponsorgw.infra.tg14.gathering.org-	12	GigabitEthernet1/12
auto-sponsorgw.infra.tg14.gathering.org-	15	GigabitEthernet1/15
auto-sponsorgw.infra.tg14.gathering.org-	52	TenGigabitEthernet1/52
auto-sponsorgw.infra.tg14.gathering.org-	60	unrouted VLAN 1005
auto-sponsorgw.infra.tg14.gathering.org-	56	Vlan1
auto-sponsorgw.infra.tg14.gathering.org-	66	unrouted VLAN 233
auto-sponsorgw.infra.tg14.gathering.org-	45	GigabitEthernet1/45
auto-sponsorgw.infra.tg14.gathering.org-	19	GigabitEthernet1/19
auto-sponsorgw.infra.tg14.gathering.org-	62	unrouted VLAN 146
auto-sponsorgw.infra.tg14.gathering.org-	54	Null0
auto-sponsorgw.infra.tg14.gathering.org-	67	Vlan233
auto-sponsorgw.infra.tg14.gathering.org-	70	unrouted VLAN 225
auto-sponsorgw.infra.tg14.gathering.org-	68	Tunnel1
auto-sponsorgw.infra.tg14.gathering.org-	2	GigabitEthernet1/2
auto-sponsorgw.infra.tg14.gathering.org-	17	GigabitEthernet1/17
auto-sponsorgw.infra.tg14.gathering.org-	1	GigabitEthernet1/1
auto-sponsorgw.infra.tg14.gathering.org-	30	GigabitEthernet1/30
auto-sponsorgw.infra.tg14.gathering.org-	25	GigabitEthernet1/25
auto-sponsorgw.infra.tg14.gathering.org-	28	GigabitEthernet1/28
auto-sponsorgw.infra.tg14.gathering.org-	40	GigabitEthernet1/40
auto-sponsorgw.infra.tg14.gathering.org-	14	GigabitEthernet1/14
auto-sponsorgw.infra.tg14.gathering.org-	69	Vlan225
auto-sponsorgw.infra.tg14.gathering.org-	59	unrouted VLAN 1004
auto-sponsorgw.infra.tg14.gathering.org-	49	TenGigabitEthernet1/49
auto-sponsorgw.infra.tg14.gathering.org-	24	GigabitEthernet1/24
auto-sponsorgw.infra.tg14.gathering.org-	22	GigabitEthernet1/22
auto-sponsorgw.infra.tg14.gathering.org-	42	GigabitEthernet1/42
auto-sponsorgw.infra.tg14.gathering.org-	46	GigabitEthernet1/46
auto-sponsorgw.infra.tg14.gathering.org-	23	GigabitEthernet1/23
auto-sponsorgw.infra.tg14.gathering.org-	13	GigabitEthernet1/13
auto-sponsorgw.infra.tg14.gathering.org-	6	GigabitEthernet1/6
auto-sponsorgw.infra.tg14.gathering.org-	3	GigabitEthernet1/3
auto-sponsorgw.infra.tg14.gathering.org-	36	GigabitEthernet1/36
auto-sponsorgw.infra.tg14.gathering.org-	9	GigabitEthernet1/9
auto-sponsorgw.infra.tg14.gathering.org-	51	TenGigabitEthernet1/51
auto-sponsorgw.infra.tg14.gathering.org-	47	GigabitEthernet1/47
auto-sponsorgw.infra.tg14.gathering.org-	8	GigabitEthernet1/8
auto-sponsorgw.infra.tg14.gathering.org-	38	GigabitEthernet1/38
auto-sponsorgw.infra.tg14.gathering.org-	4	GigabitEthernet1/4
auto-sponsorgw.infra.tg14.gathering.org-	34	GigabitEthernet1/34
auto-sponsorgw.infra.tg14.gathering.org-	37	GigabitEthernet1/37
auto-sponsorgw.infra.tg14.gathering.org-	43	GigabitEthernet1/43
auto-sponsorgw.infra.tg14.gathering.org-	5	GigabitEthernet1/5
auto-fuglebergetsw02-00:24:01:ef:68:4a	33	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	32	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	21	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	7	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	26	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	331	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	324	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	18	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	329	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	16	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	44	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	27	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	316	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	313	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	20	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	10	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	31	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	35	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	11	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	330	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	48	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	325	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	29	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	100000	vlan
auto-fuglebergetsw02-00:24:01:ef:68:4a	304	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	39	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	41	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	12	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	15	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	312	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	302	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	321	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	45	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	19	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	311	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	306	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	309	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	322	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	2	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	17	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	327	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	315	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	1	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	320	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	30	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	25	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	28	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	40	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	310	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	303	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	323	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	305	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	9000	Internal Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	14	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	308	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	319	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	24	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	328	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	307	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	314	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	22	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	42	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	46	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	318	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	23	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	13	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	301	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	6	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	3	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	36	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	332	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	326	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	9	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	47	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	8	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	38	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	4	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	317	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	34	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	37	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	43	Ethernet Interface
auto-fuglebergetsw02-00:24:01:ef:68:4a	5	Ethernet Interface
\.


--
-- Data for Name: seen_mac; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY seen_mac (mac, address, seen) FROM stdin;
\.


--
-- Data for Name: squeue; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY squeue (id, gid, added, updated, addr, cmd, locked, processed, disabled, priority, sysname, author, result, delay, delaytime) FROM stdin;
\.


--
-- Name: squeue_group_sequence; Type: SEQUENCE SET; Schema: public; Owner: nms
--

SELECT pg_catalog.setval('squeue_group_sequence', 147, true);


--
-- Name: squeue_sequence; Type: SEQUENCE SET; Schema: public; Owner: nms
--

SELECT pg_catalog.setval('squeue_sequence', 5914, true);


--
-- Name: stemppoll_sequence; Type: SEQUENCE SET; Schema: public; Owner: nms
--

SELECT pg_catalog.setval('stemppoll_sequence', 1, false);


--
-- Data for Name: switches; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY switches (switch, ip, sysname, switchtype, last_updated, locked, priority, poll_frequency, community, lldp_chassis_id, secondary_ip) FROM stdin;
488	151.216.142.194	e39-2	dlink3100	2014-04-19 22:11:55.549704+02	f	0	00:01:00	<removed>	00:26:5a:e4:9f:e4	\N
444	151.216.131.194	e11-2	dlink3100	2014-04-19 22:11:55.55006+02	f	0	00:01:00	<removed>	00:26:5a:bd:28:59	\N
508	151.216.147.194	e51-2	dlink3100	2014-04-19 22:11:55.550398+02	f	0	00:01:00	<removed>	00:26:5a:e4:a5:24	\N
477	151.216.140.2	e29-1	dlink3100	2014-04-19 22:11:55.550762+02	f	0	00:01:00	<removed>	00:26:5a:e4:ae:24	\N
629	151.216.227.130	fuglebergetsw02	auto-fuglebergetsw02-00:24:01:ef:68:4a	2014-04-19 22:11:55.825393+02	f	0	00:01:00	<removed>	00:24:01:ef:68:4a	\N
623	151.216.177.2	komplett	dlink3100	2014-04-19 22:11:55.547236+02	f	0	00:01:00	<removed>	00:24:01:ef:66:60	\N
556	151.216.159.194	e75-2	dlink3100	2014-04-19 22:11:55.54768+02	f	0	00:01:00	<removed>	00:24:01:ef:67:e8	\N
562	151.216.161.66	e77-4	dlink3100	2014-04-19 22:11:55.548028+02	f	0	00:01:00	<removed>	00:26:5a:e9:56:21	\N
491	151.216.143.130	e43-1	dlink3100	2014-04-19 22:11:55.548373+02	f	0	00:01:00	<removed>	00:26:5a:e4:ae:a4	\N
449	151.216.133.2	e13-3	dlink3100	2014-04-19 22:11:55.548792+02	f	0	00:01:00	<removed>	00:24:01:ef:6a:f8	\N
463	151.216.136.130	e21-1	dlink3100	2014-04-19 22:11:55.549158+02	f	0	00:01:00	<removed>	00:24:01:ef:6a:96	\N
591	151.216.255.17	Distro1.infra.tg14.gathering.org	auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	2014-04-19 22:11:58.830591+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	d0:d0:fd:cc:66:80	2a02:ed02:ffff::17
539	151.216.155.130	e67-1	dlink3100	2014-04-19 22:11:55.544794+02	f	0	00:01:00	<removed>	00:26:5a:e9:51:a1	\N
486	151.216.142.66	e37-2	dlink3100	2014-04-19 22:11:55.545142+02	f	0	00:01:00	<removed>	00:26:5a:e4:a4:e4	\N
526	151.216.152.66	e59-4	dlink3100	2014-04-19 22:11:55.54549+02	f	0	00:01:00	<removed>	00:26:5a:e9:4d:a1	\N
565	151.216.162.2	e81-1	dlink3100	2014-04-19 22:11:55.545822+02	f	0	00:01:00	<removed>	00:26:5a:e9:4e:a1	\N
480	151.216.140.194	e31-2	dlink3100	2014-04-19 22:11:55.546189+02	f	0	00:01:00	<removed>	00:24:01:ef:6a:c7	\N
461	151.216.136.2	e19-3	dlink3100	2014-04-19 22:11:55.546535+02	f	0	00:01:00	<removed>	00:24:01:ef:68:dd	\N
442	151.216.131.66	e9-4	dlink3100	2014-04-19 22:11:55.546871+02	f	0	00:01:00	<removed>	00:26:5a:e4:a9:a4	\N
534	151.216.154.66	e63-4	dlink3100	2014-04-19 22:11:55.543761+02	f	0	00:01:00	<removed>	00:26:5a:e9:55:e1	\N
474	151.216.139.66	e25-4	dlink3100	2014-04-19 22:11:55.544102+02	f	0	00:01:00	<removed>	00:24:01:ef:6c:1e	\N
490	151.216.143.66	e41-2	dlink3100	2014-04-19 22:11:55.544454+02	f	0	00:01:00	<removed>	00:26:5a:e9:58:a1	\N
626	151.216.232.4	resepsjonssw	auto-resepsjonssw-00:26:5a:e4:ac:24	2014-04-19 22:12:11.492006+02	f	0	00:01:00	<removed>	00:26:5a:e4:ac:24	\N
452	151.216.133.194	e15-2	dlink3100	2014-04-19 22:11:55.542739+02	f	0	00:01:00	<removed>	00:26:5a:e9:53:e1	\N
522	151.216.151.66	e57-4	dlink3100	2014-04-19 22:11:55.543085+02	f	0	00:01:00	<removed>	00:26:5a:e9:4c:21	\N
502	151.216.146.66	e47-4	dlink3100	2014-04-19 22:11:55.54342+02	f	0	00:01:00	<removed>	00:26:5a:e9:4e:e1	\N
601	151.216.165.66	creative7-1	dlink3100	2014-04-19 22:11:55.541712+02	f	0	00:01:00	<removed>	00:26:5a:c0:0a:df	\N
476	151.216.139.194	e27-2	dlink3100	2014-04-19 22:11:55.542054+02	f	0	00:01:00	<removed>	00:26:5a:e4:a6:e4	\N
597	151.216.164.66	creative5-1	dlink3100	2014-04-19 22:11:55.542387+02	f	0	00:01:00	<removed>	00:26:5a:e4:9e:64	\N
421	151.216.255.6	LogGW.infra.tg14.gathering.org	auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	2014-04-19 22:11:55.808932+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	64:9e:f3:eb:c5:c0	2a02:ed02:ffff::6
617	151.216.255.11	distro0.infra.tg14.gathering.org	auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	2014-04-19 22:11:55.809288+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	30:e4:db:a5:25:80	2a02:ed02:ffff::11
484	151.216.141.194	e35-2	dlink3100	2014-04-19 22:11:55.538627+02	f	0	00:01:00	<removed>	00:26:5a:e4:a3:a4	\N
453	151.216.134.2	e15-3	dlink3100	2014-04-19 22:11:55.538975+02	f	0	00:01:00	<removed>	00:24:01:ef:68:7b	\N
605	151.216.166.66	crew1-1	dlink3100	2014-04-19 22:11:55.539471+02	f	0	00:01:00	<removed>	00:26:5a:e9:50:61	\N
527	151.216.152.130	e61-1	dlink3100	2014-04-19 22:11:55.53987+02	f	0	00:01:00	<removed>	00:26:5a:e4:ad:64	\N
604	151.216.166.2	creative8-2	dlink3100	2014-04-19 22:11:55.540232+02	f	0	00:01:00	<removed>	00:24:01:ef:6b:bc	\N
456	151.216.134.194	e17-2	dlink3100	2014-04-19 22:11:55.540623+02	f	0	00:01:00	<removed>	00:24:01:ef:6c:b1	\N
592	151.216.163.2	creative1-1	dlink3100	2014-04-19 22:11:55.540964+02	f	0	00:01:00	<removed>	00:26:5a:e9:56:e1	\N
499	151.216.145.130	e47-1	dlink3100	2014-04-19 22:11:55.537222+02	f	0	00:01:00	<removed>	00:26:5a:c0:0b:41	\N
434	151.216.129.66	e1-4	dlink3100	2014-04-19 22:11:55.537572+02	f	0	00:01:00	<removed>	00:26:5a:e9:56:61	\N
561	151.216.161.2	e77-3	dlink3100	2014-04-19 22:11:55.537946+02	f	0	00:01:00	<removed>	00:26:5a:e9:50:e1	\N
531	151.216.153.130	e63-1	dlink3100	2014-04-19 22:11:55.538284+02	f	0	00:01:00	<removed>	00:26:5a:e4:a5:e4	\N
541	151.216.156.2	e67-3	dlink3100	2014-04-19 22:11:55.536533+02	f	0	00:01:00	<removed>	00:26:5a:e9:49:e1	\N
481	151.216.141.2	e33-1	dlink3100	2014-04-19 22:11:55.536884+02	f	0	00:01:00	<removed>	00:24:01:ef:69:0e	\N
429	151.216.255.22	SlutGW.infra.tg14.gathering.org	auto-SlutGW.infra.tg14.gathering.org-00:07:7d:64:0d:00	2014-04-19 22:11:55.8035+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	00:07:7d:64:0d:00	2a02:ed02:ffff::22
509	151.216.148.2	e51-3	dlink3100	2014-04-19 22:11:55.535266+02	f	0	00:01:00	<removed>	00:26:5a:e9:4b:a1	\N
537	151.216.155.2	e65-3	dlink3100	2014-04-19 22:11:55.535627+02	f	0	00:01:00	<removed>	00:26:5a:e9:4b:e1	\N
457	151.216.135.2	e17-3	dlink3100	2014-04-19 22:11:55.535977+02	f	0	00:01:00	<removed>	00:26:5a:e4:a4:64	\N
614	151.216.255.20	Distro4.infra.tg14.gathering.org	auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	2014-04-19 22:11:58.668356+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	7c:ad:74:60:da:c0	2a02:ed02:ffff::20
469	151.216.138.2	e23-3	dlink3100	2014-04-19 22:11:55.534164+02	f	0	00:01:00	<removed>	00:26:5a:e9:5a:e1	\N
487	151.216.142.130	e39-1	dlink3100	2014-04-19 22:11:55.534553+02	f	0	00:01:00	<removed>	00:26:5a:e9:5a:21	\N
599	151.216.164.194	creative6-1	dlink3100	2014-04-19 22:11:55.534914+02	f	0	00:01:00	<removed>	00:26:5a:e9:54:21	\N
622	151.216.255.9	crewgw.infra.tg14.gathering.org	auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	2014-04-19 22:11:55.808573+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	c8:9c:1d:ef:33:00	2a02:ed02:ffff::9
610	151.216.167.2	crew4-1	dlink3100	2014-04-19 22:11:55.53313+02	f	0	00:01:00	<removed>	00:26:5a:e4:a3:64	\N
493	151.216.144.2	e43-3	dlink3100	2014-04-19 22:11:55.533524+02	f	0	00:01:00	<removed>	00:26:5a:e4:a7:64	\N
418	151.216.255.2	NocGW.infra.tg14.gathering.org	auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	2014-04-19 22:11:56.598274+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	00:15:2c:8d:f4:00	2a02:ed02:ffff::2
588	151.216.255.18	Distro2.infra.tg14.gathering.org	auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	2014-04-19 22:11:57.919448+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	d0:d0:fd:44:dd:00	2a02:ed02:ffff::18
494	151.216.144.66	e43-4	dlink3100	2014-04-19 22:11:55.531988+02	f	0	00:01:00	<removed>	00:26:5a:e4:a5:64	\N
441	151.216.131.2	e9-3	dlink3100	2014-04-19 22:11:55.532423+02	f	0	00:01:00	<removed>	00:26:5a:e9:58:21	\N
423	151.216.255.5	wtfGW.infra.tg14.gathering.org	auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	2014-04-19 22:11:55.808002+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	d0:d0:fd:e3:06:80	2a02:ed02:ffff::5
466	151.216.137.66	e21-4	dlink3100	2014-04-19 22:11:55.531311+02	f	0	00:01:00	<removed>	00:24:01:ef:6b:8b	\N
618	151.216.255.23	CreativiaGW.infra.tg14.gathering.org	auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	2014-04-19 22:11:55.807642+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	f8:66:f2:b7:3e:40	2a02:ed02:ffff::23
514	151.216.149.66	e53-4	dlink3100	2014-04-19 22:11:55.530579+02	f	0	00:01:00	<removed>	00:26:5a:e4:a2:24	\N
496	151.216.144.194	e45-2	dlink3100	2014-04-19 22:11:55.53011+02	f	0	00:01:00	<removed>	00:26:5a:e9:54:61	\N
495	151.216.144.130	e45-1	dlink3100	2014-04-19 22:11:55.529662+02	f	0	00:01:00	<removed>	00:24:01:ef:69:a1	\N
432	151.216.252.2	NocSW1.infra.tg14.gathering.org	auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	2014-04-19 22:11:55.563538+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	50:17:ff:da:d4:80	\N
447	151.216.132.130	e13-1	dlink3100	2014-04-19 22:11:55.529104+02	f	0	00:01:00	<removed>	00:26:5a:e9:51:21	\N
616	151.216.240.2	medicsw.infra.tg14.gathering.org	auto-medicsw.infra.tg14.gathering.org-6c:9c:ed:82:34:00	2014-04-19 22:11:55.823925+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	6c:9c:ed:82:34:00	\N
424	151.216.253.254	nocnexus	auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	2014-04-19 22:11:14.737602+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	00:05:73:ac:05:da	\N
627	151.216.229.3	GameHQSW2	auto-GameHQSW2-00:26:5a:e4:9e:e4	2014-04-19 22:11:55.192012+02	f	0	00:01:00	<removed>	00:26:5a:e4:9e:e4	\N
454	151.216.134.66	e15-4	dlink3100	2014-04-19 22:11:55.526665+02	f	0	00:01:00	<removed>	00:26:5a:e4:ac:e4	\N
516	151.216.149.194	e55-2	dlink3100	2014-04-19 22:11:55.527018+02	f	0	00:01:00	<removed>	00:26:5a:e9:58:61	\N
471	151.216.138.130	e25-1	dlink3100	2014-04-19 22:11:55.527366+02	f	0	00:01:00	<removed>	00:26:5a:e9:49:21	\N
521	151.216.151.2	e57-3	dlink3100	2014-04-19 22:11:55.527709+02	f	0	00:01:00	<removed>	00:26:5a:e9:51:61	\N
472	151.216.138.194	e25-2	dlink3100	2014-04-19 22:11:55.528049+02	f	0	00:01:00	<removed>	00:24:01:ef:67:86	\N
557	151.216.160.2	e75-3	dlink3100	2014-04-19 22:11:55.528398+02	f	0	00:01:00	<removed>	00:24:01:ef:6a:34	\N
532	151.216.153.194	e63-2	dlink3100	2014-04-19 22:11:55.528748+02	f	0	00:01:00	<removed>	00:26:5a:e4:ae:64	\N
467	151.216.137.130	e23-1	dlink3100	2014-04-19 22:11:55.526286+02	f	0	00:01:00	<removed>	00:26:5a:e4:a6:a4	\N
468	151.216.137.194	e23-2	dlink3100	2014-04-19 22:11:55.525938+02	f	0	00:01:00	<removed>	00:26:5a:e9:4a:a1	\N
470	151.216.138.66	e23-4	dlink3100	2014-04-19 22:11:55.525259+02	f	0	00:01:00	<removed>	00:26:5a:e9:4e:21	\N
563	151.216.161.130	e79-1	dlink3100	2014-04-19 22:11:55.525598+02	f	0	00:01:00	<removed>	00:26:5a:e4:9f:64	\N
435	151.216.129.130	e3-3	dlink3100	2014-04-19 22:11:55.524569+02	f	0	00:01:00	<removed>	00:24:01:ef:67:24	\N
498	151.216.145.66	e45-4	dlink3100	2014-04-19 22:11:55.524915+02	f	0	00:01:00	<removed>	00:26:5a:e9:52:61	\N
536	151.216.154.194	e65-2	dlink3100	2014-04-19 22:11:55.524225+02	f	0	00:01:00	<removed>	00:26:5a:e4:af:64	\N
455	151.216.134.130	e17-1	dlink3100	2014-04-19 22:11:55.522153+02	f	0	00:01:00	<removed>	00:24:01:ef:6a:03	\N
500	151.216.145.194	e47-2	dlink3100	2014-04-19 22:11:55.522513+02	f	0	00:01:00	<removed>	00:24:01:ef:6b:29	\N
545	151.216.157.2	e69-3	dlink3100	2014-04-19 22:11:55.522868+02	f	0	00:01:00	<removed>	00:26:5a:e4:a0:64	\N
606	151.216.166.130	crew2-1	dlink3100	2014-04-19 22:11:55.523212+02	f	0	00:01:00	<removed>	00:26:5a:e4:a7:e4	\N
459	151.216.135.130	e19-1	dlink3100	2014-04-19 22:11:55.52355+02	f	0	00:01:00	<removed>	00:26:5a:e4:a2:64	\N
510	151.216.148.66	e51-4	dlink3100	2014-04-19 22:11:55.523888+02	f	0	00:01:00	<removed>	00:1e:58:35:c6:ae	\N
464	151.216.136.194	e21-2	dlink3100	2014-04-19 22:11:55.520641+02	f	0	00:01:00	<removed>	00:26:5a:e9:50:21	\N
544	151.216.156.194	e69-2	dlink3100	2014-04-19 22:11:55.521026+02	f	0	00:01:00	<removed>	00:26:5a:e9:4c:e1	\N
504	151.216.146.194	e49-2	dlink3100	2014-04-19 22:11:55.521445+02	f	0	00:01:00	<removed>	00:26:5a:e9:4f:e1	\N
437	151.216.130.2	e5-3	dlink3100	2014-04-19 22:11:55.521801+02	f	0	00:01:00	<removed>	00:26:5a:e4:aa:e4	\N
428	151.216.252.3	NocSW2.infra.tg14.gathering.org	auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	2014-04-19 22:11:55.563184+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	e8:ed:f3:ef:6c:00	\N
419	151.216.255.1	TeleGW.infra.tg14.gathering.org	auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	2014-04-19 22:11:55.8324+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	00:1a:e3:16:a4:00	2a02:ed02:ffff::1
594	151.216.163.130	creative3-1	dlink3100	2014-04-19 22:11:55.518368+02	f	0	00:01:00	<removed>	00:26:5a:e4:a0:e4	\N
550	151.216.158.66	e71-4	dlink3100	2014-04-19 22:11:55.518768+02	f	0	00:01:00	<removed>	00:26:5a:e4:ae:e4	\N
482	151.216.141.66	e33-2	dlink3100	2014-04-19 22:11:55.519117+02	f	0	00:01:00	<removed>	00:26:5a:e4:a5:a4	\N
479	151.216.140.130	e31-1	dlink3100	2014-04-19 22:11:55.519454+02	f	0	00:01:00	<removed>	00:26:5a:e4:a3:24	\N
543	151.216.156.130	e69-1	dlink3100	2014-04-19 22:11:55.519797+02	f	0	00:01:00	<removed>	00:26:5a:e9:59:61	\N
511	151.216.148.130	e53-1	dlink3100	2014-04-19 22:11:55.517683+02	f	0	00:01:00	<removed>	00:26:5a:e9:53:21	\N
595	151.216.163.194	creative4-1	dlink3100	2014-04-19 22:11:55.518028+02	f	0	00:01:00	<removed>	00:26:5a:e4:a8:a4	\N
420	151.216.255.3	CamGW.infra.tg14.gathering.org	auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	2014-04-19 22:11:55.807062+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	e8:b7:48:e6:6e:80	2a02:ed02:ffff::3
549	151.216.158.2	e71-3	dlink3100	2014-04-19 22:11:55.504284+02	f	0	00:01:00	<removed>	00:26:5a:e4:a8:e4	\N
513	151.216.149.2	e53-3	dlink3100	2014-04-19 22:11:55.504639+02	f	0	00:01:00	<removed>	00:26:5a:c0:0e:e4	\N
598	151.216.164.130	creative5-2	dlink3100	2014-04-19 22:11:55.51131+02	f	0	00:01:00	<removed>	00:26:5a:e4:a4:a4	\N
520	151.216.150.194	e57-2	dlink3100	2014-04-19 22:11:55.503927+02	f	0	00:01:00	<removed>	00:24:01:ef:6c:4f	\N
621	151.216.242.4	BussEventSW01.infra.tg14.gathering.org	auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	2014-04-19 22:11:55.562636+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	e8:ed:f3:ef:aa:00	\N
530	151.216.153.66	e61-4	dlink3100	2014-04-19 22:11:55.501117+02	f	0	00:01:00	<removed>	00:26:5a:e4:a3:e4	\N
589	151.216.227.6	secbua-lowersw.infra.tg14.gathering.org	auto-secbua-lowersw.infra.tg14.gathering.org-6c:9c:ed:82:6b:00	2014-04-19 22:11:55.824287+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	6c:9c:ed:82:6b:00	\N
507	151.216.147.130	e51-1	dlink3100	2014-04-19 22:11:55.50077+02	f	0	00:01:00	<removed>	00:26:5a:e4:a0:24	\N
564	151.216.161.194	e79-2	dlink3100	2014-04-19 22:11:55.50813+02	f	0	00:01:00	<removed>	00:26:5a:e4:9e:24	\N
540	151.216.155.194	e67-2	dlink3100	2014-04-19 22:11:55.509863+02	f	0	00:01:00	<removed>	00:26:5a:e9:57:a1	\N
478	151.216.140.66	e29-2	dlink3100	2014-04-19 22:11:55.500248+02	f	0	00:01:00	<removed>	00:26:5a:e9:57:21	\N
518	151.216.150.66	e55-4	dlink3100	2014-04-19 22:11:55.56081+02	f	0	00:01:00	<removed>	00:26:5a:e9:52:21	\N
558	151.216.160.66	e75-4	dlink3100	2014-04-19 22:11:55.499567+02	f	0	00:01:00	<removed>	00:26:5a:e9:52:e1	\N
542	151.216.156.66	e67-4	dlink3100	2014-04-19 22:11:55.499907+02	f	0	00:01:00	<removed>	00:26:5a:e4:ab:64	\N
519	151.216.150.130	e57-1	dlink3100	2014-04-19 22:11:55.507789+02	f	0	00:01:00	<removed>	00:26:5a:e9:59:21	\N
596	151.216.164.2	creative4-2	dlink3100	2014-04-19 22:11:55.507089+02	f	0	00:01:00	<removed>	00:26:5a:e4:ab:e4	\N
497	151.216.145.2	e45-3	dlink3100	2014-04-19 22:11:55.507442+02	f	0	00:01:00	<removed>	00:26:5a:e9:58:e1	\N
560	151.216.160.194	e77-2	dlink3100	2014-04-19 22:11:55.497437+02	f	0	00:01:00	<removed>	00:26:5a:e4:af:24	\N
438	151.216.130.66	e5-4	dlink3100	2014-04-19 22:11:55.497785+02	f	0	00:01:00	<removed>	00:24:01:ef:66:f3	\N
524	151.216.151.194	e59-2	dlink3100	2014-04-19 22:11:55.498885+02	f	0	00:01:00	<removed>	00:26:5a:e9:57:61	\N
555	151.216.159.130	e75-1	dlink3100	2014-04-19 22:11:55.499221+02	f	0	00:01:00	<removed>	00:26:5a:e9:49:a1	\N
489	151.216.143.2	e41-1	dlink3100	2014-04-19 22:11:55.508814+02	f	0	00:01:00	<removed>	00:26:5a:e9:51:e1	\N
515	151.216.149.130	e55-1	dlink3100	2014-04-19 22:11:55.509165+02	f	0	00:01:00	<removed>	00:26:5a:e9:4d:61	\N
450	151.216.133.66	e13-4	dlink3100	2014-04-19 22:11:55.498127+02	f	0	00:01:00	<removed>	00:24:01:ef:66:91	\N
608	151.216.166.194	crew3-1	dlink3100	2014-04-19 22:11:55.498475+02	f	0	00:01:00	<removed>	00:26:5a:e9:4a:21	\N
535	151.216.154.130	e65-1	dlink3100	2014-04-19 22:11:55.496747+02	f	0	00:01:00	<removed>	00:26:5a:e9:55:21	\N
538	151.216.155.66	e65-4	dlink3100	2014-04-19 22:11:55.4971+02	f	0	00:01:00	<removed>	00:26:5a:e4:a1:24	\N
624	151.216.229.2	GameHQSW1	auto-GameHQSw1-00:26:5a:e9:4b:21	2014-04-19 22:11:57.083056+02	f	0	00:01:00	<removed>	00:26:5a:e9:4b:21	\N
462	151.216.136.66	e19-4	dlink3100	2014-04-19 22:11:55.496394+02	f	0	00:01:00	<removed>	00:26:5a:e9:4a:e1	\N
431	151.216.227.3	FuglebergDistro.infra.tg14.gathering.org	auto-FuglebergDistro.infra.tg14.gathering.org-2c:36:f8:88:48:00	2014-04-19 22:11:55.823355+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	2c:36:f8:88:48:00	\N
546	151.216.157.66	e69-4	dlink3100	2014-04-19 22:11:55.496047+02	f	0	00:01:00	<removed>	00:24:01:ef:6b:5a	\N
485	151.216.142.2	e37-1	dlink3100	2014-04-19 22:11:55.510952+02	f	0	00:01:00	<removed>	00:26:5a:e4:a7:a4	\N
448	151.216.132.194	e13-2	dlink3100	2014-04-19 22:11:55.493502+02	f	0	00:01:00	<removed>	00:26:5a:e4:ab:a4	\N
547	151.216.157.130	e71-1	dlink3100	2014-04-19 22:11:55.495689+02	f	0	00:01:00	<removed>	00:26:5a:e4:a7:24	\N
446	151.216.132.66	e11-4	dlink3100	2014-04-19 22:11:55.510205+02	f	0	00:01:00	<removed>	00:26:5a:e4:a8:64	\N
443	151.216.131.130	e11-1	dlink3100	2014-04-19 22:11:55.495335+02	f	0	00:01:00	<removed>	00:26:5a:e9:4d:21	\N
506	151.216.147.66	e49-4	dlink3100	2014-04-19 22:11:55.50847+02	f	0	00:01:00	<removed>	00:26:5a:e4:ac:64	\N
465	151.216.137.2	e21-3	dlink3100	2014-04-19 22:11:55.494248+02	f	0	00:01:00	<removed>	00:26:5a:e9:56:a1	\N
554	151.216.159.66	e73-4	dlink3100	2014-04-19 22:11:55.494977+02	f	0	00:01:00	<removed>	00:26:5a:e9:4f:a1	\N
551	151.216.158.130	e73-1	dlink3100	2014-04-19 22:11:55.493892+02	f	0	00:01:00	<removed>	00:26:5a:e9:54:e1	\N
590	151.216.227.2	fuglebergetsw01	auto-fuglebergetsw01-00:26:5a:e4:a1:a4	2014-04-19 22:11:28.789942+02	f	0	00:01:00	snmpv3:techserver/SHA/fiskebollerihvitsaus	00:26:5a:e4:a1:a4	\N
523	151.216.151.130	e59-1	dlink3100	2014-04-19 22:11:55.501674+02	f	0	00:01:00	<removed>	00:26:5a:e9:5a:61	\N
602	151.216.165.130	creative7-2	dlink3100	2014-04-19 22:11:55.509522+02	f	0	00:01:00	<removed>	00:26:5a:e4:9f:a4	\N
600	151.216.165.2	creative6-2	dlink3100	2014-04-19 22:11:55.512076+02	f	0	00:01:00	<removed>	00:26:5a:e4:ab:24	\N
528	151.216.152.194	e61-2	dlink3100	2014-04-19 22:11:55.513214+02	f	0	00:01:00	<removed>	00:26:5a:e9:55:a1	\N
475	151.216.139.130	e27-1	dlink3100	2014-04-19 22:11:55.51171+02	f	0	00:01:00	<removed>	00:26:5a:e9:4f:61	\N
559	151.216.160.130	e77-1	dlink3100	2014-04-19 22:11:55.51245+02	f	0	00:01:00	<removed>	00:26:5a:e9:4c:61	\N
445	151.216.132.2	e11-3	dlink3100	2014-04-19 22:11:55.502058+02	f	0	00:01:00	<removed>	00:26:5a:e9:49:61	\N
593	151.216.163.66	creative2-1	dlink3100	2014-04-19 22:11:55.502484+02	f	0	00:01:00	<removed>	00:24:01:ef:68:19	\N
548	151.216.157.194	e71-2	dlink3100	2014-04-19 22:11:55.502856+02	f	0	00:01:00	<removed>	00:26:5a:e4:ad:e4	\N
512	151.216.148.194	e53-2	dlink3100	2014-04-19 22:11:55.512803+02	f	0	00:01:00	<removed>	00:26:5a:e4:ad:24	\N
440	151.216.130.194	e7-4	dlink3100	2014-04-19 22:11:55.506381+02	f	0	00:01:00	<removed>	00:24:01:ef:6b:ed	\N
492	151.216.143.194	e43-2	dlink3100	2014-04-19 22:11:55.506748+02	f	0	00:01:00	<removed>	00:26:5a:e4:a4:24	\N
603	151.216.165.194	creative8-1	dlink3100	2014-04-19 22:11:55.513592+02	f	0	00:01:00	<removed>	00:26:5a:e4:a6:64	\N
566	151.216.162.66	e81-2	dlink3100	2014-04-19 22:11:55.514325+02	f	0	00:01:00	<removed>	00:24:01:ef:6d:13	\N
439	151.216.130.130	e7-3	dlink3100	2014-04-19 22:11:55.514923+02	f	0	00:01:00	<removed>	00:26:5a:e4:aa:a4	\N
612	151.216.255.19	Distro3.infra.tg14.gathering.org	auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	2014-04-19 22:11:58.822489+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	f8:66:f2:b4:0f:40	2a02:ed02:ffff::19
460	151.216.135.194	e19-2	dlink3100	2014-04-19 22:11:55.510558+02	f	0	00:01:00	<removed>	00:26:5a:e4:9d:e4	\N
503	151.216.146.130	e49-1	dlink3100	2014-04-19 22:11:55.515714+02	f	0	00:01:00	<removed>	00:26:5a:e4:9e:a4	\N
473	151.216.139.2	e25-3	dlink3100	2014-04-19 22:11:55.553238+02	f	0	00:01:00	<removed>	00:26:5a:e4:a0:a4	\N
451	151.216.133.130	e15-1	dlink3100	2014-04-19 22:11:55.515324+02	f	0	00:01:00	<removed>	00:26:5a:e9:50:a1	\N
533	151.216.154.2	e63-3	dlink3100	2014-04-19 22:11:55.516786+02	f	0	00:01:00	<removed>	00:26:5a:e9:5a:a1	\N
483	151.216.141.130	e35-1	dlink3100	2014-04-19 22:11:55.516079+02	f	0	00:01:00	<removed>	00:26:5a:e9:53:61	\N
517	151.216.150.2	e55-3	dlink3100	2014-04-19 22:11:55.503221+02	f	0	00:01:00	<removed>	00:24:01:ef:67:b7	\N
525	151.216.152.2	e59-3	dlink3100	2014-04-19 22:11:55.503582+02	f	0	00:01:00	<removed>	00:26:5a:e4:a9:24	\N
430	151.216.255.32	RohypnolGW.infra.tg14.gathering.org	auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	2014-04-19 22:11:55.829354+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	00:08:e3:ff:fc:04	2a02:ed02:ffff::32
529	151.216.153.2	e61-3	dlink3100	2014-04-19 22:11:55.51396+02	f	0	00:01:00	<removed>	00:26:5a:e9:55:61	\N
501	151.216.146.2	e47-3	dlink3100	2014-04-19 22:11:55.494626+02	f	0	00:01:00	<removed>	00:24:01:ef:69:d2	\N
552	151.216.158.194	e73-2	dlink3100	2014-04-19 22:11:55.517132+02	f	0	00:01:00	<removed>	00:26:5a:e4:aa:64	\N
458	151.216.135.66	e17-4	dlink3100	2014-04-19 22:11:55.516428+02	f	0	00:01:00	<removed>	00:26:5a:e4:a9:64	\N
613	151.216.255.14	sponsorgw.infra.tg14.gathering.org	auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	2014-04-19 22:11:55.806381+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	64:9e:f3:eb:c6:40	2a02:ed02:ffff::14
422	151.216.255.4	StageBoH.infra.tg14.gathering.org	auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	2014-04-19 22:11:55.805992+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	00:07:7d:63:b9:80	2a02:ed02:ffff::4
433	151.216.129.2	e1-3	dlink3100	2014-04-19 22:11:55.504987+02	f	0	00:01:00	<removed>	00:26:5a:e4:aa:24	\N
553	151.216.159.2	e73-3	dlink3100	2014-04-19 22:11:55.50534+02	f	0	00:01:00	<removed>	00:26:5a:e4:ad:a4	\N
505	151.216.147.2	e49-3	dlink3100	2014-04-19 22:11:55.505682+02	f	0	00:01:00	<removed>	00:26:5a:e4:a8:24	\N
436	151.216.129.194	e3-4	dlink3100	2014-04-19 22:11:55.506037+02	f	0	00:01:00	<removed>	00:24:01:ef:69:70	\N
615	151.216.255.21	Distro5.infra.tg14.gathering.org	auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	2014-04-19 22:11:57.882187+02	f	0	00:01:00	snmpv3:techserver/SHA/<removed>/AES/<removed>	d0:d0:fd:cc:66:c0	2a02:ed02:ffff::21
\.


--
-- Name: switches_switch_seq; Type: SEQUENCE SET; Schema: public; Owner: nms
--

SELECT pg_catalog.setval('switches_switch_seq', 629, true);


--
-- Data for Name: switchtypes; Type: TABLE DATA; Schema: public; Owner: nms
--

COPY switchtypes (switchtype, ports) FROM stdin;
auto-NocGW.infra.tg14.gathering.org-00:15:2c:8d:f4:00	1-126
auto-TeleGW.infra.tg14.gathering.org-00:1a:e3:16:a4:00	1-78
auto-CamGW.infra.tg14.gathering.org-e8:b7:48:e6:6e:80	1-52,55
auto-LogGW.infra.tg14.gathering.org-64:9e:f3:eb:c5:c0	1-52,55
auto-StageBoH.infra.tg14.gathering.org-00:07:7d:63:b9:80	1-52,55
auto-wtfGW.infra.tg14.gathering.org-d0:d0:fd:e3:06:80	1-52,55
auto-nocnexus-43:69:73:63:6f:20:4e:58:2d:4f:53:28:74:6d:29:20:6e:35:30:30:30:2c:20:53:6f:66:74:77:61:72:65:20:28:6e:35:30:30:30:2d:75:6b:39:29:2c:20:56:65:72:73:69:6f:6e:20:35:2e:30:28:33:29:4e:31:28:31:61:29:2c:20:52:45:4c:45:41:53:45:20:53:4f:46:54:57:41:52:45:20:43:6f:70:79:72:69:67:68:74:20:28:63:29:20:32:30:30:32:2d:32:30:31:30:20:62:79:20:43:69:73:63:6f:20:53:79:73:74:65:6d:73:2c:20:49:6e:63:2e:20:44:65:76:69:63:65:20:4d:61:6e:61:67:65:72:20:56:65:72:73:69:6f:6e:20:35:2e:32:28:31:29:2c:20:20:43:6f:6d:70:69:6c:65:64:20:33:2f:37:2f:32:30:31:31:20:32:33:3a:30:30:3a:30:30	83886080,436207616,436211712,436215808,436219904,436224000,436228096,436232192,436236288,436240384,436244480,436248576,436252672,436256768,436260864,436264960,436269056,436273152,436277248,436281344,436285440
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:db	83886080,436207616,436211712,436215808,436219904,436224000,436228096,436232192,436236288,436240384,436244480,436248576,436252672,436256768,436260864,436264960,436269056,436273152,436277248,436281344,436285440
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d8	83886080,436207616,436211712,436215808,436219904,436224000,436228096,436232192,436236288,436240384,436244480,436248576,436252672,436256768,436260864,436264960,436269056,436273152,436277248,436281344,436285440
auto-nocnexus.infra.tg14.gathering.org-00:05:73:ac:05:d9	83886080,436207616,436211712,436215808,436219904,436224000,436228096,436232192,436236288,436240384,436244480,436248576,436252672,436256768,436260864,436264960,436269056,436273152,436277248,436281344,436285440
auto-NocSW2.infra.tg14.gathering.org-e8:ed:f3:ef:6c:00	10101-10150,10201-10202,14002
auto-SlutGW.infra.tg14.gathering.org-00:07:7d:64:0d:00	1-52
auto-RohypnolGW.infra.tg14.gathering.org-00:08:e3:ff:fc:04	1,150-189,270,273,276,279,282,285,288,291,294,297,300,303,306,309,312,315,318,321,324,327,330,333,336,339,342,345,348,351,354,357,360,363,366,369,372,375,378,381,384,387
auto-FuglebergDistro.infra.tg14.gathering.org-2c:36:f8:88:48:00	10101-10110
auto-NocSW1.infra.tg14.gathering.org-50:17:ff:da:d4:80	10101-10150,10201-10202,14002
auto-Distro2.infra.tg14.gathering.org-d0:d0:fd:44:dd:00	1-201
auto-secbua-lowersw.infra.tg14.gathering.org-6c:9c:ed:82:6b:00	10101-10110
auto-fuglebergetsw01-00:26:5a:e4:a1:a4	1-39
auto-Distro1.infra.tg14.gathering.org-d0:d0:fd:cc:66:80	1-201
auto-Distro3.infra.tg14.gathering.org-f8:66:f2:b4:0f:40	1-201
auto-sponsorgw.infra.tg14.gathering.org-64:9e:f3:eb:c6:40	1-52,55
auto-Distro4.infra.tg14.gathering.org-7c:ad:74:60:da:c0	1-201
auto-Distro5.infra.tg14.gathering.org-d0:d0:fd:cc:66:c0	1-201
auto-medicsw.infra.tg14.gathering.org-6c:9c:ed:82:34:00	10101-10110
auto-distro0.infra.tg14.gathering.org-30:e4:db:a5:25:80	1-52,55
auto-CreativiaGW.infra.tg14.gathering.org-f8:66:f2:b7:3e:40	1-52,55
auto-GameHQSW1-00:26:5a:e9:4b:21	1-78
auto-BussEventSW01.infra.tg14.gathering.org-e8:ed:f3:ef:aa:00	10101-10150,10201-10202,14002
auto-crewgw.infra.tg14.gathering.org-c8:9c:1d:ef:33:00	1-52,55
dlink3100	1-48
auto-GameHQSw1-00:26:5a:e9:4b:21	1-48,301-332
auto-e63-2_DGS-3100-00:26:5a:e4:ae:64	1-39
auto-resepsjonssw-00:26:5a:e4:ac:24	1-39
auto-GameHQSW2-00:26:5a:e4:9e:e4	1-39
auto-sponsorgw.infra.tg14.gathering.org-	1-52,55
auto-fuglebergetsw02-00:24:01:ef:68:4a	1-48,301-332
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
\.


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
-- Name: polls_switchporttime; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX polls_switchporttime ON polls USING btree (switch, port, "time");


--
-- Name: polls_time; Type: INDEX; Schema: public; Owner: nms; Tablespace: 
--

CREATE INDEX polls_time ON polls USING btree ("time");


--
-- Name: seen_mac_addr_family; Type: INDEX; Schema: public; Owner: postgres; Tablespace: 
--

CREATE INDEX seen_mac_addr_family ON seen_mac USING btree (family(address));


--
-- Name: seen_mac_seen; Type: INDEX; Schema: public; Owner: postgres; Tablespace: 
--

CREATE INDEX seen_mac_seen ON seen_mac USING btree (seen);


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
GRANT ALL ON TABLE dhcp TO root;


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
GRANT ALL ON TABLE placements TO root;


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
GRANT ALL ON TABLE squeue TO root;


--
-- Name: switches; Type: ACL; Schema: public; Owner: nms
--

REVOKE ALL ON TABLE switches FROM PUBLIC;
REVOKE ALL ON TABLE switches FROM nms;
GRANT ALL ON TABLE switches TO nms;
GRANT ALL ON TABLE switches TO root;


--
-- PostgreSQL database dump complete
--

