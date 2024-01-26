#!/bin/bash
set -x
set -e # https://mywiki.wooledge.org/BashFAQ/105

[[ $SANOID_SCRIPT == post ]] || exit
[[ $SANOID_PRE_FAILURE -eq 0 ]] || exit
[[ $SANOID_TARGETS ]] || exit
[[ $SANOID_SNAPNAMES ]] || exit
export SAS=
export CONTAINER=
azcopy list "$CONTAINER$SAS"

process() {
    file_system=$2
    umask 177 # for newly created log files
    cd /bak/sanoid
    # https://stackoverflow.com/questions/75474417/bash-pv-outputting-m-at-the-end-of-each-line/75481792#75481792
    # https://stackoverflow.com/questions/70398228/transform-stream-sent-to-a-file-by-tee/70398383#70398383
    ./snapshots.sh "$file_system" 2>&1 \
        | tee >(stdbuf -oL tr "\r" "\n" \
            >> logs/"${file_system//\//.}".log)
}
# https://github.com/jimsalterjrs/sanoid/issues/455
# https://github.com/jimsalterjrs/sanoid/issues/104
# https://stackoverflow.com/questions/918886/how-do-i-split-a-string-on-a-delimiter-in-bash/15988793#15988793
mapfile -td , -c 1 -C process < <(printf "%s\0" "$SANOID_TARGETS")