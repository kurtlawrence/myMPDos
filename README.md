# myMPDos

myMPDos is a Raspberry Pi image (aarch64) based on Alpine Linux. It is running entirely in RAM and it does not write to the SD-card unless you want to save settings. Therefore, myMPDos is very robust and you can simply pull the power without any risk of corruption of your SD card.

myMPDos is a turnkey music playback solution and is designed arround [MPD](https://www.musicpd.org/) and [myMPD](https://github.com/jcorporation/myMPD). After startup you can access the myMPD webinterface, copy music to the sdcard data partition or mount a music storage and enjoy your music.

WARNING: myMPDOS is currently in an early development stage. If it evolves I will add prebuild images.

## Building the image

The `build.sh` script creates a qemu image, starts it and compiles myMPD and MPD. The resulting packages are integrated in a custom overlay for the default Alpine Linux Raspberry image.

1. Create the image with `./build.sh`
2. Optionally run `./cleanup.sh` to cleanup things

## Usage

1. Transfer the image to a sdcard
2. Edit `mympd/bootstrap.txt`
3. Boot your Raspberry Pi

## Test

Qemu does not support a raspberry pi comptabile network interace.

- Run `./startimage.sh`

## Depedencies

- Qemu (qemu-system-aarch64)
- DHCP server in your network
- Working internet connection

## Copyright
2020 Juergen Mang <mail@jcgames.de>
