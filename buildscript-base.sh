#!/bin/bash
set -x
set -e


[ -z "$MOCK_BUILDER" ] && MOCK_BUILDER="$1" || true
#[ -z "$MOCK_BUILDER" ] && MOCK_BUILDER="epel-6-x86_64" || true
[ -n "$MOCK_BUILDER" ] 

# prepare for next automated steps
make dist
rpmbuild -bs --define '%_topdir '"`pwd`" --define '%_sourcedir %{_topdir}' *.spec
#Wrote: /tmp/rctc-repo/SRPMS/rctc-1.10-0.el6.src.rpm

# prepare tmp and out dirs
rm -rf repo/$MOCK_BUILDER


mkdir -p repo/$MOCK_BUILDER


# build

/usr/bin/mock --resultdir "repo/$MOCK_BUILDER" SRPMS/*.src.rpm

# create repo files
createrepo repo/$MOCK_BUILDER

