***************************************************************************
*                                                                         *
*         Windows Change Password / Registry Editor / Boot CD             *
*                                                                         *
*  (c) 1998-2014 Petter Nordahl-Hagen. Distributed under GNU GPL v2       *
*                                                                         *
* DISCLAIMER: THIS SOFTWARE COMES WITH ABSOLUTELY NO WARRANTIES!          *
*             THE AUTHOR CAN NOT BE HELD RESPONSIBLE FOR ANY DAMAGE       *
*             CAUSED BY THE (MIS)USE OF THIS SOFTWARE                     *
*                                                                         *
* More info at: http://pogostick.net/~pnh/ntpasswd/                       *
* Email       : pnh@pogostick.net                                         *
***************************************************************************

Just boot this CD and follow instructions.
Usually, just pressing return/enter should work, except some
drivers may have to be loaded manually with the 'm' menu option after boot.

 ---

The password reset and registry edit has now been tested with the following:

NT 3.51, NT 4, Windows 2000, Windows XP, Windows 2003 Server,
Vista, Windows 7, Server 2008, Windows 8, Windows 8.1, Server 2012

As far as I know, it will work with all Service Packs (SP) and
all editions (Professional, Server, Home etc)
Also, 64 bit windows versions shold be OK.

 ---

To make a bootable USB drive / key:

1. Copy all files from this CD onto the USB drive.
   It cannot be in a subdirectory on the drive.
   You do not need delete files already on the drive.
2. Install the bootloader
   On the USB drive, there should now be a file "syslinux.exe".
   Start a command line window (cmd.exe) with "run as administrator"
   From the command line, run the command like this:


	j:\syslinux.exe -ma j:

replace j with some other letter if your USB drive is on another
drive letter than j:
On some drives, you may have to omit the -ma option if you
get an error.
If it says nothing, it probably did install the bootloader.

Please note that you may have to adjust settings in your computers BIOS
setup to boot from USB.
Also, some BIOS (often older machines) simply won't boot from USB anyway.
Unfortunately, there are extremely many different versions of BIOS,
and a lot of them are rather buggy when it comes to booting off different
media, so I am unable to help you.


