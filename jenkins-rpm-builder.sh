#!/bin/bash
set -x
set -e

# match nothing when glob does not matches any file
shopt -s nullglob

# used in in next step for mock and splitin el5 and el6 packages into subdirs 
[ -z "$MOCK_BUILDER" ] && MOCK_BUILDER="$1" || true
#[ -z "$MOCK_BUILDER" ] && MOCK_BUILDER="epel-6-x86_64" || true
[ -n "$MOCK_BUILDER" ] 

# enable building snapshot versions with customized version number
[ -z "$SNAP_BUILD" ] && SNAP_BUILD="$2" || true

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

mock_cmd='/usr/bin/mock'
case "$MOCK_BUILDER" in
	epel-5-x86_64)
		pkg_dist_suffix=".el5"
		mock_cmd="$mock_cmd -D \"_source_filedigest_algorithm 1\""
		mock_cmd="$mock_cmd -D \"_binary_filedigest_algorithm 1\""
		mock_cmd="$mock_cmd -D \"_binary_payload w9.gzdio\""
		;;
	epel-6-x86_64)
		pkg_dist_suffix=".el6"
		;;
	*)
		pkg_dist_suffix=""
		;;
esac

# get the last version from vcs repo
tagversion="$(git describe --tags --match 'release*')"
tagversion="${tagversion#release-}"
tagversionmajor="${tagversion%%-*}"

# when only spec template is prepared, then use it
for specfilein in *.spec.in
do
	specfile=${specfilein%.in}
	cp $specfilein $specfile

	# for templated spec, replace version with version from tag
	sed -r -i -e 's/@@version@@/'"$tagversionmajor"/g $specfile
done

# customizing version in spec for snapshot building
# notice: rpm release number is appended after the version
if [ "$SNAP_BUILD" = "snap" ]
then
	# current version format is: 2.0.99.snap.20130116.161144.git.041ef6c
	sed -r -i -e '/^Version:/s/\s*$/'".99.snap.$(date +%F_%T | tr -d .:- | tr _ .).git.$(git log -1 --pretty=format:%h)/" *.spec
fi

case $BUILDER in
	make)
		# prepare for next automated steps
		make dist
		rm -f SRPMS/*.src.rpm
		rpmbuild -bs --define '%_topdir '"`pwd`" --define '%_sourcedir %{_topdir}' *.spec
		#sample output: Wrote: /tmp/rctc-repo/SRPMS/rctc-1.10-0.el6.src.rpm

		# build
		eval $mock_cmd --resultdir \"repo/$MOCK_BUILDER\" -D \"dist $pkg_dist_suffix\" SRPMS/*.src.rpm
		;;
	tito)
		# override path to use mock from /usr/bin and not /usr/sbin
		export PATH=/usr/bin:$PATH

		# move reulting packages in one directory for next steps
		tito build --dist $pkg_dist_suffix --debug -o tmp-tito/$MOCK_BUILDER --builder mock --builder-arg mock=$MOCK_BUILDER --rpm

		# create repository (all files from this repo should be saved as artifacts)
		find tmp-tito/$MOCK_BUILDER -maxdepth 1 -type f -exec mv '{}' repo/$MOCK_BUILDER \;
		;;
	fpm)
		FPM_PARAMS=$(ls .fpm.* | grep -v .fpm.depends | grep -v .fpm.config-files| grep -v .builder | while read param ; do param=${param##.fpm.} ; echo "--${param} '$(head -n 1 .fpm.${param})' " ; done)
		FPM_PARAMS_DEPENDS=$(while read dep ; do echo "--depends $dep " ; done < .fpm.depends )
		FPM_PARAMS_CONFIG_FILES=$(while read conffile_wild ; do for conffile in ./$conffile_wild ; do echo "--config-files ${conffile#./} " ; done ; done < .fpm.config-files || true )
		rpmarch=noarch
		#rpmarch=${MOCK_BUILDER##*-}
		rpmout=$(head -n1 .fpm.name)-$(head -n1 .fpm.version)$([ -f .fpm.iteration ] && echo -n "-" && head -n1 .fpm.iteration || true)-${rpmarch}.rpm
		eval fpm -s dir -x \'.fpm.*\' -x repo -x \'tmp-*\' -x .git -t rpm -p repo/$MOCK_BUILDER/$rpmout $FPM_PARAMS $FPM_PARAMS_DEPENDS $FPM_PARAMS_CONFIG_FILES .
		;;
	*)
		echo "Build method not detected or specified"
		exit 1
		;;
esac

# create repo files
n=$(pwd | cut -d / -f 6)

case "$MOCK_BUILDER" in
	epel-5-x86_64)
		createrepo -s sha repo/$MOCK_BUILDER
		;;
	*)
		createrepo repo/$MOCK_BUILDER
		;;
esac

echo "
[local-devel-$n-$MOCK_BUILDER]
name=CI build of $n on $MOCK_BUILDER builder
enabled=1
gpgcheck=0
baseurl=http://one1-pkgbuild-jenkins-1.mit.etn.cz/repo/$n/$MOCK_BUILDER/
proxy=_none_
" > repo/$MOCK_BUILDER/local-devel-$n-$MOCK_BUILDER.repo
