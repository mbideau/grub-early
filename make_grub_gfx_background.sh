#!/bin/sh
# Create images required by grub to fake transparency of the terminal box

set -e

# padding to add when croping (will extend dimensions to the right and the bottom)
if [ "$CROP_PADDING" = '' ]; then
    CROP_PADDING=0
fi

# background color of the extended canvas
if [ "$CANVAS_COLOR" = '' ]; then
    CANVAS_COLOR=black
fi

# generate border images
if [ "$BORDER_IMAGES" = '' ]; then
    BORDER_IMAGES=false
fi

# border size
if [ "$BORDER_TOP_BOTTOM" = '' ]; then
    BORDER_TOP_BOTTOM=30
fi
if [ "$BORDER_LEFT_RIGHT" = '' ]; then
    BORDER_LEFT_RIGHT=30
fi

# the steps to reduce size of image
if [ "$REDUCTION_PERCENT_STEP" = '' ]; then
    REDUCTION_PERCENT_STEP=2
fi

# size under which this is useless to attemp a reduction (because it will be too ugly/blured)
MINIMUM_IMG_SIZE_SUMMED=20

# quiet mode
if [ "$QUIET" = '' ]; then
    QUIET=false
fi

# usage
usage()
{
    this_script_name="$(basename "$0")"
    cat <<ENDCAT

$this_script_name - Create images required by grub to fake transparency of the terminal box

USAGE

    $this_script_name -h|--help
        Display this help

    $this_script_name  IMAGE_SRC  DEST_RESOLUTION  THEME_FILE  [MAX_SIZE]
        Create two images, one for theme 'desktop-image' and one for grub term 'background_image'


ARGUMENTS

    IMAGE_SRC
        Path to image that will be used as the source.
        It can be any image type supported by ImageMagick.

    DEST_RESOLUTION
        The resolution that grub will be displayed to (in graphical/gfx mode).
        Format is: WIDTHxHEIGHT, like i.e.: 1440x900.

    THEME_FILE
        Path to a grub2 theme file specifying terminal box dimensions and position.
        The file must have the following directives specified: terminal-width,
        terminal-height, terminal-top, terminal-left (terminal-right and terminal-bottom
        are not yet supported).
        The values of 'terminal-top' and 'terminal-left' can be relatives (like i.e.: 50%,
        or 50%-25), others must be integers.

    MAX_SIZE (optional)
        Maximum size of both images summed. Images will be resized by step of $REDUCTION_PERCENT_STEP % while
        their sizes's sum is not below the specified maximum.
        If you don't like the images to be resized (which I recommend) and you prefer reducing
        their size in an other way do it manualy with the tool of yor choosing (like using optipng,
        pngquant, zopflipng, or whatever).


OPTIONS

    -h|--help
        Display help message.


ENVIRONMENT

    CROP_PADDING
        Amount of pixel to add to width and height of the cropped picture to have a slightly bigger
        image in case of the terminal being displayed a little bigger.
        Default: 0.

    CANVAS_COLOR
        Color (one understandable by ImageMagick) of the background of the croped image when its
        canvas will be extended.
        Default: black.

    BORDER_IMAGES
        If set to 'true' will generate border images, i.e. all the images around the terminal box.
        See grub theming for more information about border images.
        Default: false.

    BORDER_TOP_BOTTOM
        The size of the top and bottom border images.
        Default: 30.

    BORDER_LEFT_RIGHT
        The size of the left and right border images.
        Default: 30.

    REDUCTION_PERCENT_STEP
        Reduction step percentage when resizing down the images to go below MAX_SIZE.
        Default: 2.

    QUIET
        If set to 'true' will not print messages. Errors will still be thrown to STDERR.
        Default: false.


EXAMPLES

    $this_script_name  /tmp/awesome_bg.jpg 1440x900 /tmp/theme.txt
        Lets say that:
            - this image have a resolution of '3515x2344'
            - the theme file defines a terminal box like: '818x469' at x:326 y:180
        This program will produce following images :
            /tmp/awesome_bg.1440x900.png
                Resized image to final resolution, will be used for theme 'desktop-image'.
            /tmp/awesome_bg.cropped.818x469.png
                Croped image that represent the grub terminal position.
            /tmp/awesome_bg.1440x900.cropped.818x469.extended.1440x900.png
                Extended image that will be used for the grub terminal 'backgroud_image'.

    $this_script_name  /tmp/awesome_bg.jpg 1440x900 /tmp/theme.txt 100
        This program will produce the same images as above plus two :
            /tmp/awesome_bg.1440x900.resized.png
                Reduced image size that will be used for theme 'desktop-image'.
            /tmp/awesome_bg.1440x900.cropped.818x469.extended.1440x900.resized.png
                Reduced image size that will be used for the grub terminal 'backgroud_image'.
        Note: the sum of those images's size will be lower than 100 K (as specified).

ENDCAT
}

