# myMPDos

myMPDos is my playground to create Raspberry Pi images (aarch64). The images are based on a minimal Alpine Linux image and a custom compiled MPD (latest master and latest stable release).

WARNING: THIS IS A HIGHLY EXPERIMENTAL VERSION

The `build.sh` script creates a qemu image, starts it and compiles myMPD and MPD. The resulting packages are integrated in a custom overlay for the default Alpine Linux Raspberry image.

## Usage

1. Create the image with `./build.sh`
2. Transfer the image to a sdcard
3. Optional edit wifi.txt to setup wlan
4. ssh to the raspberry (root password is blank)
5. Run mympd-os-config to setup the system


## Copyright
2020 <mail@jcgames.de>
