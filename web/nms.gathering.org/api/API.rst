API-dok
=======

Work in progress.

There are two relevant paths: /api/public and /api/private. One requires
user-login in, the other does not.

General: All end-points that output time-based data accept the "now=<time>"
argument, where, <time> is YYYY-MM-DDThh:mm:ss. E.g:

GET /api/public/switch-state?now=2015-04-02T15:00:00

There is no guarantee that the data is exact time-wise, thus each endpoint
should also output relevant time stamps.

Currently error handling sucks.

This document is in no way complete, but it's a start. It will be updated
as time permits and API's stabilize.

Private
.......

/api/private/comment-add
------------------------

Methods: POST

Add a comment

/api/private/comment-change
---------------------------

Methods: POST

Note that comments are never really deleted, but the state can be set to
deleted, making sure they are never shown.

/api/private/comments
---------------------

Methods: GET

Update frequency: on user input

Lists comments.

/api/private/port-state
-----------------------

Methods: GET

Update frequency: Every few seconds, based on SNMP data.

Returns detailed per-port statistics. Being somewhat reorganized but will
remain highly relevant.

/api/private/switches-management
--------------------------------

Methods: GET

Update frequency: Infrequent (on topology/config changes)

List management information for switches.

/api/private/switch-add
-----------------------

Methods: POST

Add switches, supports same format as tools/add_switches.txt.pl

Accepts an array of switches.

Public
......

/api/public/ping
----------------

Methods: GET
Update frequency: every second or so.

Used to report linknet latency.

The switch latency is being integrated into switch-state.pl and linknet
latency will similarly be moved.

/api/public/switches
--------------------

Methods: GET
Update frequency: Infrequent (on topology/config changes)

List all switches and map positions.

Used to draw switches on a map and provide static information.

/api/public/switch-state
------------------------

Methods: GET
Update frequency: Every second

Provides state for each switch, including total port speed, uplink port
speed, latency and temperature.
