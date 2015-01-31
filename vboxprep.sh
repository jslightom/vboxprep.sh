#!/bin/bash 
########################################################################## 
# This script is designed to inject vboxPrep of the vbox image and setup. 
########################################################################## 

RSYNCPATH='IP ADDRESS::vbox/' 

######################################################### 
# Output usage if need be. 
######################################################### 
usage() 
{ 
	cat <<HERE 

Usage: ${0} imageName 
Examples: 
	${0} staff 
	${0} student 

Parameter Information: 
	imageNames: staff|student 

HERE 
	exit 0 
} 

######################################################### 
# Check for parameters. 
######################################################### 
# imageName 
if [ -z "${1}" ]; then 
	usage 
fi 
# Set variable RSYNCVM for settings injection path. 
echo "I: Parameter imageName passed." 
RSYNCVM="${RSYNCPATH}${1}/ /virtualbox/" 


######################################################### 
# This section is to mount and prep the vbox operations 
######################################################### 
# This will be the block device that has the label vbox. 
echo "I: Looking for virtualbox label." 
MOUNTDEV="$(blkid | grep virtualbox | awk -F: '{print $1}')" 
if [ -z "${MOUNTDEV}" ] 
then 
	echo "W: NO virtualbox PARTITION FOUND!" 
	echo "W: EXITING PROGRAM" 
	exit 0 
fi 

# If we are here we found a virtualbox partition label. 
echo "I: Potential virtualbox partition of: ${MOUNTDEV}" 

# Check for the mount point directory and take correct action. 
if [ -d '/virtualbox' ] 
then 
	echo "I: The /virtualbox directory exists." 
else 
	echo "I: Making the /virtualbox directory." 
	mkdir -p /virtualbox 
fi 

echo "I: Attempting to mount virtualbox partition and perform system prep." 
mount -v ${MOUNTDEV} /virtualbox 
if [ $? -eq 0 ] 
then 
	echo "I: It appears that we did mount the virtualbox partition on /virtualbox ." 
	######################################### 
	# Start the install of the vbox files 
	echo "I: Starting to rsync of ${RSYNCVM}." 
	rsync -av --delete ${RSYNCVM} 
else 
	echo "W:  FAILED TO MOUNT THE virtualbox PARTITION." 
	echo "W:  EXITING PROGRAM" 
	exit 0 
fi 

######################################################### 
# This section is to mount and prep the Firmware partition 
######################################################### 
# We will get the first partition of the block device. 
echo "Looking for firmware partition." 
MOUNTDEV="$(fdisk -l | grep da1 | awk '{print $1}')" 
if [ -z "${MOUNTDEV}" ] 
then 
	echo "W:  NO FIRMWARE PARTITION FOUND!" 
	echo "W:  EXITING PROGRAM" 
	exit 0 
fi 

# If we are here we found believe to have a firmware partition. 
echo "Potential firmware partition of: ${MOUNTDEV}" 
 
# Check for the mount point directory and take correct action. 
if [ -d '/firmware' ] 
then 
	echo "I: The /firmware directory exists." 
else 
	echo "I: Making the /firmware directory." 
	mkdir -p /firmware 
fi 

echo "I: Attempting to mount firmware partition and perform a few system prep steps." 
mount -v ${MOUNTDEV} /firmware 
if [ $? -eq 0 ] 
then 
	echo "I: It appears that we did mount the firmware partition on /firmware ." 
	######################################################### 
	# extlinux work here. 
	echo "I: Backup original linux.cfg ." 
	cp /firmware/boot/extlinux/linux.cfg /firmware/boot/extlinux/linux.cfg.old 
	echo "I: Copy /virtualbox/extlinux/linux.cfg to /firmware/boot/extlinux/" 
	cp /virtualbox/extlinux/linux.cfg /firmware/boot/extlinux/linux.cfg 

	######################################################### 
	# manual inject 900-virtualbox here. 
	echo "I: Copy /virtualbox/900-virtualbox to /firmware/lib/live/config/" 
	cp /virtualbox/900-virtualbox /firmware/lib/live/config/ 

	######################################################### 
	# This section is to prep the /usr/lib/virtualbox/Extensions 
	echo "I: Updating Virtualbox Extensions." 
	rsync -av /virtualbox/ExtensionPacks /firmware/usr/lib/virtualbox/ 

	######################################################### 
	# This section is to prep /etc/apt 
	echo "I: Updating /etc/apt on firmware." 
	rsync -av /virtualbox/apt/ /firmware/etc/apt/ 

	######################################################### 
	# This section is to prep /home/user/.VirtualBox 
	echo "I: Installing /home/user/.VirtualBox ." 
	rsync -av /virtualbox/.VirtualBox /home/user/ 
	chown user: -R /home/user/.VirtualBox 

	######################################################### 
	# Mount some things so we can act like a real install. 
	echo "I: Mounting for chroot update." 
	mount --bind /dev /firmware/dev 
	mount --bind /proc /firmware/proc 
	mount --bind /sys /firmware/sys 
	mount --bind /dev/pts /firmware/dev/pts 

	######################################################### 
	# Do an apt-get update with new /etc/apt configs. 
	echo "I: Running apt-get update." 
	chroot /firmware apt-get update 
	echo "I: Remove virtualbox-dkms." 
	chroot /firmware apt-get -y remove virtualbox-dkms 
	# preseed.cfg not working correctly so just stack in here. 
	#chroot /firmware apt-get -y install virtualbox-dkms stalonetray metacity 
	# 20120918 Adding ntp to list of tools for date and time. 
	chroot /firmware apt-get -y install virtualbox-dkms stalonetray metacity ntp 

	######################################################### 
	# UMount some things. 
	echo "I: Unmounting for chroot update." 
	umount -l /firmware/dev 
	umount -l /firmware/proc 
	umount -l /firmware/sys 
	umount -l /firmware/dev/pts 

	######################################################### 
	# This section is to prep /etc/fstab 
	echo "I: Removing any /dev/sdb1 entries from /firmware/etc/fstab." 
	sed "/\/dev\/sdb1*/d" /firmware/etc/fstab > /firmware/etc/fstab.tmp 
	mv /firmware/etc/fstab.tmp /firmware/etc/fstab 

	######################################################### 
	# Add an entry to /etc/fstab for usb things 
	# FIXME Only need to do it once so test for usb entry. 
	#echo "I: Making backup of /firmware/etc/fstab" 
	#cp /firmware/etc/fstab /firmware/etc/fstab.orig 
	#echo "I: Adding entry to /firmware/etc/fstab for vboxusers" 
	#VBOXGID=$(grep vboxusers /etc/group | awk -F: '{print $3}') 
	#echo "none /proc/bus/usb usbfs devgid=${VBOXGID},devmode=664 0 0" \
	# >> /firmware/etc/fstab 

	######################################################### 
	# all done so umount 
	echo "I: Unmount the /firmware partition." 
	cd 
	umount /firmware 
else 
	echo "W:  FAILED TO MOUNT THE FIRMWARE PARTITION." 
	echo "W:  EXITING PROGRAM" 
	exit 0 
fi 

######################################### 
# Unmount the /virtualbox mount. 
echo "I: Unmount the /virtualbox partition." 
cd 
umount /virtualbox 


# If we get here all done. 
echo "I: All finished now with VBox Sysprep exiting script!" 
exit 0 
