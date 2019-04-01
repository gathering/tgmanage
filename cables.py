from itertools import chain
import operator

from gondul import fetch_gondul_switches

cable_label_format = "%(switch_name)s-%(switch_num)s-%(cable_name)s"
mark_twice = True
num_tabs = 1



def generate_label(switch, cable_name):
    data = {
        "switch_name": switch.split("-")[0],
        "switch_num": switch.split("-")[1],
        "cable_name": cable_name,
    }
    label = cable_label_format % data
    if not mark_twice:
        return label

    return "{}{}{}".format(label, "\t" * num_tabs, label)


def generate_label_copies(switch, cable_name, copies=2):
    return [generate_label(switch, cable_name) for _ in range(0, copies)]


def generate_labels(switches, copies=2, uplinks=3):
    print("Generating {} copies of each label for {} uplinks for {} switches ({} labels)".format(
        copies, uplinks, len(switches), len(switches) * uplinks * copies))
    labels = list(map(lambda switch:
                      [generate_label_copies(switch[1:], i + 1, copies=copies)
                       for i in range(0, uplinks)],
                      switches))
    return list(chain.from_iterable(chain.from_iterable(labels)))


def write_to_file(data, outfile="cable_labels.csv", filenum=1):
    outfile_numbered = outfile.replace(".", "-{}.".format(filenum))

    with open(outfile_numbered, "w") as f:
        f.writelines("\n".join(data))


def chunk_list(li, items):
    for i in range(0, len(li), items):
        yield li[i:i+items]


def write_csv(data, outfile="cable_labels.csv", split_per_num=100):
    split_data = list(chunk_list(data, split_per_num))

    for i in range(0, len(split_data)):
        write_to_file(split_data[i], filenum=i+1)

    print("Wrote cable labels to {} files, starting from {}".format(
        len(split_data), outfile.replace(".", "-1.")))


def make_cable_labels(uplinks=3):
    print("Generating labels for cables")
    switches = fetch_gondul_switches()
    labels = generate_labels(switches, uplinks=uplinks)
    write_csv(labels)
