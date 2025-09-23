#!/bin/bash

echo -e -n "creating symlink \e[1;32mln -s \e[0m$PWD/drc.service \e[1;31m-->\e[0m \e[0;36m~/.config/systemd/user/drc.service\e[0m..."
ln -sf $PWD/drc.service ~/.config/systemd/user/drc.service && echo -e "\t[ \e[1;32mOK\e[0m ]" || echo -e "\t[ \e[1;31mFAILED\e[0m ]"

echo -e "calling systemctl --user daemon-reload..."
systemctl --user daemon-reload

echo -e "calling systemctl --user enable --now drc.service..."

systemctl --user enable --now drc.service

