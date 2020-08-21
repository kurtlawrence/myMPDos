#!/bin/bash
#
# SPDX-License-Identifier: GPL-2.0-or-later
# myMPD (c) 2020 Juergen Mang <mail@jcgames.de>
# https://github.com/jcorporation/myMPDos
#

source config || { echo "config not found"; exit 1; }

function check_deps()
{
  echo "Checking dependencies"
  for DEP in wget tar gzip cpio dd losetup sfdisk mkfs.vfat mkfs.ext4 sudo install sed patch
  do
    if ! command -v "$DEP" > /dev/null
    then
      echo "Tool $DEP not found"
      exit 1
    fi
  done
}

umount_retry() {
  if ! sudo umount "$1"
  then
    echo "Retrying in 2s"
    sleep 2
    sudo umount "$1" || return 1
  fi
  return 0
}

install_tmp() {
  if [ ! -f .mympdos-tmp ]
  then
    install -d tmp
    cd tmp || exit 1
    touch .mympdos-tmp
  fi
}

build_stage1()
{
  echo "myMPDos build stage 1: Download"
  if [ ! -f "$NETBOOT_ARCHIVE" ]
  then
    echo "Getting $NETBOOT_ARCHIVE"
    wget -q "${ALPINE_MIRROR}/v${ALPINE_MAJOR_VERSION}/releases/${ARCH}/$NETBOOT_ARCHIVE" \
      -O "$NETBOOT_ARCHIVE"
  fi
  if [ ! -d boot ]
  then
    install -d netboot
    if ! tar -xzf "$NETBOOT_ARCHIVE" -C netboot
    then
      echo "Can not extract $NETBOOT_ARCHIVE"
      exit 1
    fi
  fi

  if [ ! -f "$ARCHIVE" ]
  then
    echo "Getting $ARCHIVE"
    wget -q "${ALPINE_MIRROR}/v${ALPINE_MAJOR_VERSION}/releases/${ARCH}/$ARCHIVE" \
      -O "$ARCHIVE"
    if ! tar -tzf "$ARCHIVE" > /dev/null
    then
      echo "Can not extract $ARCHIVE"
      exit 1
    fi
  fi
}

