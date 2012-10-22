#!/bin/bash -ls
set -x
set -e

rm -rf rctc-repo
rm -rf repo

mkdir -p repo

git clone /opt/rctc-repo/
cd  rctc-repo

# override path to use mock from /usr/bin and not /usr/sbin
export PATH=/usr/bin:$PATH

# move reulting packages in one directory for next steps
mkdir tmp-tito
tito build -o tmp-tito --builder mock --builder-arg mock=epel-6-x86_64 --rpm

# create repository (all files from this repo should be saved as artifacts)
find tmp-tito/ -maxdepth 1 -type f -exec mv '{}' ../repo/ \;
createrepo ../repo

