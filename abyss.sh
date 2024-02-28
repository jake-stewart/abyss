#!/bin/bash
set -e

[ -z "$XDG_CACHE_HOME" ] && XDG_CACHE_HOME="$HOME/.config"
CACHE="$XDG_CACHE_HOME/abyss"
mkdir -p "$CACHE"

command_exists() {
    command -v "$1" &>/dev/null; 
}

abort() {
    echo "error: $1" >/dev/stderr
    exit 1
}

idle-darwin() {
    ns="$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/{print $NF}')"
    echo "$((ns / 1000000000))"
}

idle-xorg() {
    ms="$(xprintidle)"
    echo "$((ms / 1000))"
}

capture() {
    for program in scrot maim screencapture; do
        if command_exists "$program"; then
            screenshot="$program"
        fi
    done
    [ -n "$screenshot" ] || abort "install maim or scrot"

    if command_exists xprintidle; then
        idle="idle-xorg"
    elif command_exists ioreg; then
        idle="idle-darwin"
    else
        case "$(uname)" in
            Linux | OpenBSD)
                abort "install xprintidle for idle checking";;
            *)
                abort "your OS is not supported";;
        esac
    fi

    case "$screenshot" in
        screencapture)
            # do not play sounds
            flags="-x";;
    esac

    # INTERVAL="$((10 * 60))"
    INTERVAL=10

    while true; do
        sleep "$INTERVAL"
        if (($($idle) > INTERVAL)); then
            echo "idle..."
            continue
        fi
        fname="$CACHE/$(date +%s).png"
        "$screenshot" $flags "$fname"
        echo "$fname"
    done
}

parse-duration() {
    [ "$1" = "" ] && abort "duration not specified"
    echo "$1" | grep -qE "^[0-9]+[dhms]$" || abort "invalid duration"
    num=$(echo "$1" | grep -oE "[0-9]+")
    unit=$(echo "$1" | grep -oE "[dhms]")
    case "$unit" in
        s) echo "$num";;
        m) echo "$((num * 60))";;
        h) echo "$((num * 60 * 60))";;
        d) echo "$((num * 60 * 60 * 24))";;
    esac
}

combine() {
    seconds="$(parse-duration "$duration")"
    earliest="$(($(date +%s) - $seconds))"

    command_exists ffmpeg || abort "install ffmpeg"
    cd "$CACHE"

    fname="$(date +%Y-%m-%d_%H:%M:%S.mp4)"
    ls | grep '^[0-9]*\.png$' | sort -n | awk -F. \
        "\$1 > $earliest {print \"file '\" \$0 \"'\\nduration 1\"}" \
        > input.txt

    ffmpeg -safe 0 -f concat -i input.txt -c:v libx264 -pix_fmt yuv420p "$fname"
    rm input.txt
    cd - >/dev/null

    if [ -n "$output" ]; then
        mv "$CACHE/$fname" "$output"
    else
        echo "$CACHE/$fname"
    fi
}

usage() {
    echo "--help                 show this menu"
    echo "--record               begin taking screenshots"
    echo "--generate [duration]  generate slideshow"
    echo "--output [file]        specify output for --generate"
    echo "                       (defaults to $CACHE/*.mp4)"
    echo ""
    echo "example duration: 2h"
}

while [ -n "$1" ]; do
    case "$1" in
        "--generate")
            shift
            [ -z "$1" ] && abort "--generate requires duration argument"
            duration="$1"
            ;;
        "--output")
            shift
            [ -z "$1" ] && abort "--output requires file argument"
            output="$1"
            ;;
        "--record")
            record=1
            ;;
        "-h" | "--help")
            usage
            exit 0
            ;;
    esac
    shift
done

[ -n "$record" ] && [ -n "$duration" ] && \
    abort "can only use --record and --generate exclusively"
if [ -n "$duration" ]; then
    combine
elif [ -n "$record" ]; then
    capture
else
    usage
fi
