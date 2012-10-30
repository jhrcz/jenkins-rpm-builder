#!/bin/bash
set -x
set -e

# used in in next step for mock and splitin el5 and el6 packages into subdirs 
[ -z "$MOCK_BUILDER" ] && MOCK_BUILDER="$1" || true
#[ -z "$MOCK_BUILDER" ] && MOCK_BUILDER="epel-6-x86_64" || true
[ -n "$MOCK_BUILDER" ] 

# prepare for next automated steps
# ... not needed, all in tito
# prepare tmp and out dirs
rm -rf repo/$MOCK_BUILDER
rm -rf tmp-tito/$MOCK_BUILDER

mkdir -p repo/$MOCK_BUILDER
mkdir -p tmp-tito/$MOCK_BUILDER

[ -f Makefile ] \
	&& BUILDER=make
[ -d rel-eng ] \
	&& BUILDER=tito
[ -f .fpm.name ] \
	&& BUILDER=fpm
# make it possible to override builder detection
[ -f .builder ] \
	&& BUILDER=$(head -n 1 .builder)

case $BUILDER in
	make)
		# prepare for next automated steps
		make dist
		rpmbuild -bs --define '%_topdir '"`pwd`" --define '%_sourcedir %{_topdir}' *.spec
		#sample output: Wrote: /tmp/rctc-repo/SRPMS/rctc-1.10-0.el6.src.rpm

		# build
		/usr/bin/mock --resultdir "repo/$MOCK_BUILDER" SRPMS/*.src.rpm
		;;
	tito)
		# override path to use mock from /usr/bin and not /usr/sbin
		export PATH=/usr/bin:$PATH

		# move reulting packages in one directory for next steps
		tito build --debug -o tmp-tito/$MOCK_BUILDER --builder mock --builder-arg mock=$MOCK_BUILDER --rpm

		# create repository (all files from this repo should be saved as artifacts)
		find tmp-tito/$MOCK_BUILDER -maxdepth 1 -type f -exec mv '{}' repo/$MOCK_BUILDER \;
		;;
	fpm)
		FPM_PARAMS=$(ls .fpm.* | grep -v .fpm.depends | grep -v .builder | while read param ; do param=${param##.fpm.} ; echo "--${param} '$(head -n 1 .fpm.${param})' " ; done)
		FPM_PARAMS_DEPENDS=$(while read dep ; do echo "--depends $dep " ; done < .fpm.depends )
		rpmarch=noarch
		#rpmarch=${MOCK_BUILDER##*-}
		rpmout=$(head -n1 .fpm.name)-$(head -n1 .fpm.version)$([ -f .fpm.iteration ] && echo -n "-" && head -n1 .fpm.iteration || true)-${rpmarch}.rpm
		eval fpm -s dir -x \'.fpm.*\' -x repo -x \'tmp-*\' -x .git -t rpm -p repo/$MOCK_BUILDER/$rpmout $FPM_PARAMS $FPM_PARAMS_DEPENDS .
		;;
	*)
		echo "Build method not detected or specified"
		exit 1
		;;
esac

# create repo files
createrepo repo/$MOCK_BUILDER

