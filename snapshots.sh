#!/bin/bash
set -x
set -e # https://mywiki.wooledge.org/BashFAQ/105

week=$(date +%G-W%V) # https://en.wikipedia.org/wiki/ISO_week_date
send() {
    send_params=$1
    file_system=$2
    snapshot=$3
    export AZCOPY_BUFFER_GB=0.5 # https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-optimize#optimize-memory-use
    # intentionally word-splitting https://unix.stackexchange.com/questions/378584/spread-bash-argument-by-whitespace/378591#378591
    # shellcheck disable=SC2086
    send_size_uncompressed=$(zfs send -LcPn $send_params | awk '/^size/{print $2}')
    [[ $send_size_uncompressed -eq 624 ]] && return 0 # 624 bytes usually means "no changes" between snapshots
    # shellcheck disable=SC2086
    send_size=$(zfs send -LcPn $send_params | awk '/^size/{print $2}')
    # shellcheck disable=SC2086
    zfs send -LcP $send_params \
        | pv -pterabfs "$send_size" \
        | azcopy cp --from-to PipeBlob --block-size-mb 32 \
            "$CONTAINER/$week/${file_system#rpool/}/${snapshot#autosnap_}$SAS"
}
FILE_SYSTEM=$1
process() {
    snapshot=$2
    case $snapshot in
        autosnap_*_daily)
            directory=$week/${FILE_SYSTEM#rpool/}/
            latest_snapshot=$(azcopy list "$CONTAINER$SAS" --output-type json \
                | jq -r 'select(.MessageType == "Info").MessageContent | split(";") | .[0]
                    | ltrimstr("INFO: ") | select(startswith("'"$directory"'"))' \
                | sort -n \
                | tail -n 1)
            [[ $latest_snapshot ]] || return 0
            latest_snapshot=autosnap_${latest_snapshot#"$directory"}
            send "-i $FILE_SYSTEM@$latest_snapshot $FILE_SYSTEM@$snapshot" "$FILE_SYSTEM" "$snapshot"
            ;;
        autosnap_*_weekly)
            send "$FILE_SYSTEM@$snapshot" "$FILE_SYSTEM" "$snapshot"
    esac
}
# https://stackoverflow.com/questions/918886/how-do-i-split-a-string-on-a-delimiter-in-bash/15988793#15988793
mapfile -td , -c 1 -C process < <(printf "%s\0" "$SANOID_SNAPNAMES")
# order of frequency types in $SANOID_SNAPNAMES seems to be ensured by sanoid
# https://github.com/jimsalterjrs/sanoid/blob/a5fa5e7badecc435663e40e6a0f69523c2a0fd1c/sanoid#L146
# https://github.com/jimsalterjrs/sanoid/blob/a5fa5e7badecc435663e40e6a0f69523c2a0fd1c/sanoid#L585