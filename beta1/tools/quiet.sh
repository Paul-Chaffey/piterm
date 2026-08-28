#!/bin/bash
# A socket that accepts and then says NOTHING, for timing empty polls.
#
# Measuring what a poll costs when there is no data needs a connection
# with no data on it. Draining a live feeder to get there does not work:
# on the host a data-returning read costs ~41ms, so draining one that is
# still sending sits for minutes and looks exactly like a lockup. That is
# what hung FBCOSTH.
sleep 600
