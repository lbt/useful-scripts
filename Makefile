install:
	install -d $(DESTDIR)/usr/bin/
	install -D -m 755 send_to_OBS.sh        $(DESTDIR)/usr/bin/
	install -D -m 755 project_status.pl     $(DESTDIR)/usr/bin/

