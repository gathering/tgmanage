import argparse
import sys

from cables import make_cable_labels
from gondul import fetch_gondul_switches
from switches import make_switch_labels
from planning_output import read_planning_switches

parser = argparse.ArgumentParser(
    "Label generator script 2000",
    formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("labler", type=str,
                    help="The label function to run. Either [c]ables or [s]witches.")
parser.add_argument("--gondul-user", type=str,
                    help="Gondul username. Overrides env GONDUL_USERNAME")
parser.add_argument("--gondul-pass", type=str,
                    help="Gondul password. Overrides env GONDUL_PASSWORD")
parser.add_argument("--gondul-api", type=str,
                    help="Gondul API base. Overrides env GONDUL_API")
parser.add_argument("--gondul-switches", type=str,
                    help="Gondul switches endpoint. Overrides env GONDUL_SWITCHES_ENDPOINT")
parser.add_argument("--match-switches", type=str, default="^e([0-9]+-[0-9]+)",
                    help="Regex for matching switches")
parser.add_argument("--outfile", "-o", type=str, default=None,
                    help="Output (base) file name. Might be appended with numbers for cables.")
parser.add_argument("--planning-input-file", type=str, help="Output file from planning, to use as input")

cables_args = parser.add_argument_group("cables")
cables_args.add_argument("--ap", type=str, action="append",
                         help="Name of a switch where an AP should be connected")
cables_args.add_argument("--aps-file", type=str,
                         help="Path to a newline-separated file with switches where an AP should be connected")
cables_args.add_argument("--copies", "-c", type=int, default=2,
                         help="Number of copies per label")
cables_args.add_argument("--uplinks", "-u", type=int, default=3,
                         help="Number of uplinks per switch")
cables_args.add_argument("--split", "-s", type=int, default=100,
                         help="Split into CSV files of this size")

if __name__ == "__main__":
    args = parser.parse_args()

    switches = None
    if args.planning_input_file:
        switches = read_planning_switches(args.planning_input_file, match=args.match_switches)
    else:
        switches = fetch_gondul_switches(
            api=args.gondul_api,
            endpoint=args.gondul_switches,
            username=args.gondul_user,
            password=args.gondul_pass,
            match=args.match_switches,
        )

    kwargs = {}
    if args.outfile is not None:
        kwargs['outfile'] = args.outfile

    if args.labler[0] == "c":
        make_cable_labels(switches,
                          aps=args.ap if args.ap is not None else [],
                          ap_file=args.aps_file,
                          copies=args.copies,
                          split_per_num=args.split,
                          **kwargs)
    elif args.labler[0] == "s":
        make_switch_labels(switches, **kwargs)
    else:
        parser.print_help()
        sys.exit("Invalid labler operation.")
