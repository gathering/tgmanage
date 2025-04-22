TG label scripts
================

Scripts.

Usage
-----

The ``--help`` parameter is pretty helpful.

Run the script with either ``cables`` or ``switches``,
depending if you want labels for cables or switches.
Configure the application further if needed. Consult ``--help``.

Specify gondul credentials using environment variables
(``GONDUL_USERNAME``, ``GONDUL_PASSWORD``) or the command line
to fetch from Gondul. It's possible to specify the API root
or API endpoint to use.
Use ``--planning-input-file`` to read from a local file
which contains the output from `planning <../../planning>`_.

Specify the output file with the ``--outfile`` argument.

For cables, specify the number of uplinks (``--uplinks``),
copies (``--copies``) and when to split (``--split``)
the CSV files for the label printer. Supply APs to print
labels for them to, either by identifying the switch with ``--ap``
or by supplying a newline-separated file of switch identifiers
through ``--aps-file`` (e.g. ``33-1`` to add an AP to that switch).
