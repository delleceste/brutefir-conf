#!/bin/bash

if [[ -z "$1" ]]; then
  echo "$0 eq_type, e.g. $0 noeq, $0 eq1, $0 off"
  exit 1
fi

drc_root="/home/giacomo/digital-room-correction"
conf_file="$drc_root/brutefir-$1.conf"

process_name="brutefir"

if [[ "$1" != "off" ]] && [ ! -e "$conf_file" ]; then
  echo "file $conf_file does not exist"
  exit 1
fi

if pgrep "$process_name" > /dev/null
then
  echo "stopping brutefir"
  killall "$process_name"
else
  echo "brutefir not running"
fi

if [[ "$1" == "off" ]]; then

  # mpd on port 6600
  # /etc/mpd.conf
  mpc enable only 1

  # /etc/mpd-upmpdcli.conf 
  # upmpdcli
  mpc --port 6601 enable only 1
  
  echo "DRC stopped"
  exit 0
fi

sleep 1

echo "Starting 'brutefir $conf_file -daemon'..."
brutefir $conf_file -daemon &>/tmp/brutefir.out

sleep 1


# mpd on port 6600
# /etc/mpd.conf
mpc enable only 3

# /etc/mpd-upmpdcli.conf 
# upmpdcli
mpc --port 6601 enable only 3

