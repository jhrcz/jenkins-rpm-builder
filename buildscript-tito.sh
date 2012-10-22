#!/bin/bash -ls
set -x
set -e


[ -z "$MOCK_BUILDER" ] && MOCK_BUILDER="$1" || true
#[ -z "$MOCK_BUILDER" ] && MOCK_BUILDER="epel-6-x86_64" || true
[ -n "$MOCK_BUILDER" ] 

#rm -rf *-repo
rm -rf repo/$MOCK_BUILDER
rm -rf tmp-tito/$MOCK_BUILDER

mkdir -p repo/$MOCK_BUILDER
mkdir -p tmp-tito/$MOCK_BUILDER

# override path to use mock from /usr/bin and not /usr/sbin
export PATH=/usr/bin:$PATH

# move reulting packages in one directory for next steps
tito build --debug -o tmp-tito/$MOCK_BUILDER --builder mock --builder-arg mock=$MOCK_BUILDER --rpm

# create repository (all files from this repo should be saved as artifacts)
find tmp-tito/$MOCK_BUILDER -maxdepth 1 -type f -exec mv '{}' repo/$MOCK_BUILDER \;
createrepo repo/$MOCK_BUILDER
