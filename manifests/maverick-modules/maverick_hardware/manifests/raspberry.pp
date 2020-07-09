# @summary
#   Maverick_hardware::Raspberry class
#   This class installs/manages the Raspberry Pi hardware environment
#
# @example Declaring the class
#   This class is included from maverick_hardware class and should not be included from elsewhere
#
# @param expand_root
#   If true, expand the root filesystem to the full size of the SD card
# @param gpumem
#   Set the split of cpu/gpu memory.  128M is recommended to fully enable GPU functions.
# @param overclock
#   Set the overclocking state of the CPU.  Recommended to keep None unless cooling hardware and a specific need.
# @param devicetree
#   If true, enable devicetree in kernel boot.  Should almost always be true.
# @param spi
#   If true, enable SPI support in the kernel.
# @param i2c
#   If true, enable I2C support in the kernel.
# @param serialconsole
#   Should be set to false to disable the console on the hardware serial port, so it can be used for flight controller link.
# @param serialoverride
#   If true, move the serial link back to the more reliable hardware pins.  This gives better high speed serial link.
# @param camera
#   If true, install raspberry picam support.
# @param xgl
#   If true, Add X GL support.  Only needed if using 3D desktop functions.
# @param v4l2
#   If true, add specific kernel support for V4L2 device.
# @param overpower_usb
#   If true, allow the USB ports to draw more power than the USB standards.  Useful, but use with care.
# @param auto_login
#   If true and using desktop enivronment, automatically login without need for password.
# @param desktop_autologin_user
#   The username used to login automatically to the desktop, if auto_login is set.
# @param manage_pi_password
#   If true, manage the pi user password, and shut off the default password warnings
# @param pi_password
#   Hashed pi user password to set.
# @param remove_extrapackages
#   If true, remove large packages that should not be needed in UAV environment, to free up useful space.
# @param remove_glpackages
#   If true, remove packages that provide GL support
# @param swapsize
#   Set the filesystem swap size.  Default should only normally be changed when needing to compile large components.
#
class maverick_hardware::raspberry (
    Boolean $expand_root = true,
    Integer $gpumem = 128,
    Enum['None', 'High', 'Turbo'] $overclock = "None",
    Boolean $devicetree = true,
    Boolean $spi = true,
    Boolean $i2c = true,
    Boolean $serialconsole = false, # Normally leave the serial lines free for pixhawk
    Boolean $serialoverride = true, # Disable bluetooth on Pi 3/ZeroW for more reliable serial
    Boolean $camera = true,
    Boolean $xgl = false,
    Boolean $v4l2 = true,
    Boolean $overpower_usb = false,
    Boolean $auto_login = false,
    String $desktop_autologin_user = "mav",
    Boolean $manage_pi_password = false,
    String $pi_password = '$6$YuXyoBZR$cR/cNLGZV.Y/nfW6rvK//fjnr84kckI1HM0fhPnJ3MVVlsl7UxaK8vSw.bM4vTlkF4RTbOSAdi36c5d2hJ9Gj1',
    Boolean $remove_extrapackages = true,
    Boolean $remove_glpackages = false,
    Integer $swapsize = 1024, # /var/swap swapfile size in Mb
    ) {

    # https://github.com/goodrobots/maverick/issues/234
    if $manage_pi_password == true {
        user { "pi":
            password    => "${pi_password}",
        } ->
        file { ["/etc/profile.d/sshpassword.sh", "/etc/profile.d/sshpwd.sh"]:
            ensure      => absent
        }
    }

    # Disable raspberry wifi-country service
    service { "wifi-country":
        ensure  => stopped,
        enable  => false,
    }

    file { "/boot/wpa_supplicant.conf.sample":
        ensure      => present,
        content     => template("maverick_hardware/wpa_supplicant.conf.sample.erb")
    }

    # Remove large packages to save space
    if $remove_extrapackages == true {
        package { ["wolfram-engine", "wolfram-script", "freepats", "realvnc-vnc-server", "scratch", "nuscratch", "sonic-pi", "bluej", "nodered", "minecraft-pi", "claws-mail", "greenfoot", "chromium-browser"]:
            ensure  => purged,
        }
        package { ["libjs-mathjax", "fonts-mathjax", "pyton-picamera-docs", "libraspberrypi-doc", "libllvm3.9", "libc6-dbg"]:
            ensure  => purged,
        }
        if ! getvar("maverick_intelligence::tensorflow") == true {
            exec { "raspberry-remove-java":
                command     => "/usr/bin/apt purge -y oracle-java8-jdk oracle-java7-jdk openjdk-8-jdk* openjdk-8-jre* openjdk-7-jdk* openjdk-7-jre* libservlet2.5-java",
                onlyif      => "/usr/bin/dpkg -s openjdk-8-jdk || /usr/bin/dpkg -s openjdk-7-jdk",
            }
        }
        
    }
    if $remove_glpackages == true {
        package { ["libgl1-mesa-dri"]:
            ensure  => purged,
        }
    }
    
    # Install raspberry supporting utils
    ensure_packages(["raspi-config", "python-rpi.gpio", "python3-rpi.gpio", "rpi-update", "raspi-gpio", "raspberrypi-net-mods", "raspberrypi-sys-mods"])
    # Install wiringpi through pip as it's not always available through apt
    install_python_module { 'pip-wiringpi':
        pkgname     => 'wiringpi',
        ensure      => present,
    }
    
    if ($expand_root) {
        # $rootpart_expanded and $rootfs_expanded are facts provided by facts.d/filesystems.py
        if str2bool($::rootpart_expanded) == false or str2bool($::rootfs_expanded) == false {
            exec { "raspberry-expandroot":
                command     => "/usr/bin/raspi-config nonint do_expand_rootfs; echo 'done' > /etc/raspi-expandroot",
                unless      => "/bin/grep 'done' /etc/raspi-expandroot",
                require	    => Package["raspi-config"],
            }
            warning("Root filesystem/partition needs expanding, *please stop configure* then expandrootfs using sudo raspi-config, and reboot before continuing.")
        }
    }
        
    exec { "raspberry-setgpumem":
        command     => "/usr/bin/raspi-config nonint do_memory_split ${gpumem}",
        unless      => "/bin/grep 'gpu_mem=${gpumem}' /boot/config.txt",
        require     => Package["raspi-config"]
    }
    
    if $auto_login == false {
        file { "/etc/systemd/system/getty.target.wants/getty@tty1.service":
            ensure  => link,
            target  => "/lib/systemd/system/getty@.service",
            force   => true,
        }
    } else {
        file { "/etc/systemd/system/getty.target.wants/getty@tty1.service":
            ensure  => link,
            target  => "/etc/systemd/system/autologin@.service",
            force   => true,
        }
    }
    
    if getvar("base::desktop::enable") == true {
        confval { "rpi-desktop-autologin":
            file        => "/etc/lightdm/lightdm.conf",
            field       => "autologin-user",
            value       => $desktop_autologin_user,
        }
    }

    confval{ "rpi-enableuart":
        file        => "/boot/config.txt",
        field       => "enable_uart",
        value       => 1,
    }
    # If this is a RPi 3, disable the onboard bluetooth and reassign the GPIO UART to uart0 which is more reliable
    if ($raspberry_model == "4 Model B" or $raspberry_model == "3 Model B+" or $raspberry_model == "3 Model B" or $raspberry_model == "Zero W") and $serialoverride == true {
        confline { "rpi3-uartoverlay":
            file        => "/boot/config.txt",
            line        => "dtoverlay=disable-bt",
        }
        service { "hciuart":
            enable      => false,
            ensure      => stopped,
        } ->
        package { "hciuart":
            ensure      => purged
        }
    } else {
        exec { 'rpi3-disable-dtoverlay':
            command => "/bin/sed -i -e 's/^dtoverlay=pi3-disable-bt/#dtoverlay=pi3-disable-bt/' /boot/config.txt",
            onlyif  => "/bin/grep '^dtoverlay=pi3-disable-bt' /boot/config.txt",
        }
    }

    if ($overclock) {
        exec { "raspberry-overclock":
            command     => "/usr/bin/raspi-config nonint do_overclock ${overclock}; echo '${overclock}' >/etc/raspi-overclock",
            unless      => "/bin/grep '${overclock}' /etc/raspi-overclock",
            require     => Package["raspi-config"],
        }
    }
    
    if ($devicetree == true) {
        exec { "raspberry-devicetree":
            command     => "/usr/bin/raspi-config nonint do_devicetree 0",
            onlyif	    => "/bin/grep 'device_tree' /boot/config.txt |/bin/grep -v '#.*device_tree'",
            require     => Package["raspi-config"],
        }
    } else {
        exec { "raspberry-devicetree":
            command     => "/usr/bin/raspi-config nonint do_devicetree 1",
            unless      => "/bin/grep 'device_tree' /boot/config.txt |/bin/grep -v '#.*device_tree'",
            require     => Package["raspi-config"],
        }
    }

    if ($spi == true) {
        exec { "raspberry-spi":
            command     => "/usr/bin/raspi-config nonint do_spi 0",
            unless      => "/bin/grep '^dtparam=spi=on' /boot/config.txt",
            require     => Package["raspi-config"],
        }
    } else {
        exec { "raspberry-spi":
            command     => "/usr/bin/raspi-config nonint do_spi 1",
            unless      => "/bin/grep '^dtparam=spi=off' /boot/config.txt",
            require     => Package["raspi-config"],
        }
    }
    
    if ($i2c == true) {
        exec { "raspberry-i2c":
            command     => "/usr/bin/raspi-config nonint do_i2c 0",
            unless      => "/bin/grep -E '^dtparam=i2c(_arm)=on' /boot/config.txt",
            require     => Package["raspi-config"],
        }
    } else {
        exec { "raspberry-i2c":
            command     => "/usr/bin/raspi-config nonint do_i2c 1",
            unless      => "/bin/grep -E '^dtparam=i2c(_arm)=off' /boot/config.txt",
            require     => Package["raspi-config"],
        }
    }

    if ($serialconsole == false) {
        exec { "raspberry-serial":
            command     => "/usr/bin/raspi-config nonint do_serial 1",
            onlyif      => "/bin/grep 'console=serial' /boot/cmdline.txt",
            require     => Package["raspi-config"],
        }
        service { "serial-getty@ttyAMA0":
            ensure      => stopped,
            enable      => false,
        }
    } else {
        exec { "raspberry-serial":
            command     => "/usr/bin/raspi-config nonint do_serial 0",
            unless      => "/bin/grep 'console=serial' /boot/cmdline.txt",
            require     => Package["raspi-config"],
        }
        service { "serial-getty@ttyAMA0":
            ensure      => running,
            enable      => true,
        }
    }
    
    if ($camera == true) {
        exec { "raspberry-camera":
            command     => "/usr/bin/raspi-config nonint do_camera 0; echo 'true' >/etc/raspi-camera",
            unless      => "/bin/grep 'true' /etc/raspi-camera",
            require     => Package["raspi-config"],
        }
    } else {
        exec { "raspberry-camera":
            command     => "/usr/bin/raspi-config nonint do_camera 1; echo 'false' >/etc/raspi-camera",
            unless      => "/bin/grep 'false' /etc/raspi-camera",
            require     => Package["raspi-config"],
        }
    }
    
    if ($xgl == true) {
        package { ["libgl1-mesa-dri", "xcompmgr" ]:
            ensure      => present
        } ->
        exec { "raspberry-xgl":
            command     => "/usr/bin/raspi-config nonint do_gldriver 1; echo 'true' >/etc/raspi-xgl",
            unless      => "/bin/grep 'true' /etc/raspi-xgl",
            require     => Package["raspi-config"],
        }
    } else {
        exec { "raspberry-xgl":
            command     => "/usr/bin/raspi-config nonint do_gldriver 0; echo 'false' >/etc/raspi-xgl",
            unless      => "/bin/grep 'false' /etc/raspi-xgl",
            require     => Package["raspi-config"],
        }
    }
    
    exec { "raspberry-disableconfig":
        command     => "/usr/bin/raspi-config nonint disable_raspi_config_at_boot",
        onlyif      => "/bin/ls /etc/profile.d/raspi-config.sh",
        require     => Package["raspi-config"],
    }
    
    if $v4l2 == true {
        exec { "raspberry-v4l2-kernelmodule":
            command     => "/bin/echo 'bcm2835-v4l2' >>/etc/modules",
            unless      => "/bin/grep '^bcm2835-v4l2' /etc/modules",
        }
        file { "/etc/modprobe.d/raspicam.conf":
            content     => "options bcm2835_v4l2 gst_v4l2src_is_broken=1"
        }
    }
    
    if ($overpower_usb == true) {
        exec { "overpower_usb_true_add":
            command     => "/bin/echo 'max_usb_current=1' >>/boot/config.txt",
            unless      => "/bin/grep -e '^max_usb_current' /boot/config.txt",
        } ->
        exec { "overpower_usb_true":
            command     => "/bin/sed /boot/config.txt -i -r -e 's/^max_usb_current=.*/max_usb_current=1/'",
            unless      => "/bin/grep -e '^max_usb_current=1' /boot/config.txt",
        }
    } else {
        exec { "overpower_usb_false":
            command     => "/bin/sed /boot/config.txt -i -r -e 's/^max_usb_current=1/#max_usb_current=1/'",
            onlyif      => "/bin/grep -e '^max_usb_current=1' /boot/config.txt",
        }
    }
    
    # Size swap
    exec { "raspberry-swapsize":
        command     => "/bin/sed -i -e 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=${swapsize}/' /etc/dphys-swapfile",
        unless      => "/bin/grep -e '^CONF_SWAPSIZE=${swapsize}$' /etc/dphys-swapfile",
    }

    # Set CXXFLAGS so Raspbian Buster broadcasts atomic library
    file { "/etc/profile.d/20-maverick-raspbian-cxxflags.sh":
        mode        => "644",
        owner       => "root",
        group       => "root",
        content     => 'export CXXFLAGS="-latomic"',
    }
}
