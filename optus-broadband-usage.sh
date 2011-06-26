#!/bin/sh
# Filename:         optus-broadband-usage.sh
# Version:          0.2
# Description:
#   Automatically logs into your Optus account, downloads current usage data, and
#   notifies you of your current usage (or just when your usage pace is in the
#   danger zone).
#
# Platforms:        OS X, GNU/Linux (not yet tested), Cygwin (not yet tested)
# Depends:          curl, cron (for regular checks), sendmail (if option selected),
#                   growlnotify (OS X & if option selected)
# Source:           https://github.com/huyz/optus-broadband-usage
# Author:           Huy Z, http://huyz.us/
# Created on:       2011-01-29
#
# Installation:
# - If necessary:
#   1. If on OS X and you will be using Growl, install growlnotify.
#      If you have Homebrew, you can run: brew install growlnotify
#   2. Install curl from http://curl.haxx.se/
# - Required:
#   3. Edit this script and configure your Optus username and password
#     (they're the same as your Optusnet email username and password)
# - Recommended:
#   4. Add something like this to your crontab:
#      # Check every 4 hours
#      50 2,6,10,14,18,22 * * * exec $HOME/git/optus-broadband-usage/optus-broadband-usage.sh -g -p highany
#
# Usage:
#   optus-broadband-usage [-p pace] [-g] [-e recipient] [-f output_format]
#   -p   only notify if pace qualifies as:
#            highpeak: on pace to reach peak allowance early
#            highany: on pace to reach peak or off-peak allowance early
#            excesspeak: on pace to reach peak allowance VERY early
#            excessany: on pace to reach peak or off-peak allowance VERY early
#   -g   send usage to growl (Mac OS X only)
#   -e   email usage to specified recipient (Repeat option for multiple)
#   If neither growl or email, display on standard output, in which case:
#   -f   output_format: 'standard' (default), 'brief', or 'oneline'

# Copyright (C) 2011 Huy Z
# 
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


##############################################################################
### Configuration

# Your Optus login name (Optusnet email address, but without @optusnet.com.au),
# as you'd enter it at http://www.optuszoo.com.au/
OPTUS_USERNAME=
# Your Optus password (Optusnet email password)
OPTUS_PASSWORD=

# if '-p excesspeak' or '-p excessany' options is used, this specifies the
# usage pace threshold that triggers notification.
# Format is in percents; e.g., for 130%, enter '130' (default is 120)
#PACE_EXCESS_THRESHOLD=120

# If you need to send mail the script will search for sendmail, but
# you can specify the full path here, especially if invoking this script
# in cron
#SENDMAIL=/usr/sbin/sendmail

# You can specify the email address to send from, format 'email@addre.ss'
#MAIL_FROM=cron-optus@localhost

# If you need to use growl, the script will search for growlnotify, but
# you can specify the full path here, especially if invoking this script
# in cron
#GROWLNOTIFY=/brew/bin/growlnotify

### End of Configuration
##############################################################################
### Internal Configuration

USAGE_PATH=${TMPDIR:-$HOME/tmp}/optus-usage
COOKIES_PATH=${TMPDIR:-$HOME/tmp}/.optus-cookies
HEADER_PATH=${TMPDIR:-$HOME/tmp}/.optus-header
USER_AGENT='Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.6; en-US; rv:1.9.2.11) Gecko/20101012 Firefox/3.6.11'

### Read config

execname="${0##*/}"
execroot="${0%.*}"

if [ -r "$execroot.config" ]; then
  . "$execroot.config"
fi

if [ -z "$OPTUS_USERNAME" ]; then
  echo "$execname: ERROR: \$OPTUS_USERNAME not defined." >&2
  echo "    Edit configuration in $0." >&2
  exit 1
fi
if [ -z "$OPTUS_PASSWORD" ]; then
  echo "$execname: ERROR: \$OPTUS_PASSWORD not defined." >&2
  echo "    Edit configuration in $0." >&2
  exit 1
