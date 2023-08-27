# ArgonONEforLibreelec

Control of fan speed an power button of the Argon ONE case for for Raspberry Pi running LibreELEC

The official script taht controls fan and power button in the caseAargon ONE for Raspberry Pi is not suitable por LibreELEC OS. There is a downloasd for Raspberry Pi hidden somewhere in the web server of Argon ONE makers, but it doesn't work.

This is a complete rework intended to be installed in the Rasperrry Pi running LibreELEC.

Prerequisites:
  1. Raspberri Pi 4.
  2. LibreELEC installed and running.
  3. Two addons installed from the LibreELEC repository in the Program Addons section:
      a) System tools
      b) Raspberry Pi Tools

Instructions:
  1. Enable SSH and SAMBA services (Setup > LibreELEC > Services)
  2. Download script file argonone-install-libreelec.sh 
  3. Upload script file to any directory in the Pi (I use /storage/.kodi/userdata/ArgonONE/ that is accesible through the samba server in the folder \\sarver>\Userdata)
  4. Open a ssh terminal to the PI and run the script.

Notes:
  1. You can configure the fan set points in file /storage/.config/argonone.d/argononed.conf (Samba file: \\<server>\Configfiles\argonone.d\argononed.conf)
  2. My Argon ONE V2 case does not generate the signal for the shutdown (pressing power button 3 to 4 seconds) so I have changed the double click action to shutdown (so there is no reboot posibility using the case button)
  3. As You can see, I spend my time coding, no writing nice readmes. Also, wrinting english is an effort to me. If you want to rewrite this readme, You will be welcomed.
