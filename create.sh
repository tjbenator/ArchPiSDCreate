#!/bin/bash
DISK=$1
STORAGE=$HOME/Downloads/ArchLinuxARM/

MIRROR=http://archlinuxarm.org/os/

R1IMAGE=ArchLinuxARM-rpi-latest.tar.gz
R1IMAGEMD5=ArchLinuxARM-rpi-latest.tar.gz.md5

R2IMAGE=ArchLinuxARM-rpi-2-latest.tar.gz
R2IMAGEMD5=ArchLinuxARM-rpi-2-latest.tar.gz.md5

###########################################

confirm () {
    read -r -p "${1:-Are you sure? [y/N]} " response
    case $response in
        [yY][eE][sS]|[yY]) 
            true
            ;;
        *)
            false
            ;;
    esac
}

#Check if all required programs are installed(useful for people running minimal systems)
hash parted &> /dev/null
if [ $? -eq 1 ]; then
  echo >&2 "Parted is not installed. Aborting!"
  exit $?
fi

hash mkfs.vfat &> /dev/null
if [ $? -eq 1 ]; then
    echo >&2 "Mkfs.vfat is not avalible. Aborting!"
    exit $?
fi

hash curl &> /dev/null
if [ $? -eq 1 ]; then
  echo >&2 "Curl is not installed. Aborting!"
  exit $?
fi

#Check if disk exists
if [ ! -e "$DISK" ]; then
  echo "The disk you specified does not exist"
  exit 1
fi

#Check if disk is mounted
if grep -qs '$DISK' /proc/mounts; then
    #Abort. We do not want to risk over writing a disk that is in use.
    echo "The disk you specified is currently mounted. Aborting! "
    exit 1
fi

#Create storage directory
if [ ! -d $STORAGE ]; then
   mkdir -p $STORAGE
fi

#Which Pi are we creating a SD card for?
PS3='Which Pi are you creating an SD for: '
options=("Pi" "Pi2" "Quit")
select opt in "${options[@]}"
do
    case $opt in
        Pi)
            IMAGE=$R1IMAGE
            IMAGEMD5SUM=$R1IMAGEMD5
            break
            ;;
        Pi2)
            IMAGE=$R2IMAGE
            IMAGEMD5SUM=$R2IMAGEMD5
            break
            ;;
        *) echo Invalid Entry. Please select a valid Pi;;
    esac
done

#We will update unless decided otherwise.
UPDATE=true

#Does the image exist on the disk?
if [ -f $STORAGE$IMAGE ]; then
  SERVERMD5=$(curl -skL $MIRROR$IMAGEMD5SUM | awk -F ' ' '{print $1}')
  LOCALMD5=$(md5sum $STORAGE$IMAGE | awk -F ' ' '{print $1}')

  #Do we have the current version?
  if [ "$LOCALMD5" = "$SERVERMD5" ]; then
    UPDATE=false
  fi
fi

#Update if required.
if $UPDATE; then
  echo "Selected image is out of date. Downloading the latest version..."
  curl -Lo $STORAGE$IMAGE $MIRROR$IMAGE
else
  echo "Selected image is up to date!"
fi

echo ""
echo "Here is the disk you are about to wipe:"
echo ""
fdisk -l "$DISK"

confirm "Are you sure you want to erase the above disk? [y/N]" || exit 1

echo "Partitioning disk..."

fdisk "$DISK" <<EOF > /dev/null 2>&1
o
p
n
p
1

+100M
t
c
n
p
2


w
EOF

echo "Refresh partition"
partprobe "${DISK}"

if grep -qs '${DISK}1' /proc/mounts; then
  umount "${DISK}1"
fi

if grep -qs '${DISK}2' /proc/mounts; then
  umount "${DISK}2"
fi

TEMPBOOT=/tmp/ArchPiSDCreate/boot
TEMPROOT=/tmp/ArchPiSDCreate/root

mkfs.vfat "${DISK}1"
mkfs.ext4 "${DISK}2"

mkdir -p "$TEMPBOOT"
mkdir -p "$TEMPROOT"

mount "${DISK}1" "$TEMPBOOT"
mount "${DISK}2" "$TEMPROOT"

bsdtar -xpf "$STORAGE$IMAGE" -C "$TEMPROOT"
echo "Syncing disk... (This may take a few minutes)"
sync

mv "$TEMPROOT"/boot/* "$TEMPBOOT"

#TODO:
# CHROOT in to our newly imaged SD Card
# Rename the alarm user
# Change the alarm user's password
# Move the alara user's home folder to reflect the name change
# Add public ssh key.
# Possibly install sudo and add alarm to the wheel group

#umount "$TEMPBOOT" "$TEMPROOT"
