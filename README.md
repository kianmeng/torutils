[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# Torutils

Few tools for a Tor relay.

## Block DDoS Traffic

The scripts [ipv4-rules.sh](./ipv4-rules.sh) and [ipv6-rules.sh](./ipv6-rules.sh) were made
to protect a Tor relay against a DDoS attack at TCP/IP level.
They do block ip addresses making too much connection (attempts) to the local ORPort.
[This](./doc/network-metric.svg) metric shows the effect (protection was active the whole day).
The data were gathered by [sysstat](http://pagesperso-orange.fr/sebastien.godard/).
Details are in issue [40636](https://gitlab.torproject.org/tpo/core/tor/-/issues/40636)
and [40093](https://gitlab.torproject.org/tpo/community/support/-/issues/40093#note_2841393).

### Quick start
Run the command below to configure the _filter_  table of [iptables](https://upload.wikimedia.org/wikipedia/commons/3/37/Netfilter-packet-flow.svg) using [this](#rule-set) rule set:

```bash
wget -q https://raw.githubusercontent.com/toralf/torutils/main/ipv4-rules.sh -O ipv4-rules.sh
chmod +x ./ipv4-rules.sh
sudo ./ipv4-rules.sh start
```

Best is to (re-)start Tor afterwards.
The live statistics are given by:

```bash
sudo watch -t ./ipv4-rules.sh
```

The output should look similar to these [IPv4](./doc/iptables-L.txt) and [IPv6](./doc/ip6tables-L.txt) examples.
To stop protection, just run:

```bash
sudo ./ipv4-rules.sh stop
```

### Rule set
Beside common network filter rules here are the 5 Tor specific rules for an inbound ip address connecting to the local ORPort:

1. trust Tor authorities and snowflake
2. block the ip for 30 min if > 5 inbound connection attempts per minute are made
3. block the ip for 30 min if > 3 inbound connections are established
4. ignore any further connection attempt if the ip is hosting 1 relay and has already 1 inbound connection established
5. ignore any further connection attempt if 2 inbound connections are already established

### Installation and configuration hints
The instructions do belong to the IPv4 variant. They are similar for IPv6 script.
The package [iptables](https://www.netfilter.org/projects/iptables/) is needed,
[jq](https://stedolan.github.io/jq/) is needed for rule 4 to get the information which relays do run at the same ip.
If the parsing of Tors config file _torrc_ doesn't work (line [150](ipv4-rules.sh#L150)), then:
1. define the relay(s) (space separated) in the environment variable, eg.:
    ```bash
    export CONFIGURED_RELAYS="3.14.159.26:535"
    export CONFIGURED_RELAYS6="[cafe::dead:beef]:4711"
    ```
1. -and/or- create a pull requests to fix the parsing ;)
before you start the protection.

Same happens for additional local network services:
1. define them (space separated) in the environment variable, eg.:
    ```bash
    export ADD_LOCAL_SERVICES="2.718.281.828:459"
    export ADD_LOCAL_SERVICES6="[eff:eff::affe:edda:fade]:1984"
    ```
1. -or- hard code the relay/s in line [93](ipv4-rules.sh#L93)
1. -or- edit the default policy in line [6](ipv4-rules.sh#L6) (not recommended):
    ```bash
    iptables -P INPUT ACCEPT
    ```

If Hetzners [system monitor](https://docs.hetzner.com/robot/dedicated-server/security/system-monitor/) isn't needed, then
1. remove the _addHetzner()_ code (line [107ff](ipv4-rules.sh#L107)) and its call in line [177](ipv4-rules.sh#L177)
1. -or- just ignore it

### Sysctl settings

I have set the _uname_ limit for the Tor process to _60000_.
Furthermore I configured few sysctl values in _/etc/sysctl.d/local.conf_:

```console
net.ipv4.ip_local_port_range = 2000 63999
kernel.kptr_restrict = 1
kernel.perf_event_paranoid = 3
kernel.kexec_load_disabled = 1
kernel.yama.ptrace_scope = 1
user.max_user_namespaces = 0
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
```

## Query Tor via its API

[info.py](./info.py) gives a summary of all  connections, eg.:

```bash
sudo ./info.py --address 127.0.0.1 --ctrlport 9051
```

gives here:

```console
 0.4.8.0-alpha-dev   uptime: 2-08:25:40   flags: Fast, Guard, Running, Stable, V2Dir, Valid

+------------------------------+-------+-------+
| Type                         |  IPv4 |  IPv6 |
+------------------------------+-------+-------+
| Inbound to our OR from relay |  2269 |   809 |
| Inbound to our OR from other |  2925 |    87 |
| Inbound to our ControlPort   |     2 |       |
| Outbound to relay OR         |  2823 |   784 |
| Outbound to relay non-OR     |     4 |     4 |
| Outbound exit traffic        |       |       |
| Outbound unknown             |    40 |    29 |
+------------------------------+-------+-------+
| Total                        |  8063 |  1713 |
+------------------------------+-------+-------+
```

For a monitoring of _exit_ connections use [ps.py](./ps.py):

```bash
sudo ./ps.py --address 127.0.0.1 --ctrlport 9051
```

### Prerequisites
An open Tor control port is needed to query the Tor process via API.
Configure it in _torrc_, eg.:

```console
ControlPort 127.0.0.1:9051
ControlPort [::1]:9051
```

The [Stem](https://stem.torproject.org/index.html) python library is mandatory.
The latest version can be derived by eg.:

```bash
cd <your favourite path>
git clone https://github.com/torproject/stem.git
export PYTHONPATH=$PWD/stem
```

The package [gnuplot](http://www.gnuplot.info/) is needed to plot graphs.

## Misc

[ddos-inbound.sh](./ddos-inbound.sh) lists ips having more inbound connections to a local ORPort than the given upper limit (default: 2).
It should usually list _snowflake-01_ only:

```console
ip                       193.187.88.42           12
relay:65.21.94.13:443            ips:1     conns:12
```

The script [ipset-stats.sh](./ipset-stats.sh) (needs package [gnuplot](http://www.gnuplot.info/))
dumps the content of an [ipset](https://ipset.netfilter.org) and plots those data.
[This](./doc/crontab.txt) crontab example (of user _root_) shows how to gather data,
from which histograms like the one below can be plotted by:

```bash
sudo ./ipset-stats.sh -p /tmp/ipset4.*.txt
```

which gives currently
```console
                       100475 hits of 7079 ips
       +o----------------------------------------------------+
       |    +     +    +     +    +    +     +    +     +    |
  1024 |-+                   o                             +-|
       |                    o o                              |
       |   o              o                                  |
   256 |-oo o                  o                           +-|
       |                 o                                   |
       |                                     oo            o |
    64 |-+   o          o       o              o           +-|
       |                                                     |
       |       o                        o         o o        |
       |          o    o                    o      o o    o  |
    16 |-+      oo oo o          o    oo         o       o +-|
       |             o            oo o    o            o     |
       |                            o           o            |
     4 |-+                                              o  +-|
       |    +     +    +     +    +    +   o +    +     +    |
       +-----------------------------------------------------+
       0    5     10   15    20   25   30    35   40    45   50
                                 hit
```

The next example shows, how to check if Tor relays were blocked:

```bash
curl -s 'https://onionoo.torproject.org/summary?search=type:relay' -o - | jq -cr '.relays[].a' | tr '\[\]" ,' ' ' | xargs -n 1 | sort -u > /tmp/relays
grep -h -w -f /tmp/relays /tmp/ipset4.*.txt | sort | uniq -c | sort -bn
```

[orstatus.py](./orstatus.py) logs the reason of Tor circuit closing events.
[orstatus-stats.sh](./orstatus-stats.sh) prints and/or plots statistics from the output, eg.:

```bash
sudo ./orstatus-stats.sh /tmp/orstatus.9051 TLS_ERROR
```

If you do use [Tor offline keys](https://support.torproject.org/relay-operators/offline-ed25519/)
then [key-expires.py](./key-expires.py) helps you to not miss the key rotation timeline.
It returns the seconds before the mid-term signing key expires, eg:

```bash
n=$(( $(/opt/torutils/key-expires.py /var/lib/tor/data/keys/ed25519_signing_cert)/86400 ))
[[ $n -lt 23 ]] && echo "Tor signing key expires in less than $n day(s)"
```
