~/decklink-sdk/Linux/Samples/bmdtools/bmdcapture $(
        echo '-C 0'                     # Decklink card number
        echo '-m 11'                    # Input format mode (ID 8 = 1080i/25)
        echo '-V 4'                     # Video input (4 = SDI)
        echo '-A 2'                     # Audio input (2 = Embedded)
        echo '-c 2'                     # Number of audio channels
        echo '-M 10'                    # Memory limit, in GB, for the output buffer (it leaks slightly...)
        echo '-F nut -f pipe:1'         # Output format and file name
) | \
ffmpeg $(
        echo '-y -re -i -'                                      # Input from pipe
        echo '-v verbose'                                       # Verbosity level
#       echo '-filter:v format=yuv420p,yadif=1:0:0'             # Video format conversion and deinterlacing
        echo '-filter:v scale=480x270'
        echo '-c:v libx264'                                     # Video encoder to use
        echo '-tune film -preset slow'                  # Video encoder options
        echo '-x264opts keyint=50:rc-lookahead=0'               # x264-specific options
#       echo '-b:v 1M'                                          # Video bitrate
        echo '-c:a libfaac'                                     # Audio encoder to use
        echo '-b:a 192k'                                        # Audio bitrate
        echo '-threads auto'                                    # Number of threads to use
        echo '-f mpegts udp://151.216.125.4:4013'   # Output format and file name
)

