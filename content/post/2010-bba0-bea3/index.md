+++
title = "Xorg"
author = ["YAMASHITA Takao"]
date = 2010-06-01T07:39:00+09:00
lastmod = 2026-09-25T16:30:44+09:00
tags = ["Xorg"]
categories = ["Tech"]
draft = false
+++

GuruPlug がなかなか届かないので、待っている間に Funtoo と xorg-1.8 まわりを整理してみた。


## boot-update {#boot-update}

grubの設定を助けてくれるツールのようだ。[boot-update](http://www.funtoo.org/en/funtoo/core/boot/) というもので、grub-1.97+を試してみたけれど、multiboot にはまだきちんと対応していないみたい。/etc/boot.conf に次のように書いておいて \`boot-update\` と打つだけで済むので楽ではあるものの、"Backtrack 4" のほうは利用側の root-fs が無理やり埋め込まれてしまっているので、少し手直しが必要になる。/boot/grub/grub.cfg を手で修正すれば大丈夫。

```sh
boot {
    path /boot
    generate grub
    default "Funtoo Linux"
    timeout 3
}

"Funtoo Linux" {
    kernel /kernel-genkernel-x86[-v]
    initrd initramfs-genkernel-x86[-v]
    params += crypt_root=/dev/sdc2 root_keydev=/dev/sde1 root_key=/keyfile
    params += dolvm real_root=/dev/mapper/LVG-root
    params += i915.modeset=1 fbcon=map:1
    params += ramdisk=8192 quiet init=/linuxrc
}

"Backtrack 4" {
    kernel /bt4/vmlinuz
    initrd /bt4/initrd.gz
    params += BOOT=casper boot=casper persistent rw quiet
    params += real_root=auto
}
```


## xorg-1.8 {#xorg-1.8}

しばらく放置していたので、そろそろと思い試してみることにした。


### MASKを外す {#maskを外す}

```sh
echo 'x11-base/xorg-server' >> /etc/portage/package.unmask
echo 'x11-base/xorg-server * ~* **' >> /etc/portage/package.keywords/x11-base
```


## emege xorg-server {#emege-xorg-server}

USE="udev -hal" で emerge してみたところ、キーボードとマウスが認識されなくなってしまった。ある程度予想はしていたので、sshd を立ち上げておいて、別端末から pkill して対処した。

参考：[こちらの記事](http://body0r.wordpress.com/2010/04/16/xorg-udev-toggle/)


## emerge udev {#emerge-udev}

MASKを外して、udev をアップデートする。

```sh
echo 'sys-fs/udev' >> /etc/portage/package.unmask
echo 'sys-fs/udev * ~* **' >> /etc/portage/package.keywords/sys-fs
emerge -u udev
```


## udevルールの追加 {#udevルールの追加}

/usr/share/X11/xorg.conf.d がシステム設定になっているので、/etc/X11/xorg.conf.d 側にキーボードとマウスの設定を追加しておく。

これで無事解決。

```sh
# cat /etc/X11/xorg.conf.d/10-keyboard.conf
Section "InputClass"
        Identifier "Keyboard"
        Driver "evdev"
        MatchIsKeyboard "on"
        Option "xkbmodel" "jp106"
        Option "xkblayout" "jp"
EndSection

# cat /etc/X11/xorg.conf.d/20-synaptics.conf
Section "InputClass"
    Identifier "Touchpad"
    Driver "synaptics"
    MatchIsTouchpad "on"
    Option "SHMConfig" "true"
    Option "MinSpeed" "0.20"
    Option "MaxSpeed" "0.60"
    Option "AccelFactor" "0.020"
    Option "HorizEdgeScroll" "true"
    Option "HorizScrollDelta" "100"
    Option "VertEdgeScroll" "true"
    Option "VertScrollDelta" "100"
    Option "TapButton1" "1"
EndSection
```
