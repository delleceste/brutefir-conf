SYSTEMD_DIR = /etc/systemd/system
UDEV_DIR    = /etc/udev/rules.d
FREEBSD_RC_DIR   = /usr/local/etc/rc.d
FREEBSD_DEVD_DIR = /usr/local/etc/devd

SERVICES = etc/systemd/system/brutefir-drc.service \
           etc/systemd/system/drc-usb-audio.service

RULES = 99-usb-audio-drc.rules
FREEBSD_SERVICES = etc/rc.d/FreeBSD/brutefir_drc \
                   etc/rc.d/FreeBSD/drc_usb_audio
FREEBSD_DEVD = etc/devd/FreeBSD/usb-audio-drc.conf

.PHONY: install install-systemd install-udev install-freebsd

install: install-systemd install-udev

install-systemd:
	sudo cp $(SERVICES) $(SYSTEMD_DIR)/
	sudo systemctl daemon-reload

install-udev:
	sudo cp $(RULES) $(UDEV_DIR)/
	sudo udevadm control --reload-rules

install-freebsd:
	sudo install -d $(FREEBSD_RC_DIR) $(FREEBSD_DEVD_DIR)
	sudo install -m 555 $(FREEBSD_SERVICES) $(FREEBSD_RC_DIR)/
	sudo install -m 444 $(FREEBSD_DEVD) $(FREEBSD_DEVD_DIR)/
	sudo service devd restart
