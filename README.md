# multitech-gateway-config

Copy [flash-upgrade](https://drive.google.com/drive/folders/1FPnVB3JWDk1xwo8Y4_Cs1f3adNat0rO1?usp=sharing) and installer.sh to the root directory of a FAT32 formatted MBR partitioned micro sd card

Remove front panel, insert SIM card and micro SD card, connect usb cable, connect cell and lora antenna, connect power

Open a terminal to serial device at 115200 baud

```screen /dev/tty.usbmodem148111 115200 -L```

Login with username: ```admin```, pw: ```admin```

Upgrade firmware

```touch /var/volatile/do_flash_upgrade```

```reboot```

Login again with username: ```root```, pw: ```root```

Run install script

```sh /media/card/installer.sh```

Add device EUI to LoRa Server, Hologram, and print a barcode label
