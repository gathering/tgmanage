# TG16 Network Configuration

We've included some of the configs used in the network for TG16. Some of the configuration files contains `set` commands in addition to normal `show configuration` commands.

Comments for some of the files;
- **distro3_clean_generated.conf**: Contains set-commands for distro 3. This was untouched configwise for TG16 (except for removing BFD, which the config reflects).
- **distro5_after_l3_was_moved_to_edge.conf**: Contains set-commands, whith a list of new set-commands at the bottom used to reconfigure from L3 directly terminated to L3 being statically routed towards the edge switches.
- **ex2200.conf**: The template used to generate the configuration at the edge switches towards the participants. The variables inside would be substituted with real values when FAP made the config available for download for the specific config. Please note that this config is without first-hop-security, as that feature came later than Junos 12.3, as some of the EX2200-es ran that version.
- **ex2200_secure.conf**: Template identical to "ex2200.conf", except that first-hop-security has been added.
- **ex2200_secure_with_l3.conf**: Identical to "ex2200_secure.conf" file. The difference is that it contains the necessary set commands to terminate L3 directly at the edge switch, and not at the distro switch.

The rest of the files contains only "show configuration" output.

Best regards,
Jonas H. Lindstad
on behalf of The Gathering 2016 Tech:Net-crew.