# functions
msg()
{
    if [ "$QUIET" != 'true' ]; then
        echo "$@"
    fi
}
min()
{
    echo "$1 $2"|awk '{print ($1 < $2 ? $1 : $2) }'
}
get_fixed_value()
{
    value="$1"
    reference="$2"
    new_value="$value"
    if echo "$value"|grep -q '^[0-9]\+%[-+][0-9]\+$'; then
        rel_value="$(echo "$value"|sed 's/^\([0-9]\+\)%[-+][0-9]\+$/\1/g')"
        mod_sign="$(echo "$value"|sed 's/^[0-9]\+%\([-+]\)[0-9]\+$/\1/g')"
        fix_value="$(echo "$value"|sed 's/^[0-9]\+%[-+]\([0-9]\+\)$/\1/g')"
        new_value="$(echo "$rel_value $fix_value"|LC_ALL=C awk "{ printf "'"%.f"'", ($reference * \$1 / 100) $mod_sign \$2 }")"
    elif echo "$value"|grep -q '^[0-9]\+%$'; then
        rel_value="$(echo "$value"|sed 's/^\([0-9]\+\)%$/\1/g')"
        new_value="$(echo "$rel_value"|LC_ALL=C awk "{ printf "'"%.f"'", $reference * \$1 / 100 }")"
    fi
    echo "$new_value"
}


# help
if [ "$1" = '-h' ] || [ "$1" = '--help' ]; then
    usage
    exit 0
fi

# arguments
image_src="$1"
dest_resolution="$2"
theme_file="$3"
max_size="$4"

# check arguments
if [ ! -e "$image_src" ]; then
    echo "ERROR: image source file '$image_src' doesn't exist" >&2
    exit 1
fi
if ! echo "$dest_resolution"|grep -q '^[0-9]\+x[0-9]\+$'; then
    echo "ERROR: invalid resolution specified '$dest_resolution' (must be: ^[0-9]\\+x[0-9]\\+$)" >&2
    exit 1
fi
if [ ! -e "$theme_file" ]; then
    echo "ERROR: theme file '$theme_file' doesn't exist" >&2
    exit 1
fi
if [ "$max_size" != '' ] && ! echo "$max_size"|grep -q '^[0-9]\+$'; then
    echo "ERROR: invalid maximum size '$max_size' (must be a positive integer)" >&2
    exit 1
fi
if [ "$max_size" != '' ] && [ "$max_size" -le "$MINIMUM_IMG_SIZE_SUMMED" ]; then
    echo "ERROR: invalid maximum size '$max_size' (must be greater than $MINIMUM_IMG_SIZE_SUMMED)" >&2
    exit 1
fi

# image file basename
img_src_basename_no_suffix="$(basename "$image_src"|sed 's/\.\w\+$//g')"

# get each dimension values for source and destination resolution
img_src_width="$(identify -format %w "$image_src")"
img_src_height="$(identify -format %h "$image_src")"
dest_res_width="$(echo "$dest_resolution"|sed 's/^\([0-9]\+\)[^0-9].*/\1/g')"
dest_res_height="$(echo "$dest_resolution"|sed 's/^.*[^0-9]\([0-9]\+\)$/\1/g')"
msg "Resolution: ${img_src_width} x $img_src_height -> $dest_res_width x $dest_res_height"

# calculate image convertion ratios to fit (stretched) the destination resolution
width_ratio="$(echo "$img_src_width $dest_res_width"|LC_ALL=C awk '{printf "%f", $2 * 100 / $1}')"
height_ratio="$(echo "$img_src_height $dest_res_height"|LC_ALL=C awk '{printf "%f", $2 * 100 / $1}')"
msg "Width : $img_src_width -> $dest_res_width => $width_ratio %"
msg "Height: $img_src_height -> $dest_res_height => $height_ratio %"

# calculate the terminal dimensions and position from the theme file
term_width_raw="$(grep '^ *terminal-width *: *' "$theme_file"|sed 's/^ *terminal-width *: *"\?\([0-9]\+\)"\?.*$/\1/g')" 
term_height_raw="$(grep '^ *terminal-height *: *' "$theme_file"|sed 's/^ *terminal-height *: *"\?\([0-9]\+\)"\?.*$/\1/g')" 
term_x_raw="$(grep '^ *terminal-left *: *' "$theme_file"|sed 's/^ *terminal-left *: *"\?\([0-9%+-]\+\)"\?.*$/\1/g')"
term_y_raw="$(grep '^ *terminal-top *: *' "$theme_file"|sed 's/^ *terminal-top *: *"\?\([0-9%+-]\+\)"\?.*$/\1/g')"
term_width="$((term_width_raw + CROP_PADDING))"
term_height="$((term_height_raw + CROP_PADDING))"
term_x="$(get_fixed_value "$term_x_raw" "$dest_res_width")"
term_y="$(get_fixed_value "$term_y_raw" "$dest_res_height")"
# TODO support right and bottom too
msg "Terminal: ${term_width} x ${term_height} at x:${term_x} y:${term_y} (x_raw: $term_x_raw, y_raw: $term_y_raw, crop padding: $CROP_PADDING)"

# convert the image to its destination resolution
img_dest_res="$(dirname "$image_src")/$img_src_basename_no_suffix.$dest_resolution.png"
msg "Converting from image source to destination resolution: $img_dest_res"
convert -resize "${dest_resolution}!" "$image_src" "$img_dest_res"

