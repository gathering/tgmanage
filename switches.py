switch_label_format = "%(switch_name)s-%(switch_num)s"
switch_label_layout = """<!DOCTYPE html>
<html><head>
    <style>
        div.a4 {
            font-size: 24em;
            text-align: center;
            @page size: A4 landscape;

            /* this is the part that makes each div print per page. */
            page-break-after: always;
        }
    </style>
</head>
<body>%s</body></html>
"""
switch_label_page = '<div class="a4">%s</div>'


def generate_label(switch_name, switch_number):
    return switch_label_page % switch_label_format % {
        "switch_name": switch_name,
        "switch_num": switch_number,
    }


def generate_labels(switches):
    labels = list(map(lambda switch: generate_label(
        switch[1:].split("-")[0], switch.split("-")[1]), switches))

    return switch_label_layout % "".join(labels)


def write_html_to_file(html, outfile="switch_labels.html"):
    with open(outfile, "w") as f:
        f.write(html)
    print("Wrote labels to '{}'.\nOpen the file in your browser and print it.".format(outfile))


def make_switch_labels(switches, outfile="switch_labels.html"):
    print("Generating labels for switches")
    labels = generate_labels(switches)
    write_html_to_file(labels, outfile=outfile)
