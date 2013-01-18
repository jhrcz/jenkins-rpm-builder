#!/bin/bash

mkdir -p "repo"
for dir in ../../yum-conf-etn-matrix/configurations/axis-BUILDER_BUILD/*/axis-SNAP_BUILD/*/lastStable/archive/repo/*/
do

  resultdir=$(echo "$dir" | cut -d / -f 12 )
  rm -rf "repo/$resultdir"

  cp -a "$dir" "repo/"

  sed -i -e 's,matrix/,matrix-collected/'"$builder"',' repo/$resultdir/*.repo

done
