#!/bin/bash
# set -x


function addCommon() {
  iptables -P INPUT  DROP
  iptables -P OUTPUT ACCEPT

  # allow loopback
  iptables -A INPUT --in-interface lo -m comment --comment "$(date -R)" -j ACCEPT

  # make sure NEW incoming tcp connections are SYN packets
  iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
  iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

  # ssh
  local port=$(grep -m 1 -E "^Port\s+[[:digit:]]+$" /etc/ssh/sshd_config | awk '{ print $2 }')
  local addr=$(grep -m 1 -E "^ListenAddress\s+.+$"  /etc/ssh/sshd_config | awk '{ print $2 }' | grep -F '.')
  iptables -A INPUT -p tcp --dst ${addr:-"0.0.0.0/0"} --dport ${port:-22} -j ACCEPT

  ## ratelimit ICMP echo
  iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 6/s -j ACCEPT
  iptables -A INPUT -p icmp --icmp-type echo-request                      -j DROP
}


function __fill_trustlist() {
  # dig +short snowflake-01.torproject.net. A
  # curl -s 'https://onionoo.torproject.org/summary?search=flag:authority' -o - | jq -cr '.relays[].a[0]'
  echo 193.187.88.42 45.66.33.45 66.111.2.131 86.59.21.38 128.31.0.34 131.188.40.189 154.35.175.225 171.25.193.9 193.23.244.244 199.58.81.140 204.13.164.118 |
  xargs -r -n 1 -P 20 ipset add -exist $trustlist
}


function __fill_multilist() {
  curl -s 'https://onionoo.torproject.org/summary?search=type:relay' -o - |
  jq -cr '.relays[].a' | tr '][",' ' ' | sort | uniq -c | grep -v ' 1 ' |
  xargs -n 1 | grep -F '.' |
  xargs -r -n 1 -P 20 ipset add -exist $multilist
}


function addTor() {
  local blocklist=tor-ddos
  local multilist=tor-multi   # rule 4
  local trustlist=tor-trust

  ipset create -exist $blocklist hash:ip timeout 1800
  ipset create -exist $multilist hash:ip                # rule 4
  ipset create -exist $trustlist hash:ip

  __fill_trustlist
  __fill_multilist &  # rule 4

  for relay in $*
  do
    read -r orip orport <<< $(tr ':' ' ' <<< $relay)

    # rule 1
    if ! iptables -A INPUT -p tcp --dst $orip --dport $orport -m set --match-set $trustlist src -j ACCEPT; then
      echo " addTor(): error for $relay"
      continue
    fi

    # rule 2
    iptables -A INPUT -p tcp --dst $orip --dport $orport --syn -m hashlimit --hashlimit-name $blocklist --hashlimit-mode srcip --hashlimit-srcmask 32 --hashlimit-above 5/minute --hashlimit-htable-expire 60000 -j SET --add-set $blocklist src --exist
    iptables -A INPUT -p tcp -m set --match-set $blocklist src -j DROP

    # rule 3
    iptables -A INPUT -p tcp --dst $orip --dport $orport -m connlimit --connlimit-mask 32 --connlimit-above 3 -j SET --add-set $blocklist src --exist
    iptables -A INPUT -p tcp -m set --match-set $blocklist src -j DROP

    # rule 4
    iptables -A INPUT -p tcp --dst $orip --dport $orport --syn -m connlimit --connlimit-mask 32 --connlimit-above 1 -m set ! --match-set $multilist src -j DROP

    # rule 5
    iptables -A INPUT -p tcp --dst $orip --dport $orport --syn -m connlimit --connlimit-mask 32 --connlimit-above 2 -j DROP

    # accept remaining connections
    iptables -A INPUT -p tcp --dst $orip --dport $orport -j ACCEPT
  done

  # initiated locally
  iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
}


function addLocalServices() {
  local addr
  local port

  for service in ${ADD_LOCAL_SERVICES:-}
  do
    read -r addr port <<< $(tr ':' ' ' <<< $service)
    if ! iptables -A INPUT -p tcp --dst $addr --dport $port -j ACCEPT; then
      echo " addLocalServices(): error for $service"
    fi
  done
}


function addHetzner() {
  local monlist=hetzner-monlist

  ipset create -exist $monlist hash:ip
  # getent ahostsv4 pool.sysmon.hetzner.com | awk '{ print $1 }' | sort -u | xargs
  for i in 188.40.24.211 213.133.113.82 213.133.113.83 213.133.113.84 213.133.113.86
  do
    ipset add -exist $monlist $i
  done
  iptables -A INPUT -m set --match-set $monlist src -j ACCEPT
}


function clearAll() {
  local table

  iptables -P INPUT  ACCEPT
  iptables -P OUTPUT ACCEPT

  for table in filter
  do
    iptables -F -t $table 2>/dev/null
    iptables -X -t $table 2>/dev/null
    iptables -Z -t $table 2>/dev/null
  done
}


function printFirewall()  {
  local table

  date -R
  echo
  for table in raw mangle nat filter
  do
    echo "table: $table"
    if iptables -nv -L -t $table 2>/dev/null; then
      echo
    fi
  done
}


function getConfiguredRelays4()  {
  local orport
  local address

  for f in /etc/tor/torrc*
  do
    if orport=$(sed 's,\s*#.*,,' $f | grep -m 1 -P "^ORPort\s+.+\s*$"); then
      if grep -q -Po "^ORPort\s+\d+\.\d+\.\d+\.\d+\:\d+\s*$" <<< $orport; then
        awk '{ print $2 }' <<< $orport
      else
        if address=$(sed 's,\s*#.*,,' $f | grep -m 1 -P "^Address\s+\d+\.\d+\.\d+\.\d+\s*$"); then
          echo $(awk '{ print $2 }' <<< $address):$(awk '{ print $2 }' <<< $orport)
        fi
      fi
    fi
  done
}


#######################################################################
set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

case ${1:-} in
  start)  clearAll
          addCommon
          addHetzner
          addLocalServices
          addTor ${CONFIGURED_RELAYS:-$(getConfiguredRelays4)}
          ;;
  stop)   clearAll
          ;;
  *)      printFirewall
          ;;
esac

