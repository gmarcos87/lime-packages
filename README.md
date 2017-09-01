[![travis](https://api.travis-ci.org/libremesh/lime-packages.svg?branch=develop)](https://travis-ci.org/libremesh/lime-packages)
[![tip for next commit](http://tip4commit.com/projects/804.svg)](http://tip4commit.com/projects/804)

# [LibreMesh][5] packages "Dayboot Relay" release (17.06)

[![LibreMesh logo](https://raw.githubusercontent.com/libremesh/lime-web/master/logo/logo.png)](http://libremesh.org)
[![FOSSA Status](https://app.fossa.io/api/projects/git%2Bhttps%3A%2F%2Fgithub.com%2Fgmarcos87%2Flime-packages.svg?type=shield)](https://app.fossa.io/projects/git%2Bhttps%3A%2F%2Fgithub.com%2Fgmarcos87%2Flime-packages?ref=badge_shield)

[LibreMesh project][5] includes the development of several tools used for deploying libre/free mesh networks.

The firmware (the main piece) will allow simple deployment of auto-configurable, yet versatile, multi-radio mesh networks. Check the [Network Architecture][4] to see the basic ideas.

## Download Precompiled Binaries

This is the easiest way to first test and install LibreMesh in your router.

You can download a firmware image with **generic configuration** of the last **release** at [downloads][9] subdomain.

## Customize and Download a Firmware Image Using Chef

We encourage each network community to create its firmware profile on our own web application [Chef][10]. It generates and delivers **customized firmware images** (for example custom ESSID, IP range, additional packets or scripts...). 

## Building a Firmware Image on Your PC

The LibreMesh firmware can be compiled either using the easy to use [lime-sdk][2] tool or manually adding the feed to a [OpenWrt buildroot][1] environment.

### Using lime-build

Refer to [lime-build][2] README.

### Using OpenWrt buildroot

Clone LEDE stable repository, nowadays is version 17.01 (Reboot).

    git clone -b lede-17.01 https://git.lede-project.org/source.git lede
    cd lede

Add lime-packages, libremap and lime-ui-ng feeds to the default ones.

    cp feeds.conf.default feeds.conf
    echo "src-git libremesh https://github.com/libremesh/lime-packages.git" >> feeds.conf
    echo "src-git libremap https://github.com/libremap/libremap-agent-openwrt.git" >> feeds.conf
    echo "src-git limeui https://github.com/libremesh/lime-ui-ng.git" >> feeds.conf

If you want to use a specific branch of lime-packages specify it adding ;nameofthebranch at the end of the last line. For example:

    src-git lime https://github.com/libremesh/lime-packages.git;17.06

Download the new packages.

    scripts/feeds update -a
    scripts/feeds install -a

Select needed packages in menuconfig.

    make menuconfig

We suggest you to deselect the package _dnsmasq_ from _Base system_ section and to select _dnsmasq-dhcpv6_ in the same section. Then to deselect _firewall_ from _Base system_ section. Finally to deselect _odhcpd_ from _Network_ section. 

Finally enter the _LiMe_ section and select the wanted LibreMesh features, a good option is to select lime-full. 

Compile the firmware images.

    make

The resulting files will be present in _bin_ directory.


## Get in Touch with LibreMesh Community

### Mailing Lists

The project offers the following mailing lists

* [lime-dev@lists.libremesh.org][7] - This list is used for general development related work.
* [lime-users@lists.libremesh.org][8] - This list is used for project organisational purposes. And for user specific questions.

### IRC Channel

The project uses an IRC channel on freenode.net

* #libremesh - a public channel for everyone to join and participate

[1]: http://wiki.openwrt.org/doc/start#building_openwrt
[2]: https://github.com/libremesh/lime-sdk
[4]: http://libremesh.org/howitworks.html
[5]: http://libremesh.org/
[7]: https://lists.libremesh.org/mailman/listinfo/lime-dev
[8]: https://lists.libremesh.org/mailman/listinfo/lime-users
[9]: http://repo.libremesh.org/current/
[10]: https://chef.altermundi.net/


## License
[![FOSSA Status](https://app.fossa.io/api/projects/git%2Bhttps%3A%2F%2Fgithub.com%2Fgmarcos87%2Flime-packages.svg?type=large)](https://app.fossa.io/projects/git%2Bhttps%3A%2F%2Fgithub.com%2Fgmarcos87%2Flime-packages?ref=badge_large)