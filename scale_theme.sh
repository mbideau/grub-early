#!/bin/sh

# scale a theme resolution using keyword "scale"

set -e

if [ "$DEBUG" = '' ]; then
    DEBUG=false
fi
NL="$(printf '\n\e')"
SCALE_KEYWORD=scale
SOURCE_RESOLUTION_REGEXP='^#[[:blank:]]*for a resolution of:[[:blank:]]*\([0-9]\+[xX*][0-9]\+\)[[:blank:]]*$'

usage()
{
    cat <<ENDCAT
$(basename "$0") - Scale a Grub theme file to desired resolution

USAGE

    $(basename "$0") -h|--help
        Display this help

    $(basename "$0") SOURCE DESTINATION WIDTH HEIGHT
        Scale the theme to specified resolution

ARGUMENTS

    SOURCE
        A GRUB theme file to scale from

    DESTINATION
        The produced scaled theme file destination path

    WIDTH
        The width to scale to

    HEIGHT
        The height to scale to

OPTIONS

    -h|--help
        Display this help

EXAMPLES

    $(basename "$0") /path/to/theme.txt /path/to/new/scaled/theme.txt 1920 1080
        Scale a theme from a resolution (detected automatically) to 1920x1080

NOTES

    To detect what is the source resolution of the theme, this programme use the following
    regex (first group match should be the resolution):
        $SOURCE_RESOLUTION_REGEXP

    To detect what value needs to be scanned this programme use the keyword: $SCALE_KEYWORD.
    This keyword must be on the same line that the value requires to be scaled.
    It should be in a comment to not produce a syntax error.

    The keyword might be followed by a colon ':' and other keywords from:
        min
            Scale using the ratio (width or height) of the minimum factor between width and
            height.
            Usefull for scaling images because their ratio aspect must be maintained.
            For example: if we are going from 1280x1024 to 1440x900: 
                - the minimum between 1280 and 1024 is 1024, so height (wide display)
                - the minimum between 1440 and 900 is 900, so height (wide display)
                - so the ratio that will be used is the height
            Another example: if we are going from 1280x1024 to 750x1334: 
                - the minimum between 1280 and 1024 is 1024, so height (wide display)
                - the minimum between 720 and 1334 is 720, so width (high display)
                - so the ratio that will be used is the width
            Opposite example: if we are going from 750x1334 to 1280x1024: 
                - the minimum between 720 and 1334 is 720, so width (high display)
                - the minimum between 1280 and 1024 is 1024, so height (wide display)
                - so the ratio that will be used is the width
               
        multiply
            Scale by multiplying the value by the selected ratio (the default).

        divide
            Scale by dividing the value by the selected ratio (the default).

    Example of lines in the theme file:

      + image {
        top    = "50%-100" # scale: min
        left   = "50%-64"  # scale: min
        width  = 128       # scale: min
        height = 128       # scale: min
        file   = "logo.png"
      }

      + boot_menu {
        left         = "50%-58" # scale
        top          = "36%"    # scale
        width        = 2        # scale
        height       = "50%"    # scale
        ...
      }

ENDCAT
}

is_positive()
{
    echo "$1"|awk '{printf "%s", ($0 > 1.0 ? "true" : "false") }'|grep -q 'true'
}

min()
{
    echo "$1 $2"|awk '{ print ($1 > $2 ? $2 : $1) }'
}

max()
{
    echo "$1 $2"|awk '{ print ($1 > $2 ? $1 : $2) }'
}

select_ratio()
{
    width_ratio="$1"
    height_ratio="$2"
    ratio="$width_ratio"
    if is_positive "$width_ratio" && is_positive "$height_ratio"; then       # both grow
        ratio="$(min "$width_ratio" "$height_ratio")"
    elif ! is_positive "$width_ratio" && ! is_positive "$height_ratio"; then # both degrow
        ratio="$(max "$width_ratio" "$height_ratio")"
    elif ! is_positive "$width_ratio" && is_positive "$height_ratio"; then   # wide to high
        ratio="$width_ratio"
    elif is_positive "$width_ratio" && ! is_positive "$height_ratio"; then   # high to wide
        ratio="$width_ratio"
    fi
    echo "$ratio"
}

debug()
{
    if [ "$DEBUG" = 'true' ]; then
        echo "$@"|sed 's/^/[DEBUG] /g' >&2
    fi
}


# help
if [ "$1" = '-h' ] || [ "$1" = '--help' ]; then
    usage
    exit 0
fi

# arguments
src_file="$1"
dest_file="$2"
dest_width="$3"
dest_height="$4"

debug "src_file   : $src_file"
debug "dest_file  : $dest_file"
debug "dest_width : $dest_width"
debug "dest_height: $dest_height"

# check arguments
if [ ! -e "$src_file" ]; then
    echo "Error: file '$src_file' not found" >&2
    exit 1
fi
if ! echo "$dest_width"|grep -q '^[0-9]\+$'; then
    echo "Error: invalid destination width '$dest_width'" >&2
    exit 1
fi
if ! echo "$dest_height"|grep -q '^[0-9]\+$'; then
    echo "Error: invalid destination height '$dest_height'" >&2
    exit 1
fi

source_resolution="$(grep "$SOURCE_RESOLUTION_REGEXP" "$src_file"|sed "s/$SOURCE_RESOLUTION_REGEXP/\\1/g" || true)"
debug "source_resolution: $source_resolution"

if [ "$source_resolution" = '' ]; then
    echo "Error: failed to auto detect resolution of the source theme file '$src_file'" >&2
    exit 1
fi

src_width="$(echo "$source_resolution"|sed 's/^\([0-9]\+\)[^0-9].*/\1/g')"
src_height="$(echo "$source_resolution"|sed 's/^.*[^0-9]\([0-9]\+\)$/\1/g')"
debug "src_width : $src_width"
debug "src_height: $src_height"

