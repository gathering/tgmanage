#!/usr/bin/env python3
 
'''
    Parse the exported table of tg23-koblingsplan (copypaste via libreoffice -> save as csv (standard values everywhere)) into a sensible yaml file
    Will handle merged cells (e.g. keep previous iterations value if current iteration is empty)
'''
 
import csv
import yaml
 
with open('tg23-koblingsplan.csv', newline='') as csvfile:
    csv_data = csv.reader(csvfile, delimiter=',', quotechar='"')
 
    # for loop counter
    i = 0
 
    # Holds the data from the current iteration
    current_iteration = {}
 
    # Holds all data. List of objects, each object represents a row in the table
    dataset = []
 
    for row in csv_data:
        i += 1
        # skip first 2 lines, they only contain table headers
        if i <= 2:
            continue
 
        # To be able to access previous iteration fields, so we can handle merged cells
        prev_iteration = current_iteration.copy()
 
        # The not-so-delicate blob of code for assigning data to object keys
        current_iteration = {}
        current_iteration['a_type'] = row[0] if len(row[0].strip()) > 0 else prev_iteration['a_type']
        current_iteration['a_model'] = row[1] if len(row[1].strip()) > 0 else prev_iteration['a_model']
        current_iteration['a_node'] = row[2] if len(row[2].strip()) > 0 else prev_iteration['a_node']
        current_iteration['a_interface'] = row[3].strip() if len(row[3].strip()) > 0 else prev_iteration['a_interface']
        current_iteration['a_ae'] = row[4] if len(row[4].strip()) > 0 else prev_iteration['a_ae']
        current_iteration['b_type'] = row[5] if len(row[5].strip()) > 0 else prev_iteration['b_type']
        current_iteration['b_model'] = row[6] if len(row[6].strip()) > 0 else prev_iteration['b_model']
        current_iteration['b_node'] = row[7] if len(row[7].strip()) > 0 else prev_iteration['b_node']
        current_iteration['b_interface'] = row[8].strip() if len(row[8].strip()) > 0 else prev_iteration['b_interface']
        current_iteration['b_ae'] = row[9] if len(row[9].strip()) > 0 else prev_iteration['b_ae']
        current_iteration['cable_type'] = row[10] if len(row[10].strip()) > 0 else prev_iteration['cable_type']
        dataset.append(current_iteration)
 
    print(yaml.dump(dataset, default_flow_style=False, sort_keys=False))
