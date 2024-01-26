SANOID_SCRIPT=post \
SANOID_PRE_FAILURE=0 \
SANOID_SNAPNAMES=autosnap_2024-01-26_09:03:36_weekly,autosnap_2024-01-26_09:03:36_daily \
SANOID_TARGETS=rpool/ROOT \
file_systems.sh

# https://github.com/jimsalterjrs/sanoid#sanoid-script-hooks
# https://github.com/jimsalterjrs/sanoid/wiki/Sanoid#options
[template_azcopy]
daily=7
daily_hour = 3
daily_min = 0

weekly=8
weekly_wday = 1
weekly_hour = 3
weekly_min = 0

monthly=0

# https://github.com/jimsalterjrs/sanoid/blob/a5fa5e7badecc435663e40e6a0f69523c2a0fd1c/sanoid#L1658
script_timeout=0
post_snapshot_script=/bak/sanoid/file_systems.sh

autosnap=yes
autoprune=yes