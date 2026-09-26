+++
title = "New PC"
author = ["YAMASHITA Takao"]
date = 2009-11-14T14:22:00+09:00
lastmod = 2026-09-26T22:31:32+09:00
tags = ["ISO-Image", "Gentoo", "LiveCD"]
categories = ["Tech"]
draft = false
+++

息子が iPod nano を買ったところ、今まで使っていたPCでは容量が足りなくなってしまったので、私のPCと交換することにした。交換後に私が使うのは EeePC 901-X という少し古めのUMPCなので、外付けディスクを Linux 用に割り当てて、Live CD 作成マシンとして活用することにした。

Live CD のイメージ作成には、以前は metro を使っていたのだけど、自分しか使わないものなので、もう少し手軽な方法に切り替えることにする。

パーティションレイアウトはこんな感じ。


## fdisk -l {#fdisk-l}

```sh
ディスク /dev/sdc: 160.0 GB, 160041885696 バイト
ヘッド 255, セクタ 63, シリンダ 19457
Units = シリンダ数 of 16065 * 512 = 8225280 バイト
ディスク識別子: 0x1b155f8d

デバイス ブート     始点        終点    ブロック   Id  システム
/dev/sdc1               1        9436    75794638+  83  Linux
/dev/sdc2            9437        9497      489982+  83  Linux
/dev/sdc3            9498       19457    80003700   83  Linux
```


## /etc/fstab {#etc-fstab}

```sh
/dev/sde1       /boot       ext3        noauto,noatime  1 2
/dev/mapper/root        /       ext4        noatime     0 1
/dev/mapper/swap    none        swap        sw      0 0
/dev/cdrom      /mnt/cdrom  auto        noauto,ro   0 0
/dev/fd0        /mnt/floppy auto        noauto      0 0
none    /proc/sys/fs/binfmt_misc    binfmt_misc defaults    0 0
/var/tmp/jail/portage   /usr/portage    none        bind,rw     0 0
/var/tmp/jail/local-portage /usr/local/portage  none        bind,rw     0 0
/var/tmp/jail/distfiles /usr/portage/distfiles  none        bind,rw     0 0
```


## Live CD の起動は Grub で行う {#live-cd-の起動は-grub-で行う}

```sh
# This is a sample grub.conf for use with Genkernel, per the Gentoo handbook
# http://www.gentoo.org/doc/en/handbook/handbook-x86.xml?part=1&chap=10#doc_chap2
# If you are not using Genkernel and you need help creating this file, you
# should consult the handbook. Alternatively, consult the grub.conf.sample that
# is included with the Grub documentation.

#color white/red black/red
#splashimage=/boot/splash.xpm.gz
splashimage=/boot/grub/bt4.xpm.gz

default 0
timeout 30
password --md5 $1$jBaL5/$pIpowSTX5ip2pDXllzSd90

title=Gentoo Linux (2.6.31-pentoo-r2)
root (hd0,0)
kernel /boot/kernel-genkernel-x86-2.6.31-pentoo-r2 root=/dev/ram0 \
       crypt_root=/dev/sdc3 \
       ramdisk=8192 quiet CONSOLE=/dev/tty1 \
       resume=swap:/dev/mapper/swap init=/linuxrc

initrd /boot/initramfs-genkernel-x86-2.6.31-pentoo-r2

# -- Backtrack4
title BT-4
root (hd0,0)
kernel /boot/bt4/vmlinuz  BOOT=casper boot=casper persistent rw quiet

initrd /boot/bt4/initrd.gz

title=USB stick Pentoo
root (hd0,0)
kernel /boot/kernel-genkernel-x86-2.6.31-pentoo-r2 root=/dev/ram0 \
    root=/dev/ram0 cdroot aufs \
    init=/linuxrc max_loop=256 nokeymap \
    looptype=squashfs loop=/image/root-20091113.squashfs

initrd /boot/initramfs-genkernel-x86-2.6.31-pentoo-r2

#title USB stick Pentoo
#root (hd0,0)
#kernel /boot/pentoo/pentoo \
#    root=/dev/ram0 cdroot aufs changes=/dev/sde2 \
#    init=/linuxrc max_loop=256 nokeymap \
#    looptype=squashfs loop=/pentoo/image-2009.squashfs
#initrd /boot/pentoo/pentoo.igz

#title USB stick Pentoo
#root (hd0,0)
#kernel /boot/kernel-genkernel-x86-2.6.29-pentoo-r2 \
#    root=/dev/ram0 cdroot aufs changes=/dev/sdc2 \
#    init=/linuxrc max_loop=256 nokeymap \
#    looptype=squashfs loop=/pentoo/image.squashfs
#
#initrd /boot/initramfs-genkernel-x86-2.6.29-pentoo-r2

title grub-install
lock
install (hd0,0)/boot/grub/stage1 d (hd0) (hd0,0)/boot/grub/stage2 p (hd0,0)/boot/grub/grub.conf

title Other Operating System - Microsoft Windows XP
lock
    rootnoverify (hd0,0)
    makeactive
    chainloader +1

# vim:ft=conf:
```


## Live CD の作成は chroot 環境で行う {#live-cd-の作成は-chroot-環境で行う}

-   [CHROOT環境設定](http://github.com/ac1965/config-ac1965/blob/master/etc/skel/script/in.sh)
-   [コンパイル用](http://github.com/ac1965/config-ac1965/blob/master/etc/skel/script/in.sh)
-   [CHROOT](http://github.com/ac1965/config-ac1965/blob/master/etc/skel/script/chroot.sh)
-   [MAKE ROOT-IMAGE](http://github.com/ac1965/config-ac1965/blob/master/etc/skel/script/mkrootimg.sh)

こんな感じで使っている。CHROOT は私の環境では "/var/tmp/jail/squashfs-root" にしている。

```sh
# ./in.sh
# cp chroot.sh ${CHROOT}/tmp
# chroot ${CHROOT} /tmp/chroot.sh
# ./out.sh
# ./mkrootimg.sh
```
