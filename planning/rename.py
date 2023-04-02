# Rename switches in a planning output file
# num is how many numbers to move as a whole, skips is to skip a subsection (in addition to num)
def rename_switches_in_file(filename, num=14, skips=[]):   
    lines = []
    with open(filename, 'r') as f:
        lines = f.readlines()

    for i, line in enumerate(lines):
        switch = line.split()[0]
        switch_num = switch.split('-')[1]
        switch_row_num = int(switch.split('-')[0].split('e')[1])

        _switch_row_num_original = switch_row_num
        for skip in skips:
            if _switch_row_num_original >= skip:
                switch_row_num -= 2
            print(f"{_switch_row_num_original} skip? vs. {skip} new: {switch_row_num}")
        if _switch_row_num_original != switch_row_num:
            switch_row_num -= 2

        new_switch_num = switch_row_num - num
        new_switch = f"e{new_switch_num}-{switch_num}"
        new_line = f"{new_switch} " + " ".join(line.split()[1:])
        lines[i] = f"{new_line}\n"
        print(f"renamed {switch} -> {new_switch}")

    with open(filename, 'w') as f:
        f.writelines(lines)


if __name__ == "__main__":
    rename_switches_in_file('./switches.txt', num=14, skips=[25, 27, 29, 31])
    rename_switches_in_file('./patchlist.txt', num=14, skips=[25, 27, 29, 31])
    rename_switches_in_file('./patchlist.txt.distrosort', num=14, skips=[25, 27, 29, 31])
