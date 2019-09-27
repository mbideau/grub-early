#!/bin/sh
#
# Replaces 'grub-install' utility to provide a more user-friendly grub2 early stage
# It adds extra feature support to grub2 'core.img'. See help for more informations.
#
# inspired by: https://wiki.archlinux.org/index.php/GRUB/Tips_and_tricks#Manual_configuration_of_core_image_for_early_boot
#
#
# Standards in this script:
#   POSIX compliance:
#      - http://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html
#      - https://www.gnu.org/software/autoconf/manual/autoconf.html#Portable-Shell
#   CLI standards:
#      - https://www.gnu.org/prep/standards/standards.html#Command_002dLine-Interfaces
#
# Source code, documentation and support:
#   https://github.com/mbideau/grub-early
#
# Copyright (C) 2019 Michael Bideau [France]
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
# 

# TODO allow to "boot-to" a 2nd grub in /boot partition "on-disk"
#      this will allow to access other boot options, and specially a list of rollbacks
#      that can be btrfs subvolumes for example.
#      This should be the fallback menu entry, and the fallback behavior (if no menu).
#      The "on-disk" grub should on-par with the MBR on (theming mostly). Maybe it
#      can (re)use the Environment Block to store the day/time mode and theme selected ?

# TODO implement RANDOM_BG_IMAGE
#   RANDOM_BG_IMAGE
#       If true, will display a random background, according to the directory:
#       \`$GRUB_BG_DIR'.
#       For each background found, the main theme and inner theme will be copied
#       with the directive \`desktop-image' replaced by the background file path.
#       Then it will enable the \`RANDOM_THEME' feature.

# TODO support grub configuration directives:
#         - GRUB_DEFAULT/GRUB_SAVEDEFAULT
#           If you set this to ‘saved’, then the default menu entry will be that 
#           saved by ‘GRUB_SAVEDEFAULT’ or grub-set-default. This relies on the
#           environment block, which may not be available in all situations (see
#           Environment block).
#
#         - GRUB_EARLY_INITRD_LINUX_CUSTOM
#           List of space-separated early initrd images to be loaded from ‘/boot’.
#           These early images will be loaded in the order declared, and all will
#           be loaded before the actual functional initrd image.
#
#         - GRUB_VIDEO_BACKEND
#           If graphical video support is required, either because the ‘gfxterm’
#           graphical terminal is in use or because ‘GRUB_GFXPAYLOAD_LINUX’ is set,
#           then grub-mkconfig will normally load all available GRUB video drivers
#           and use the one most appropriate for your hardware. If you need to
#           override this for some reason, then you can set this option. 
#
#         - GRUB_PRELOAD_MODULES
#           This option may be set to a list of GRUB module names separated by spaces.
#           Each module will be loaded as early as possible, at the start of grub.cfg. 

# TODO handle to set color_normal and color_highlight for each kernel menu entry


# halt on first error
set -e

# config
GRUB_PREFIX=/usr
GRUB_KBDCOMP=$GRUB_PREFIX/bin/grub-kbdcomp
GRUB_MKIMAGE=$GRUB_PREFIX/bin/grub-mkimage
GRUB_PROBE=$GRUB_PREFIX/sbin/grub-probe
GRUB_BIOS_SETUP=$GRUB_PREFIX/sbin/grub-bios-setup
GRUB_MODDIR=$GRUB_PREFIX/lib/grub/i386-pc
GRUB_CONFIG_DEFAULT=/etc/default/grub
BOOT_DIR=/boot
GRUB_DIR=$BOOT_DIR/grub
GRUB_EARLY_DIR=$GRUB_DIR/early
GRUB_CORE_FORMAT=i386-pc
GRUB_CORE_IMG=$GRUB_EARLY_DIR/core.img
GRUB_CORE_COMPRESSION=auto
GRUB_CORE_MEMDISK=$GRUB_EARLY_DIR/memdisk.tar
GRUB_CORE_CFG=$GRUB_EARLY_DIR/load.cfg
GRUB_BOOT_IMG=$GRUB_EARLY_DIR/boot.img
GRUB_BOOT_IMG_SRC=$GRUB_MODDIR/boot.img
GRUB_MEMTEST_BIN=$BOOT_DIR/memtest86+.bin
GRUB_MEMDISK_DIR=$GRUB_EARLY_DIR/memdisk
GRUB_NORMAL_CFG=$GRUB_MEMDISK_DIR/normal.cfg
GRUB_HOST_DETECTION_FILENAME=detect.cfg
GRUB_HOST_CONFIGURATION_FILENAME=params.cfg
GRUB_HOST_MENUS_FILENAME=menus.cfg
GRUB_MODULES_REQUIREMENTS_FILENAME=requirements.txt
GRUB_COMMON_CONF_FILENAME=conf_common.cfg
GRUB_EXTRA_MENUS_FILENAME=menus_extra.cfg

# theming
GRUB_THEME_FILENAME=theme.txt
GRUB_THEME_INNER_FILENAME=theme-inner.txt
GRUB_THEMES_DIR=$GRUB_MEMDISK_DIR/themes
#GRUB_BG_DIR=$GRUB_MEMDISK_DIR/backgrounds
GRUB_TERMINAL_BG_IMAGE=$GRUB_MEMDISK_DIR/terminal_background.tga

# user defaults
GRUB_EARLY_CMDLINE_LINUX='quiet splash'
GRUB_EARLY_TIMEOUT=15
GRUB_EARLY_EMPTY_MEMDISK_DIR=yes
GRUB_EARLY_SHORT_UUID=true
GRUB_EARLY_NOPROGRESS=yes
GRUB_EARLY_KEYMAP=us
GRUB_EARLY_LOCALE=en
GRUB_EARLY_FONT=ascii
GRUB_EARLY_GFXMODE=auto
GRUB_EARLY_GFXPAYLOAD=keep
GRUB_EARLY_RANDOM_THEME=false
GRUB_EARLY_WRAPPER_SUBMENU_CLASSES='default'
GRUB_EARLY_DISABLE_SUBMENU=false
GRUB_EARLY_KERNEL_WRAPPER_SUBMENU_TITLE='Kernels'
GRUB_EARLY_KERNEL_SUBMENUS_CLASSES='linux,os,kernel'
GRUB_EARLY_KERNEL_SUBLENUS_TITLE='GNU/Linux %s'
GRUB_EARLY_PARSE_OTHER_HOSTS_CONFS=true

# internal const
NL="
"
IFS_BAK="$IFS"
TRUE=0
FALSE=1
THIS_SCRIPT_NAME="$(basename "$0")"
V_DEBUG=2
V_INFO=1
V_QUIET=0

# verbosity
if [ -z "$VERBOSITY" ]; then
    VERBOSITY=$V_QUIET
fi


