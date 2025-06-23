
sudo apt update
sudo apt install build-essential lzop u-boot-tools net-tools bison flex libssl-dev libncurses5-dev libncursesw5-dev unzip chrpath xz-utils minicom wget git-core

# replace the compiler download with installing the one from debian (this ends up using gcc13, much newer than the gcc7.5 in the class)
sudo apt install gcc-arm-linux-gnueabihf


#STEP 0
git clone https://github.com/beagleboard/linux.git sources/linux_bbb
# from the linux_bbb folder
# I'm using the latest (2025) BBB drop that has debian 12.11 and uses 6.12 kernel, I use this instead of the 5.x kernel.
git switch v6.12.24-ti-arm64-r41


make ARCH=arm distclean

make ARCH=arm omap2plus_defconfig

# I did not run/verify this one
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- menuconfig

make -j 12 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- LOADADDR=0x80008000 uImage dtbs
make -j 12 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- modules
sudo make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- modules_install

# attaching SD card directly to VirtualBox
# copying new kernel to SD card BOOT partition, from linux_bbb folder
mv /media/sharif/BOOT/uImage /media/sharif/BOOT/uImage_4.4.62
mv /media/sharif/BOOT/am335x-boneblack.dtb /media/sharif/BOOT/am335x-boneblack_old.dtb

cp arch/arm/boot/uImage /media/sharif/BOOT/
cp arch/arm/boot/dts/ti/omap/am335x-boneblack.dtb /media/sharif/BOOT/
sync

# copy kernel modules to ROOTFS partition
sudo cp -a /lib/modules/6.12.24-g33d950e8d86d/ /media/sharif/ROOTFS/lib/modules/
sync

# did not mess with internet tethering... plugged beagleboard into home router via ethernet

# building loadable module for host, from the /custom_drivers/001hello_world/ folder
make host
sudo insmod main.ko
sudo dmesg
sudo rmmod main.ko
sudo dmesg

# comment out the KERN_DIR definition in the existing Makefile, then
make KERN_DIR=../../sources/linux_bbb/ clean

# building loadable module for target, from the /custom_drivers/001hello_world/ folder
make KERN_DIR=../../sources/linux_bbb/
file main.ko
modinfo main.ko

# copying to BBB, attach to BBB usb to VirtualBox, check that ubuntu sees both 6.2 and 7.2 ip addresses.
# on target
mkdir drivers
# on host
scp main.ko debian@192.168.7.2:/home/debian/drivers/
# back on target
sudo insmod drivers/main.ko
sudo rmmod main.ko

//in-tree compilation
# from root folder
cp -a custom_drivers/001hello_world/ sources/linux_bbb/drivers/char/

# command and contents for Kconfig
nano sources/linux_bbb/drivers/char/001hello_world/Kconfig
# contents
menu "001 Hello World"
    config CUSTOM_HELLOWORLD
        tristate "001 hello world module support"
        default m
endmenu

# command and contents for Makefile
nano sources/linux_bbb/drivers/char/001hello_world/Makefile
# contents
obj-$(CONFIG_CUSTOM_HELLOWORLD) += main.o

# command and contents for /char/Kconfig
nano sources/linux_bbb/drivers/char/Kconfig
# contents
source "drivers/char/001hello_world/Kconfig"

# command and contents for /char/Makefile
nano sources/linux_bbb/drivers/char/Makefile
# contents
obj-y                           += 001hello_world/

# run and verify the menuconfig stuff
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- menuconfig
cat .config | grep CUSTOM

# build the module in-tree
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- modules

# I ran into problems here and had to dist-clean and start over, this speeds things up significantly
# I think the issue was using the terminal in vscode vs native linux terminal
alias arm-make='make -j 12 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-'
arm-make omap2plus_defconfig uImage dtbs modules LOADADDR=0x80008000

# PCD driver: mostly follow the lectures
# Watch all of chapter 3 & 4, then just used the final version of the driver.
# Note: class_create() proto in kernel 6.x has changed! only one arg, so updated the driver source.
# on host, from /custom_drivers/002pseudo_char_driver/
make
scp pcd.ko debian@192.168.7.2:/home/debian/drivers/
# on target
sudo -s
insmod drivers/pcd.ko
echo "Test!" > /dev/pcd
cat /dev/pcd
rmmod drivers/pcd.ko

# should be able to read/write to the char device and see all the output.

# PCD_n driver, needs same changes to compile cleanly and same update to makefile.
# on host, from /custom_drivers/003pseudo_char_driver/
make
scp pcd_n.ko debian@192.168.7.2:/home/debian/drivers/
# on target
# if not already in sudo mode
sudo -s
insmod drivers/pcd_n.ko
ls -l /dev/pcdev-*
# notice the perms in fs are still showing as rw ??! hmm...
echo "test write" > /dev/pcdev-1
# however this does fail the open as intended.
# i needed to install strace on the target.
apt install strace
# this is testing on the target, so use a different input file that exists
# write to dev 1
strace dd if=/etc/sysctl.conf of=/dev/pcdev-1

# write to dev 2
dd if=/etc/sysctl.conf of=/dev/pcdev-2
dd if=/etc/sysctl.conf of=/dev/pcdev-2 count=1
# read from dev 2
dd if=/dev/pcdev-2 of=file.txt

# write to dev 3
dd if=/etc/sysctl.conf of=/dev/pcdev-3 count=1 bs=100
cat /dev/pcdev-3

# compile dev_read.c for target and scp to target
# on host, from /custom_drivers/003pseudo_char_driver/ 
arm-linux-gnueabihf-gcc dev_read.c -o dev_read
file dev_read
scp dev_read debian@192.168.7.2:/home/debian/

# back to target
file dev_read
cat /etc/sysctl.conf > /dev/pcdev-3
./dev_read /dev/pcdev-3 10
./dev_read /dev/pcdev-3 10000


# Section 6. Platform drivers
# Fixed the typical kernel 5 -> 6 issues, and found a function signature mismatch that was updated to return void() on destroy.
# on the host, from the 004_pcd_platform_driver/ folder
make host
sudo -s
dmesg -C
insmod pcd_device_setup.ko
dmesg
ls -l /sys/devices/platform/
rmmod pcd_device_setup
dmesg
insmod pcd_platform_driver.ko
dmesg
insmod pcd_device_setup.ko
dmesg
# should see all the probe calls and pulling in the specific device versions and their configuration parameters.
rmmod pcd_device_setup
rmmod pcd_platform_driver


