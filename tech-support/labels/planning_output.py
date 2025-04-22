from gondul import _match_switches
from gondul import _sort_switches 

def read_planning_switches(path, match=None):
    lines = None
    with open(path) as f:
        lines = f.readlines()

    switches = []
    for line in lines:
        switches.append(line.split(" ")[0])

    switches = _match_switches(switches, match=match)
    return _sort_switches(switches)