# print usage
usage()
{
    cat <<ENDCAT

$THIS_SCRIPT_NAME - create a customized _grub2_ \`core.img' and install it to a device

USAGE

    $THIS_SCRIPT_NAME [-h|--help]
        Display help

    $THIS_SCRIPT_NAME [-c|--config FILE] [-v|--verbosity LEVEL] DEVICE
        Create and install \`core.img' to specified device

    $THIS_SCRIPT_NAME --no-install DEVICE
        Create but not install \`core.img' to specified device

    $THIS_SCRIPT_NAME ..OPTIONS.. DEVICE
        Create and install \`core.img' to specified device with options

ARGUMENTS

    DEVICE
        Path to a device (i.e.: /dev/sdx).
        It can also be one of the following:
         - device name       (NAME   in \`lsblk')
         - device model      (MODEL  in \`lsblk')
         - device serial     (SERIAL in \`lsblk')
         - device storage id (WWN    in \`lsblk')

OPTIONS

    -c|--config FILE
        Path to a configuration script. Default to: \`$GRUB_CONFIG_DEFAULT'.

    -v|--verbosity LEVEL
        An integer whose value is:
            $V_QUIET : quiet (default)
            $V_INFO : info
            $V_DEBUG : debug

    -n|--no-install
        Do not install grub to MBR BIOS of specified disk.
        It is not a dry-run: it will execute everything (modifying files)
        but not make the last step of installation.

    -o|--other-hosts HOSTS
        This program can handle to install and configure grub to boot
        multiple hosts (usually from an external device, like a usb dongle).
        This option is a list of host name/IDs with their \`archive file'.
        More on the \`archive file' in the section 'HOST ARCHIVE FILE' below.
        The format is the following:
            host_id_1:host_archive_path_1 | host_id_2:host_archive_path_2 ...

    -m|--multi-hosts
        Force the multi host mode, even if no option '--other-hosts'.

    -i|--host-id ID
        Force/use this value as this host unique identifier (HOST_ID).

    -p|--part-uuid
        The device where grub will be installed to is the "top level" device
        that have the specified partition UUID in its "children" devices.
        With this flag, you specify the partition UUID as the "device" argument.
        This option is usefull to prevent installing to a bad device if their
        order has changed at boot (/dev/sda becoming /dev/sdb for example).


FILES

    $GRUB_CONFIG_DEFAULT
        Default configuration file path.

    $GRUB_MODDIR
        Default grub2 modules directory.
    
    $GRUB_DIR
        Default grub2 \`boot' directory.

    $GRUB_EARLY_DIR
        Default grub-early \`boot' directory.

    $GRUB_CORE_IMG
        Default path for grub-early \`core.img'.

    $GRUB_MEMDISK_DIR
        Default path for grub-early memdisk directory.

    $GRUB_CORE_MEMDISK
        Default path for grub-early memdisk tarball.

    $GRUB_CORE_CFG
        Default path for grub-early early stage script configuration.

    $GRUB_NORMAL_CFG
        Default path for grub-early \`normal' mode script configuration.

    $GRUB_BOOT_IMG
        Default path for grub-early \`boot.img'.

    $GRUB_BOOT_IMG_SRC
        Default path for grub2 \`boot.img' source.

    $GRUB_MEMTEST_BIN
        Default path for memtest binary.


CONFIGURATION

    This script can be configured with variables in a configuration file.
    Variables must be prefixed by \`GRUB_EARLY_'.

    CORE_CFG
        Use a custom configuration script for early grub instead of the default
        one in this script (that just loads the "normal" mode with NORMAL_CFG).

    NORMAL_CFG
        Use a custom configuration script for early grub in "normal" mode
        instead of the default one in this script (that use all options below).

    VERBOSITY
        If '$V_QUIET' try to be silent, if '$V_VERBOSE' talk a little, and if
        '$V_DEBUG' enter "kind of" debug mode (and set pager=1).

    HOOK_SCRIPT
        Trigger a hook script before running \`grub-mkimage' but after all files
        where generated. It will be sourced, not executed. So it will have access
        to all variables of this script, and if it fails, this script will too.

    CMDLINE_LINUX
        The same as the "standard" \`GRUB_CMDLINE_LINUX_DEFAULT' option. Default
        to \`$GRUB_EARLY_CMDLINE_LINUX'. If empty, uses the value of the
        \`GRUB_CMDLINE_LINUX_DEFAULT' configuration variable.

    SINGLE_KERNEL
        The value of a kernel file in /boot (i.e.: 'vmlinuz-4.19.0-4-amd64').
        Only this kernel will be considered (only this one entry for kernels).
        No detection of other kernels.

    DISABLE_RECOVERY
        If true, do not generate menu entries for recovery mode.

    TIMEOUT
        The number of second to wait before automatically booting the default
        menu entry. Same as the "standard" \`GRUB_TIMEOUT' option. Default to
        \`$GRUB_EARLY_TIMEOUT'. If empty, uses the value of the \`GRUB_TIMEOUT'
        configuration variable.

    EMPTY_MEMDISK_DIR
        If true, empty the memdisk directory before adding content to it.
        Default to \`$GRUB_EARLY_EMPTY_MEMDISK_DIR'.

    ALTERNATIVE_MENU
        The content of a submenu to display when the SHIFT key is pressed
        (at boot time, before/during grub2 loading).
    
    CRYPTOMOUNT_OPTS
        Options passed to \`cryptomount' (i.e.: --keyfile (hd2,msdos1)/secret.bin).
        I recommend using the patched \`cryptomount' (http://grub.johnlane.ie/).

    KEYMAP
        A keyboard layout name (i.e.: fr). Default to: \`$GRUB_EARLY_KEYMAP'.

    NO_USB_KEYBOARD
        If true, disable using the alternative terminal input \`usb_keyboard'.
        Note: When keymap is specified, one of the alternative terminal input
        \`usb_keyboard' or \`at_keyboard' is required, because the \`console' one
        doesn't handle keymap.

    NO_PS2_KEYBOARD
        If true, disable using the alternative terminal input \`at_keyboard'.
        Note: When keymap is specified, one of the alternative terminal input
        \`usb_keyboard' or \`at_keyboard' is required, because the \`console' one
        doesn't handle keymap.

    FORCE_USB_KEYBOARD
        If true, force the use of the alternative terminal input \`usb_keyboard'.

    FORCE_PS2_KEYBOARD
        If true, force the use of the alternative terminal input \`at_keyboard'.

    LOCALE
        A locale name (i.e.: fr_FR). Default to: \`$GRUB_EARLY_LOCALE'.

    FONT
        A name of, or path to, a font file (i.e.: euro). Default to \`$GRUB_EARLY_FONT'.

    GFXMODE
        The same as the "standard" \`GRUB_GFXMODE' option. Default to \`$GRUB_EARLY_GFXMODE'.
        If empty, uses the value of the \`GRUB_GFXMODE' configuration variable.

    GFXPAYLOAD
        The same as the "standard" \`GRUB_GFXPAYLOAD_LINUX' option. Default to
        \`$GRUB_EARLY_GFXPAYLOAD'. If empty, uses the value of the
        \`GRUB_GFXPAYLOAD_LINUX' configuration variable.

    NO_GFXTERM
        Disable using \`gfxterm' which allow for a nice graphical rendering.

    TERMINAL_BG_COLOR
        A color to set the background of the terminal to (i.e.: #E0E0E0).

    TERMINAL_BG_IMAGE
        A path to an image used as a background of the terminal.
        It must be in 'tga' or 'png' format.

    THEMES_DIR
        A path to a themes directory.
        All the theme it contains will be added to the "memdist" so be
        aware that it may be too big to be able to create the core.img.

    THEME_DEFAULT
        The name of the default theme if there are multiple themes in the
        themes directory \`THEMES_DIR'. Else it default to the one found.
    
    NO_MENU
        If true, will not use any menu entry.

    DISABLE_SUBMENU
        The same as the "standard" \`GRUB_DISABLE_SUBMENU' option.
        It will disable wraping all the kernel menu entries into one submenu.
        Default to \`$GRUB_EARLY_DISABLE_SUBMENU'. If empty, uses the value
        of the \`GRUB_DISABLE_SUBMENU' configuration variable.

    KERNEL_WRAPPER_SUBMENU_TITLE
        The title of the kernel wrapper submenu.
        Default to: \`$GRUB_EARLY_KERNEL_WRAPPER_SUBMENU_TITLE'

    KERNEL_WRAPPER_SUBMENU_CLASSES
        The classes of the kernel wrapper submenu. Separated by comma.
        Default to: \`wrapper,\$GRUB_EARLY_KERNEL_SUBMENUS_CLASSES'.

    KERNEL_SUBMENUS_CLASSES
        The classes of the kernel submenus. Separated by comma.
        Default to: \`$GRUB_EARLY_KERNEL_SUBMENUS_CLASSES'.

    KERNEL_SUBMENUS_TITLE
        The title of the kernel submenus.
        First '%s' match, will be replaced by the kernel version (with printf).
        Default to: \`$GRUB_EARLY_KERNEL_SUBLENUS_TITLE'.

    KERNEL_SUBMENUS_TITLE_RECOVERY
        The title of the kernel submenus for recovery mode.
        First '%s' match, will be replaced by the kernel version (with printf).
        Default to: \`\$GRUB_EARLY_KERNEL_SUBLENUS_TITLE (recovery)'.

    WRAP_IN_SUBMENU
        If not empty, will wrap all the menu/submenu entries inside one
        submenu entries which title is the value of this option.
        It will have the class 'default'.
        It is intended to help having a cleaner theme and display with only
        one entry instead of dosens. So by default the booting splash will be
        more elegant. And with the help of inner theme, when entering this
        submenu it will have a theme that is made for multiple menu entries.
        So no feature loss and better looking.

    WRAPPER_SUBMENU_CLASSES
        The classes of the wrapper submenu. Separated by comma.
        Default to: \`$GRUB_EARLY_WRAPPER_SUBMENU_CLASSES'

    RANDOM_THEME
        If true, will use a theme randomly.

    RANDOM_BG_COLOR
        A list of HEX colors (space separated) to be used as theme background.
        If the value is 'generated', the colors will be generated randomly by
        this script.
        For each background color, the main theme and inner theme will be copied
        with the directive \`desktop-color' set to the color.
        Then it will enable the \`RANDOM_THEME' feature.

    RANDOM_BG_COLOR_NODEFAULT
        If true, will not includ the default theme in the themes, just use it to
        generate all colored derivatives.

    DAY_TIME
        The time in the day after which only the following variables will be
        used instead of the "un-suffixed" ones:
            - THEMES_DIR_DAY
            - THEME_DEFAULT_DAY
            - TERMINAL_BG_COLOR_DAY
            - TERMINAL_BG_IMAGE_DAY
            - RANDOM_BG_COLOR_DAY
            - RANDOM_BG_COLOR_NODEFAULT_DAY.
       You must specify both: DAY_TIME and NIGHT_TIME.

    NIGHT_TIME
        The time in the day after which only the following variables will be
        used instead of the "un-suffixed" ones:
            - THEMES_DIR_NIGHT
            - THEME_DEFAULT_NIGHT
            - TERMINAL_BG_COLOR_NIGHT
            - TERMINAL_BG_IMAGE_NIGHT
            - RANDOM_BG_COLOR_NIGHT
            - RANDOM_BG_COLOR_NODEFAULT_NIGHT.
       You must specify both: DAY_TIME and NIGHT_TIME.

    NOPROGRESS
        If true, will set 'enable_progress_indicator=0' to disable 'progress indicator'
        in order to prevent 'terminal box' poping out for no reason when in graphical
        mode.

    COMMON_CONF
        If a path of a file is specified, it will be added as the common configuration
        grub shell script for all hosts, preceding each host own configuration script.

    EXTRA_MENUS
        If a path of a file is specified, it will be added as this host extra menus
        appended after kernels menus.

    SHORT_UUID
        If true, will truncate MACHINE_UUID that identifies the host when in
        multi-hosts mode. It will truncate at the first underscore '_', then
        will use the first 16 characters.

    ADD_GRUB_MODULES
        A space separated list of grub modules that need to be added (copied)
        to the modules directory (to be avaible at boot time with command
        \`insmod').

    INSTALL_ARGS
        Extra arguments to pass to \`grub-bios-setup'.

    PARSE_OTHER_HOSTS_CONFS
        If true, will also parse other hosts conf files to build the modules
        list (instead of only the current host conf files, plus other hosts
        module requirements files). It is usefull if the other hosts require-
        ment files might not be up-to-date and risk of causing a boot failure.


HOST ARCHIVE FILE

    An \`archive file' is a _tar_ file containing all the host files:

        $GRUB_HOST_DETECTION_FILENAME
            A grub script file that define a way to identify at boot time
            if it is executed on this host (i.e.: use the PCI trick).

        $GRUB_HOST_MENUS_FILENAME
            A grub script file containing the menu definitions
            for this host.

        $GRUB_HOST_CONFIGURATION_FILENAME (optional)
            A grub script file containing parameters to be loaded before
            the menu file (i.e.: switch to gfx mode, set background, etc.)

        $(basename "$GRUB_THEMES_DIR") (optional)
            A directory containing a directory per theme.
            A theme dir must contain a grub theme file \`$GRUB_THEME_FILENAME'
            and optionaly a grub theme file for submenu \`$GRUB_THEME_INNER_FILENAME'.

        ${GRUB_EARLY_FONT}.pf2 (optional)
            A font file (or many) named after the font.

        $(echo "$GRUB_EARLY_LOCALE"|trim|cut -c -2).mo (optional)
            A gettext compiled locale file named after the locale (short).

        ${GRUB_EARLY_KEYMAP}.gkb (optional)
            A keymap file generated by \`grub-kbdcomp' named after the keymap.

        $GRUB_MODULES_REQUIREMENTS_FILENAME (optional)
            A list of space separated grub module names that are required for this
            host. Usually only the device related module should be listed, if the
            option \`PARSE_OTHER_HOSTS_CONFS' is true (currently: $GRUB_EARLY_PARSE_OTHER_HOSTS_CONFS).


EXAMPLES

    # install the custom \`core.img' build by \`grub-early' with default configuration
    > grub-early /dev/vda

    # use a custom configuration file
    > grub-early -c /usr/local/etc/default/grub /dev/vda

    # do everything as usual but do not install grub in the device MBR
    > grub-early -n /dev/vda

    # force the multi-host mode and generate a tarball
    > grub-early -m /dev/vda
    > tar -czf /tmp/\$(hostname).tar.gz -C $GRUB_MEMDISK_DIR/\$(hostname) .

    # use that host tarball in another host executing this script
    > other_hostname=the_other_hostname
    > grub-early -o "\${other_hostname}:/tmp/\${other_hostname}.tar.gz" /dev/sde


PROBLEM SOLVED

    The problem this script solves can be summarized with:
    "A more user-friendly grub2 early stage".

    It only targets grub2 MBR installations with /boot partition encrypted.

    The current grub2 implementation (i.e.: 2.02) can deal with an
    encrypted /boot partition by embeding decryption code in its early
    stage state.
    In that state, grub is *too minimalist* in its features, which can be
    really problematic, like keymap forced to 'en/us', no locale support,
    and a raw output (terminal white on black).
    More akward, it loads grub2 again after having decrypted /boot but
    this time with full capabilies (so it is a double boot).

    That minimalism and akwardness is caused by the implentation in the
    extra utility of grub2: \`grub-install'.
    This utility configures the early stage state with the generated file:
    \`/boot/grub/i386-pc/load.cfg'. Currently it is scripted to do only one
    thing: it decrypts and mounts the encrypted /boot partition.
    This will produce the really raw and akward user experience described
    above.

    This script intends to replace \`grub-install', to enable a much more
    user friendly early stage state.
    In particular it tries to:

     * prevent double grub2 by booting directly into the kernel from
       early stage

     * store additionnal files into a tarball (memdisk) copied
       to MBR and available at boot time by grub script files

     * support other keymap though the unreliable alternative terminal
       input module \`at_keyboard' and keymap files generated by
       \`grub-kbdcomp'

     * support for multi-hosts, when using grub2 to boot multiple hosts
       from a single device (usually a usb dongle)

     * enable graphical mode (gfx)

     * support for theming (full support: timeout, progress, fonts, etc.)
       and even up to 10 random themes (enthropy based on datetime seconds)
       and a day/night mode!

     * support for full grub2 scripting (by switching to normal mode ASAP)

     * support for triggering an alternative menu when pressing SHIFT key

     * wrapping all the menus into a single submenu (usefull for theming)

     * auto-detecting /boot partitions devices and kernels modules required
       at realy stage to have a successfull decryption and booting process

     * support for a configuration file to be the most flexible

     * provide sane defaults to have a good user experience but the closest
       to the current \`grub-install' one

     * implement a reliable way to identify host (with PCI devices ID).

    A challenge is that, by being executed in the early stage state, grub
    has a very limited amount of space to store its files (even with a
    memdisk tarball, accounted in the amount of space available in the MBR).
    So theming and grub modules are limited in fancyness.
    But even with this limitation, the user experience can be near a no-limit
    one, by choosing wisely the modules and optimizing the themes resources.


SEE ALSO

    The _grub2_ user manual, which is very simple to understand:
    https://www.gnu.org/software/grub/manual/grub/html_node/

    The _grub2_ \`cryptomount' patched to add a much better user experience
    for encryopted device, by supporting:
        - automated key decryption
        - detached LUKS headers
        - passphrase input retries
    http://grub.johnlane.ie/


LICENSE

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
    
    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
    
    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.


AUTHORS

    Written by: Michael Bideau [France]


REPORTING BUGS

    Report bugs to: mica.devel@gmail.com


COPYRIGHT

    Copyright (C) 2019 Michael Bideau [France]
    License GPLv3+: GNU GPL version 3 or later <https://gnu.org/licenses/gpl.html>
    This is free software: you are free to change and redistribute it.
    There is NO WARRANTY, to the extent permitted by law.

ENDCAT
}

# display a fatal error and exit
#  $1  string   the message to display
#  $2  string   a replacement string in the message (printf)
#  $3  string   another replacement string in the message
#  ..  string   a nth replacement string in the message
fatal_error()
{
    _msg="$1\\n"
    shift
    # shellcheck disable=SC2059
    printf "$_msg" "$@"|sed 's/^/Fatal error: /g' >&2
    exit 1
}

# display a warning
#  $1  string   the message to display
#  $2  string   a replacement string in the message (printf)
#  $3  string   another replacement string in the message
#  ..  string   a nth replacement string in the message
warning()
{
    _msg="$1\\n"
    shift
    # shellcheck disable=SC2059
    printf "$_msg" "$@"|sed 's/^/Warning: /g' >&2
}

# display a message according to $VERBOSITY level (0 = quiet)
#  $1  int      the verbosity level (message displayed only
#               when lower or equals to VERBOSITY value)
#  $2  string   the message to display
#  $3  string   a replacement string in the message (printf)
#  $4  string   another replacement string in the message
#  ..  string   a nth replacement string in the message
msg()
{
    if [ "$1" -le "$VERBOSITY" ]; then
        shift
        _msg="$1\\n"
        shift
        # shellcheck disable=SC2059
        printf "$_msg" "$@"
    fi
}

# display a debug message (when VERBOSITY is > 1)
debug()
{
    msg "$V_DEBUG" "$@"|sed 's/^/[DEBUG] /g'
}

# display a info message (when VERBOSITY is > 0)
info()
{
    _msg="* $1"
    shift
    msg "$V_INFO" "$_msg" "$@"
}

# return a boolean value
bool()
{
    if [ "$1" = '1' ] \
    || [ "$1" = 'y' ] || [ "$1" = 'Y' ] \
    || [ "$1" = 'yes' ] || [ "$1" = 'Yes' ] || [ "$1" = 'YES' ] \
    || [ "$1" = 'o' ] || [ "$1" = 'O' ] \
    || [ "$1" = 'on' ] || [ "$1" = 'On' ] || [ "$1" = 'ON' ] \
    || [ "$1" = 'true' ] || [ "$1" = 'True' ] || [ "$1" = 'TRUE' ]; then
        return $TRUE
    fi
    return $FALSE
}

# remove spaces before and after a string
# use stdin
trim()
{
    sed 's/^[[:blank:]]*//g;s/[[:blank:]]*$//g'
}

# indent a string after each line break
#  $1  int  the number of space to use for indentation
# use stdin
indent()
{
    _spaces=
    # shellcheck disable=SC2034
    for i in $(seq 1 "$1"); do
        _spaces="$_spaces "
    done
    sed ":a;N;\$!ba;s/\\n/\\n$_spaces/g"
}

# trim and uniquify a words list from stdin (line separated)
# options are:
#   --from-sep-space : words are separated by space (not line)
#   --to-sep-space   : words are outputed separated by space (not line)
#   -s|--space       : equals both options --from-sep-space and --to-sep-space
uniquify()
{
    cmd_line='trim|sort -u'
    if [ "$1" = '--from-sep-space' ] || [ "$2" = '--from-sep-space' ] \
    || [ "$1" = '-s' ] || [ "$1" = '--space' ] \
    || [ "$2" = '-s' ] || [ "$2" = '--space' ]; then
        cmd_line="tr ' ' '\\n'|$cmd_line"
    fi
    if [ "$1" = '--to-sep-space' ] || [ "$2" = '--to-sep-space' ] \
    || [ "$1" = '-s' ] || [ "$1" = '--space' ] \
    || [ "$2" = '-s' ] || [ "$2" = '--space' ]; then
        cmd_line="$cmd_line|tr '\\n' ' '|trim"
    fi
    eval "$cmd_line"
}

# extract the classes defined for a menu/submenu entry
#  $1  string  a menu/submenu entry definition
# return format is '--class class1 --class class2'
get_menu_entry_classes()
{
    echo "$1"|grep -o '\(menuentry\|submenu\).*' \
             |head -n 1 \
             |sed  's/^\(menuentry\|submenu\) \+'"'"'[^'"'"']\+'"'"' '`
                   `'*\(\( \+--class \+[^ ]\+\)\+\)* \+--id.*$/\2/' \
             |trim
}

# list all grub modules requirements for a file (parse 'insmod MODULE')
get_manually_loaded_grub_modules_for_file()
{
    grep '^[[:blank:]]*insmod[[:blank:]]\+[^ ]\+[[:blank:]]*$' "$1" \
    |sed 's/^[[:blank:]]*insmod[[:blank:]]\+\([^ ]\+\)[[:blank:]]*$/ \1 /g' \
    |uniquify --to-sep-space
}

# extract the commands used in the configuration scripts specified
#  $1  string   a list of paths to config script separated by $NL (newline)
# return format is a list separated by space
get_command_list()
{
    cmds=""
    IFS="$NL"
    for f in $1; do
        IFS="$IFS_BAK"
        if [ -r "$f" ]; then
            IFS="$NL"
            # shellcheck disable=SC2013
            for line in $(cat -s "$f"); do
                IFS="$IFS_BAK"
                cmds="$cmds $(get_command_list_for_line "$line")"
            done
        fi
    done
    echo "$cmds"|uniquify -s
}

# return a command list for a line
#  $1  string  the line
get_command_list_for_line()
{
    cmds=""
    line="$1"
    if echo "$line"|grep -v '^ *#' \
                   |grep -v '^ *[{}] *$'|grep -q '^ *[^ ]\+'
    then
        line="$(echo "$line"|trim)"
        line_split_pos=1
        cmd="$(echo "$line"|awk '{print $1}'|trim)"

        # if/elif command
        if [ "$cmd" = 'if' ] || [ "$cmd" = 'elif' ]; then
            line_split_pos="$((line_split_pos + 1))"
            tested="$(echo "$line"|awk '{print $'"$line_split_pos"'}')"

            # negation is useless
            if [ "$tested" = '!' ]; then
                line_split_pos="$((line_split_pos + 1))"
                tested="$(echo "$line"|awk '{print $'"$line_split_pos"'}')"
            fi

            # '[' is useless (we already have 'if' which is also the 'test' module)
            # what is inside [] is only vars
            if [ "$tested" != '[' ]; then
                cmds="$cmds $cmd"
                cmd="$(echo "$tested"|sed 's/ *; *\(then *\)\?$//g')"
            fi
        fi

        # assignation is a 'set' command
        if echo "$line"|grep -q '^ *[^ ]\+ *= *.*$'; then
            cmd="set"
            line="set $line"
        fi

        # if the commands arguments are important for module analysis
        if is_command_loading_modules_depending_on_its_args "$cmd"; then
            line_split_pos="$((line_split_pos + 1))"
            arg="$(echo "$line"|awk '{print $'"$line_split_pos"'}')"
            if echo "$line"|grep -q '^ *\(el\)\?if '; then
                arg="$(echo "$arg"|sed 's/ *; *\(then *\)\?$//g')"
            fi
            if [ "$cmd" = 'set' ]; then
                setted="$(echo "$arg"|sed 's/^\([^=]\+\)=.*/\1/g')"
                cmd="set($setted)"
            else
                cmd="$cmd($arg)"
            fi
        fi

        # special case for disks mentions
        if echo "$line"|grep -q '([[:blank:]]*\(memdisk\|proc\|\(hd\|ahci\|p\?ata\|scsi\)[0-9]\+'`
                                `'\(,[^)]\+\)\?\)[[:blank:]]*)'; then
            cmds="$cmds $cmd"
            disk="$(echo "$line" \
                    |sed -e 's/^.*([[:blank:]]*\(memdisk\|proc\|\(hd\|ahci\|p\?ata\|scsi\)[0-9]\+'`
                            `'\(,[^)]\+\)\?\)[[:blank:]]*).*$/\1/g' \
                         -e 's/ //g')"
            cmd="disk($disk)"
        fi

        # special case for datehook variables
        if echo "$line"|grep -q '["'"'"']\?$\(SECOND\|MINUTE\|HOUR'`
                                `'\|DAY\|MONTH\|YEAR\)["'"'"']\?'; then
            cmds="$cmds $cmd"
            var="$(echo "$line"|sed 's/^.*["'"'"']\?$\(SECOND\|MINUTE\|HOUR'`
                                    `'\|DAY\|MONTH\|YEAR\)["'"'"']\?.*$/\1/g')"
            cmd="var($var)"
        fi
        cmds="$cmds $cmd"
    fi
    echo "$cmds"
}

# return $TRUE if the command loads grub modules dynamically according to its arguments
#  $1  string  the command
is_command_loading_modules_depending_on_its_args()
{
    case "$1" in
        set)                            return "$TRUE" ;;
        terminal_input|terminal_output) return "$TRUE" ;;
    esac
    return "$FALSE"
}

# get grub modules for a 'set' command (using special keywords like 'pager')
#  $1  string  the key that is sat
get_grub_modules_for_set_command()
{
    modules=
    case "$1" in
        pager) modules="$modules sleep" ;; # pager functionnality loosely depends on sleep module
    esac
    echo "$modules"
}

# get grub modules for 'terminal*' command
#  $1  string  the terminal input or output
#  $2  string  the terminal module that is used
get_grub_modules_for_terminal_command()
{
    modules=
    case "$1" in
        gfxterm|at_keyboard) modules="$modules $1" ;;
        usb_keyboard*)       modules="$modules usb_keyboard" ;;
    esac
    echo "$modules"
}
get_grub_modules_for_terminal_input_command()
{
    echo "terminal_input $(get_grub_modules_for_terminal_command "$@")"
}
get_grub_modules_for_terminal_output_command()
{
    echo "terminal_output $(get_grub_modules_for_terminal_command "$@")"
}

# get grub modules for a special 'disk' command
#  $1  string  the disk that is used
get_grub_modules_for_disk_command()
{
    modules=
    case "$1" in
        memdisk) modules="$modules memdisk tar" ;;
        proc)    modules="$modules procfs" ;;
        hd*)     modules="$modules biosdisk" ;;
        ahci*|ata*|pata*|scsi*) modules="$modules $(echo "$1"|sed 's/[0-9]\+\(,[^)]\+\)\?$//g')" ;;
    esac
    if echo "$1"|grep -q ',[^)]\+$'; then
        part="$(echo "$1"|sed 's/^.*,//g;s/[0-9]\+$//g')"
        case "$part" in
            msdos) modules="$modules part_msdos" ;;
        esac
    fi
    echo "$modules"
}

# get grub modules for a special 'var' command
#  $1  string  the var that is used
get_grub_modules_for_var_command()
{
    modules=
    case "$1" in
        SECOND|MINUTE|HOUR|DAY|MONTH|YEAR) modules="$modules datehook" ;;
    esac
    echo "$modules"
}

# get grub modules for a grub shell command
#  $1  string  the grub shell command
get_cmd_grub_modules()
{
    cmd="$1"
    modules=

    # command is one of the 'test' module
    if echo "$cmd"|grep -q '^\(\(el\)\?if\|else\|fi\)$'; then
        modules="test"

    # if command is a special command (with parenthesis)
    elif echo "$cmd"|grep -q '^[^(]\+([^)]\+)$'; then
        special_command_name="$(echo "$cmd"|sed 's/^\([^(]\+\)(.*$/\1/g')"
        special_command_arg="$(echo "$cmd"|sed 's/^[^(]\+(\([^)]\+\))$/\1/g')"
        func="get_grub_modules_for_${special_command_name}_command"
        modules="$modules $(eval "$func '$special_command_arg'")"

    # no special command
    else
        modules="$(grep "^ *$cmd *:" "$GRUB_MODDIR/command.lst"|awk '{print $2}')"
    fi
    echo "$modules"
}

# get dependencies of a grub module
#  $1  string  the grub command/module name
# env vars used:
#  $GRUB_MODDIR  the grub modules directory
# return format is a list separated by space
# note: recursive
get_grub_module_deps()
{
    module="$1"

    already_found_deps="$(echo "$2"|trim|tr '\n' ' '|trim)"
    deps="$already_found_deps"

    new_deps=
    dep_line="$(grep "^\\*\\?$module:" "$GRUB_MODDIR"/moddep.lst 2>/dev/null || true)"
    if [ "$dep_line" != '' ]; then
        new_deps="$(echo "$dep_line"|sed 's/^\\*\\//g;s/ *: */ /g')"
    fi

    if [ "$new_deps" != '' ] && [ "$new_deps" != "$already_found_deps" ]; then
        for m in $new_deps; do
            if ! echo " $deps "|grep -q " $m "; then
                m_deps="$(get_grub_module_deps "$m" "$deps $m")"
                deps="$(echo "$deps $m_deps"|uniquify -s)"
            fi
        done
    fi
    echo "$deps"
}

# get the list of grub modules required for a command line
# in a grub shell script
#  $1  string  the line to parse
get_grub_modules_deps_for_line()
{
    for cmd in $(get_command_list_for_line "$1"); do
        get_cmd_grub_modules "$cmd"
    done|uniquify -s
}

# get the top level parent device of specified device path
#  $1  string  the device path
#  $2  string  (optional) the type of return value: name|path. Default: name
get_top_level_parent_device()
{
    key="$(if [ "$2" = 'path' ]; then echo 'PATH'; else echo 'NAME'; fi)"
    toplvldisks=$(lsblk --inverse --ascii --noheading --output "$key" "$1" 2>/dev/null \
                 |sed 's/^[[:blank:]]*`-//g' \
                 |cat -s)
    if [ "$toplvldisks" = '' ]; then
        fatal_error "Top level device %s not found for device path '%s' (not a device?)" "$key" "$1"
        return $FALSE
    fi
    if [ "$key" = 'PATH' ]; then
        echo "$toplvldisks"|head -n 1
    else
        echo "$toplvldisks"|tail -n 1
    fi
    return $TRUE
}