build_stage2()
{
  echo "myMPDos build stage 2: Create build image"
  dd if=/dev/zero of="$BUILDIMAGE" bs=1M count="$IMAGESIZEBUILD"
  sfdisk "$BUILDIMAGE" <<< "1, ${BOOTPARTSIZEBUILD}, b, *"
  sfdisk -a "$BUILDIMAGE" <<< ","

  LOOP=$(sudo losetup --partscan --show -f "$BUILDIMAGE")
  [ "$LOOP" = "" ] && exit 1
  sudo mkfs.vfat "${LOOP}p1"
  sudo mkfs.ext4 "${LOOP}p2"
  install -d mnt
  sudo mount -ouid="$BUILDUSER" "${LOOP}p1" mnt || exit 1
  if ! tar -xzf "$ARCHIVE" -C mnt
  then
    echo "Extracting $ARCHIVE failed"
    exit 1
  fi
  cp netboot/boot/modloop-lts mnt/boot

  echo "Copy build scripts"
  install -d mnt/mympdos
  cp -r ../mympdos/build/* mnt/mympdos

  echo "Copy existing packages"
  install -d mnt/mympdos-apks
  if [ -f "../mympdos-apks/$ARCH/APKINDEX.tar.gz" ]
  then
    cp "../mympdos-apks/$ARCH/"*.apk mnt/mympdos-apks/
    cp "../mympdos-apks/$ARCH/APKINDEX.tar.gz" mnt/mympdos-apks/
  else
    echo "No existing packages found"
  fi
  if [ -f ../mympdos-apks/abuild.tgz ]
  then
    cp ../mympdos-apks/abuild.tgz mnt/mympdos/
  else
    echo "No saved abuild.tgz found"
  fi
  date +%s > mnt/date
  umount_retry mnt || exit 1
  sudo losetup -d "${LOOP}"

  echo "Patching initramfs"
  cd netboot || exit 1
  rm -f init
  gzip -dc boot/initramfs-lts | cpio -id init
  if ! patch init ../../mympdos/netboot/init.patch
  then
    echo "Patching netboot init failed"
    exit 1
  fi
  echo ./init | cpio -H newc -o | gzip >> boot/initramfs-lts
  cd .. || exit 1
}

build_stage3()
{
  echo "myMPDos build stage 3: Starting build"
  qemu-system-aarch64 \
    -M virt -m "$BUILDRAM" -cpu cortex-a57 -smp "$BUILDCPUS" \
    -kernel netboot/boot/vmlinuz-lts -initrd netboot/boot/initramfs-lts \
    -append "console=ttyAMA0 ip=dhcp" \
    -nographic \
    -drive "file=${BUILDIMAGE},format=raw" \
    -netdev user,id=mynet0,net=192.168.76.0/24,dhcpstart=192.168.76.9 \
    -nic user,id=mynet0
}

build_stage4()
{
  echo "myMPDos build stage 4: Saving packages"
  BACKUPDATE=$(stat -c"%Y" ../mympdos-apks)
  BACKUPDIR=../mympdos-apks.$(date -d@"$BACKUPDATE" +%Y%m%d_%H%M)
  [ -d ../mympdos-apks ] && mv ../mympdos-apks "$BACKUPDIR"
  install -d "../mympdos-apks/$ARCH"
  LOOP=$(sudo losetup --partscan --show -f "$BUILDIMAGE")
  sudo mount -text4 "${LOOP}p2" mnt || exit 1
  if [ -f mnt/build/abuild.tgz ]
  then
    cp mnt/build/abuild.tgz ../mympdos-apks/
  else
    echo "No abuild.tgz found"
  fi
  if [ -f "mnt/build/packages/package/${ARCH}/APKINDEX.tar.gz" ]
  then
    cp mnt/build/packages/package/"${ARCH}"/* "../mympdos-apks/$ARCH/"
  else
    echo "No APKINDEX.tar.gz found"
  fi
  umount_retry mnt || exit 1
  sudo losetup -d "${LOOP}"
}

build_stage5()
{
  echo "myMPDos build stage 5: Create image"
  dd if=/dev/zero of="$IMAGE" bs=1M count="$IMAGESIZE"
  sfdisk "$IMAGE" <<< "1, ${BOOTPARTSIZE}, b, *"

  LOOP=$(sudo losetup --partscan --show -f "$IMAGE")
  [ "$LOOP" = "" ] && exit 1
  sudo mkfs.vfat "${LOOP}p1"
  install -d mnt
  sudo mount -ouid="$BUILDUSER" "${LOOP}p1" mnt || exit 1
  if ! tar -xzf "$ARCHIVE" -C mnt
  then
    echo "Extracting $ARCHIVE failed"
    exit 1
  fi
  cd ../mympdos/overlay || exit 1
  if ! tar -czf ../../tmp/mnt/mympdos-bootstrap.apkovl.tar.gz .
  then
    echo "Creating overlay failed"
    exit 1
  fi
  cd ../../tmp || exit 1
  if [ "$PRIVATEIMAGE" = "true" ]
  then
    echo "Copy private bootstrap.txt"
    cp ../mympdos/bootstrap.txt mnt/
  else
    echo "Copy sample bootstrap.txt files"
    cp ../mympdos/bootstrap-*.txt mnt/
  fi
  echo "Setting version to $VERSION"
  echo "$VERSION" > mnt/myMPDos.version
  echo "Copy saved packages to image"
  install -d "mnt/mympdos-apks/$ARCH"
  if [ -f "../mympdos-apks/$ARCH/APKINDEX.tar.gz" ]
  then
    cp ../mympdos-apks/"$ARCH"/*.apk "mnt/mympdos-apks/$ARCH/"
    cp ../mympdos-apks/"$ARCH"/APKINDEX.tar.gz "mnt/mympdos-apks/$ARCH/"
    tar --wildcards -xzf ../mympdos-apks/abuild.tgz -C mnt/mympdos-apks ".abuild/*.rsa.pub"
  else
    echo "No myMPDos apks found"
  fi

  umount_retry mnt || exit 1
  sudo losetup -d "${LOOP}"
  install -d ../images
  mv "$IMAGE" ../images
  [ "$COMPRESSIMAGE" = "true" ] && gzip "../images/$IMAGE"

  echo ""
  echo "Image $IMAGE created successfully"
  if [ "$PRIVATEIMAGE" = "true" ]
  then
    echo ""
    echo "A productive bootstrap.txt was copied to the image."
    echo "Dont redistribute this image!"
    echo ""
  else
    echo ""
    echo "Next step is to burn the image to a sd-card and"
    echo "create the bootstrap.txt file."
    echo "There are samples in the image."
    echo ""
  fi
}

cleanup()
{
  umountbuild
  echo "Removing tmp"
  [ -f tmp/.mympdsos-tmp ] || exit 0
  rm -fr tmp
  echo "Removing old images"
  find ./images -name \*.img -mtime "$KEEPIMAGEDAYS" -delete
  find ./images -name \*.img.gz -mtime "$KEEPIMAGEDAYS" -delete
  echo "Removing old package directories"
  find ./ -maxdepth 1 -type d -name mympdos-apks.\* -mtime "$KEEPPACKAGEDAYS" -exec rm -rf {} \;
}

umountbuild() 
{
  echo "Umounting build environment"
  LOOPS=$(losetup | grep "myMPDos" | awk '{print $1}')
  for LOOP in $LOOPS
  do
    echo "Found dangling $LOOP"
    MOUNTS=$(mount | grep "$LOOP" | awk {'print $1}')
    for MOUNT in $MOUNTS
    do
      sudo umount "$MOUNT"
    done
  done
  LOOPS=$(losetup | grep "myMPDos" | awk '{print $1}')
  for LOOP in $LOOPS
  do
    sudo losetup -d "$LOOP"
  done
}

case "$2" in
  private)
    PRIVATEIMAGE="true";;
  *)
    PRIVATEIMAGE="false";;
esac

case "$1" in
  stage1)
    check_deps
    install_tmp
    build_stage1
    ;;
  stage2)
    check_deps
    install_tmp
    build_stage2
    ;;
  stage3)
    check_deps
    install_tmp
    build_stage3
    ;;
  stage4)
    check_deps
    install_tmp
    build_stage4
    ;;
  stage5)
    check_deps
    install_tmp
    build_stage5
    ;;
  build)
    check_deps
    install_tmp
    build_stage1
    build_stage2
    build_stage3
    build_stage4
    build_stage5
    ;;
  umountbuild)
    umountbuild;;
  cleanup)
    cleanup
    ;;
  *)
    echo "Usage: $0 (build|stage1|stage2|stage3|stage4|stage5|cleanup|umountbuild) [private|public]"
    echo ""
    echo "  build:        runs all stages"
    echo "  stage1:       downloads and extracts all needed sources"
    echo "  stage2:       creates a build environment"
    echo "  stage3:       starts the build image"
    echo "  stage4:       copies the packages from build into mympdos-apks"
    echo "  stage5:       creates the image"
    echo ""
    echo "  cleanup:      cleanup things"
    echo "  umountbuild:  removes dangling mounts and loop devices"
    echo ""
    echo "  private:      creates a image with a productive bootstrap.txt file"
    echo "  public:       creates a image with samble bootstrap.txt files (default)"
    echo ""
    ;;
esac

exit 0
