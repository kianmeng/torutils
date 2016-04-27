#!/usr/bin/env python
# -*- coding: utf-8 -*-

# exit port stats of a running Tor relay, eg.:
#
#   port  curr  prev opened closed   8.5 sec
#     81     4     4      0      0   (HTTP Alternate)
#     88     1     1      0      0   (Kerberos)
#    443   491   490     13     12   (HTTPS)
#    993     6     6      0      0   (IMAPS)
#   1500     2     2      0      0   (NetGuard)
#   3128     1     1      0      0   (SQUID)
#   3389     1     1      0      0   (WBT)
#   5222    21    21      0      0   (Jabber)
#   5228    10    10      0      0   (Android Market)
#   6667     4     4      0      0   (IRC)
#   8082     4     4      0      0   (None)
#   8333     4     4      0      0   (Bitcoin)
#   8888     1     1      0      0   (NewsEDGE)
#   9999     5     5      0      0   (distinct)
#  50002    15    15      0      0   (Electrum Bitcoin SSL)

import os
import time
from stem.control import Controller
from stem.util.connection import get_connections, port_usage

def main():
  with Controller.from_port(port = 9051) as controller:

    def printOut (curr, prev, duration):
      os.system('clear')
      print ("   port   curr prev opened closed   %.1f sec" % duration)

      ports = set(list(curr.keys()) + list(prev.keys()))

      for port in sorted(ports):
        if port in prev:
          p = set(prev[port])
        else:
          p = set({})
        if port in curr:
          c = set(curr[port])
        else:
          c = set({})
        opened = c - p
        closed = p - c
        print ("  %5i %5i %5i %6i %6i   (%s)" % (port, len(c), len(p), len(opened), len(closed), port_usage(port)))

      return

    controller.authenticate()
    relays  = {}
    for s in controller.get_network_statuses():
      relays.setdefault(s.address, []).append(s.or_port)

    Curr = {}
    while True:
      try:
        start_time = time.time()
        connections = get_connections('lsof', process_name='tor')

        policy = controller.get_exit_policy()

        Prev = Curr.copy()
        Curr.clear()
        for conn in connections:
          raddr, rport, lport = conn.remote_address, conn.remote_port, conn.local_port
          if raddr in relays:
            continue  # this speeds up from 8.5 sec to 2.5 sec
            if rport in relays[raddr]:
              continue  # this speeds up from 8.5 sec to 6.5 sec
          if policy.can_exit_to(raddr, rport):
            Curr.setdefault(rport, []).append(str(lport) + ':' + raddr)

        printOut (Curr, Prev, time.time() - start_time)

      except KeyboardInterrupt:
        break

      time.sleep(1) # be nice to the CPU

if __name__ == '__main__':
  main()