# crop the image to the size and position of the terminal box
img_term_no_canvas="$(dirname "$image_src")/$(basename "$img_dest_res" '.png').cropped.${term_width}x${term_height}.png"
msg "Croping image at the destination resolution with terminal dimensions and position: $img_term_no_canvas"
convert -crop "${term_width}x${term_height}+${term_x}+${term_y}" "$img_dest_res" "$img_term_no_canvas"

# extract border images
if [ "$BORDER_IMAGES" = 'true' ]; then
    msg "Croping borders images at the destination resolution ..."
    for pos in nw n ne w e sw se s; do
        border_width="$BORDER_LEFT_RIGHT"
        if [ "$pos" = 'n' ] || [ "$pos" = 's' ]; then
            border_width="$term_width"
        fi
        border_height="$BORDER_TOP_BOTTOM"
        if [ "$pos" = 'w' ] || [ "$pos" = 'e' ]; then
            border_height="$term_height"
        fi
        case "$pos" in
            nw) border_x="$((term_x - border_width))"; border_y="$((term_y - border_height))"; ;;
            n)  border_x="$term_x"                   ; border_y="$((term_y - border_height))"; ;;
            ne) border_x="$term_width"               ; border_y="$((term_y - border_height))"; ;;
            sw) border_x="$((term_x - border_width))"; border_y="$((term_y + term_height))"; ;;
            s)  border_x="$term_x"                   ; border_y="$((term_y + term_height))"; ;;
            se) border_x="$term_width"               ; border_y="$((term_y + term_height))"; ;;
            w)  border_x="$((term_x - border_width))"; border_y="$term_y" ;;
            e)  border_x="$term_width"               ; border_y="$term_y" ;;
        esac
        img_border_pos="$(dirname "$image_src")/$(basename "$img_dest_res" '.png').cropped.border-$pos.${border_width}x${border_height}.png"
        msg " - $(printf "%2s" "$pos"): $border_width x $border_height at x:$border_x y:$border_y => '$img_border_pos'"
        convert -crop "${border_width}x${border_height}+${border_x}+${border_y}" "$img_dest_res" "$img_border_pos"
    done
fi

# extends the canvas to the size of the destination resolution
img_term_with_canvas="$(dirname "$image_src")/$(basename "$img_term_no_canvas" '.png').extended.$dest_resolution.png"
msg "Extending image cropped to the destination resolution (background $CANVAS_COLOR): $img_term_with_canvas"
convert -gravity NorthWest -extent "$dest_resolution" -background "$CANVAS_COLOR" "$img_term_no_canvas" "$img_term_with_canvas"

# images to use for
theme_desktop_image="$img_dest_res"
grub_shell_term_bg_img="$img_term_with_canvas"

# reduce size/resolution of both images to be below the maximum size specified (summed)
if [ "$max_size" != '' ]; then
    img_dest_res_size="$(du -k "$img_dest_res"|awk '{ print $1 }')"
    img_term_with_canvas_size="$(du -k "$img_term_with_canvas"|awk '{ print $1 }')"
    size_summed="$((img_dest_res_size + img_term_with_canvas_size))"
    reduction_percent="$REDUCTION_PERCENT_STEP"
    if [ "$size_summed" -gt "$max_size" ]; then
        msg "Sum of images sizes is over the maximum size of '$max_size K' reducing them (by steps of $REDUCTION_PERCENT_STEP %) ..."
        img_dest_res_resized="$(dirname "$image_src")/$(basename "$img_dest_res" '.png').resized.png"
        img_term_with_canvas_resized="$(dirname "$image_src")/$(basename "$img_term_with_canvas" '.png').resized.png"
    fi
    while [ "$size_summed" -gt "$max_size" ]; do
        image_percent=$((100 - reduction_percent))
        convert -resize "${image_percent}%" "$img_dest_res" "$img_dest_res_resized"
        img_dest_res_size="$(du -k "$img_dest_res_resized"|awk '{ print $1 }')"
        convert -resize "${image_percent}%" "$img_term_with_canvas" "$img_term_with_canvas_resized"
        img_term_with_canvas_size="$(du -k "$img_term_with_canvas_resized"|awk '{ print $1 }')"
        size_summed="$((img_dest_res_size + img_term_with_canvas_size))"
        img_resized_width="$(identify -format %w "$img_dest_res_resized")"
        img_resized_height="$(identify -format %h "$img_dest_res_resized")"
        msg " - $(printf '%2d' "$reduction_percent") % => $img_resized_width x $img_resized_height => $img_dest_res_size K + $img_dest_res_size K = $size_summed K"
        reduction_percent="$((reduction_percent + REDUCTION_PERCENT_STEP))"
    done
    theme_desktop_image="$img_dest_res_resized"
    grub_shell_term_bg_img="$img_term_with_canvas_resized"
fi

msg
msg "Now use image"
msg " - '$theme_desktop_image' as the theme 'desktop-image'"
msg " - '$grub_shell_term_bg_img' as the grub shell terminal 'background_image' (with '-m stretch')"
msg
msg "Done ;-)"

