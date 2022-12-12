[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Torutils

Few tools for a Tor relay.

## Block DDoS Traffic

The scripts [ipv4-rules.sh](./ipv4-rules.sh) and [ipv6-rules.sh](./ipv6-rules.sh) protect a Tor relay
against DDoS attacks¹ at the IP [network layer](https://upload.wikimedia.org/wikipedia/commons/3/37/Netfilter-packet-flow.svg).

The goal is more than traffic shaping:
The (presumably) intention of the attacker to unveil onion service/s is targeted.
Therefore, in addition to network filtering, the usually rectangular input signal of the DDoS²
is achieved to be transformed into a more smeared output response³.
This makes it harder for an attacker to gather information using time correlation techniques,
at least it makes the DDoS more expensive.

Therefore [ipsets](https://ipset.netfilter.org) are used.
Its _timeout_ feature adds the needed "memory" to continue blocking an as malicous considered ip
for a much longer time than an single iptables rule usually could do.
Metrics of rx/tx packets, traffic and socket counts from [5th](./doc/network-metric-Nov-5th.svg),
[6th](./doc/network-metric-Nov-6th.svg) and [7th](./doc/network-metric-Nov-7th.svg) of Nov
show the results for few DDoS attacks over 3 days.
A there was a more heavier attack from [12th](./doc/network-metric-Nov-12th.svg) of Nov.
Currently periodic drop down of the socket count, vanishing over time as seen at
[5th](./doc/network-metric-Dec-05th.svg) of Dec, happened with the current rule set.

¹Discussion was started in [40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636) and
continued in [40093](https://gitlab.torproject.org/tpo/community/support/-/issues/40093#note_2841393)
of the [Tor project](https://www.torproject.org/).

²Thousands of new TLS connections are opened within second/s and stayed for a longer time, then closed altogether.

³Much longer time is needed before the maximum is reached -and/or- only 1 connection per ip is created.

### Quick start

Install dependencies, eg. for Ubuntu 22.04, this is required:

```bash
sudo apt install iptables ipset jq
```

Run:

```bash
wget -q https://raw.githubusercontent.com/toralf/torutils/main/ipv4-rules.sh -O ipv4-rules.sh
chmod +x ./ipv4-rules.sh
sudo ./ipv4-rules.sh start
```

This **replaces** any current content of the iptables _filter_ table with the rule set described below.
Best is to (re-)start Tor afterwards.
Make a backup of the current tables before if needed.
If the script doesn't work for you out of the box then please proceed with the [Installation](#installation) section.

The live statistics can be watched by:

```bash
sudo watch -t ./ipv4-rules.sh
```

The output should look similar to the [IPv4](./doc/iptables-L.txt) and the [IPv6](./doc/ip6tables-L.txt) example respectively.

To clear the _filter_ table, run:

```bash
sudo ./ipv4-rules.sh stop
```

### Rule set

Objectives:

Neither touch established nor outbounds connections.
Filter single ips, not networks.

Details:

Generic rules for local network, ICMP, ssh and user services (if defined) are applied.
Then these 5 rules are applied (in this order) for an TCP connection attempt to the local ORPort:

1. trust Tor authorities and snowflake
1. block it for 1 day if the rate is > 6/min
1. limit rate to 0.5/minute
1. allow not more than 2 connections
1. accept it

This usually allows an ip to connect to the ORPort with its 1st SYN packet.
If the rate exceeds a given limit (rule 2) then any further connection attempt is blocked for a given time.
Otherwise subsquently (rule 3) more connections are allowed up to a maximum number (rule 4).

### Installation

The instructions belongs to the IPv4 variant.
They can be applied in a similar way for the IPv6 script

If the parsing of the Tor config (line [151](ipv4-rules.sh#L151)) doesn't work for you then:

1. define the relay(s) space separated before starting the script, eg.:

    ```bash
    export CONFIGURED_RELAYS="3.14.159.26:535 1.41.42.13:562"
    export CONFIGURED_RELAYS6="[cafe::dead:beef]:4711"
    ```

1. -or- open an [issue](https://github.com/toralf/torutils/issues) for that

1. -or- create a GitHub PR with a fix ;)

To allow access to additional local network services (the default input policy is `DROP`), either:

1. define all of them space separated, eg.:

    ```bash
    export ADD_LOCAL_SERVICES="2.718.281.828:459"
    export ADD_LOCAL_SERVICES6="[edda:fade:baff:192::/112]:80"
    ```

1. -or- change the default filter policy for incoming packets:

    ```bash
    export DEFAULT_POLICY_INPUT="ACCEPT"
    ```

    (I wouldn't recommended the later.)

If Hetzners [system monitor](https://docs.hetzner.com/robot/dedicated-server/security/system-monitor/) isn't used,
then either ignore that single rule or comment out its function call (line [185](ipv4-rules.sh#L185)).

### misc

Few scripts were made to fine tune the parameters or the rules:

[ddos-inbound.sh](./ddos-inbound.sh) lists ips having more inbound connections to the ORPort than a given limit.
[orstatus.py](./orstatus.py) logs the reason of Tor circuit closing events,
[orstatus-stats.sh](./orstatus-stats.sh) prints/plots statistics ([example](./doc/orstatus-stats.sh.txt)) from that output.
[hash-stats.sh](./hash-stats.sh) plots the distribution of timeout values of an iptables hash ([example](./doc/hash-stats.sh.txt)).
[ipset-stats.sh](./ipset-stats.sh) plots distribution of ip occurrencies in subsequent ipset output files ([example](./doc/ipset-stats.sh.txt)).

The package [gnuplot](http://www.gnuplot.info/) is needed to plot the graphs.
The crontab entry below is used to create [sysstat](http://sebastien.godard.pagesperso-orange.fr/) metrics:

```console
# crontab for user root

@reboot     /usr/lib/sa/sa1 --boot
* * * * *   /usr/lib/sa/sa1 1 1 -S XALL
```

The metric graphs are created by:

```bash
args="-n DEV,SOCK,SOCK6 --iface=enp8s0"   # "-A" to display all metrics
svg=/tmp/graph.svg
TZ=UTC sadf -g -T /var/log/sa/sa${DAY:-`date +%d`} -O skipempty,oneday -- $args > $svg
h=$(tail -n 2 $svg | head -n 1 | cut -f5 -d' ')   # fix othe SVG canvas size
sed -i -e "s,height=\"[0-9]*\",height=\"$h\"," $svg
firefox $svg
```

## Query Tor via its API

[info.py](./info.py) gives a summary of all connections, eg.:

```bash
sudo ./info.py --address 127.0.0.1 --ctrlport 9051
```

gave here:

```console
 ORport 9051
 0.4.8.0-alpha-dev   uptime: 01:50:23   flags: Fast, Guard, Running, Stable, V2Dir, Valid

+------------------------------+-------+-------+
| Type                         |  IPv4 |  IPv6 |
+------------------------------+-------+-------+
| Inbound to our OR from relay |  2654 |   884 |
| Inbound to our OR from other |  5583 |    77 |
| Inbound to our ControlPort   |     1 |     2 |
| Outbound to relay OR         |  2209 |   576 |
| Outbound to relay non-OR     |       |       |
| Outbound exit traffic        |       |       |
| Outbound unknown             |     6 |       |
+------------------------------+-------+-------+
| Total                        | 10453 |  1539 |
+------------------------------+-------+-------+
```

For a monitoring of _exit_ connections use [ps.py](./ps.py):

```bash
sudo ./ps.py --address 127.0.0.1 --ctrlport 9051
```

An open Tor control port is needed to query the Tor process via API.
Configure it in _torrc_, eg.:

```console
ControlPort 127.0.0.1:9051
ControlPort [::1]:9051
```

The [Stem](https://stem.torproject.org/index.html) python library is mandatory.
The latest version can be derived at:

```bash
git clone https://github.com/torproject/stem.git
export PYTHONPATH=$PWD/stem
```

## Tor offline keys

If you do use [Tor offline keys](https://support.torproject.org/relay-operators/offline-ed25519/)
then [key-expires.py](./key-expires.py) helps you to not miss the key rotation timeline.
It returns the time in seconds before the Tor mid-term signing key expires, eg:

```bash
seconds=$(sudo ./key-expires.py /var/lib/tor/data/keys/ed25519_signing_cert)
days=$(( seconds/86400 ))
[[ $days -lt 23 ]] && echo "Tor signing key expires in less than $days day(s)"
```
