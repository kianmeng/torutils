#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# count inbound to local ORPort per remote ip address

function show() {
  local relay=$1

  local v=""
  if [[ $relay =~ '[' ]]; then
    v="6"
  fi
  local sum=0
  local ips=0

  while read -r conns ip
  do
    if [[ $conns -gt $limit ]]; then
      printf "%-10s %-40s %5i\n" ip$v $ip $conns
      (( ++ips ))
      (( sum += conns ))
    fi
  done < <(
    ss --no-header --tcp -${v:-4} --numeric |
    grep "^ESTAB" |
    grep -F " $relay " |
    awk '{ print $5 }' | sort | sed 's,:[[:digit:]]*$,,g' | uniq -c
  )

  if [[ $ips -gt 0 ]]; then
    printf "relay:%-42s           ips:%-5i conns:%-5i\n\n" $relay $ips $sum
  fi
}


function getConfiguredRelays4()  {
  local orport
  local address

  for f in /etc/tor/torrc*
  do
    if orport=$(sed 's,\s*#.*,,' $f | grep -m 1 -P "^ORPort\s+.+\s*$"); then
      if ! grep -Po "^ORPort\s+\d+\.\d+\.\d+\.\d+\:\d+\s*$" <<< $orport; then
        if address=$(sed 's,\s*#.*,,' $f | grep -m 1 -P "^Address\s+\d+\.\d+\.\d+\.\d+\s*$"); then
          echo $(awk '{ print $2 }' <<< $address):$(awk '{ print $2 }' <<< $orport)
        fi
      fi
    fi
  done
}


function getConfiguredRelays6()  {
  sed 's,#.*,,' /etc/tor/torrc* | grep -P "^ORPort\s+[0-9a-f:\[\]]+:\d+\s*$" | awk '{ print $2 }'
}


#######################################################################
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

limit=2
relays=$(getConfiguredRelays4; getConfiguredRelays6)

while getopts l:r: opt
do
  case $opt in
    l)  limit=$OPTARG ;;
    r)  relays="$OPTARG" ;;
    *)  echo "unknown parameter '$opt'"; exit 1 ;;
  esac
done

for relay in $relays
do
  show $relay
done
