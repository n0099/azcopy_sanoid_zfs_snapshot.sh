SANOID_SCRIPT=post \
SANOID_PRE_FAILURE=0 \
SANOID_SNAPNAMES=autosnap_2024-01-26_09:03:36_weekly,autosnap_2024-01-26_09:03:36_daily \
SANOID_TARGETS=rpool/ROOT \
file_systems.sh

[template_azcopy]
hourly=24

daily=7
#daily=0
# https://github.com/jimsalterjrs/sanoid/issues/720
# https://github.com/jimsalterjrs/sanoid/issues/617
# https://github.com/jimsalterjrs/sanoid/issues/560
# T04:00+08:00
daily_hour=12
daily_min=0

weekly=8
#weekly=0
# Tue in UTC+8
weekly_wday=1
# T03:00+08:00
weekly_hour=11
weekly_min=0

monthly=0

# https://github.com/jimsalterjrs/sanoid/blob/a5fa5e7badecc435663e40e6a0f69523c2a0fd1c/sanoid#L1658
script_timeout=0
post_snapshot_script=/bak/sanoid/file_systems.sh

autosnap=yes
autoprune=yes