echo "Scaling theme: $src_file ($source_resolution) -> $dest_file (${dest_width}x${dest_height})"

# destination parent dir needs to exists
if [ ! -d "$(dirname "$dest_file")" ]; then
    mkdir -p "$(dirname "$dest_file")"
fi

ratio_width="$(echo "$dest_width"|LC_ALL=C awk "{ print \$0 / $src_width }")"
ratio_height="$(echo "$dest_height"|LC_ALL=C awk "{ print \$0 / $src_height }")"
debug "ratio_width : $ratio_width"
debug "ratio_height: $ratio_height"
ratio_preserved="$(select_ratio "$ratio_width" "$ratio_height")"

# build sed command
sed_cmd="sed -e 's/$SOURCE_RESOLUTION_REGEXP/# for a resolution of: ${dest_width}x${dest_height}/'"
IFS_BAK="$IFS"
IFS="$NL"
# shellcheck disable=SC2013
for line in $(grep -n "^[^#]\\+[[:blank:]]*#[[:blank:]]*$SCALE_KEYWORD\\([[:blank:]]*:.*\\)*[[:blank:]]*\$" "$src_file"); do
    IFS="$IFS_BAK"
    debug "---"
    line_num="$(echo "$line"|sed 's/^\([0-9]\+\):.*$/\1/g')"
    debug "line_num   : $line_num"
    line_no_comment="$(echo "$line"|sed 's/^[0-9]\+:\([^#]\+\)[[:blank:]]*#.*/\1/g')"
    debug "line no #  : $line_no_comment"
    line_comment="$(echo "$line"|sed "s/^[0-9]\\+:[^#]\\+[[:blank:]]*#[[:blank:]]*\\(.*\\)[[:blank:]]*$/\\1/g")"
    debug "line comnt : $line_comment"
    scale_info="$(echo "$line_comment"|sed "s/^$SCALE_KEYWORD\\([[:blank:]]*:.*\\)*\$/\\1/g")"
    debug "scale info : $scale_info"
    scale_params="$(echo "$scale_info"|sed -e 's/^[[:blank:]]*:[[:blank:]]*$//g' -e 's/[[:blank:]]*$//g')"
    debug "scale param: $scale_params"
    key="$(echo "$line_no_comment"|sed 's/^[[:blank:]]*\([^[:blank:]]\+\)[[:blank:]]*[=:][[:blank:]]*"\?[^[:blank:]]\+"\?[[:blank:]]*$/\1/g')"
    debug "key        : $key"
    scale_ratio=1
    case "$key" in
        *left*|*right*|*width*)  scale_ratio="$ratio_width"  ;;
        *top*|*bottom*|*height*) scale_ratio="$ratio_height" ;;
    esac
    if echo " $scale_params "|grep -q "[[:blank:]]preserve-ratio[[:blank:]]"; then
        scale_ratio="$ratio_preserved"
    fi
    debug "scale_ratio: $scale_ratio"
    scale_operator="$(if echo " $scale_params "|grep -q "[[:blank:]]divide[[:blank:]]"; then echo "/"; else echo "*"; fi)"
    debug "scale_op   : $scale_operator"
    value="$(echo "$line_no_comment"|sed 's/^[[:blank:]]*[^[:blank:]]\+[[:blank:]]*[=:][[:blank:]]*"\?\([^[:blank:]"]\+\)"\?[[:blank:]]*$/\1/g')"
    debug "value      : $value"
    new_value="$value"
    if echo "$value"|grep -q '^[0-9]\+%[-+][0-9]\+$'; then
        debug "value type : relative percentage modified by fixed value"
        rel_value="$(echo "$value"|sed 's/^\([0-9]\+\)%[-+][0-9]\+$/\1/g')"
        debug "rel_value  : $rel_value"
        mod_sign="$(echo "$value"|sed 's/^[0-9]\+%\([-+]\)[0-9]\+$/\1/g')"
        debug "mod_sign   : $mod_sign"
        fix_value="$(echo "$value"|sed 's/^[0-9]\+%[-+]\([0-9]\+\)$/\1/g')"
        debug "fix_value  : $fix_value"
        new_fix_value="$(echo "$fix_value"|LC_ALL=C awk "{ printf "'"%.f"'", \$0 $scale_operator $scale_ratio }")"
        debug "new_fix_val: $new_fix_value"
        new_value="$rel_value%${mod_sign}$new_fix_value"
    elif echo "$value"|grep -q '^[0-9]\+%$'; then
        debug "value type : relative percentage"
        rel_value="$(echo "$value"|sed 's/^\([0-9]\+\)%$/\1/g')"
        debug "rel_value  : $rel_value"
        new_value="$(echo "$rel_value"|LC_ALL=C awk "{ printf "'"%.f"'", \$0 $scale_operator $scale_ratio }")%"
    elif echo "$value"|grep -q '^[0-9]\+$'; then
        debug "value type : fixed value"
        new_value="$(echo "$value"|LC_ALL=C awk "{ printf "'"%.f"'", \$0 $scale_operator $scale_ratio }")"
    fi
    debug "new value  : $new_value"
    new_sed_cmd="s/$value/$new_value/"
    debug "new sed cmd: $new_sed_cmd"
    debug "new line   : $(echo "$line"|sed -e 's/^[0-9]\+://' -e "$new_sed_cmd")"
    sed_cmd="$sed_cmd -e '$line_num $new_sed_cmd'"
    IFS="$NL"
done
IFS="$IFS_BAK"

sed_cmd="$sed_cmd '$src_file'"
debug "sed_cmd : $sed_cmd"

eval "$sed_cmd" > "$dest_file"

