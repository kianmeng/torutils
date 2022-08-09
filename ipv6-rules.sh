#!/bin/bash
# set -x


function addTor() {
  # ipset for Tor authorities https://metrics.torproject.org/rs.html#search/flag:authority%20
  local authlist=tor-authorities6

  ipset create -exist $authlist hash:ip family inet6
  for i in 2001:638:a000:4140::ffff:189 2001:678:558:1000::244 2001:67c:289c::9 2001:858:2:2:aabb:0:563b:1526 2607:8500:154::3 2610:1c0:0:5::131 2620:13:4000:6000::1000:118
  do
    ipset add -exist $authlist $i
  done

  # ipset for blocked ip addresses
  if [[ -s /var/tmp/ipset.$blocklist ]]; then
    ipset restore -exist -f /var/tmp/ipset.$blocklist
  else
    ipset create -exist $blocklist hash:ip family inet6 timeout 1800
  fi

  # iptables
  ip6tables -P INPUT   DROP
  ip6tables -P OUTPUT  ACCEPT
  ip6tables -P FORWARD DROP
  
  # make sure NEW incoming tcp connections are SYN packets
  ip6tables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP -m comment --comment "$(date)"
  
  # allow local traffic
  ip6tables -A INPUT --in-interface lo                                -j ACCEPT
  ip6tables -A INPUT -p udp --source fe80::/10 --destination ff02::1  -j ACCEPT
 
  # the ruleset for inbound to an ORPort
  for orport in ${orports[*]}
  do
    # trust Tor authorities
    ip6tables -A INPUT -p tcp --destination $oraddr --destination-port $orport -m set --match-set $authlist src -j ACCEPT
    # block for >2 conenctions
    ip6tables -A INPUT -p tcp --destination $oraddr --destination-port $orport -m connlimit --connlimit-mask 128 --connlimit-above 2 -j SET --add-set $blocklist src --exist
    # drop traffic from blocklist
    ip6tables -A INPUT -p tcp --destination $oraddr --destination-port $orport -m set --match-set $blocklist src -j DROP
    # allow to connect to ORport
    ip6tables -A INPUT -p tcp --destination $oraddr --destination-port $orport -j ACCEPT
  done

  # trust already established connections - this is almost Tor traffic outbound to an ORPort
  ip6tables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  ip6tables -A INPUT -m conntrack --ctstate INVALID             -j DROP

  # ssh
  local port=$(grep -m 1 -E "^Port\s+[[:digit:]]+" /etc/ssh/sshd_config | awk '{ print $2 }')
  ip6tables -A INPUT -p tcp --destination-port ${port:-22} -j ACCEPT
 
  ## ratelimit ICMP echo, allow others
  ip6tables -A INPUT -p ipv6-icmp --icmpv6-type echo-request -m limit --limit 6/s -j ACCEPT
  ip6tables -A INPUT -p ipv6-icmp --icmpv6-type echo-request -j DROP
  ip6tables -A INPUT -p ipv6-icmp                            -j ACCEPT
}


# only needed for Hetzner customers
# https://wiki.hetzner.de/index.php/System_Monitor_(SysMon)
function addHetzner() {
  local monlist=hetzner-monlist6

  ipset create -exist $monlist hash:ip family inet6
  getent ahostsv6 pool.sysmon.hetzner.com | awk '{ print $1 }' | sort -u |\
  while read i
  do
    ipset add -exist $monlist $i
  done
  ip6tables -A INPUT -m set --match-set $monlist src -j ACCEPT
}


function clearAll() {
  ip6tables -F
  ip6tables -X
  ip6tables -Z

  ip6tables -P INPUT   ACCEPT
  ip6tables -P OUTPUT  ACCEPT
  ip6tables -P FORWARD ACCEPT

  ipset save $blocklist -f /var/tmp/ipset.$blocklist.tmp &&\
  mv /var/tmp/ipset.$blocklist.tmp /var/tmp/ipset.$blocklist &&\
  ipset destroy $blocklist
}


#######################################################################
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

# Tor
oraddr="2a01:4f9:3b:468e::13"
orports=(443 9001)

blocklist=tor-ddos6

case $1 in
  start)  addTor
          addHetzner
          ;;
  stop)   clearAll
          ;;
esac

