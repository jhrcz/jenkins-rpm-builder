DESTDIR ?= DESTDIR

default:
	@echo unsupported target
	@exit 1

install:
	install -D {,$(DESTDIR)/usr/libexec/jenkins-rpm-builder/}jenkins-matrix-rpm-build-collector.sh
	install -D {,$(DESTDIR)/usr/libexec/jenkins-rpm-builder/}jenkins-rpm-builder.sh
	install -D {,$(DESTDIR)/usr/libexec/jenkins-rpm-builder/}rpm-sign.exp
	install -D {,$(DESTDIR)/usr/libexec/jenkins-rpm-builder/}update-repo-aliases.sh
	install -D jenkins-rpm-builder.conf.SAMPLE $(DESTDIR)/etc/jenkins-rpm-builder.conf
	cd $(DESTDIR)/usr/libexec/jenkins-rpm-builder/ && ln -sf /etc/jenkins-rpm-builder.conf jenkins-rpm-builder.conf
