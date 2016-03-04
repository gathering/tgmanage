API-dok
=======

Work in progress.

General: All end-points that output time-based data accept the "now=<time>"
argument, where, <time> is YYYY-MM-DDThh:mm:ss. E.g:

GET /switch-state.pl?now=2015-04-02T15:00:00

There is no guarantee that the data is exact time-wise, thus each endpoint
should also output relevant time stamps.

Currently error handling sucks.

This document is in no way complete, but it's a start. It will be updated
as time permits and API's stabilize.

comment-add.pl
--------------

Methods: POST

 -- Add a comment

comment-change.pl
-----------------

Methods: POST

Note that comments are never really deleted, but the state can be set to
deleted, making sure they are never shown.

comment.pl -- View comments
---------------------------

Methods: GET
Update frequency: on user input

ping.pl -- Being phased out
---------------------------

Methods: GET
Update frequency: every second or so.

Used to report switch latency and linknet latency.

The switch latency is being integrated into switch-state.pl and linknet
latency will similarly be moved.

port-state.pl -- Get per-port statistics
----------------------------------------

Methods: GET
Update frequency: Every few seconds, based on SNMP data.

Private.

Returns detailed per-port statistics. Being somewhat reorganized but will
remain highly relevant.

switches_add.pl -- Add a switch
-------------------------------

Methods: POST

Add switches, supports same format as tools/add_switches.txt.pl

Accepts an array of switches.

switches.pl
-----------

Methods: GET
Update frequency: Infrequent (on topology/config changes)

List all switches and map positions. Output is filtered for public users.

Used to draw switches on a map and provide static information.

switch-state.pl -- List state for switches
------------------------------------------

Methods: GET
Update frequency: Every second

Provides state for each switch, including total port speed, uplink port
speed, latency and temperature.

100% public.