fi

##############################################################################
### Usage

opt_format=standard
opt_email=
opt_growl=
opt_pace=

while [ $# -gt 0 ]; do
  case "$1" in
    -g)
        opt_growl=1
        ;;
    -e)
        shift
        if [ $# -gt 0 ]; then
          case "$1" in
            -*) ;;
            *)  opt_email="$opt_email $1" ;;
          esac
        fi
        if [ -z "$opt_email" ]; then
          echo "$execname: ERROR: Unspecified or unrecognied email recipient"
          exit 1
        fi
        ;;
    -f)
        shift
        case "$1" in
          standard|brief|oneline) opt_format="$1" ;;
          *)
            echo "$execname: ERROR: output format can be 'standard' (default), 'brief', or 'oneline'" >&2
            exit 1
            ;;
        esac
        ;;
    -p)
        shift
        case "$1" in
          highpeak|highany|excesspeak|excessany) opt_pace="$1" ;;
          *)
            echo "$execname: ERROR: pace can be 'highpeak', 'highany', 'excesspeak', 'excessany'" >&2
            exit 1
            ;;
        esac
        ;;
    *)
        echo "Usage: $execname [-p pace] [-g] [-e recipient] [-f output_format]"
        echo "  -p   only notify if pace qualifies as:"
        echo "           highpeak: on pace to reach peak allowance early"
        echo "           highany: on pace to reach peak or off-peak allowance early"
        echo "           excesspeak: on pace to reach peak allowance VERY early"
        echo "           excessany: on pace to reach peak or off-peak allowance VERY early"
        echo "  -g   send usage to growl (Mac OS X only)"
        echo "  -e   email usage to specified recipient (Repeat option for multiple)"
        echo "  If neither growl or email, display on standard output, in which case:"
        echo "  -f   output_format: 'standard' (default), 'brief', or 'oneline'"
        echo ""
        exit 1
        ;;
  esac
  shift
done


##############################################################################
### Prerequisites, depending on usage

if [ -n "$opt_growl" ]; then
  if [ -n "$GROWLNOTIFY" ]; then
    if [ ! -x "$GROWLNOTIFY" ] && ! hash growlnotify >& /dev/null; then
      echo "$execname: ERROR: Can't execute '$GROWLNOTIFY'." >&2
      echo "    Edit configuration in $0" >&2
      exit 1
    fi 
  else
    if [ -x /brew/bin/growlnotify ]; then
      GROWLNOTIFY=/brew/bin/growlnotify
    elif ! hash growlnotify >& /dev/null; then
      echo "$execname: ERROR: Can't find 'growlnotify'." >&2
      echo "    Install growlnotify (On OS X, you can use Homebrew)," >&2
      echo "    or check configuration in $0" >&2
      exit 1
    else
      GROWLNOTIFY=growlnotify
    fi
  fi
fi

if [ -n "$opt_email" ]; then
  if [ -n "$SENDMAIL" ]; then
    if [ ! -x "$SENDMAIL" ] && ! hash sendmail >& /dev/null; then
      echo "$execname: ERROR: Can't execute '$SENDMAIL'." >&2
      echo "    Edit configuration in $0" >&2
      exit 1
    fi 
  else
    if [ -x /usr/sbin/sendmail ]; then
      SENDMAIL=/usr/sbin/sendmail
    elif ! hash sendmail >& /dev/null; then
      echo "$execname: ERROR: Can't find 'sendmail'." >&2
      echo "    Install sendmail or check configuration in $0" >&2
      exit 1
    else
      SENDMAIL=sendmail
    fi
  fi
fi

if [ -z "$PACE_EXCESS_THRESHOLD" ]; then
  PACE_EXCESS_THRESHOLD=120
fi


##############################################################################
### Download Usage Meter

