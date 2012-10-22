#!/bin/bash -ls
set -x
set -e

#rm -rf *-repo
rm -rf repo
rm -rf tmp-tito

mkdir -p repo
mkdir -p tmp-tito

[ -z "$MOCK_BUILDER" ] && MOCK_BUILDER="$1" || true
#[ -z "$MOCK_BUILDER" ] && MOCK_BUILDER="epel-6-x86_64" || true

# override path to use mock from /usr/bin and not /usr/sbin
export PATH=/usr/bin:$PATH

# move reulting packages in one directory for next steps
tito build --debug -o tmp-tito --builder mock --builder-arg mock=$MOCK_BUILDER --rpm

# create repository (all files from this repo should be saved as artifacts)
find tmp-tito/ -maxdepth 1 -type f -exec mv '{}' repo/ \;
createrepo repo
