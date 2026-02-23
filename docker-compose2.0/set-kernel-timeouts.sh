#!/usr/bin/env bash

CID=docker-compose20-gateway-lb-1
PID=$(docker inspect -f '{{.State.Pid}}' "$CID")

sudo nsenter -t "$PID" -n sysctl -w net.netfilter.nf_conntrack_udp_timeout_stream=1
sudo nsenter -t "$PID" -n sysctl -w net.netfilter.nf_conntrack_udp_timeout=1