curl \
    --silent \
    --location \
    --user-agent "$USER_AGENT" \
    --cookie-jar "$COOKIES_PATH.txt" \
    --dump-header "$HEADER_PATH-1.txt" \
    'https://idp.optusnet.com.au/idp/optus/Authn/Service?spEntityID=https%3A%2F%2Fwww.optuszoo.com.au%2Fshibboleth&j_principal_type=ISP' >$USAGE_PATH-1.html 2>&1 && sleep 3 &&

# --location because the previous request returns with a series of redirects "302 Moved Temporarily" or "302 Found"
curl \
    --silent \
    --location \
    --user-agent "$USER_AGENT" \
    --cookie "$COOKIES_PATH.txt" \
    --cookie-jar "$COOKIES_PATH.txt" \
    --dump-header "$HEADER_PATH-2.txt" \
    --referer 'https://idp.optusnet.com.au/idp/optus/Authn/Service?spEntityID=https%3A%2F%2Fwww.optuszoo.com.au%2Fshibboleth&j_principal_type=ISP' \
    --data "spEntityID=https://www.optuszoo.com.au/shibboleth&j_principal_type=ISP&j_username=$OPTUS_USERNAME&j_password=$OPTUS_PASSWORD&j_security_check=true" \
    'https://idp.optusnet.com.au/idp/optus/Authn/Service' >$USAGE_PATH-2.html 2>&1 && sleep 1 &&

curl \
    --silent \
    --location \
    --user-agent "$USER_AGENT" \
    --cookie "$COOKIES_PATH.txt" \
    --cookie-jar "$COOKIES_PATH.txt" \
    --dump-header "$HEADER_PATH-3.txt" \
    --referer 'https://www.optuszoo.com.au/' \
    'https://www.optuszoo.com.au//r/ffmu' >$USAGE_PATH-3.html 2>/dev/null &&

ln -f $USAGE_PATH-3.html $USAGE_PATH.html


# Check download
if ! grep "Billing Period" $USAGE_PATH.html >/dev/null; then
  echo "$execname: ERROR: Something wrong happened during download." >&2
  echo "    Check $USAGE_PATH*.html and $HEADER_PATH*.txt files" >&2
  exit 2
fi

# Cleanup
rm -f $COOKIES_PATH* $HEADER_PATH* $USAGE_PATH-?.html

##############################################################################
### Parse

USAGE_PATH="$USAGE_PATH.html"

