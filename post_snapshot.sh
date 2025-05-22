#!/bin/bash
# https://mywiki.wooledge.org/BashFAQ/105
# https://gist.github.com/mohanpedala/1e2ff5661761d3abd0385e8223e16425
set -euxo pipefail

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
set -o allexport
source "$bundledir/.env"
set +o allexport
month_directory=$CONTAINER/$(date -u +%Y-%m)/

zfs_send_to_azcopy() {
    local file_system=$1
    local snapshot=$2
    local latest_snapshot=$3
    local send_params=()
    [[ -n $latest_snapshot ]] && send_params+=('-i' "$file_system@$latest_snapshot" "$file_system@$snapshot")

    local AZCOPY_LOG_LOCATION=$bundledir/logs/azcopy
    export AZCOPY_LOG_LOCATION # https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-configure#change-the-location-of-log-files
    export AZCOPY_BUFFER_GB=0.5 # https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-optimize#optimize-memory-use

    local send_size
    send_size=$(zfs send -LcPn "${send_params[@]}" | awk '/^size/{print $2}')
    [[ $send_size ]] || return 0

    # https://mywiki.wooledge.org/BashFAQ/050
    /usr/bin/time -v zfs send -LcP "${send_params[@]}" \
        | pv -pterabfs "$send_size" \
        | /usr/bin/time -v azcopy cp --from-to PipeBlob --block-size-mb 256 --block-blob-tier cold \
            "$month_directory${file_system#rpool/}/${snapshot#autosnap_}$SAS"
    # https://github.com/Azure/azure-storage-azcopy/issues/1642
    # https://learn.microsoft.com/en-us/azure/storage/blobs/access-tiers-overview
}

process_snapshots() {
    file_system=$1 # share with process_snapshot()
    # shellcheck disable=SC2317
    process_snapshot() {
        local snapshot=$2
        case $snapshot in
            autosnap_*_daily)
                # azcopy ls "$CONTAINER/virtual/directory/prefix/$SAS" require READ permission for SAS
                # instead of LIST permission to filter files with virtual directory prefix
                # https://github.com/Azure/azure-storage-azcopy/issues/583
                # https://github.com/Azure/azure-storage-azcopy/issues/858
                # https://github.com/Azure/azure-storage-azcopy/issues/1546
                # may requires custom sorter to put complete _monthly after increasemental _daily https://superuser.com/questions/489275/how-to-do-custom-sorting-using-unix-sort
                local latest_snapshot
                latest_snapshot=$(azcopy ls --output-type=json "$month_directory${file_system#rpool/}/$SAS" \
                    | jq -sr 'map(select(.MessageType == "ListObject")
                            | .MessageContent | fromjson
                            | select(.Path | contains("/") | not) | .Path)
                        | sort | last')
                [[ $latest_snapshot ]] || return 0
                zfs_send_to_azcopy "$file_system" "$snapshot" autosnap_"$latest_snapshot"
                ;;
            autosnap_*_monthly)
                zfs_send_to_azcopy "$file_system" "$snapshot"
        esac
    }
    mapfile -td, -c 1 -C process_snapshot < <(printf "%s\0" "$SANOID_SNAPNAMES")
    # order of frequency types in $SANOID_SNAPNAMES seems to be ensured by sanoid
    # https://github.com/jimsalterjrs/sanoid/blob/a5fa5e7badecc435663e40e6a0f69523c2a0fd1c/sanoid#L146
    # https://github.com/jimsalterjrs/sanoid/blob/a5fa5e7badecc435663e40e6a0f69523c2a0fd1c/sanoid#L585
}

process_file_system() {
    local file_system=$2
    local file_system_dot=${file_system//\//.}
    local file_system_log=${file_system_dot#rpool.}
    local log_file=$bundledir/logs/$file_system_log.log
    umask 177 # for newly created log files
    # https://stackoverflow.com/questions/75474417/bash-pv-outputting-m-at-the-end-of-each-line/75481792#75481792
    # https://stackoverflow.com/questions/70398228/transform-stream-sent-to-a-file-by-tee/70398383#70398383
    process_snapshots "$file_system" 2>&1 \
        | tee >(stdbuf -oL tr "\r" "\n" >> "$log_file")
    echo >> "$log_file" # extra newline
}

azcopy ls --running-tally "$month_directory$SAS"
# https://github.com/jimsalterjrs/sanoid/issues/455
# https://github.com/jimsalterjrs/sanoid/issues/104
# https://stackoverflow.com/questions/918886/how-do-i-split-a-string-on-a-delimiter-in-bash/15988793#15988793
mapfile -td, -c 1 -C process_file_system < <(printf "%s\0" "$SANOID_TARGETS")
