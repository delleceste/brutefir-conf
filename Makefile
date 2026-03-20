SYSTEMD_DIR = /etc/systemd/system
UDEV_DIR    = /etc/udev/rules.d

SERVICES = etc/systemd/system/brutefir-drc.service \
           etc/systemd/system/drc-usb-audio.service

RULES = 99-usb-audio-drc.rules

.PHONY: install install-systemd install-udev

install: install-systemd install-udev

install-systemd:
	sudo cp $(SERVICES) $(SYSTEMD_DIR)/
	sudo systemctl daemon-reload

install-udev:
	sudo cp $(RULES) $(UDEV_DIR)/
	sudo udevadm control --reload-rules
