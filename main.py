import argparse
import sys

from cables import make_cable_labels
from gondul import fetch_gondul_switches
from switches import make_switch_labels

parser = argparse.ArgumentParser("Label generator script 2000")
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
parser.add_argument("--match-switches", type=str, default="^e(.*)",
                    help="Regex for matching switches")

if __name__ == "__main__":
    args = parser.parse_args()

    switches = fetch_gondul_switches(
        api=args.gondul_api,
        endpoint=args.gondul_switches,
        username=args.gondul_user,
        password=args.gondul_pass,
        match=args.match_switches,
    )

    if args.labler[0] == "c":
        make_cable_labels(switches)
    elif args.labler[0] == "s":
        make_switch_labels(switches)
    else:
        parser.print_help()
        sys.exit("Invalid labler operation.")
