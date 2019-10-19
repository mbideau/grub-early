#!/bin/sh

# TODO implement RANDOM_BG_IMAGE
#   RANDOM_BG_IMAGE
#       If true, will display a random background, according to the directory:
#       \`$GRUB_BG_DIR'.
#       For each background found, the main theme and inner theme will be copied
#       with the directive \`desktop-image' replaced by the background file path.
#       Then it will enable the \`RANDOM_THEME' feature.

set -e

GRUB_THEME_FILENAME=theme.txt
GRUB_THEME_INNER_FILENAME=theme-inner.txt
GRUB_THEME_ONDISK_FILENAME=theme-ondisk.txt

THIS_SCRIPT_NAME="$(basename "$0")"
COLOR_NUMBER_DEFAULT=10

usage()
{
    cat <<ENDCAT

$THIS_SCRIPT_NAME - generate theme derivatives from a list of background colors

USAGE

    $THIS_SCRIPT_NAME -h|--help
        Display help

    $THIS_SCRIPT_NAME [-e|--exclude-src] SRC_DIR OUT_DIR ..BG_COLORS..
        Generate theme derivatives with specified colors

    $THIS_SCRIPT_NAME [-e|--exclude-src] -a|--auto SRC_DIR OUT_DIR
        Generate theme derivatives with $COLOR_NUMBER_DEFAULT randomly generated colors

    $THIS_SCRIPT_NAME -g|--generate-colors NUMBER
        Generate NUMBER of colors

ARGUMENTS

    SRC_DIR
        The source theme directory from which this script will generate other theme directories.

    OUT_DIR
        the destination directory where this script is going to generate derivatives theme
        directories.

    BG_COLORS
        A list of HEX colors (space separated) to be used as theme background color.
        If option '--auto' is not specified, this argument is mandatory.

    NUMBER
        The number of colors to generate. By default it is '$COLOR_NUMBER_DEFAULT'.

OPTIONS

    -h|--help
        Display help

    -e|--exclude-src
        Do not include the source theme directory in the themes, just use it to
        generate all colored derivatives.

    -a|--auto
        Background colors will be generated randomly by this script.

NOTE

    For each background color, the source theme directory will be copied with a random suffix
    append to its name, in the OUT_DIR directory, and its theme files will have their
    directive \`desktop-color' replaced/added to the specific color.

EXAMPLES

    $THIS_SCRIPT_NAME --auto /path/to/themes/simple_theme /path/to/other_dir

    $THIS_SCRIPT_NAME --auto --exclude-src /path/to/themes/simple_theme /path/to/themes

    $THIS_SCRIPT_NAME --exclude-src /path/to/themes/simple_theme /path/to/themes ..BG_COLORS..

ENDCAT
}

# Generate a list of HEX colors (space separated)
generate_color_list()
{
    # from: https://stackoverflow.com/a/40278172
    # shellcheck disable=SC2034
    for i in $(seq 1 "$1"); do
        hexdump -n 3 -v -e '"#" 3/1 "%02X" "\n"' /dev/urandom
    done
}

# check a list of HEX colors (space separated)
check_color_list()
{
    # shellcheck disable=SC2048
    for c in $*; do
        if ! echo "$c"|grep -q '^#[a-fA-F0-9]\{6\}$'; then
            return 0
        fi
    done
    return 1
}

# display a fatal error and exit
fatal_error()
{
    _msg="$1\\n"
    shift
    # shellcheck disable=SC2059
    printf "$_msg" "$@"|sed "s/^/FATAL ERROR: /g" >&2
    exit 1
}

# display an error
error()
{
    _msg="$1\\n"
    shift
    # shellcheck disable=SC2059
    printf "$_msg" "$@"|sed "s/^/ERROR: /g" >&2
}

# display a warning
warning()
{
    _msg="$1\\n"
    shift
    # shellcheck disable=SC2059
    printf "$_msg" "$@"|sed "s/^/WARNING: /g" >&2
}

# display a debug message (when VERBOSITY is not empty)
debug()
{
    if [ "$VERBOSITY" != '' ]; then
        _msg="$1\\n"
        shift
        # shellcheck disable=SC2059
        printf "$_msg" "$@"|sed 's/^/[DEBUG] /g'
    fi
}

# display an info message
info()
{
    _msg="$1\\n"
    shift
    # shellcheck disable=SC2059
    printf "$_msg" "$@"|sed 's/^/* /g'
}


# options definition
# using GNU getopt here, install it if not the default on your distro
options_definition="$( \
    getopt --options heag: \
           --longoptions 'help,exclude-src,auto,generate:' \
           --name "$THIS_SCRIPT_NAME" \
           -- "$@")"
if [ "$options_definition" = '' ]; then
    fatal_error "Empty option definition"
fi
eval set -- "$options_definition"

# options parsing
opt_help=false
opt_exclude_src=false
opt_auto=false
opt_generate=
while true; do
    case "$1" in
        -h | --help            ) opt_help=true        ; shift   ;;
        -e | --exclude-src     ) opt_exclude_src=true ; shift   ;;
        -a | --auto            ) opt_auto=true        ; shift   ;;
        -g | --generate-colors ) opt_generate="$2"    ; shift 2 ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
done

# help option
if [ "$opt_help" = 'true' ]; then
    usage
    exit 0
fi

# generate option
if [ "$opt_generate" != '' ]; then
    if ! echo "$opt_generate"|grep -q '^[0-9]\+$'; then
        fatal_error "Number of colors must be a postive number (not: '%s')" "$opt_generate"
    fi
    generate_color_list "$opt_generate"|tr '\n' ' '
    echo
    exit 0
fi

# not enough arguments
if [ "$#" -lt 2 ] && [ "$opt_auto" = 'true' ] || [ "$#" -lt 3 ] && [ "$opt_auto" != 'true' ]; then
    error "Too few arguments"
    usage
    exit 1
fi

# source directory
src_dir="$1"
shift
if [ ! -d "$src_dir" ]; then
    fatal_error "Directory '%s' doesn't exist" "$src_dir"
fi

# destination directory
dest_dir="$1"
shift
if [ ! -d "$dest_dir" ]; then
    debug "Creating directory '%s'" "$dest_dir"
    mkdir -p "$dest_dir"
fi

# background colors
bg_colors="$(echo "$*"|sed 's/#//g;s/ *$//g;s/^ *//g')"

# auto option conflict with colors argument
if [ "$opt_auto" = 'true' ] && [ "$bg_colors" != '' ]; then
    error "You have specified option '--auto' and colors argument, which are mutualy exclusive"
    usage
fi

# need to generate colors
if [ "$opt_auto" = 'true' ]; then
    number_of_colors="$COLOR_NUMBER_DEFAULT"
    if [ "$opt_exclude_src" != 'true' ]; then
        number_of_colors="$((number_of_colors -1))"
    fi
    bg_colors="$(generate_color_list "$number_of_colors"|tr '\n' ' '|sed 's/#//g;s/ *$//g')"
    debug "Colors generated: %s" "$bg_colors"
fi

# check colors
if ! check_color_list "$bg_colors"; then
    fatal_error "Invalid color list (%s)" "$bg_colors"
fi

# source theme name
src_theme_name="$(basename "$src_dir")"

# if default theme should be included
if [ "$opt_exclude_src" != 'true' ]; then

    # copy default (first) theme
    d_path="$dest_dir/$src_theme_name"
    if [ ! -d "$d_path" ]; then
        info "Copying source theme '%s' to '%s'" "$src_dir" "$dest_dir"
        cp -r "$src_dir" "$dest_dir"/
    else
        fatal_error "Destination directory '%s' already exists" "$d_path"
    fi

# source dir excluded
else
    debug "Source dir '%s' is excluded by user demand" "$src_dir"
fi

# generate derivative from the default theme with the background color changed
info "Generating random background theme derivatives to '%s' ..." "$dest_dir"
for c in $bg_colors; do
    t_name="${src_theme_name}_$c"
    t_path="$dest_dir/$t_name"
    t_overwrite=
    if [ -d "$t_path" ]; then
        t_overwrite=" (overwritten)"
    fi
    debug " - %s%s" "$t_name" "$t_overwrite"
    cp -r "$src_dir" "$t_path"
    sed_cmd='s/^[[:blank:]]*#\?\([[:blank:]]*desktop-color'`
            `'[[:blank:]]*:[[:blank:]]*\)"[^"]\+"/\1"#'"$c"'"/g'
    sed "$sed_cmd" -i "$t_path/$GRUB_THEME_FILENAME"
    if [ -w "$t_path/$GRUB_THEME_INNER_FILENAME" ]; then
        sed "$sed_cmd" -i "$t_path/$GRUB_THEME_INNER_FILENAME"
    fi
    if [ -w "$t_path/$GRUB_THEME_ONDISK_FILENAME" ]; then
        sed "$sed_cmd" -i "$t_path/$GRUB_THEME_ONDISK_FILENAME"
    fi
done