# get the PCI bus for the specified device path
#  $1  string  the device path
# return: the PCI bus
get_pci_bus_for_disk_device()
{
    toplvldisk="$(get_top_level_parent_device "$1")"
    pciblockpath="$(realpath /sys/block/"$toplvldisk")"
    pci_bus="$(get_pci_bus_for_device "$pciblockpath" "$toplvldisk")"
    echo "$pci_bus"
}

# get the PCI bus for the specified device path
#  $1  string  the device path
#  $2  string  an informative description of the device
# return: the PCI bus
get_pci_bus_for_device()
{
    device_desc="$2"
    if [ "$device_desc" != '' ]; then
        device_desc=" '$device_desc'"
    fi
    if ! echo "$1"|grep -q '^/sys/.*/pci[^/]\+/\([^/]\+\)/'; then
        echo "ERROR: not a PCI device$device_desc" >&2
        return $FALSE
    fi
    echo "$1"|sed 's#^/sys/.*/pci[^/]\+/\([^/]\+\)/.*$#\1#g'
}

# get the kernel driver used for a PCI device
#  $1  string  the PCI bus of the device
# return the driver name used by the kernel
get_driver_for_pci_device()
{
    LC_ALL=C lspci -s "$1" -k \
    |grep 'Kernel driver in use: '|awk -F ':' '{print $2}'|trim \
    ||true
}

# Generate a list of 9 HEX colors (space separated)
generate_color_list()
{
    # from: https://stackoverflow.com/a/40278172
    # shellcheck disable=SC2034
    for i in $(seq 1 9); do
        hexdump -n 3 -v -e '"#" 3/1 "%02X" "\n"' /dev/urandom
    done
}

# check a list of HEX colors (space separated)
check_color_list()
{
    # shellcheck disable=SC2048
    for c in $*; do
        if ! echo "$c"|grep -q '^#[a-fA-F0-9]\{6\}$'; then
            return $FALSE
        fi
    done
    return $TRUE
}

# select random theme name/bg
# based on current seconds
# $1  string  the list of theme names
select_random_theme()
{
    themes_count="$(echo "$1"|wc -w)"
    if [ "$themes_count" -eq 7 ] \
    || [ "$themes_count" -eq 8 ] \
    || [ "$themes_count" -eq 9 ]; then
        fatal_error "Invalid number of themes (can't be '%s', needs to be a divider of 60, "`
                    `"because randomness is based on seconds). Tips: remove themes to get to 6 "`
                    `"or add some to get to 10"
    elif [ "$themes_count" -gt 10 ]; then
        fatal_error "Invalid number of themes (can't be '%s', maximum allowed is 10)"
    fi
    steps="$((60 / themes_count))"
    echo '# select random theme based on current seconds'
    for multiplier in $(seq 0 "$((themes_count - 1))"); do
        s_value="$((59 - steps - $((steps * multiplier))))"
        s_cond="$(if [ "$multiplier" -eq 0 ]; then echo 'if'; else echo 'elif'; fi)"
        t_name="$(echo "$1"|tr ' ' '\n'|tail -n $((multiplier + 1))|head -n 1)"
    cat <<ENDCAT
$s_cond [ "\$SECOND" -gt "$s_value" ]; then
    set theme_name=$t_name
ENDCAT
    done
    echo 'fi'
}

