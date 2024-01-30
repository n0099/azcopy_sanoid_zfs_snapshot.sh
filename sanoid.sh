#!/bin/bash
set -x
set -e # https://mywiki.wooledge.org/BashFAQ/105

[[ $SANOID_SCRIPT == post ]] || exit
[[ $SANOID_PRE_FAILURE -eq 0 ]] || exit
[[ $SANOID_TARGETS ]] || exit
[[ $SANOID_SNAPNAMES ]] || exit

# https://mywiki.wooledge.org/BashFAQ/028
# https://stackoverflow.com/questions/35006457/choosing-between-0-and-bash-source
if [[ ${BASH_SOURCE[0]} = */* ]]; then
    bundledir=${BASH_SOURCE%/*}
else
    bundledir=.
fi
source "$bundledir/config.sh"

azcopy ls --running-tally "$CONTAINER$SAS"
# https://github.com/jimsalterjrs/sanoid/issues/455
# https://github.com/jimsalterjrs/sanoid/issues/104
# https://stackoverflow.com/questions/918886/how-do-i-split-a-string-on-a-delimiter-in-bash/15988793#15988793
mapfile -td, -c 1 -C process_file_system < <(printf "%s\0" "$SANOID_TARGETS")

process_file_system() {
    local file_system=$2
    local file_system_dot=${file_system//\//.}
    local file_system_log=${file_system_dot#rpool.}
    umask 177 # for newly created log files
    # https://stackoverflow.com/questions/75474417/bash-pv-outputting-m-at-the-end-of-each-line/75481792#75481792
    # https://stackoverflow.com/questions/70398228/transform-stream-sent-to-a-file-by-tee/70398383#70398383
    process_snapshots "$file_system" 2>&1 \
        | tee >(stdbuf -oL tr "\r" "\n" \
            >> logs/"$file_system_log".log)
}

process_snapshots() {
    week=$(date +%G-W%V) # https://en.wikipedia.org/wiki/ISO_week_date
    file_system=$1 # share with process_snapshot()
    # shellcheck disable=SC2317
    process_snapshot() {
        local snapshot=$2
        case $snapshot in
            autosnap_*_daily)
                directory=$week/${file_system#rpool/}/
                # azcopy ls "$CONTAINER$directory$SAS" require READ permission for SAS
                # instead of LIST permission to filter files with directory prefix
                # https://github.com/Azure/azure-storage-azcopy/issues/583
                # https://github.com/Azure/azure-storage-azcopy/issues/858
                # https://github.com/Azure/azure-storage-azcopy/issues/1546
                # may requires custom sorter to put complete _weekly after increasemental _daily https://superuser.com/questions/489275/how-to-do-custom-sorting-using-unix-sort
                local latest_snapshot
                latest_snapshot=$(azcopy ls "$CONTAINER$SAS" \
                    | awk -F\; '{print $1}' \
                    | grep -oP '(?<=^INFO: )'"$directory"'[^/]*$' \
                    | sort -n \
                    | tail -n 1)
                [[ $latest_snapshot ]] || return 0
                latest_snapshot=autosnap_${latest_snapshot#"$directory"}
                zfs_send_to_azcopy "-i $file_system@$latest_snapshot $file_system@$snapshot" \
                    "$file_system" "$snapshot"
                ;;
            autosnap_*_weekly)
                zfs_send_to_azcopy "$file_system@$snapshot" \
                    "$file_system" "$snapshot"
        esac
    }
    mapfile -td, -c 1 -C process_snapshot < <(printf "%s\0" "$SANOID_SNAPNAMES")
    # order of frequency types in $SANOID_SNAPNAMES seems to be ensured by sanoid
    # https://github.com/jimsalterjrs/sanoid/blob/a5fa5e7badecc435663e40e6a0f69523c2a0fd1c/sanoid#L146
    # https://github.com/jimsalterjrs/sanoid/blob/a5fa5e7badecc435663e40e6a0f69523c2a0fd1c/sanoid#L585
}

zfs_send_to_azcopy() {
    local send_params=$1
    local file_system=$2
    local snapshot=$3
    local AZCOPY_LOG_LOCATION=$bundledir/logs/azcopy
    export AZCOPY_LOG_LOCATION # https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-configure#change-the-location-of-log-files
    export AZCOPY_BUFFER_GB=0.5 # https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-optimize#optimize-memory-use

    # intentionally word-splitting https://unix.stackexchange.com/questions/378584/spread-bash-argument-by-whitespace/378591#378591
    # shellcheck disable=SC2086
    local send_size_uncompressed
    send_size_uncompressed=$(zfs send -LcPn "$send_params" | awk '/^size/{print $2}')
    [[ $send_size_uncompressed -le 624 ]] && return 0 # increasemental <=624 bytes usually means "no changes" between snapshots
    # shellcheck disable=SC2086
    local send_size
    send_size=$(zfs send -LcPn "$send_params" | awk '/^size/{print $2}')
    [[ $send_size ]] || return 0

    # https://serverfault.com/questions/95639/count-number-of-bytes-piped-from-one-snapshot-to-another/95654#95654
    # https://superuser.com/questions/1470608/file-redirection-vs-dd/1470733#1470733
    # shellcheck disable=SC2086
    zfs send -LcP $send_params \
        | tee >(dd of=/dev/null) \
        | pv -pterabfs "$send_size" \
        | azcopy cp --from-to PipeBlob --block-size-mb 32 \
            "$CONTAINER/$week/${file_system#rpool/}/${snapshot#autosnap_}$SAS"
}
