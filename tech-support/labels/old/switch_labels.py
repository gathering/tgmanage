#!/usr/bin/python
#coding: utf-8
#
#	@version: 0.1
#	@date:	19.04.2011
#
#	@description: A quick script to output a html page that prints 
#				  switch labels in the format: <row>-<switch> 
#				  i.e:  71-4. One label per page.   
#				
#				  NB! only makes odd number labels. 
#
#	@author:	technocake
#	Found at: 	blog.technocake.net
#--------------------------------------------

import sys

######################################
#	Configuration
######################################
rows 		= 84	#rows
switches 	= 4	#switches per row
outFile 	= "tg-switch-labels-print-me.html"


#### CREATIVIA ####
creative_rows		= 12
creative_prepend	= "C"


output = ""

# the top of the html page
def head():
        return """<!Doctype html>
<html> <head>
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
<body>
"""

#the bottom of the html page
def tail():
        return  "</body></html>" 

#ONE switch label
def a4(s ):
	return "<div class='a4'> %s </div>" % (s, )


def saveToFile(data, fileName):
	f = open(fileName, 'w+')
	f.write( data )
	f.close()

#	In python 3, raw_input is renamed to input. In python v <3. input does something else.
#	this function fixes that
def prompt(text):
        try:
                return raw_input(text)
        except:
                try:
                        return input(text)

                except:
                        exit()
	

###################################################
#	This is where the actual generating	takes place
###################################################	


if __name__ == "__main__":
	output += head() 


	#Generating all the labels for the switches
	for row in range(1, rows+1, 2):
		for SWITCH in range(1, switches+1):
			output += a4("%s-%s\n" % (row, SWITCH) ) 


	# Generating all the labels for the CREATIVE area
	for row in range(1, creative_rows+1):
		output += a4("%s-%s\n" % (creative_prepend, row))


			
	output += tail() 

	#	Taking it out to the big tg-world

	if len(sys.argv) > 1:	
		#Printing to stdout if second argument is passed to the script
		print ( output )
	else:
		saveToFile(output, outFile)	
		#normally, this is what happens. Saving it to a new html file


	print ( """ 
	Generated labels for %d switches per row and %d rows. \n
	The html file is in this folder, and is named %s \n
	Pages to print:  %d \n\n
	""" 
		% (switches, rows, outFile, (switches*rows)/2 + creative_rows)
	)
	
	prompt( "Press any key to exit...")