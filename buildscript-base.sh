#!/bin/bash
set -x
set -e

rm -rf rctc-repo
rm -rf repo

git clone /opt/rctc-repo/
cd  rctc-repo
make dist

rpmbuild -bs --define '%_topdir '"`pwd`" --define '%_sourcedir %{_topdir}' rctc.spec
#Wrote: /tmp/rctc-repo/SRPMS/rctc-1.10-0.el6.src.rpm
mkdir ../repo

/usr/bin/mock --resultdir "`pwd`/../repo" SRPMS/*.src.rpm
createrepo ../repo