# define terminal background color
# based on the current theme name
#  $1  string  the theme names (separated by space)
set_term_background_color()
{
    t_count=0
    for t in $1; do
        t_path="$GRUB_THEMES_DIR/$t/$GRUB_THEME_FILENAME"
        t_bgcolor="$(grep '^[[:blank:]]*#\?[[:blank:]]*desktop-color'`
                          `'[[:blank:]]*:[[:blank:]]*"[^"]\+"' "$t_path" \
                    |sed 's/^[[:blank:]]*#\?[[:blank:]]*desktop-color'`
                         `'[[:blank:]]*:[[:blank:]]*"\([^"]\+\)"/\1/'||true)"
        if [ "$t_bgcolor" != '' ]; then
            t_cond="$(if [ "$t_count" -eq 0 ]; then echo 'if'; else echo 'elif'; fi)"
            t_count="$((t_count + 1))"
cat <<ENDCAT
$t_cond [ "\$theme_name" = "$t" ]; then
    background_color "$t_bgcolor"
ENDCAT
        fi
    done
    if [ "$t_count" -gt 0 ]; then
        echo 'fi'
    fi
}

# define theme's modules to load
#  $1  string  the themes names (separated by space)
load_theme_modules()
{
    t_count=0
    for t in $1; do
        modules_theme="$(get_modules_from_theme_files \
            "$(find "$GRUB_THEMES_DIR/$t" \( -name "$GRUB_THEME_FILENAME" \
                                          -o -name "$GRUB_THEME_INNER_FILENAME" \) \
                                          -printf "%p$NL")" \
        )"
        t_cond="$(if [ "$t_count" -eq 0 ]; then echo 'if'; else echo 'elif'; fi)"
        t_count="$((t_count + 1))"
        cat <<ENDCAT
$t_cond [ "\$theme_name" = "$t" ]; then
    $(for m in $modules_theme; do echo "insmod $m"; done|indent 4)
ENDCAT
    done
    if [ "$t_count" -gt 0 ]; then
        echo 'fi'
    fi
}

# check other hosts option input value
check_opt_other_hosts()
{
    _s='[[:blank:]]*'
    if [ "$opt_other_hosts" = '' ]; then
        return $TRUE
    fi
    echo "$opt_other_hosts" \
       | grep -q "^${_s}\\(\\w\\|-\\)\\+${_s}:${_s}[^|]\\+${_s}"`
                 `"\\(|${_s}\\(\\w\\|-\\)\\+${_s}:${_s}[^|]\\+${_s}\\)*$"
}

# get machine UUID to uniquely identify the host
get_machine_uuid()
{
    m_uuid=
    # shellcheck disable=SC2230
    if ! which dmidecode >/dev/null 2>&1; then
        fatal_error "Binary 'dmidecode' is required to get the host UUID"
    fi
    m_uuid="$(LC_ALL=C dmidecode --string system-uuid|sed 's/-/_/g')"
    if [ "$m_uuid" = '' ]; then
       m_uuid="$(LC_ALL=C dmidecode --type processor|grep  '^[[:blank:]]\+ID:[[:blank:]]\+'\
                                                    |sed 's/^[[:blank:]]\+ID:[[:blank:]]\+//g')"
    fi
    if bool "$GRUB_EARLY_SHORT_UUID"; then
        m_uuid="$(echo "$m_uuid"|sed 's/_.*//g'|cut -c -16)"
    fi
    echo "$m_uuid"
}

# get a list of submenu class key/value arguments from a list of classes
get_submenu_classes()
{
    echo "--class $1"|sed 's/[[:blank:]]*,[[:blank:]]*/ --class /g'
}

# parse theme files to extract modules required
#  $1  string  a list of paths separated by $NL (newline)
get_modules_from_theme_files()
{
    t_modules=
    IFS="$NL"
    for f in $1; do
        IFS="$IFS_BAK"
        if [ -r "$f" ]; then
            if grep -q '^[[:blank:]]*+[[:blank:]]*\(progress_bar\|circular_progress\)'`
                       `'[[:blank:]]*\({\|$\)' "$f"; then
                t_modules="$t_modules progress"
            fi
            if grep -q -i '^[^#]\+\.png["'"'"']\?$' "$f"; then
                t_modules="$t_modules png"
            fi
            if grep -q -i '^[^#]\+\.tga["'"'"']\?$' "$f"; then
                t_modules="$t_modules tga"
            fi
            if grep -q -i '^[^#]\+\.jpe\?g["'"'"']\?$' "$f"; then
                t_modules="$t_modules jpeg"
            fi
        fi
    done
    echo "$t_modules"|uniquify -s
}

# list ps2 keyboard detected
# return format is: [serioXXX/inputYYY] serio_name: keyboard name
detect_ps2_keyboards()
{
    # or grep -li 'keyboard driver' /sys/class/input/*/device/driver/description
    #ls -1 /sys/bus/serio/drivers/atkbd/*/input/*/name|while read -r input_name_file; do
    find /sys/bus/serio/drivers/atkbd/ -follow -maxdepth 4 -type f -name 'name' \
            -path '/sys/bus/serio/drivers/atkbd/*/input/*/name' 2>/dev/null     \
            |while read -r input_name_file; do
        input_dev_dir="$(dirname "$input_name_file")"
        input_dev="$(basename "$input_dev_dir")"
        input_name="$(head -n 1 "$input_name_file")"
        serio_dev_dir="$(dirname "$(dirname "$input_dev_dir")")"
        serio_dev="$(basename "$serio_dev_dir")"
        serio_dev_name='unkown'
        if [ -r "$serio_dev_dir"/description ]; then
            serio_dev_name="$(head -n 1 "$serio_dev_dir"/description)"
        fi
        printf '[%s/%s] %s: %s' "$serio_dev" "$input_dev" "$serio_dev_name" "$input_name"
    done || true
}

# list usb keyboard detected
# return format is: [usbhid_dev_num] vendor/product: keyboard name
detect_usb_keyboards()
{
    grep -l '^01$' /sys/bus/usb/drivers/*/*/bInterfaceProtocol 2>/dev/null|while read -r h_ip; do
        usb_driver_dir="$(dirname "$h_ip")"
        usb_driver_dirname="$(basename "$usb_driver_dir")"
        find "$usb_driver_dir/" -maxdepth 1 -not -path "$usb_driver_dir/" -type d \
        |while read -r dev; do
            if [ -d "$dev"/input ]; then
                find "$dev/input" -maxdepth 1 -not -path "$dev" -type d|while read -r input; do
                    dev_name='unknown'
                    if [ -r "$input"/name ]; then
                        dev_name="$(head -n 1 "$input"/name)"
                    fi
                    dev_vendor='unknown'
                    if [ -r "$input"/id/vendor ]; then
                        dev_vendor="$(head -n 1 "$input"/id/vendor)"
                    fi
                    dev_product='unknown'
                    if [ -r "$input"/id/product ]; then
                        dev_product="$(head -n 1 "$input"/id/product)"
                    fi
                    if [ "$dev_name" != 'unknown' ] \
                    || [ "$dev_vendor" != 'unknown' ] \
                    || [ "$dev_product" != 'unknown' ]; then
                        txt_id_name="$(printf "%s (%s/%s)" "$dev_name" "$dev_vendor" "$dev_product")"

                        usb_dev_path="$(realpath "$usb_driver_dir")"
                        pci_bus="$(get_pci_bus_for_device "$usb_dev_path" "$usb_driver_dirname")"
                        driver="$(get_driver_for_pci_device "$pci_bus")"
                        if [ "$driver" = '' ]; then
                            fatal_error "Failed to find driver for usb keyboard '%s'" "$txt_id_name"
                        fi

                        printf "(%s) [%s] %s/%s: %s\\n" \
                            "$driver" "$usb_driver_dirname" "$dev_vendor" "$dev_product" "$dev_name"
                    fi
                done || true
            fi
        done || true
    done || true
}

# get the drivers required for the disk
#  $1  string  the disk device path (i.e.: /dev/sda1)
#  $2  string  (optional) the pci bus ()
get_drivers_for_disk()
{
    driver=
    device_path="$1"
    pci_bus="$2"
    if [ "$pci_bus" = '' ]; then
        pci_bus="$(get_pci_bus_for_disk_device "$device_path")"
    fi
    driver="$(get_driver_for_pci_device "$pci_bus")"
    if [ "$driver" = '' ]; then
        fatal_error "Failed to find driver for disk '%s'" "$device_path"
    fi
}

# return true if the grub modules list contains one that prevent using the firmware driver
#  $1  string  the list of grub modules (space separated)
contains_a_grub_module_that_disable_firmware_driver()
{
    echo " $1 "|grep -q ' [uoae]hci\|usbms\|nativedisk '
}


# options definition
# using GNU getopt here, install it if not the default on your distro
options_definition="$( \
    getopt --options hv:c:no:mi:p \
           --longoptions 'help,verbosity:,config:,no-install,other-hosts:,'`
                         `'multi-hosts,host-id,dev-from-child-part-uuid' \
           --name "$THIS_SCRIPT_NAME" \
           -- "$@")"
if [ "$options_definition" = '' ]; then
    echo "Terminating..." >&2
    exit 1
fi
eval set -- "$options_definition"

# options parsing
opt_help=false
config=$GRUB_CONFIG_DEFAULT
opt_noinstall=false
opt_other_hosts=
opt_multi_hosts=false
opt_host_id=
opt_part_uuid=false
while true; do
    case "$1" in
        -h | --help        ) opt_help=true        ; shift   ;;
        -v | --verbosity   ) VERBOSITY=$2         ; shift 2 ;;
        -c | --config      ) config=$2            ; shift 2 ;;
        -n | --no-install  ) opt_noinstall=true   ; shift ;;
        -o | --other-hosts ) opt_other_hosts=$2   ; shift 2 ;;
        -m | --multi-hosts ) opt_multi_hosts=true ; shift ;;
        -i | --host-id     ) opt_host_id=$2       ; shift 2 ;;
        -p | --part-uuid   ) opt_part_uuid=true   ; shift ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
done

# help option
if bool "$opt_help"; then
    usage
    exit 0
fi

# config option
if [ ! -r "$config" ]; then
    fatal_error "Configuration file '%s' doesn't exist nor is readable" "$config"
fi

# device argument
if [ "$1" != "" ]; then
    device="$1"
else
    fatal_error "no device specified"
fi

# partition UUID option
if bool "$opt_part_uuid"; then
    debug "Device child partition UUID: %s" "$device"
    part_dev="$(lsblk --list --output "PATH,UUID"|grep "^[^ ]\\+ \\+$device\$" \
                                                 |awk '{print $1}'|trim||true)"
    debug "Device child partition PATH: %s" "$part_dev"
    if [ "$part_dev" = '' ]; then
        fatal_error "Device with partition UUID '%s' not found" "$device"
    fi
    device="$(get_top_level_parent_device "$part_dev" 'path')"
    debug "Found top level device: %s" "$device"
fi

# not a device full path
if ! lsblk "$device" >/dev/null 2>&1; then
    dev_found=false
    for key in NAME MODEL SERIAL WWN; do
        if lsblk --list --output "$key"|grep -q "^$device\$"; then
            devices="$(lsblk --list --output "PATH,$key"|grep "^[^ ]\\+ \\+$device\$" \
                                                        |awk '{print $1}'|trim)"
            if [ "$(echo "$devices"|wc -l)" -gt 1 ]; then
                fatal_error "Found multiple device for %s '%s'" "$key" "$device"
            fi
            device="$devices"
            debug "Found device by %s: %s" "$key" "$device"
            dev_found=true
        fi
    done
    # unkown
    if ! bool "$dev_found"; then
        fatal_error "invalid device '%s'" "$device"
    fi
fi
debug "Device: %s" "$device"


# setup the hostname
HOSTNAME="$(hostname)"
debug "HOSTNAME: %s" "$HOSTNAME"

# source config file
debug "Sourcing configuration '%s'" "$config"
# shellcheck disable=SC1090
. "$config"


# ensure binaries are found, and their version matches
b_version=
b_last_vers=
b_last_bin=
for bin in \
    "$GRUB_KBDCOMP" \
    "$GRUB_MKIMAGE" \
    "$GRUB_PROBE"   \
    "$GRUB_BIOS_SETUP"
do
    if [ ! -x "$bin" ]; then
        fatal_error "binary '%s' not found (at path: '%s')" "$(basename "$bin")" "$bin"
    fi
    b_version="$("$bin" --version|awk '{print $3}')"
    if [ "$b_version" != '' ]; then
        if [ "$b_last_vers" != '' ] && [ "$b_version" != "$b_last_vers" ]; then
            fatal_error "grub binaries version differ: %s (%s) != %s (%s)" \
                "$b_version" "$bin" "$b_last_vers" "$b_last_bin"
        fi
        b_last_vers="$b_version"
        b_last_bin="$bin"
    fi
done

# and grub module directory too
if [ ! -d "$GRUB_MODDIR" ]; then
    fatal_error "grub modules directory '%s' not found" "$GRUB_MODDIR"
fi

# set some default configuration
if [ "$GRUB_EARLY_VERBOSITY" = '' ]; then
    debug "VERBOSITY (in cfg script): %s (%s)" "QUIET" "$V_QUIET"
    GRUB_EARLY_VERBOSITY="$V_QUIET"
fi
if [ "$GRUB_EARLY_CMDLINE_LINUX" = '' ]; then
    debug "CMDLINE_LINUX: %s" "$GRUB_CMDLINE_LINUX_DEFAULT"
    GRUB_EARLY_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX_DEFAULT"
fi
if [ "$GRUB_EARLY_TIMEOUT" = '' ]; then
    debug "TIMEOUT: %s" "$GRUB_TIMEOUT"
    GRUB_EARLY_TIMEOUT="$GRUB_TIMEOUT"
fi
if [ "$GRUB_EARLY_GFXMODE" = '' ]; then
    debug "GFXMODE: %s" "$GRUB_GFXMODE"
    GRUB_EARLY_GFXMODE="$GRUB_GFXMODE"
fi
if [ "$GRUB_EARLY_GFXPAYLOAD" = '' ]; then
    debug "GFXPAYLOAD: %s" "$GRUB_GFXPAYLOAD_LINUX"
    GRUB_EARLY_GFXPAYLOAD="$GRUB_GFXPAYLOAD_LINUX"
fi
if [ "$GRUB_EARLY_DISABLE_SUBMENU" = '' ]; then
    debug "DISABLE_SUBMENU: %s" "$GRUB_DISABLE_SUBMENU"
    GRUB_EARLY_DISABLE_SUBMENU="$GRUB_DISABLE_SUBMENU"
fi
if [ "$GRUB_EARLY_KERNEL_WRAPPER_SUBMENU_CLASSES" = '' ]; then
    GRUB_EARLY_KERNEL_WRAPPER_SUBMENU_CLASSES="wrapper"
    if [ "$GRUB_EARLY_KERNEL_SUBMENUS_CLASSES" != '' ]; then
        GRUB_EARLY_KERNEL_WRAPPER_SUBMENU_CLASSES="$(printf '%s,%s' \
            "$GRUB_EARLY_KERNEL_WRAPPER_SUBMENU_CLASSES"            \
            "$GRUB_EARLY_KERNEL_SUBMENUS_CLASSES")"
    fi
fi
if [ "$GRUB_EARLY_KERNEL_SUBLENUS_TITLE_RECOVERY" = '' ]; then
    GRUB_EARLY_KERNEL_SUBLENUS_TITLE_RECOVERY="$GRUB_EARLY_KERNEL_SUBLENUS_TITLE (recovery)"
fi

# day/night mode
day_night_mode=false
for v in %s_HOUR \
         THEMES_DIR_%s \
         THEME_DEFAULT_%s \
         TERMINAL_BG_COLOR_%s \
         TERMINAL_BG_IMAGE_%s \
         RANDOM_BG_IMAGE_%s \
         RANDOM_BG_COLOR_%s
do
    # shellcheck disable=SC2059
    vday_name="$(printf "GRUB_EARLY_$v" "DAY")"
    eval 'vday="$'"$vday_name"'"'
    # shellcheck disable=SC2059
    vnight_name="$(printf "GRUB_EARLY_$v" "NIGHT")"
    eval 'vnight="$'"$vnight_name"'"'
    # shellcheck disable=SC2154
    if [ "$vday" != '' ] && [ "$vnight" = '' ] \
    || [ "$vday" = '' ] && [ "$vnight" != '' ]; then
        fatal_error "Both $vday_name and $vnight_name must be specified"
    fi
done
for k in DAY_TIME NIGHT_TIME; do
    eval 'v="$'"$k"'"'
    if [ "$v" != '' ] && ! echo "$v"|trim|grep -q '^[0-9]\{2\}:[0-9]\{2\}$'; then
        fatal_error "Invalid $k format (must be: %H:%M, i.e.: 08:00 or 21:30)"
    fi
done
if [ "$GRUB_EARLY_DAY_TIME" != '' ] && [ "$GRUB_EARLY_NIGHT_TIME" != '' ]; then
    info "Day/Night mode enabled"
    day_night_mode=true

    GRUB_EARLY_DAY_TIME="$(echo "$GRUB_EARLY_DAY_TIME"|trim)"
    GRUB_EARLY_NIGHT_TIME="$(echo "$GRUB_EARLY_NIGHT_TIME"|trim)"

    DAY_TIME_H="$(echo "$GRUB_EARLY_DAY_TIME"|awk -F ':' '{print $1}'|sed 's/^0\([0-9]\)$/\1/g')"
    DAY_TIME_M="$(echo "$GRUB_EARLY_DAY_TIME"|awk -F ':' '{print $2}'|sed 's/^0\([0-9]\)$/\1/g')"
    NIGHT_TIME_H="$(echo "$GRUB_EARLY_NIGHT_TIME"|awk -F ':' '{print $1}'|sed 's/^0\([0-9]\)$/\1/g')"
    NIGHT_TIME_M="$(echo "$GRUB_EARLY_NIGHT_TIME"|awk -F ':' '{print $2}'|sed 's/^0\([0-9]\)$/\1/g')"
fi

# suffixes according to day/night mode or none
var_suffixes=$FALSE
if bool "$day_night_mode"; then
    var_suffixes='DAY NIGHT'
fi
debug "var_suffixes: %s" "$var_suffixes"

# process all theming related vars
for s in $var_suffixes; do
    var_suffix="$(if [ "$s" != "$FALSE" ]; then echo "_$s"; fi)"
    var_text="$(  if [ "$s" != "$FALSE" ]; then echo " ($s)"; fi)"

    # theming is disabled by default
    eval 'THEME_ENABLED'"$var_suffix"'=false'

    # init theme vars
    eval 'ALL_THEME_NAMES'"$var_suffix"'='
    eval 'd="$GRUB_EARLY_THEMES_DIR'"$var_suffix"'"'

    # if the theme directory is not defined
    if [ "$d" = '' ]; then
        if [ "$s" != "$FALSE" ]; then
            if [ "$GRUB_EARLY_THEMES_DIR" != '' ]; then
                d="$GRUB_EARLY_THEMES_DIR"
                eval 'GRUB_EARLY_THEMES_DIR'"$var_suffix"'="'"$d"'"'
            else
                debug "No theme directory specified"
            fi
        else
            debug "No theme directory specified"
        fi
    fi

    # if the theme directory is defined (now)
    if [ "$d" != '' ]; then
        if [ -d "$d" ]; then

            # list all theme names
            themes_names="$(find "$d" -maxdepth 1 -type d -not -path "$d" -printf "%P$NL")"
            eval 'ALL_THEME_NAMES'"$var_suffix"'="$themes_names"'
            
            # check that they do not contain space or tab or newline
            IFS="$NL"
            for t in $themes_names; do
                IFS="$IFS_BAK"
                if printf '%s' "$t"|grep -q '[[:blank:]]'; then
                    fatal_error "Invalid theme name '%s' "`
                                `"(must not contain space/tab character) from '%s'" "$t" "$d/$t"
                fi
            done

            if [ "$themes_names" = '' ]; then
                warning "No theme found in directory '%s'" "$d"
            else
                debug "Theme names$var_text: %s" "$(printf "%s" "$themes_names"|tr '\n' ',')"

                # handle the THEMES_DIR and GRUB_EARLY_THEME_DEFAULT options
                eval 'theme_default="$GRUB_EARLY_THEME_DEFAULT'"$var_suffix"'"'
                if [ "$theme_default" = '' ]; then
                    theme_default="$(echo "$themes_names"|head -n 1)"
                    eval 'GRUB_EARLY_THEME_DEFAULT'"$var_suffix"'="$theme_default"'
                    debug "Default theme$var_text: %s" "$theme_default"
                fi

                # enable theming
                eval 'THEME_ENABLED'"$var_suffix"'=true'
                debug "Enabling theming$var_text"
            fi
        else
            debug "Theme directory '%s' doesn't exist" "$d"
        fi
    fi
done

# when day/night mode is enabled
if bool "$day_night_mode"; then

    # theming must be enabled for both modes
    if bool "$THEME_ENABLED_DAY" && ! bool "$THEME_ENABLED_NIGHT" \
    || ! bool "$THEME_ENABLED_DAY" && bool "$THEME_ENABLED_NIGHT"; then
        fatal_error "It cannot have a situation where theming is enabled at DAY time "`
                    `"but not at NIGHT time, or the opposite"
    else
        THEME_ENABLED=true
    fi
fi

# keep on processing the rest of theming related vars
RANDOM_BG_COLOR_ENABLED=false
for s in $var_suffixes; do
    var_suffix="$(if [ "$s" != "$FALSE" ]; then echo "_$s"; fi)"
    var_text="$(  if [ "$s" != "$FALSE" ]; then echo " ($s)"; fi)"

    # handle GRUB_EARLY_RANDOM_BG_COLOR option value
    eval 'random_bg_c="$GRUB_EARLY_RANDOM_BG_COLOR'"$var_suffix"'"'
    if bool "$THEME_ENABLED" && [ "$random_bg_c" != '' ]; then
        if [ "$random_bg_c" = 'generated' ]; then
            random_bg_c="$(generate_color_list)"
            eval 'GRUB_EARLY_RANDOM_BG_COLOR'"$var_suffix"'="$random_bg_c"'
            debug "Colors generated$var_text: %s" "$(printf "%s" "$random_bg_c"|tr '\n' ',')"
        fi
        if ! check_color_list "$random_bg_c"; then
            fatal_error "Invalid color list for option \`%s' (%s)" \
                "GRUB_EARLY_RANDOM_BG_COLOR$var_suffix" "$random_bg_c"
        fi
        RANDOM_BG_COLOR_ENABLED=true
    fi
done

# random theme enabling
if ! bool "$GRUB_EARLY_RANDOM_THEME"; then
    if bool "$RANDOM_BG_COLOR_ENABLED" \
    || [ "$GRUB_EARLY_RANDOM_BG_IMAGE" != '' ]    \
    || [ "$GRUB_EARLY_RANDOM_BG_IMAGE_DAY" != '' ]; then
        GRUB_EARLY_RANDOM_THEME=true
        debug "Enabling RANDOM_THEME"
    fi
fi


# check other hosts option
if ! check_opt_other_hosts; then
    fatal_error "Invalid value for option '--other-hosts' (input: %s)" "$opt_other_hosts"
fi

# define if we are in a multi-host mode
multi_host_mode=false
if [ "$opt_other_hosts" != '' ] || bool "$opt_multi_hosts"; then
    multi_host_mode=true
fi

# other hosts name/IDs
other_hosts=

# in multi-host mode
if bool "$multi_host_mode"; then
    info "Multi-host mode enabled"

    # build a unique host identifier
    if [ "$opt_host_id" = '' ]; then
        MACHINE_UUID="$(get_machine_uuid)"
        HOST_ID="${HOSTNAME}_$MACHINE_UUID"
    else
        HOST_ID="$opt_host_id"
    fi
    debug "HOST_ID: %s" "$HOST_ID"

    # if other hosts were specified
    if [ "$opt_other_hosts" != '' ]; then

        # split other hosts by line
        opt_other_hosts="$(echo "$opt_other_hosts"|tr '|' '\n'|trim)"

        # exclude current host from other hosts, and blank lines too
        opt_other_hosts="$(echo "$opt_other_hosts" \
                          |grep -v "^[[:blank:]]*${HOST_ID}[[:blank:]]*:[[:blank:]]*" \
                          |grep -v '^[[:blank:]]*$')"

        # collect hosts name/IDs
        other_hosts="$(echo "$opt_other_hosts"|awk -F ':' '{print $1}'|trim)"
        debug "Other hosts: %s" "$(printf "%s" "$other_hosts"|tr '\n' ',')"
    fi
fi

# create grub early directory and memdisk
if [ ! -d "$GRUB_EARLY_DIR" ]; then
    info "Creating early directory '%s'" "$GRUB_EARLY_DIR"
    # shellcheck disable=SC2174
    mkdir -m 0700 -p "$GRUB_EARLY_DIR"
fi
if bool $GRUB_EARLY_EMPTY_MEMDISK_DIR; then
    info "Deleting memdisk directory '%s'" "$GRUB_MEMDISK_DIR"
    rm -fr "$GRUB_MEMDISK_DIR"
fi
if [ ! -d "$GRUB_MEMDISK_DIR" ]; then
    info "Creating memdisk directory '%s'" "$GRUB_MEMDISK_DIR"
    # shellcheck disable=SC2174
    mkdir -m 0700 -p "$GRUB_MEMDISK_DIR"
fi

# list of configuration files to parse for extracting commands/modules
conf_files=
other_hosts_conf_files=

# list of requirements files from other hosts
other_hosts_requirements_files=

# path related to host files are not prefixed by default
host_prefix=

# in multi-host mode
if bool "$multi_host_mode"; then

    # if other hosts were specified
    if [ "$opt_other_hosts" != '' ]; then

        # for every host file archive
        debug "Processing other host file archives ..."
        IFS="$NL"
        for line in $opt_other_hosts; do
            IFS="$IFS_BAK"

            # get host ID
            other_host_id="$(echo "$line"|awk -F ':' '{print $1}'|trim)"
            debug " - $other_host_id"

            # get the host files archive path
            other_host_archive="$(echo "$line"|sed 's/^[^:]\+://g'|trim)"

            # archive do not exist or is not readable
            if [ ! -r "$other_host_archive" ]; then
                fatal_error "Host '%s' archive file '%s' doesn't exist "`
                            `"nor is readable" "$other_host_id" "$other_host_archive"
            fi

            # extract the files
            tmparc="$(mktemp -d)"
            debug "     extracting '%s' to '%s'" "$other_host_archive" "$tmparc"
            tar -xf "$other_host_archive" -C "$tmparc"

            # for every required file
            for fn in $GRUB_HOST_DETECTION_FILENAME \
                      $GRUB_HOST_CONFIGURATION_FILENAME \
                      $GRUB_HOST_MENUS_FILENAME
            do

                # check that file exists and is readable
                host_file="$tmparc/$fn"
                if [ ! -r "$host_file" ]; then
                    fatal_error "Required host '%s' file '%s' doesn't exist "`
                                `"nor is readable" "$other_host_id" "$host_file"
                fi
            done

            # remove existing host dir
            if [ -d "$GRUB_MEMDISK_DIR"/"$other_host_id" ] \
            && [ "$GRUB_MEMDISK_DIR/$other_host_id" != '/' ]; then
                debug "     removing current host dir '%s'" "$GRUB_MEMDISK_DIR/$other_host_id"
                # shellcheck disable=SC2115
                rm -fr "$GRUB_MEMDISK_DIR"/"$other_host_id"
            fi

            # move the files to the memdisk dir
            if [ -d "$tmparc" ]; then
                debug "     moving '%s' to '%s'" "$tmparc" "$GRUB_MEMDISK_DIR/$other_host_id"
                mv "$tmparc" "$GRUB_MEMDISK_DIR"/"$other_host_id"
            fi

            # if a requirement file is present, add it to the list
            r_file="$GRUB_MEMDISK_DIR/$other_host_id/$GRUB_MODULES_REQUIREMENTS_FILENAME"
            if [ -f "$r_file" ]; then
                debug "     adding requirement file '%s' to the list" "$r_file"
                other_hosts_requirements_files="$other_hosts_requirements_files${NL}$r_file"
            fi
        done
    fi

    # create the host directory
    host_dir="$GRUB_MEMDISK_DIR"/"$HOST_ID"
    if [ ! -d "$host_dir" ]; then
        info "Creating 'host' directory '%s'" "$host_dir"
        # shellcheck disable=SC2174
        mkdir -m 0700 -p "$host_dir"
    fi

    # path related to host files are prefixed
    host_prefix="/$HOST_ID"

    # update variables with host dir prefix
    GRUB_THEMES_DIR=${GRUB_MEMDISK_DIR}${host_prefix}/themes
    # TODO makes the backgrounds specific to the theme
    #GRUB_BG_DIR=${GRUB_MEMDISK_DIR}${host_prefix}/backgrounds
    # TODO makes the image specific to the theme
    GRUB_TERMINAL_BG_IMAGE=${GRUB_MEMDISK_DIR}${host_prefix}/terminal_background.tga
fi


# no custom core.cfg provided
if [ "$GRUB_EARLY_CORE_CFG" = '' ]; then

# echo ""
# echo "Devices detected:"
# ls
# echo ""
# echo "Hit enter to continue grub-shell script ..."
# read cont

    # /!\ comments will be removed because at this stage they are not supported
    cat > "$GRUB_CORE_CFG" <<ENDCAT | sed '/^[[:blank:]]*#/d'
set root=(memdisk)
set prefix=(\$root)

set enable_progress_indicator=0

normal \$prefix/$(basename "$GRUB_NORMAL_CFG")
ENDCAT

# custom core.cfg provided
else
    info "Copying '%s' to '%s'" "$GRUB_EARLY_CORE_CFG" "$GRUB_CORE_CFG"
    cp "$GRUB_EARLY_CORE_CFG" "$GRUB_CORE_CFG"
fi

# build the modules list
debug "Building 'preloaded' grub modules list for the current host ..."

# modules for core.cfg
modules_core="$(
    for cmd in $(get_command_list "$GRUB_CORE_CFG"); do
        get_cmd_grub_modules "$cmd"
    done|uniquify -s)"
debug " - modules for %s: %s" "$(basename "$GRUB_CORE_CFG")" "$modules_core"


# create the keyboard layout
if [ "$GRUB_EARLY_KEYMAP" != 'en' ] && [ "$GRUB_EARLY_KEYMAP" != 'us' ]; then
    kbdlayout_dest=${GRUB_MEMDISK_DIR}${host_prefix}/${GRUB_EARLY_KEYMAP}.gkb
    info "Creating layout '%s' to '%s'" "$GRUB_EARLY_KEYMAP" "$kbdlayout_dest"
    tmp_err=$(mktemp)
    if ! "$GRUB_KBDCOMP" -o "$kbdlayout_dest" "$GRUB_EARLY_KEYMAP" \
       >/dev/null 2>"$tmp_err"; then
        cat "$tmp_err" >&2
        rm -f "$tmp_err"
        fatal_error "Failed to generate the keyboard layout"
    fi
    rm -f "$tmp_err"
fi

# ensure locale is up to date
locale_short="$(echo "$GRUB_EARLY_LOCALE"|trim|cut -c -2)"
if [ "$locale_short" != 'en' ]; then
    locale_dest=${GRUB_MEMDISK_DIR}${host_prefix}/${locale_short}.mo
    info "Copying locale '%s'' to '%s'" "$GRUB_EARLY_LOCALE" "$locale_dest"
    cp "$GRUB_PREFIX/share/locale/${locale_short}/LC_MESSAGES/grub.mo" "$locale_dest"
fi

# if gfxterm is not disabled
if ! bool "$GRUB_EARLY_NO_GFXTERM"; then

    # ensure font is up to date
    font_src="$GRUB_PREFIX/share/grub/$GRUB_EARLY_FONT.pf2"
    if echo "$GRUB_EARLY_FONT"|grep -q '/' \
    || echo "$GRUB_EARLY_FONT"|grep -q '\.pf2$' && [ -f "$GRUB_EARLY_FONT" ]; then
        font_src="$GRUB_EARLY_FONT"
    elif echo "$GRUB_EARLY_FONT"|grep -q '\.pf2$'; then
        font_src="$GRUB_PREFIX/share/grub/$GRUB_EARLY_FONT"
    fi
    font_dest="${GRUB_MEMDISK_DIR}${host_prefix}/$(basename "$font_src" '.pf2').pf2"
    info "Copying font '%s' to '%s'" "$(basename "$font_src" '.pf2')" "$font_dest"
    cp "$font_src" "$font_dest"

    # ensure theme is up to date
    if bool "$THEME_ENABLED"; then

        debug "Deleting themes dir '%s'" "$GRUB_THEMES_DIR"
        rm -fr "$GRUB_THEMES_DIR"

        info "Creating theme dir '%s'" "$GRUB_THEMES_DIR"
        # shellcheck disable=SC2174
        mkdir -m 0700 -p "$GRUB_THEMES_DIR"

        # processing themes in normal mode or day/night mode
        for s in $var_suffixes; do
            var_suffix="$(if [ "$s" != "$FALSE" ]; then echo "_$s"; fi)"
            var_text="$(  if [ "$s" != "$FALSE" ]; then echo " ($s)"; fi)"

            # theme dir source
            eval 'theme_dir_src="$GRUB_EARLY_THEMES_DIR'"$var_suffix"'"'

            # no random background color
            eval 'random_bg_color="$GRUB_EARLY_RANDOM_BG_COLOR'"$var_suffix"'"'
            # shellcheck disable=SC2154
            if [ "$random_bg_color" = '' ]; then
                info "Copying themes dir$var_text '%s' to '%s'" "$theme_dir_src/*" "$GRUB_THEMES_DIR/"
                cp -r "$theme_dir_src"/* "$GRUB_THEMES_DIR"/

            # random background color
            else

                # default theme
                eval 'default_theme="$GRUB_EARLY_THEME_DEFAULT'"$var_suffix"'"'

                # if default theme should be included
                eval 'nodefault="$GRUB_EARLY_RANDOM_BG_COLOR_NODEFAULT'"$var_suffix"'"'
                if [ "$nodefault" = '' ] || ! bool "$nodefault"; then

                    # copy default (first) theme
                    if [ ! -d "$GRUB_THEMES_DIR/$default_theme" ]; then
                        info "Copying default theme$var_text '%s' to '%s'" \
                            "$theme_dir_src/$default_theme" "$GRUB_THEMES_DIR/"
                        cp -r "$theme_dir_src/$default_theme" "$GRUB_THEMES_DIR/"
                    fi

                    # update theme names
                    eval 'ALL_THEME_NAMES'"$var_suffix"'="$default_theme"'

                else
                    debug "Default theme$var_text '%s' is excluded by user demand (%s)" \
                        "$default_theme" "GRUB_EARLY_RANDOM_BG_COLOR_NODEFAULT$var_suffix"

                    # update theme names
                    eval 'ALL_THEME_NAMES'"$var_suffix"'='
                fi

                # generate derivative from the default theme with the background color changed
                info "Generating random background theme derivatives$var_text ..."
                for c in $random_bg_color; do
                    t_name="$(echo "$c"|sed 's/^#/'"$default_theme"'_/')"
                    t_path="$GRUB_THEMES_DIR/$t_name"
                    debug " - %s" "$t_name"
                    cp -r "$theme_dir_src/$default_theme" "$t_path"
                    sed_cmd='s/^[[:blank:]]*#\?\([[:blank:]]*desktop-color'`
                            `'[[:blank:]]*:[[:blank:]]*\)"[^"]\+"/\1"'"$c"'"/g'
                    sed "$sed_cmd" -i "$t_path/$GRUB_THEME_FILENAME"
                    if [ -w "$t_path/$GRUB_THEME_INNER_FILENAME" ]; then
                        sed "$sed_cmd" -i "$t_path/$GRUB_THEME_INNER_FILENAME"
                    fi
                    eval 'ALL_THEME_NAMES'"$var_suffix"'="$ALL_THEME_NAMES'"$var_suffix"' $t_name"'
                done

                debug "Theme names$var_text updated: %s" \
                    "$(eval 'echo "$ALL_THEME_NAMES'"$var_suffix"'"'|trim)"
            fi
        done
    fi

    # TODO implement day/night mode with suffixes like above
    # TODO makes the image specific to the theme
#     # ensure terminal background image is up to date
#     if bool "$THEME_ENABLED" && [ -f "$GRUB_EARLY_TERMINAL_BG_IMAGE" ]; then
#         info "Copying terminal background image dir '%s' to '%s'" "$GRUB_EARLY_TERMINAL_BG_IMAGE" "$GRUB_TERMINAL_BG_IMAGE"
#         cp "$GRUB_EARLY_TERMINAL_BG_IMAGE" "$GRUB_TERMINAL_BG_IMAGE"
#     fi
fi

# kernel entry specified by user
if [ "$GRUB_EARLY_SINGLE_KERNEL" != '' ]; then
    kernels="$GRUB_EARLY_SINGLE_KERNEL"
    info "User specified kernel: %s" "$kernels"

# detect all initramfs and kernel
else
    debug "Detecting bootable kernels ..."
    kernels="$(find /boot -maxdepth 1 -type f -name 'vmlinuz-*' -printf "%P\\n" \
              |sed 's/^vmlinuz-//g'|sort -urV)"
    info "Found kernel(s): %s" "$(echo "$kernels"|trim)"
fi

# NO_MENU option and kernel not specified by user and multiple kernels found
if bool "$GRUB_EARLY_NO_MENU" && [ "$GRUB_EARLY_SINGLE_KERNEL" = '' ] \
&& [ "$(echo "$kernels"|wc -l)" -gt 1 ]; then
    kernels="$(echo "$kernels"|head -n 1)"
    warning "Will only use the first kernel found: '%s' (because of option: %s)" "$kernels" 'NO_MENU'
fi

# detect required disk UUIDs to unlock /boot
debug "Detecting required disk UUIDs to unlock /boot ..."
boot_required_uuid="$($GRUB_PROBE -t cryptodisk_uuid /boot)"
debug "Found: %s" "$(echo "$boot_required_uuid"|tr '\n' ','|sed 's/ *, *$//')"

# detect required disk UUIDs to define initial root fs
debug "Detecting required disk UUIDs to define initial root fs ..."
rootfs_initial_uuid="$($GRUB_PROBE -t arc_hints /boot)"
debug "Found: %s" "$(echo "$rootfs_initial_uuid"|tr '\n' ','|sed 's/ *, *$//')"

# detect disk UUIDs to search for root fs
debug "Detecting disk UUIDs to search for root fs ..."
rootfs_uuid_hints="$($GRUB_PROBE -t hints_string /boot)"
debug "Found: %s" "$(echo "$rootfs_uuid_hints"|tr '\n' ','|sed 's/ *, *$//')"

# detect filesystem UUIDs of /boot
debug "Detecting filesystem UUIDs of /boot ..."
boot_fs_uuid="$($GRUB_PROBE -t fs_uuid /boot)"
debug "Found: %s" "$(echo "$boot_fs_uuid"|tr '\n' ','|sed 's/ *, *$//')"

# get PCI identification of the /boot devices
debug "Getting PCI identification of the /boot devices"
pci_devices_var_set=
pci_devices_id_functions=
for d in $($GRUB_PROBE -t device /boot); do
    toplvldisk="$(get_top_level_parent_device "$d")"
    pci_bus="$(get_pci_bus_for_disk_device "$d"|sed 's/^0000://g')"
    pci_set="setpci -s $pci_bus"
    pci_vars=
    pci_exports=
    pci_id_conditions=
    for k in \
        VENDOR_ID:00.W \
        DEVICE_ID:02.W \
        BASE_ADDRESS_0:10.L \
        BASE_ADDRESS_1:14.L \
        BASE_ADDRESS_2:18.L \
        BASE_ADDRESS_3:1c.L \
        BASE_ADDRESS_4:20.L \
        BASE_ADDRESS_5:24.L \
    ;do
        pci_register="$(echo "$k"|awk -F ':' '{print $2}')"
        pci_value="$(setpci -s "$pci_bus" "$pci_register"|sed 's/^0*//g')"
        if [ "$pci_value" != '' ]; then
            pci_var="$(echo "${HOST_ID}_${toplvldisk}"|tr '[:lower:]' '[:upper:]')_$(echo "$k" \
                      |awk -F ':' '{print $1}')"
            pci_var_set="$pci_set -v $pci_var $pci_register"
            pci_id_condition='"$'"$pci_var"'" = '"'$pci_value'"
            pci_vars="$(printf '%s\n%s' "$pci_vars" "$pci_var_set")"
            pci_exports="$(printf '%s\n%s' "$pci_exports" "export $pci_var")"
            pci_id_conditions="$pci_id_conditions -a $pci_id_condition"
        fi
    done
    pci_id_conditions="$(echo "$pci_id_conditions"|sed 's/^ *-a *//g')"
    pci_devices_var_set="$(printf '%s\n\n%s%s%s' "$pci_devices_var_set" \
                            "# PCI variables for ($HOST_ID)$d" "$pci_vars" "$pci_exports"|tail -n +2)"
    pci_devices_id_functions="$(echo "$pci_devices_id_functions -a $pci_id_conditions"|sed 's/^ -a //g')"
done

# get kernel driver used for each /boot devices
debug "Getting kernel drivers of /boot devices"
boot_devices_kernel_drivers=
for d in $($GRUB_PROBE -t device /boot); do
    pci_bus="$(get_pci_bus_for_disk_device "$d"|sed 's/^0000://g')"
    driver="$(get_driver_for_pci_device "$pci_bus" "$d")"
    boot_devices_kernel_drivers="$boot_devices_kernel_drivers $driver"
done
boot_devices_kernel_drivers="$(echo "$boot_devices_kernel_drivers"|uniquify -s)"
debug "Found: %s" "$boot_devices_kernel_drivers"

# get keyboards
debug "Detecting keyboards"
ps2_keyboards="$(detect_ps2_keyboards)"
if [ "$ps2_keyboards" != '' ]; then
    debug "Found (ps2):\\n%s" "$(echo "$ps2_keyboards"|sed 's/^/ - /g')"
fi
usb_keyboards="$(detect_usb_keyboards)"
if [ "$usb_keyboards" != '' ]; then
    debug "Found (usb):\\n%s" "$(echo "$usb_keyboards"|sed 's/^/ - /g')"
fi
if [ "$ps2_keyboards" = '' ] && [ "$usb_keyboards" = '' ]; then
    fatal_error "No keyboard found"
fi

# detecting keyboards grub modules
debug "Detecting keyboards grub modules"

if bool "$GRUB_EARLY_NO_USB_KEYBOARD" && bool "$GRUB_EARLY_NO_PS2_KEYBOARD" \
&& [ "$GRUB_EARLY_KEYMAP" != '' ]; then
    fatal_error "You cannot have keymap '%s' and no 'at_keyboard' and no 'usb_keyboard' "`
                `"grub modules (because they are the only one which support keylayouts)." \
                "$GRUB_EARLY_KEYMAP"
fi

# if ps2 keyboards were detected
modules_keyboards=
if [ "$ps2_keyboards" != '' ] && ! bool "$GRUB_EARLY_NO_PS2_KEYBOARD"; then

    # enable 'at_keyboard' module
    modules_keyboards='at_keyboard'
fi

# if usb keyboards were detected
modules_usb_keyboards=
mapping_usb_keyboards_grub_module=
if [ "$usb_keyboards" != '' ] && ! bool "$GRUB_EARLY_NO_USB_KEYBOARD"; then

    # enable 'usb_keyboard' module
    modules_keyboards="$modules_keyboards usb_keyboard"

    # for each of them
    IFS="$NL"
    for kbd_line in $usb_keyboards; do
        IFS="$IFS_BAK"

        # get their driver
        driver="$(echo "$kbd_line"|sed 's/^(\([^)]\+\)).*/\1/g')"

        # grub module for this driver	
        #driver="$(echo "$driver"|grep -o '[ue]hci')"
        grub_module="$(echo "$driver"|sed 's/\([eu]hci\)[_-].*/\1/g')"

        # add the keyboard and its modules to the mapping
        kbd_name="$(echo "$kbd_line"|sed 's/^([^)]\+).*: \(.*\)/\1/g'|trim)"
        if [ "$kbd_name" = '' ]; then
            kbd_name="$(echo "$kbd_line"|sed 's/^([^)]\+) \(.*\): .*/\1/g'|trim)"
        fi
        mapping_usb_keyboards_grub_module="$grub_module | $kbd_name"

        # 'uhci' module seem to work only with 'ehci'
        # maybe the reverse is also true but I cannot test it myself
        if [ "$grub_module" = 'uhci' ]; then
            grub_module="$grub_module ehci"
        fi
        modules_usb_keyboards="$modules_usb_keyboards $grub_module"
    done
    modules_usb_keyboards="$(echo "$modules_usb_keyboards"|uniquify -s)"
fi
modules_keyboards="$modules_keyboards $modules_usb_keyboards"
if [ "$modules_keyboards" = '' ] && [ "$modules_usb_keyboards" = '' ]; then
    fatal_error "No keyboards grub module found"
fi
debug "Found: %s" "$modules_keyboards"

# one of the usb keyboard grub module disable the use of firmware driver
if contains_a_grub_module_that_disable_firmware_driver "$modules_usb_keyboards"; then

    # if one of the /boot devices has driver 'virtio'
    if echo "$boot_devices_kernel_drivers"|grep -q 'virtio'; then
        first_incompatible_kbd="$(echo "$mapping_usb_keyboards_grub_module" \
                                 |grep '^[ueo]hci\|^usbms'|head -n 1)"
        first_incompatible_kbd_module="$(echo "$first_incompatible_kbd" \
                                        |awk -F '|' '{print $1}'|trim)"
        first_incompatible_kbd_name="$(echo "$first_incompatible_kbd" \
                                      |awk -F '|' '{print $2}'|trim)"
        err_msg="$(printf \
            "Incompatible grub module requirements between usb keyboard driver '%s' and "`
            `"disk driver '%s'." \
            "$first_incompatible_kbd_module" 'virtio'
        )"
        err_desc="$(printf \
            "The usb grub module '%s' prevents using firmware driver (grub module "`
            `"'%s'). That requires a suitable grub module for disk driver (like 'ahci' "`
            `"for SATA, or 'scsi', etc.). But there is no grub module for disk driver "`
            `"'%s'. So you will not be able to access the disk if you use this usb grub "`
            `"module '%s'.$NL"`
            `"To solve this issue: either configure your KVM virtual Machine to use SATA "`
            `"disks, or use a PS2 keyboard (instead of the usb one '%s')." \
            "$first_incompatible_kbd_module" 'biosdisk' 'virtio' \
            "$first_incompatible_kbd_module" "$first_incompatible_kbd_name"
        )"
        fatal_error "${err_msg}${NL}$err_desc"
    
    # else, add the disk drivers to the usb keyboard modules (used with nativedisk)
    else
        modules_usb_keyboards="$modules_usb_keyboards $boot_devices_kernel_drivers"
    fi
fi

# user wants to force some keyboard modules
if bool "$GRUB_EARLY_FORCE_USB_KEYBOARD" || bool "$GRUB_EARLY_FORCE_PS2_KEYBOARD"; then
    if bool "$GRUB_EARLY_FORCE_USB_KEYBOARD" \
    && ! echo " $modules_keyboards "|grep -q ' usb_keyboard '; then
        debug "Forcing 'usb_keyboard' for keyboards grub modules"
        modules_keyboards="$modules_keyboards usb_keyboard"
        usb_keyboards="User forced USB keyboard"
    fi

    if bool "$GRUB_EARLY_FORCE_PS2_KEYBOARD" \
    && ! echo " $modules_keyboards "|grep -q ' at_keyboard '; then
        debug "Forcing 'at_keyboard' for keyboards grub modules"
        modules_keyboards="$modules_keyboards at_keyboard"
        ps2_keyboards="User forced PS2 keyboard"
    fi
fi


# helper var for keyboard
using_usb_keyboard=false
using_at_keyboard=false
using_both_keyboards=false
usb_keyboards_count=
usb_keyboards_input=
if echo " $modules_keyboards "|grep -q ' usb_keyboard '; then
    using_usb_keyboard=true
    usb_keyboards_count="$(echo "$usb_keyboards"|wc -l)"
    usb_keyboards_input="$(for c in $(seq 0 "$((usb_keyboards_count - 1))"); do \
        printf ' usb_keyboard%s' "$c"; done|trim)"
fi
if echo " $modules_keyboards "|grep -q ' at_keyboard '; then
    using_at_keyboard=true
fi
if bool "$using_usb_keyboard" && bool "$using_at_keyboard"; then
    using_both_keyboards=true
fi


# grub modules for disks devices
debug "Getting grub modules for disks devices"
modules_crypto="$($GRUB_PROBE -t abstraction /boot|uniquify --to-sep-space)"
modules_disks='biosdisk'
if contains_a_grub_module_that_disable_firmware_driver "$modules_usb_keyboards"; then
    # disable biodisk when using disk drivers
    modules_disks=
fi 
modules_disks="$modules_disks $($GRUB_PROBE -t partmap /boot|sed 's/^/part_/g' \
                                                            |uniquify --to-sep-space)"
modules_fs="$($GRUB_PROBE -t fs /boot|uniquify --to-sep-space)"
modules_devices="$modules_crypto $modules_disks $modules_fs"
debug "Found: %s" "$modules_devices"


# no custom normal.cfg provided
if [ -z "$GRUB_EARLY_NORMAL_CFG" ]; then

    GRUB_SUBMENU_GFXCONF=

    # gfxterm is not disabled
    if ! bool "$GRUB_EARLY_NO_GFXTERM" && ! bool "$GRUB_EARLY_NO_MENU"; then
        GRUB_SUBMENU_GFXCONF="
# enter gfx rendering mode
submenu_gfxmode"
    fi

    GRUB_AT_TERMINAL_CONF=
    keyboard_indent=0

    if bool "$using_both_keyboards"; then
    # for m in $modules_usb_keyboards; do echo "insmod $m"; done; \
        GRUB_AT_TERMINAL_CONF="
# try to use all keyboard modules (usb* and at)
insmod usb_keyboard
insmod at_keyboard
$(if [ "$modules_usb_keyboards" != '' ]; then \
    echo "insmod nativedisk"; \
    echo "nativedisk $modules_usb_keyboards"; \
fi)
if ! terminal_input $usb_keyboards_input at_keyboard; then
"
    fi

    if bool "$using_usb_keyboard"; then
        keyboard_indent="$(if bool "$using_both_keyboards"; then echo 4; else echo 0; fi)"
        # for m in $modules_usb_keyboards; do echo "insmod $m"; done; \
        GRUB_AT_TERMINAL_CONF="$(printf '%s%s' "$GRUB_AT_TERMINAL_CONF" "$(echo "
# try to use all usb keyboards
$(if ! bool "$using_both_keyboards"; then echo \
"insmod usb_keyboard
"; \
    if [ "$modules_usb_keyboards" != '' ]; then \
        echo "insmod nativedisk"; \
        echo "nativedisk $modules_usb_keyboards"; \
    fi
fi)
if ! terminal_input $usb_keyboards_input; then"|indent "$keyboard_indent")")"
        if bool "$using_both_keyboards"; then
            GRUB_AT_TERMINAL_CONF="${GRUB_AT_TERMINAL_CONF}${NL}"
        fi
    fi

    if bool "$using_at_keyboard"; then
        keyboard_indent="$(if bool "$using_both_keyboards"; then echo 8; else echo 0; fi)"
        GRUB_AT_TERMINAL_CONF="$(printf '%s%s' "$GRUB_AT_TERMINAL_CONF" "$(echo "
# try to use ps2 keyboard
$(if ! bool "$using_both_keyboards"; then echo "insmod at_keyboard"; fi)
if ! terminal_input at_keyboard; then"|indent "$keyboard_indent")")"
    fi

    if bool "$using_usb_keyboard" || bool "$using_at_keyboard"; then
        keyboard_indent="$(if bool "$using_both_keyboards"; then echo 8; else echo 0; fi)"
        GRUB_AT_TERMINAL_CONF="$(printf '%s\n%s' "$GRUB_AT_TERMINAL_CONF" "$(echo "
    # fallback to 'console'
    terminal_input console
fi"|indent "$keyboard_indent")")"
        if bool "$using_both_keyboards"; then
            GRUB_AT_TERMINAL_CONF="$GRUB_AT_TERMINAL_CONF
    fi
fi"
        fi
    fi

    # build kernel menu entries
    GRUB_MENUS_ENTRIES_KERNELS=

    # menu are enabled
    if ! bool "$GRUB_EARLY_NO_MENU"; then

        # load submenus modules
        if [ "$GRUB_EARLY_WRAP_IN_SUBMENU" = '' ] && ! bool "$GRUB_EARLY_NO_GFXTERM"; then
            GRUB_MENUS_ENTRIES_KERNELS="
insmod gfxterm_menu
insmod gfxmenu"
        fi
    
        # submenu are enabled
        if ! bool "$GRUB_EARLY_DISABLE_SUBMENU"; then
            GRUB_MENUS_ENTRIES_KERNELS="$GRUB_MENUS_ENTRIES_KERNELS
# menu wrapper for host kernel entries
submenu '$GRUB_EARLY_KERNEL_WRAPPER_SUBMENU_TITLE' "`
`"$(get_submenu_classes "$GRUB_EARLY_KERNEL_WRAPPER_SUBMENU_CLASSES") --id 'submenu-kernels' {
    $(echo "$GRUB_SUBMENU_GFXCONF"|indent 4)
"
        fi

        GRUB_MENUS_ENTRIES_KERNELS="$GRUB_MENUS_ENTRIES_KERNELS
    # kernel menu entries"
    fi

    # for each kernel
    KERNELS_ENTRIES=
    for k in $kernels; do

        # shellcheck disable=SC2059
        k_title="$(printf "$GRUB_EARLY_KERNEL_SUBLENUS_TITLE" "$k")"
        # shellcheck disable=SC2059
        k_title_rec="$(printf "$GRUB_EARLY_KERNEL_SUBLENUS_TITLE_RECOVERY" "$k")"

        k_indent=0

        # menu are enabled
        if ! bool "$GRUB_EARLY_NO_MENU"; then
            k_indent=4
            KERNELS_ENTRIES="$KERNELS_ENTRIES
menuentry '$k_title' "`
`"$(get_submenu_classes "$GRUB_EARLY_KERNEL_SUBMENUS_CLASSES") --id 'gnulinux-$k' {"
        fi

        KERNEL_ENTRY="
$(for m in $modules_devices; do echo "insmod $m"; done)

$(for uuid in $boot_required_uuid; do
    echo "cryptomount -u $uuid $GRUB_EARLY_CRYPTOMOUNT_OPTS"
    echo 'msg'
done)

insmod search
insmod linux

search --no-floppy --fs-uuid --set=root $rootfs_uuid_hints $boot_fs_uuid

msg 'Loading Linux $k ...'
linux  /boot/vmlinuz-$k root=UUID=$boot_fs_uuid ro $GRUB_EARLY_CMDLINE_LINUX

if [ -e /boot/initrd.img-$k ]; then
    msg 'Loading intial ram disk ...'
    initrd /boot/initrd.img-$k
fi"
        
        KERNELS_ENTRIES="${KERNELS_ENTRIES}$(echo "$KERNEL_ENTRY"|indent "$k_indent")"

        # menu are enabled
        if ! bool "$GRUB_EARLY_NO_MENU"; then
            KERNELS_ENTRIES="$KERNELS_ENTRIES
}"
        fi

        # menu are enabled and recovery mode is not disabled
        if ! bool "$GRUB_EARLY_NO_MENU" && ! bool "$GRUB_DISABLE_RECOVERY" \
        && ! bool "$GRUB_EARLY_DISABLE_RECOVERY"; then
            KERNELS_ENTRIES="$KERNELS_ENTRIES
menuentry '$k_title_rec' --class recovery "`
`"$(get_submenu_classes "$GRUB_EARLY_KERNEL_SUBMENUS_CLASSES") --id 'gnulinux-$k-recovery' {"

            KERNELS_ENTRIES="$KERNELS_ENTRIES"`
                `"$(echo "$KERNEL_ENTRY" \
                    |sed "s/ ro $GRUB_EARLY_CMDLINE_LINUX/ ro single/g" \
                    |indent "$k_indent")"`
                `"$NL}"
        fi
    done
    GRUB_MENUS_ENTRIES_KERNELS="$GRUB_MENUS_ENTRIES_KERNELS
$(echo "$KERNELS_ENTRIES"|indent "$(if ! bool "$GRUB_EARLY_NO_MENU"; then echo '4'; else echo '0'; fi)")"

    # menu and submenu are enabled 
    if ! bool "$GRUB_EARLY_NO_MENU" && ! bool "$GRUB_EARLY_DISABLE_SUBMENU"; then
        GRUB_MENUS_ENTRIES_KERNELS="$GRUB_MENUS_ENTRIES_KERNELS
}"
    fi

    # create a configuration file (for normal mode)
    info "Creating configuration file '%s'" "$GRUB_NORMAL_CFG"
    touch "$GRUB_NORMAL_CFG"

    cat >> "$GRUB_NORMAL_CFG" <<ENDCAT

# loading 'test' module
insmod test
ENDCAT

    # disable 'progress indicator' to prevent terminal box poping out
    # in gfx mode
    if bool "$GRUB_EARLY_NOPROGRESS"; then
        cat >> "$GRUB_NORMAL_CFG" <<ENDCAT

# prevent terminal box poping out in gfx mode
set enable_progress_indicator=0
export enable_progress_indicator
ENDCAT
    fi

    # setup verbosity, and a msg() helper function
    cat >> "$GRUB_NORMAL_CFG" <<ENDCAT

# define verbosity level
set verbosity=$GRUB_EARLY_VERBOSITY
export verbosity

# display message if verbosity enabled
function msg {
    if [ \$verbosity -gt $V_QUIET ]; then
        shift
        insmod echo
        echo "\${1}"
    fi
}
ENDCAT

    # verbosity is DEBUG: enable pager
    if [ "$GRUB_EARLY_VERBOSITY" = "$V_DEBUG" ]; then
        cat >> "$GRUB_NORMAL_CFG" <<ENDCAT

insmod sleep
# enable pager
set pager=1
ENDCAT
    fi


    # day/night mode
    if bool "$day_night_mode"; then
        cat >> "$GRUB_NORMAL_CFG" <<ENDCAT

### day/night mode calculations ###
insmod datehook

# day time by default
set day_night_mode=day

# below are all night mode cases

# current hour is greater than the DAY hour
# and current hour is equals to the NIGHT hour
# and current minutes are greater/equals to the NIGHT minutes
if  [ "\$HOUR" -gt "$DAY_TIME_H" -a "\$HOUR" -eq "$NIGHT_TIME_H" -a "\$MINUTE" -ge "$NIGHT_TIME_M" ]; then
    day_night_mode=night

# current hour is lower than the DAY hour
elif [ "\$HOUR" -lt "$DAY_TIME_H" ]; then

    # current hour is not equals to the NIGHT hour
    # or the current minutes are greater than/equals to the NIGHT minutes
    if [ "\$HOUR" -ne "$NIGHT_TIME_H" -o "\$MINUTE" -ge "$NIGHT_TIME_M" ]; then
        day_night_mode=night
    fi

# current hour is equals to the DAY hour
else

    # current minutes are lower than the DAY minutes
    if [ "\$MINUTE" -lt "$DAY_TIME_M" ]; then

        # current hour is not equals to the NIGHT hour
        # or current minutes are greate than/equals to the NIGHT minutes
        # or DAY minutes are lower than/equals to the NIGHT minutes
        if [ "\$HOUR" -ne "$NIGHT_TIME_H" -o "\$MINUTE" -ge "$NIGHT_TIME_M" -o "$DAY_TIME_M" -le "$NIGHT_TIME_M" ]; then
            day_night_mode=night
        fi

    # current minutes are greater than the DAY minutes
    # and current hour is equals to NIGHT hour
    elif [ "\$MINUTE" -gt "$DAY_TIME_M" -a "\$HOUR" -eq "$NIGHT_TIME_H" ]; then

        # current minutes are greate than the NIGHT minutes
        # and DAY minutes are lower than the NIGHT minutes
        if [ "\$MINUTE" -gt "$NIGHT_TIME_M" -a "$DAY_TIME_M" -lt "$NIGHT_TIME_M" ]; then
            day_night_mode=night

        # current minutes are equals to the NIGHT minutes
        elif [ "\$MINUTE" -eq "$NIGHT_TIME_M" ]; then
            day_night_mode=night
        fi
    fi
fi

# export the resulting mode
export day_night_mode

### end of day/night mode calculations ###
ENDCAT
    fi

    # path are not prefixed
    h_prefix=

    # in multi-host mode
    if bool "$multi_host_mode"; then

        # path are prefixed by hostname
        h_prefix="/\$hostname"

        # load 'common' configuration if found
        if [ "$GRUB_EARLY_COMMON_CONF" != '' ] \
        && [ -f "$GRUB_EARLY_COMMON_CONF" ]; then
            info "Copying common conf file '%s' to '%s'" \
                "$GRUB_EARLY_COMMON_CONF" "$GRUB_MEMDISK_DIR/$GRUB_COMMON_CONF_FILENAME"
            cp "$GRUB_EARLY_COMMON_CONF" "$GRUB_MEMDISK_DIR/$GRUB_COMMON_CONF_FILENAME"
            cat >> "$GRUB_NORMAL_CFG" <<ENDCAT

    # common configuration
    if [ -r \$prefix/$GRUB_COMMON_CONF_FILENAME ]; then
        insmod configfile
        source  \$prefix/$GRUB_COMMON_CONF_FILENAME
    fi
ENDCAT
        fi

        info "Creating current host '%s' required files ..." "$HOSTNAME"

        # build the current host detection file
        # current host detection is based on PCI variables
        detection_host_path="$host_dir/$GRUB_HOST_DETECTION_FILENAME"
        info "Creating detection file '%s'" "$detection_host_path"
        cat > "$detection_host_path" <<ENDCAT
insmod setpci
$pci_devices_var_set

# if '$HOSTNAME' host is detected
if [ $pci_devices_id_functions ]; then
ENDCAT

        # for every host
        for h in $HOST_ID $other_hosts; do

            # add their detection
            # if detected:
            #   - set the host name
            #   - load its configuration
            host_detection_file="$GRUB_MEMDISK_DIR/$h/$GRUB_HOST_DETECTION_FILENAME"
            cat >> "$GRUB_NORMAL_CFG" <<ENDCAT

$(cat "$host_detection_file")

    # set the host name
    set hostname=$h
    
    # load host configuration
    if [ -r \$prefix${h_prefix}/$GRUB_HOST_CONFIGURATION_FILENAME ]; then
        insmod configfile
        source \$prefix${h_prefix}/$GRUB_HOST_CONFIGURATION_FILENAME
    fi
fi
ENDCAT
            c_file="$GRUB_MEMDISK_DIR/$h/$GRUB_HOST_CONFIGURATION_FILENAME"
            if [ "$h" != "$HOST_ID" ] && bool "$GRUB_EARLY_PARSE_OTHER_HOSTS_CONFS"; then
                other_hosts_conf_files="$other_hosts_conf_files${NL}$c_file"
            elif [ "$h" = "$HOST_ID" ]; then
                conf_files="$conf_files${NL}$c_file"
            fi
        done

        cat >> "$GRUB_NORMAL_CFG" <<ENDCAT

# export the host name
export hostname
ENDCAT

        # current host configuration is in another file
        params_host_path="$host_dir/$GRUB_HOST_CONFIGURATION_FILENAME"
        info "Creating parameters file '%s'" "$params_host_path"
        touch "$params_host_path"

    # not in multi-host mode
    else

        # current host configuration is in the same file
        params_host_path="$GRUB_NORMAL_CFG"
    fi

    # keymap definition
    if [ "$GRUB_EARLY_KEYMAP" != '' ]   \
    && [ "$GRUB_EARLY_KEYMAP" != 'en' ] \
    && [ "$GRUB_EARLY_KEYMAP" != 'us' ]; then
        cat >> "$params_host_path" <<ENDCAT

# load keyboard layout (not enabled yet)
insmod keylayouts
keymap \$prefix${h_prefix}/$(basename "$kbdlayout_dest")
ENDCAT
    fi

    # locale definition
    if [ "$GRUB_EARLY_LOCALE" != "" ]; then
        cat >> "$params_host_path" <<ENDCAT

# load locale (enabled instantly)
set locale_dir=\$prefix${h_prefix}
set lang=$GRUB_EARLY_LOCALE
ENDCAT
    fi

    # gfxterm is not disabled
    if ! bool "$GRUB_EARLY_NO_GFXTERM"; then

        # font definition
        if [ "$GRUB_EARLY_FONT" != "" ]; then
            cat >> "$params_host_path" <<ENDCAT

# load font
insmod font
loadfont \$prefix${h_prefix}/$(basename "$font_dest")
ENDCAT
        fi

        # theme definition
        if bool "$THEME_ENABLED"; then

            # not in day/night mode
            if ! bool "$day_night_mode"; then

                # not in random theme
                if ! bool "$GRUB_EARLY_RANDOM_THEME"; then

                    # set default theme name
                    cat >> "$params_host_path" <<ENDCAT

# define theme name
set theme_name=$GRUB_EARLY_THEME_DEFAULT
ENDCAT

                # random theme
                else

                    # inject random theme selection instructions (if enabled)
                    cat >> "$params_host_path" <<ENDCAT

$(select_random_theme "$ALL_THEME_NAMES")
ENDCAT
                fi

                # load theme modules
                cat >> "$params_host_path" <<ENDCAT

# load theme modules
$(load_theme_modules "$ALL_THEME_NAMES")
ENDCAT

            # day/night mode
            else

                # not in random theme
                if ! bool "$GRUB_EARLY_RANDOM_THEME"; then

                    # set default theme name
                    cat >> "$params_host_path" <<ENDCAT

# define theme name
if [ "\$day_night_mode" = "day" ]; then
    set theme_name=$GRUB_EARLY_THEME_DEFAULT_DAY
else
    set theme_name=$GRUB_EARLY_THEME_DEFAULT_NIGHT
fi
ENDCAT

                # in random theme
                else

                    # inject random theme selection instructions (if enabled)
                    cat >> "$params_host_path" <<ENDCAT

# select random theme name
if [ "\$day_night_mode" = "day" ]; then

    $(select_random_theme "$ALL_THEME_NAMES_DAY"|indent 4)
else
    $(select_random_theme "$ALL_THEME_NAMES_NIGHT"|indent 4)
fi
ENDCAT
                fi

                # load theme modules
                cat >> "$params_host_path" <<ENDCAT

# load theme modules
if [ "\$day_night_mode" = "day" ]; then
    $(load_theme_modules "$ALL_THEME_NAMES_DAY"|indent 4)
else
    $(load_theme_modules "$ALL_THEME_NAMES_NIGHT"|indent 4)
fi
ENDCAT
            fi

            # export theme name, set its path and load its modules
            cat >> "$params_host_path" <<ENDCAT

# export the theme name
export theme_name

# define theme path (not enabled yet)
set theme=\$prefix${h_prefix}/themes/\$theme_name/$GRUB_THEME_FILENAME
ENDCAT

        fi

        # gfxmode definition
        if [ "$GRUB_EARLY_GFXMODE" != "" ]; then
            cat >> "$params_host_path" <<ENDCAT

# define resolution (not enabled yet)
set gfxmode=$GRUB_EARLY_GFXMODE
ENDCAT
        fi

        # gfxpayload definition
        if [ "$GRUB_EARLY_GFXPAYLOAD" != "" ]; then
            cat >> "$params_host_path" <<ENDCAT

# keep payload or not
set gfxpayload=$GRUB_EARLY_GFXPAYLOAD
ENDCAT
        fi

        # gfx rendering activation
        cat >> "$params_host_path" <<ENDCAT

# switch to gfx rendering (use above settings)
insmod all_video
insmod gfxterm
terminal_output gfxterm
ENDCAT

        # not in day/night mode
        if ! bool "$day_night_mode"; then

            # background color definition
            if [ "$GRUB_EARLY_TERMINAL_BG_COLOR" != "" ]; then
                cat >> "$params_host_path" <<ENDCAT

# set terminal background color
insmod gfxterm_background
background_color "$GRUB_EARLY_TERMINAL_BG_COLOR"
ENDCAT
            # no background color defined, but theming enabled
            elif bool "$THEME_ENABLED"; then
                cat >> "$params_host_path" <<ENDCAT

# set terminal background color
insmod gfxterm_background
$(set_term_background_color "$ALL_THEME_NAMES")
ENDCAT
            fi

            # background image definition
            if [ "$GRUB_EARLY_TERMINAL_BG_IMAGE" != "" ]; then
                cat >> "$params_host_path" <<ENDCAT

# set terminal background image
background_image -m stretch \$prefix${h_prefix}/$(basename "$GRUB_TERMINAL_BG_IMAGE")
ENDCAT
            fi

        # day/night mode
        else

            # background color definition
            if [ "$GRUB_EARLY_TERMINAL_BG_COLOR_DAY" != "" ]; then
                cat >> "$params_host_path" <<ENDCAT

# set terminal background color
insmod gfxterm_background
if [ "\$day_night_mode" = "day" ]; then
    background_color "$GRUB_EARLY_TERMINAL_BG_COLOR_DAY"
else
    background_color "$GRUB_EARLY_TERMINAL_BG_COLOR_NIGHT"
fi
ENDCAT
            # no background color defined, but theming enabled
            elif bool "$THEME_ENABLED"; then
                cat >> "$params_host_path" <<ENDCAT

# set terminal background color
insmod gfxterm_background
if [ "\$day_night_mode" = "day" ]; then
    $(set_term_background_color "$ALL_THEME_NAMES_DAY"|indent 4)
else
    $(set_term_background_color "$ALL_THEME_NAMES_NIGHT"|indent 4)
fi
ENDCAT
            fi

            # background image definition
            if [ "$GRUB_EARLY_TERMINAL_BG_IMAGE_DAY" != "" ]; then
                cat >> "$params_host_path" <<ENDCAT

# set terminal background image
if [ "\$day_night_mode" = "day" ]; then
    background_image -m stretch \$prefix${h_prefix}/$(basename "$GRUB_TERMINAL_BG_IMAGE_DAY")
else
    background_image -m stretch \$prefix${h_prefix}/$(basename "$GRUB_TERMINAL_BG_IMAGE_NIGHT")
fi
ENDCAT
            fi
        fi

        # define submenu helper functions
        if bool "$THEME_ENABLED"; then
            cat >> "$params_host_path" <<ENDCAT

# set theme for submenu
function set_submenu_theme {
    if [ -r \$prefix${h_prefix}/themes/\$theme_name/$GRUB_THEME_INNER_FILENAME ]; then
        set theme=\$prefix${h_prefix}/themes/\$theme_name/$GRUB_THEME_INNER_FILENAME
    elif [ -r \$prefix${h_prefix}/themes/\$theme_name/$GRUB_THEME_FILENAME ]; then
        set theme=\$prefix${h_prefix}/themes/\$theme_name/$GRUB_THEME_FILENAME
    fi
}
ENDCAT
        fi

        # menu and submenu are enabled 
        if ! bool "$GRUB_EARLY_NO_MENU" && ! bool "$GRUB_EARLY_DISABLE_SUBMENU"; then
            cat >> "$params_host_path" <<ENDCAT

# switch to gfx rendering in submenu
function submenu_gfxmode {
ENDCAT
            if bool "$THEME_ENABLED"; then
                cat >> "$params_host_path" <<ENDCAT
    # set theme
    set_submenu_theme
ENDCAT
            fi
            cat >> "$params_host_path" <<ENDCAT
    # switch to gfx rendering
    terminal_output gfxterm
}
ENDCAT
        fi

    # gfxterm is disabled
    else

        # variable for gfxmode disabled
        cat >> "$params_host_path" <<ENDCAT

# disable gfx dependent configurations
set no_gfxterm=true
export no_gfxterm
ENDCAT
    fi

    # timeout definition
    if [ "$GRUB_EARLY_TIMEOUT" != "" ]; then
        cat >> "$params_host_path" <<ENDCAT

# set a timeout (to show a progress in gfx mode)
set timeout=$GRUB_EARLY_TIMEOUT
ENDCAT
    fi

    # alternative config and keystatus setup
    cat >> "$params_host_path" <<ENDCAT

# alternative config enabled
set alternative_config_enabled=0

# required to catch keystatus
terminal_input console

# a key status is available
insmod keystatus
if keystatus; then

    # 'shift' key was pressed
    if keystatus --shift; then

        # flag the alternative config activation
        set alternative_config_enabled=1
    fi
fi
export alternative_config_enabled
$GRUB_AT_TERMINAL_CONF
ENDCAT

    # here start the menus configuration

    # in multi-host mode
    if bool "$multi_host_mode"; then

        # for every host
        for h in $HOST_ID $other_hosts; do

            # load the current host menus
            cat >> "$GRUB_NORMAL_CFG" <<ENDCAT

# if '$h' is detected
if [ "\$hostname" = "$h" ]; then
    
    # load host menu
    if [ -r \$prefix${h_prefix}/$GRUB_HOST_MENUS_FILENAME ]; then
        insmod configfile
        source \$prefix${h_prefix}/$GRUB_HOST_MENUS_FILENAME
    fi
fi
ENDCAT
            c_file="$GRUB_MEMDISK_DIR/$h/$GRUB_HOST_MENUS_FILENAME"
            if [ "$h" != "$HOST_ID" ] && bool "$GRUB_EARLY_PARSE_OTHER_HOSTS_CONFS"; then
                other_hosts_conf_files="$other_hosts_conf_files${NL}$c_file"
            elif [ "$h" = "$HOST_ID" ]; then
                conf_files="$conf_files${NL}$c_file"
            fi
        done

        # current host menu is in another file
        menus_host_path="$host_dir/$GRUB_HOST_MENUS_FILENAME"
        info "Creating menu file '%s'" "$menus_host_path"
        touch "$menus_host_path"

    # not in multi-host mode
    else

        # current host menu is in the same file
        menus_host_path="$GRUB_NORMAL_CFG"
    fi

    # menu and wrapper are enabled
    if ! bool "$GRUB_EARLY_NO_MENU" && [ "$GRUB_EARLY_WRAP_IN_SUBMENU" != '' ]; then

        # open the menu wrapper
        cat >> "$menus_host_path" <<ENDCAT

# menu wrapper
$(if ! bool "$GRUB_EARLY_NO_GFXTERM"; then echo \
"insmod gfxterm_menu
insmod gfxmenu
"; fi)
submenu '$GRUB_EARLY_WRAP_IN_SUBMENU' $(
    get_submenu_classes "$GRUB_EARLY_WRAPPER_SUBMENU_CLASSES") --id 'submenu-default' {
    $(echo "$GRUB_SUBMENU_GFXCONF"|indent 4)
ENDCAT
    fi

    # alternative config
    if [ "$GRUB_EARLY_ALTERNATIVE_MENU" != '' ]; then
        cat >> "$menus_host_path" <<ENDCAT

    # if alternative config was enabled
    if [ \$alternative_config_enabled -eq 1 ]; then
        $(echo "$GRUB_EARLY_ALTERNATIVE_MENU"|indent 8)
    fi

ENDCAT
    fi

    # host kernel menu
    kernel_indent=0
    if ! bool "$GRUB_EARLY_NO_MENU" && [ "$GRUB_EARLY_WRAP_IN_SUBMENU" != '' ] \
    && ! bool "$GRUB_EARLY_DISABLE_SUBMENU"; then
        kernel_indent=4
    fi
    echo "$GRUB_MENUS_ENTRIES_KERNELS"|indent "$kernel_indent" >> "$menus_host_path"

    # menu and multi-host mode are enabled and common menu is specified and is a file
    if ! bool "$GRUB_EARLY_NO_MENU" && bool "$multi_host_mode" \
    && [ "$GRUB_EARLY_EXTRA_MENUS" != '' ] && [ -f "$GRUB_EARLY_EXTRA_MENUS" ]; then

        # copy the common menu file to memdisk dir
        info "Copying extra menus file '%s' to '%s'" \
            "$GRUB_EARLY_EXTRA_MENUS" "$GRUB_MEMDISK_DIR/$GRUB_EXTRA_MENUS_FILENAME"
        cp "$GRUB_EARLY_EXTRA_MENUS" "$GRUB_MEMDISK_DIR/$GRUB_EXTRA_MENUS_FILENAME"
        cat >> "$menus_host_path" <<ENDCAT

    # extra menus
    if [ -r \$prefix/$GRUB_EXTRA_MENUS_FILENAME ]; then
        insmod configfile
        source  \$prefix/$GRUB_EXTRA_MENUS_FILENAME
    fi
ENDCAT
    fi

    # menu and wrapper are enabled
    if ! bool "$GRUB_EARLY_NO_MENU" && [ "$GRUB_EARLY_WRAP_IN_SUBMENU" != '' ]; then

        # close the menu wrapper
        echo '}' >> "$menus_host_path"
    fi

# custom normal.cfg provided
else
    info "Copying '%s' to '%s'" "$GRUB_EARLY_NORMAL_CFG" "$GRUB_NORMAL_CFG"
    cp "$GRUB_EARLY_NORMAL_CFG" "$GRUB_NORMAL_CFG"
fi
conf_files="$conf_files${NL}$GRUB_NORMAL_CFG"


# modules for shell commands
debug " - config files (to parse): %s" \
    "$(echo "$conf_files"|sed "s#\\($GRUB_MEMDISK_DIR\\|$GRUB_EARLY_DIR\\)/\\?##g" \
                         |trim|tr '\n' ' '|trim)"
modules_confs="$(
    IFS="$NL"
    for f in $conf_files; do
        IFS="$IFS_BAK"
        get_manually_loaded_grub_modules_for_file "$f"
        echo
    done|uniquify -s)"
debug " - modules required by grub-shell scripts: %s" "$modules_confs"

# extra modules manually added
if [ "$GRUB_EARLY_ADD_GRUB_MODULES" != '' ]; then
    debug " - modules extra: %s" "$GRUB_EARLY_ADD_GRUB_MODULES"
fi

# # modules all merged
modules="$(echo "$modules_core $modules_usb_keyboards $modules_confs $GRUB_EARLY_ADD_GRUB_MODULES"\
          |uniquify -s)"
debug " - modules (current host): %s" "$modules"

# if one of the /boot devices has driver 'virtio'
# and grub modules contains one that disable firmware driver
if echo "$boot_devices_kernel_drivers"|grep -q 'virtio' \
&& contains_a_grub_module_that_disable_firmware_driver "$modules"; then
    first_incompatible_module="$(echo " $modules "|grep -o ' nativedisk\|[aueo]hci\|usbms '\
                                                  |tr ' ' '\n'|head -n 1|trim)"
    err_msg="$(printf \
        "Incompatible grub module requirements between '%s' and disk driver '%s'." \
        "$first_incompatible_module" 'virtio'
    )"
    err_desc="$(printf \
        "The grub module '%s' prevents using firmware driver (grub module '%s'). That "`
        `"requires a suitable grub module for disk driver (like 'ahci' for SATA, or 'scsi', "`
        `"etc.). But there is no grub module for disk driver '%s'. So you will not be able to "`
        `"access the disk if you use this grub module '%s'.$NL"`
        `"To solve this issue: configure your KVM virtual Machine to use only SATA disks, "`
        `"and/or do not use usb devices (prefer PS2 keyboard for example)." \
        "$first_incompatible_module" 'biosdisk' 'virtio' "$first_incompatible_module"
    )"
    warning "${err_msg}${NL}$err_desc"
fi

# requirements file
r_file="$GRUB_MEMDISK_DIR${host_prefix}/$GRUB_MODULES_REQUIREMENTS_FILENAME"
info "Creating requirements file '%s'" "$r_file"
echo "$modules"|tr ' ' '\n' > "$r_file"

# in multi-host mode
if bool "$multi_host_mode"; then

    # modules required by other hosts
    if bool "$GRUB_EARLY_PARSE_OTHER_HOSTS_CONFS" \
    && [ "$other_hosts_requirements_files" != '' ]; then
        debug "Getting other hosts modules from requirements files: %s" \
            "$(echo "$other_hosts_requirements_files"|sed "s#$GRUB_MEMDISK_DIR\\?/##g" \
                                                     |trim|tr '\n' ' '|trim)"
        other_hosts_modules="$(
            IFS="$NL"; for f in $other_hosts_requirements_files; do \
                IFS="$IFS_BAK"; cat -s "$f"|tr '\n' ' '; \
            done|uniquify -s)"
        if [ "$other_hosts_modules" != '' ]; then
            debug "Adding other hosts modules: %s" "$other_hosts_modules"
            modules="$(echo "$modules $other_hosts_modules"|uniquify -s)"
            debug "Modules (from all hosts merged): %s" "$modules"
        else
            debug "Empty module list for other hosts"
        fi
    fi
fi

# building the full list of module dependencies
modules_with_deps="$(for m in $modules; do get_grub_module_deps "$m"; echo; done|uniquify -s)"
debug "Modules (all hosts, with deps): %s" "$modules_with_deps"

# copying required modules to modules dir
modules_dir="$GRUB_MEMDISK_DIR/i386-pc"
info "Copying required modules to modules dir '%s'" "$modules_dir"
if [ ! -d "$modules_dir" ]; then
    # shellcheck disable=SC2174
    mkdir -m 0700 -p "$modules_dir"
fi
for m in $modules_with_deps; do
    m_path="$GRUB_MODDIR/$m.mod"
    if [ ! -r "$m_path" ]; then
        fatal_error "Module '%s' isn't readable or doesn't exist" "$m_path"
    fi
    cp "$m_path" "$modules_dir"/
done


# trigger the hook
if [ -r "$GRUB_EARLY_HOOK_SCRIPT" ]; then
    debug "Hook script '$GRUB_EARLY_HOOK_SCRIPT' being triggered (sourced)"
    # shellcheck disable=SC1090
    . "$GRUB_EARLY_HOOK_SCRIPT"
fi


# TODO deduplicate files in memdisk


# create memory disk image
info "Creating memdisk '%s' from '%s'" "$GRUB_CORE_MEMDISK" "$GRUB_MEMDISK_DIR"
# TODO explicitly derefence links?
tar -cf "$GRUB_CORE_MEMDISK" -C "$GRUB_MEMDISK_DIR" .


# create the core.img
info "Creating core image '%s' ..." "$GRUB_CORE_IMG"
debug "$GRUB_MKIMAGE --directory "'"'"$GRUB_MODDIR"'"'" --output '$GRUB_CORE_IMG' "`
      `"--format '$GRUB_CORE_FORMAT' --compression '$GRUB_CORE_COMPRESSION' "`
      `"--config '$GRUB_CORE_CFG' --memdisk '$GRUB_CORE_MEMDISK' --prefix '(memdisk)' $modules_core"
# shellcheck disable=SC2086
"$GRUB_MKIMAGE" \
    --directory "$GRUB_MODDIR" \
    --output "$GRUB_CORE_IMG" \
    --format "$GRUB_CORE_FORMAT" \
    --compression "$GRUB_CORE_COMPRESSION" \
    --config "$GRUB_CORE_CFG" \
    --memdisk "$GRUB_CORE_MEMDISK" \
    --prefix '(memdisk)' \
    $modules_core
debug "Core image size: %s (max is: %s)" \
    "$(du -h "$GRUB_CORE_IMG"|awk '{print $1}')" "$(( 458240 / 1024 ))K"

# ensure 'boot.img' is installed in grub directory
if [ ! -f "$GRUB_BOOT_IMG" ]; then
    info "Copying '%s' to '%s'" "$GRUB_BOOT_IMG_SRC" "$GRUB_BOOT_IMG"
    cp "$GRUB_BOOT_IMG_SRC" "$GRUB_BOOT_IMG"
fi

# install grub to disk MBR BIOS
if ! bool "$opt_noinstall"; then
    info "Installing grub to MBR BIOS of disk '%s' ..." "$device"
    debug "$GRUB_BIOS_SETUP --directory='$GRUB_EARLY_DIR' "'"'"$device"'"'"  $GRUB_INSTALL_ARGS"
    # shellcheck disable=SC2086
    "$GRUB_BIOS_SETUP" \
        --directory="$GRUB_EARLY_DIR" \
        --device-map="$GRUB_DEVICE_MAP" \
        "$device" \
        $GRUB_EARLY_INSTALL_ARGS
else
    info "Not installing grub to MBR BIOS of disk '%s' (user asked not to)" "$device"
fi

# done
info "Done! ;-)"

