import argparse
import sys

from switches import make_switch_labels
from cables import make_cable_labels

parser = argparse.ArgumentParser("Label generator script 2000")
parser.add_argument("labler", type=str,
                    help="The label function to run. Either [c]ables or [s]witches.")

if __name__ == "__main__":
    args = parser.parse_args()

    if args.labler[0] == "c":
        make_cable_labels()
    elif args.labler[0] == "s":
        make_switch_labels()
    else:
        parser.print_help()
        sys.exit("Invalid labler operation.")
