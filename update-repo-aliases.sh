#!/bin/bash

# crontab:
# * * * * * /usr/bin/cronic /usr/local/sbin/update-repo-aliases.sh

set -x
set -e

cd /var/lib/jenkins/jobs
echo "Alias /repo/index.html /var/www/html/repo.html " > /etc/httpd/sites-includes/repo-aliases.conf
for i in *
do
	echo "Alias /repo/$i/ /var/lib/jenkins/jobs/$i/lastSuccessful/archive/repo/"
done >> /etc/httpd/sites-includes/repo-aliases.conf

cd /var/lib/jenkins/jobs
for i in *
do
	echo "<li><a href=\"/repo/$i/\">$i</a></li>"
done > /var/www/html/repo.html

apachectl configtest 2>/dev/null
apachectl graceful

