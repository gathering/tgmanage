#!/usr/bin/env python3
 
'''
    Parse the exported table of tg23-koblingsplan (copypaste via libreoffice -> save as csv (standard values everywhere)) into a sensible yaml file
    Will handle merged cells (e.g. keep previous iterations value if current iteration is empty)
'''
 
import csv
import yaml
 
# Holds all data. List of objects, each object represents a row in the table
dataset = []

with open('tg23-koblingsplan.csv', newline='') as csvfile:
    csv_data = csv.reader(csvfile, delimiter=',', quotechar='"')
 
    # for loop counter
    i = 0
 
    # Holds the data from the current iteration
    current_iteration = {}
 
    for row in csv_data:
        i += 1
        # skip first 2 lines, they only contain table headers
        if i <= 2:
            continue
 
        # To be able to access previous iteration fields, so we can handle merged cells
        prev_iteration = current_iteration.copy()
 
        # The not-so-delicate blob of code for assigning data to object keys
        current_iteration = {}
        a = {}
        b = {}

        a['type'] = row[0] if len(row[0].strip()) > 0 else prev_iteration['a']['type']
        a['model'] = row[1] if len(row[1].strip()) > 0 else prev_iteration['a']['model']
        a['node'] = row[2] if len(row[2].strip()) > 0 else prev_iteration['a']['node']
        a['interface'] = row[3].strip() if len(row[3].strip()) > 0 else prev_iteration['a']['interface']
        a['ae'] = row[4] if len(row[4].strip()) > 0 else prev_iteration['a']['ae']
        b['type'] = row[5] if len(row[5].strip()) > 0 else prev_iteration['b']['type']
        b['model'] = row[6] if len(row[6].strip()) > 0 else prev_iteration['b']['model']
        b['node'] = row[7] if len(row[7].strip()) > 0 else prev_iteration['b']['node']
        b['interface'] = row[8].strip() if len(row[8].strip()) > 0 else prev_iteration['b']['interface']
        b['ae'] = row[9] if len(row[9].strip()) > 0 else prev_iteration['b']['ae']

        current_iteration['a'] = a
        current_iteration['b'] = b
        current_iteration['cable_type'] = row[10] if len(row[10].strip()) > 0 else prev_iteration['cable_type']

        # strip trailing data from interface sections and put it in a description field
        if (if_data := current_iteration['a']['interface'].split(" ")) and len(if_data) > 1:
            current_iteration['a']['interface_description'] = " ".join(if_data[1:])
            current_iteration['a']['interface'] = if_data[0]
        if (if_data := current_iteration['b']['interface'].split(" ")) and len(if_data) > 1:
            current_iteration['b']['interface_description'] = " ".join(if_data[1:])
            current_iteration['b']['interface'] = if_data[0]

        # strip trailing data from node sections and put it in a description field
        if (if_data := current_iteration['a']['node'].split(" ")) and len(if_data) > 1:
            current_iteration['a']['node_description'] = " ".join(if_data[1:])
            current_iteration['a']['node'] = if_data[0]
        if (if_data := current_iteration['b']['node'].split(" ")) and len(if_data) > 1:
            current_iteration['b']['node_description'] = " ".join(if_data[1:])
            current_iteration['b']['node'] = if_data[0]

        # replace multi-device with single device
        if " x " in current_iteration['a']['model'].lower():
            current_iteration['a']['model'] = current_iteration['a']['model'].split(' ')[-1]
        if " x " in current_iteration['b']['model'].lower():
            current_iteration['b']['model'] = current_iteration['b']['model'].split(' ')[-1]

        dataset.append(current_iteration)
 
with open('tg23-koblingsplan.yml', 'w') as f:
    f.write(yaml.dump(dataset, default_flow_style=False, sort_keys=False, allow_unicode=True))