billing_period=$(grep -A 2 -i 'Billing Period:' $USAGE_PATH | sed -n 's/.*<strong>\([^<]*\).*/\1/p' )
last_update=$(grep -A 1 -i 'Last Update:' $USAGE_PATH | sed -n 's/.*<td *>\([^<]*\).*/\1/p' )
#sed -n 's/.*<td class="label">\(.*\)<.*/\1/p' $USAGE_PATH > optus-usage.txt
peak_usage=$(grep "headers='planDataU'" $USAGE_PATH | tail -1 | sed -n "s/.*headers='planDataU'>\\(.*\\)<.*/\\1/p")
offpeak_usage=$(sed -n "s/.*headers='yesDataU'>\\(.*\\)<.*/\\1/p" $USAGE_PATH)
peak_allow=$(sed -n "s/.*headers='planDataAlwd'>\\(.*\\)<.*/\\1/p" $USAGE_PATH)
offpeak_allow=$(sed -n "s/.*headers='yesdataAl'>\\(.*\\)<.*/\\1/p" $USAGE_PATH)
peak_perc=$(echo "scale=0; ($peak_usage * 100 / $peak_allow)" | bc)
offpeak_perc=$(echo "scale=0; ($offpeak_usage * 100 / $offpeak_allow)" | bc)
days_elapsed=$(sed -n 's/.*\(Days Elapsed.*%\).*/\1/p' $USAGE_PATH)
days_perc=${days_elapsed#Days Elapsed }
days_perc=${days_perc%\%}
days_usage=$(grep -A 1 "Days Elapsed" $USAGE_PATH | sed -n 's/.*(\(.*\) days).*/\1/p')

### Output formats

out_oneline="${peak_perc}% (P)  ${offpeak_perc}% (OP)  ${days_perc}% (days)"

out_brief="$(echo $last_update | cut -c11-17)
Peak:  $peak_usage MB (${peak_perc}%)
Off:   $offpeak_usage MB (${offpeak_perc}%)
$days_usage days (${days_perc}%)"

out_standard="\
Billing Period:                 $billing_period
Last Update:                    $last_update

Peak-time (12pm - 12am) usage:  $peak_usage MB (${peak_perc}% of allowed $peak_allow MB)
Off-peak  (12am - 12pm) usage:  $offpeak_usage MB (${offpeak_perc}% of allowed $offpeak_allow MB)
Days Elapsed:                   $days_usage days (${days_perc}% of month)"

# FIXME This assumes 31 days to be safe, but of course should adapt to month
peak_norm=$(echo "scale=0; $peak_allow * ($days_usage + 1) / 31" | bc)
peak_excess=$(echo "scale=0; $peak_norm * $PACE_EXCESS_THRESHOLD / 100" | bc)
offpeak_norm=$(echo "scale=0; $offpeak_allow * ($days_usage + 1) / 31" | bc)
offpeak_excess=$(echo "scale=0; $offpeak_norm * $PACE_EXCESS_THRESHOLD / 100" | bc)
if [ $peak_usage -gt $peak_excess ]; then
  pace_peak=excess
  out_standard="$out_standard

WARNING: Your peak-time usage is much greater than it should be!
Peak-time usage by end of the day should have been: $peak_norm MB
($peak_excess MB is already $PACE_EXCESS_THRESHOLD% of normal pace)
"
elif [ $peak_usage -gt $peak_norm ]; then
  pace_peak=high
  out_standard="$out_standard

WARNING: Your peak-time usage is greater than it should be!
Peak-time usage by end of the day should have been: $peak_norm MB
"
fi
if [ $offpeak_usage -gt $offpeak_excess ]; then
  pace_offpeak=excess
  out_standard="$out_standard

WARNING: Your off-peak usage is much greater than it should be!
Off-peak usage by end of the day should have been: $offpeak_norm MB
($offpeak_excess MB is already $PACE_EXCESS_THRESHOLD% of normal pace)
"
elif [ $offpeak_usage -gt $offpeak_norm ]; then
  pace_offpeak=high
  out_standard="$out_standard

WARNING: Your off-peak usage is greater than it should be!
Off-peak usage by end of the day should have been: $offpeak_norm MB
"
fi

##############################################################################
### Output methods

# Pace thresholds
pace_qualify=
if [ -n "$opt_pace" ]; then
  case "$opt_pace" in
    highpeak) [ -n "$pace_peak" ] && pace_qualify=1 ;;
    highany)  [ -n "$pace_peak" -o -n "$pace_offpeak" ] && pace_qualify=1 ;;
    excesspeak) [ "$pace_peak" = excess ] && pace_qualify=1 ;;
    excessany)  [ "$pace_peak" = excess -o "$pace_offpeak" = excess ] && pace_qualify=1 ;;
  esac
  [ -z "$pace_qualify" ] && exit 0
fi

# Growl
if [ -n "$opt_growl" ]; then
  echo "$out_brief" | $GROWLNOTIFY -a "Network Utility"
fi

# Email
if [ -n "$opt_email" ]; then
  if [ -n "$MAIL_FROM" ]; then
    MAIL_FROM="-f $MAIL_FROM"
  fi
  $SENDMAIL $MAIL_FROM -F "$execname" $opt_email <<END
To: $opt_email
Subject: Optus Usage =  $out_oneline

$out_standard
END
fi

# Standard output (default)
if [ -z "$opt_growl" -a -z "$opt_email" ]; then
  eval "echo \"\$out_$opt_format\""
fi
