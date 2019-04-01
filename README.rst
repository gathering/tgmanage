TG label scripts
================

Scripts.

Usage
-----

The ``--help`` parameter is pretty helpful.

Run the script with either ``cables`` or ``switches``,
depending if you want labels for cables or switches.
Configure the application further if needed. Consult ``--help``.

Specify gondul credentials either using environment variables
(``GONDUL_USERNAME``, ``GONDUL_PASSWORD``) or the command line.
It's also possible to update the API root or API endpoint to use,
as well as a regex for matching switches.

Specify the output file with the ``--outfile`` argument.

For cables, specify the number of uplinks (``--uplinks``),
copies (``--copies``) and when to split (``--split``)
the CSV files for the label printer. Supply APs to print
labels for them to, either by identifying the switch with ``--ap``
or by supplying a newline-separated file of switch identifiers
through ``--aps-file`` (e.g. ``33-1`` to add an AP to that switch).
