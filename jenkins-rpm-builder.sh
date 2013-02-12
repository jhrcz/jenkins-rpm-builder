#!/bin/bash
set -x
set -e

# match nothing when glob does not matches any file
shopt -s nullglob

# defaults
REPO_URL_PREFIX="http://reposerver/repo"
GPG_KEY="GPG KEY FOR EL6 SIGNING"
GPG_KEY_EL5="GPG KEY FOR EL5 SIGNING"
MOCK_BUILDER_DEFAULT="epel-6-x86_64"

SNAP_BUILD_DEFAULT="nosnap"
TAGGED_BUILD_DEFAULT="notag"
SIGN_PACKAGES_DEFAULT="sign"
TEST_PACKAGES_DEFAULT="notest"

MOCK_BUILDER_EL6_DEFAULT=epel-6-x86_64
MOCK_BUILDER_EL5_DEFAULT=epel-5-x86_64

# source all possible conf file locations
for conffile in /etc/jenkins-rpm-builder.conf $HOME/jenkins-rpm-builder.conf $(dirname $0)/jenkins-rpm-builder.conf
do
	if [ -f "$conffile" ]
	then
		source $conffile
	fi
done

# used in in next step for mock and splitin el5 and el6 packages into subdirs 
[ -z "$MOCK_BUILDER" ] && MOCK_BUILDER="$1" || true

# enable building snapshot versions with customized version number
[ -z "$SNAP_BUILD" ] && SNAP_BUILD="$2" || true

# enable possibilty to build lattest tagged or head vcs build
[ -z "$TAGGED_BUILD" ] && TAGGED_BUILD="$3" || true

# enable possibilty to sign resulting packages
[ -z "$SIGN_PACKAGES" ] && SIGN_PACKAGES="$4" || true

# enable running test suite on packages
[ -z "$TEST_PACKAGES" ] && TEST_PACKAGES="$5" || true

# defaults when not defined
[ -z "$MOCK_BUILDER" ] && MOCK_BUILDER="$MOCK_BUILDER_DEFAULT" || true
[ -z "$SNAP_BUILD" ] && SNAP_BUILD="$SNAP_BUILD_DEFAULT" || true
[ -z "$TAGGED_BUILD" ] && TAGGED_BUILD="$TAGGED_BUILD_DEFAULT" || true
[ -z "$SIGN_PACKAGES" ] && SIGN_PACKAGES="$SIGN_PACKAGES_DEFAULT" || true
[ -z "$TEST_PACKAGES" ] && TEST_PACKAGES="$TEST_PACKAGES_DEFAULT" || true

[ -z "$MOCK_BUILDER_EL6" ] && MOCK_BUILDER_EL6="$MOCK_BUILDER_EL6_DEFAULT" || true
[ -z "$MOCK_BUILDER_EL5" ] && MOCK_BUILDER_EL5="$MOCK_BUILDER_EL5_DEFAULT" || true

resultdir="repo/$MOCK_BUILDER"
if [ "$SNAP_BUILD" = "snap" ]
then
	resultdir="repo/${MOCK_BUILDER}-snap"
fi

# prepare for next automated steps
# ... not needed, all in tito
# prepare tmp and out dirs
rm -rf $resultdir
rm -rf tmp-tito/$MOCK_BUILDER

mkdir -p $resultdir
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
	$MOCK_BUILDER_EL5)
		pkg_dist_suffix=".el5"
		mock_cmd="$mock_cmd -D \"_source_filedigest_algorithm 1\""
		mock_cmd="$mock_cmd -D \"_binary_filedigest_algorithm 1\""
		mock_cmd="$mock_cmd -D \"_binary_payload w9.gzdio\""
		;;
	$MOCK_BUILDER_EL6)
		pkg_dist_suffix=".el6"
		;;
	*)
		pkg_dist_suffix=""
		;;
esac

# get the last version from vcs repo
tag="$(git describe --tags --match 'release*' --abbrev=0 || true)"
tagversion="${tag#release-}"
tagversionmajor="${tagversion%%-*}"

# be safe when no tag exists
if [ -z "$tagversionmajor" ]
then
	tagversion="0.0"
fi

# reset workdir to get all files as are in git
# removes local changes in snap spec files for example
git reset --hard

# by default building from HEAD of the branch
# but for many cases it's better to use "tag" param
# specialy when doing snap build for update possibility to next major version
if [ "$TAGGED_BUILD" = "tag" -a  "$SNAP_BUILD" = "" ]
then
	git checkout "$tag"
fi

# when only spec template is prepared, then use it
for specfilein in *.spec.in
do
	specfile=${specfilein%.in}
	cp $specfilein $specfile

	# for templated spec, replace version with version from tag
	sed -r -i -e 's/@@version@@/'"$tagversionmajor"/g $specfile
done

# by default all versions are based on tagged version
# later this could be overriden when doing snap build
version=${tagversion}

# customizing version in spec for snapshot building
# notice: rpm release number is appended after the version
if [ "$SNAP_BUILD" = "snap" ]
then
	# current version format is
	# tagged build: 2.0.99.snap.20130116.161144.git.041ef6c
	# head build:   2.0.00.snap.20130116.161144.git.041ef6c
	versionsnapsuffix="snap.$(date +%F_%T | tr -d .:- | tr _ .).git.$(git log -1 --pretty=format:%h)"
	if [ "$TAGGED_BUILD" = "tag" ]
	then
		versionsnapsuffix="99.$versionsnapsuffix"
	else
		versionsnapsuffix="00.$versionsnapsuffix"
	fi

	if [ "$TAGGED_BUILD" = "tag" ]
	then
		versionmajor="$tagversionmajor.$versionsnapsuffix"
		# replace version with version based on previous tagged and snap suffix
		sed -r -i -e 's/^Version:.*$/Version: '"${versionmajor}/" *.spec
	else
		versionmajor="$(awk -F: '/^Version:/{print $2}' < *.spec | awk '{print $1}').$versionsnapsuffix"
		# append snap suffix to version
		sed -r -i -e '/^Version:/s/\s*$/'".$versionsnapsuffix/" *.spec
	fi
else
	versionmajor="$(awk -F: '/^Version:/{print $2}' < *.spec | awk '{print $1}')"
fi

# we need to know the package name for generating source tarball
name="$(awk -F: '/^Name:/{print $2}' < *.spec | awk '{print $1}')"

# clean mock environment before builds and tests
mock -r ${MOCK_BUILDER} --clean

case $BUILDER in
	make)
		# prepare for next automated steps
		#make dist
		if [ "$SNAP_BUILD" = "snap" ]
		then
			sourcerevision="HEAD"
		else
			sourcerevision="$tag"
		fi
		git archive --format=tar --prefix="${name}-${versionmajor}/" -o ${name}-${versionmajor}.tar $sourcerevision
		rm ${name}-${versionmajor}.tar.gz || true
		gzip ${name}-${versionmajor}.tar

		rm -f SRPMS/*.src.rpm
		rpmbuild -bs --define '%_topdir '"`pwd`" --define '%_sourcedir %{_topdir}' *.spec
		#sample output: Wrote: /tmp/rctc-repo/SRPMS/rctc-1.10-0.el6.src.rpm

		# build
		eval $mock_cmd --resultdir \"$resultdir\" -D \"dist $pkg_dist_suffix\" SRPMS/*.src.rpm
		;;
	tito)
		# override path to use mock from /usr/bin and not /usr/sbin
		export PATH=/usr/bin:$PATH

			# --rpmbuild-options="-D Version $versionmajor" 
		if [ "$SNAP_BUILD" = "snap" ]
		then
			prevbranch=$(git rev-parse --abbrev-ref HEAD)
			git checkout -b tmp-build
			git reset --hard

			# vytahneme si na chvili nemodifikovany spec s puvodnimi verzemi souboru
			# po prejmenovani opet navratime
			#for file in *.spec ; do mv $file $file.tmp-build ; git checkout $file ; done
			#for file in $(spectool -S -l *.spec | awk '{print $2}' | grep "$(awk -F: '/^Version:/{print $2}' < *.spec | awk '{print $1}')" ) ; do git mv $file ${file/$(awk -F: '/^Version:/{print $2}' < *.spec | awk '{print $1}')/$versionmajor} ; done
			#for file in *.spec.tmp-build ; do sed -i -e "/^Source/s/%{version}/$(awk -F: '/^Version:/{print $2}' < *.spec | awk '{print $1}')/" $file ; done
			#for file in *.spec.tmp-build ; do mv $file ${file%.tmp-build} ; done

			#sed -r -i -e '/^Release:/s/\s*$/'".$versionsnapsuffix/" *.spec
			sed -r -i -e '/^Release:/s/^.*$/Release: '"0.$versionsnapsuffix/" *.spec
			
			tito tag --keep-version --no-auto-changelog
			
			# move reulting packages in one directory for next steps
			tito build --test --dist $pkg_dist_suffix --debug -o tmp-tito/$MOCK_BUILDER --builder mock --builder-arg mock=$MOCK_BUILDER --rpm

			git checkout -- *.spec
			git checkout $prevbranch
			git branch -D tmp-build
			git tag -d $name-$(awk -F: '/^Version:/{print $2}' < *.spec | awk '{print $1}')-0.$versionsnapsuffix
		else
			# move reulting packages in one directory for next steps
			tito build --dist $pkg_dist_suffix --debug -o tmp-tito/$MOCK_BUILDER --builder mock --builder-arg mock=$MOCK_BUILDER --rpm
		fi
		
		# create repository (all files from this repo should be saved as artifacts)
		find tmp-tito/$MOCK_BUILDER -maxdepth 1 -type f -exec mv '{}' $resultdir/ \;
		;;
	fpm)
		FPM_PARAMS=$(ls .fpm.* | grep -v .fpm.depends | grep -v .fpm.config-files| grep -v .builder | while read param ; do param=${param##.fpm.} ; echo "--${param} '$(head -n 1 .fpm.${param})' " ; done)
		FPM_PARAMS_DEPENDS=$(while read dep ; do echo "--depends $dep " ; done < .fpm.depends )
		FPM_PARAMS_CONFIG_FILES=$(while read conffile_wild ; do for conffile in ./$conffile_wild ; do echo "--config-files ${conffile#./} " ; done ; done < .fpm.config-files || true )
		rpmarch=noarch
		#rpmarch=${MOCK_BUILDER##*-}
		rpmout=$(head -n1 .fpm.name)-$(head -n1 .fpm.version)$([ -f .fpm.iteration ] && echo -n "-" && head -n1 .fpm.iteration || true)-${rpmarch}.rpm
		eval fpm -s dir -x \'.fpm.\*\' -x repo -x \'tmp-\*\' -x .git -t rpm -p $resultdir/$rpmout $FPM_PARAMS $FPM_PARAMS_DEPENDS $FPM_PARAMS_CONFIG_FILES .
		;;
	*)
		echo "Build method not detected or specified"
		exit 1
		;;
esac

# create repo files
n=$(pwd | cut -d / -f 6)

# signing command requires user input, expect is required even when
# the key is is without password
if [ "$SIGN_PACKAGES" = "sign" ]
	then
	case "$MOCK_BUILDER" in
		$MOCK_BUILDER_EL5)
			signcmd="$(dirname $0)/rpm-sign.exp \
				--define \"_signature gpg\" \
				--define \"_gpg_name ${GPG_KEY_EL5}\" \
				--define \"__gpg_sign_cmd %{__gpg} gpg --force-v3-sigs --digest-algo=sha1 --batch --no-verbose --no-armor --passphrase-fd 3 --no-secmem-warning -u '%{_gpg_name}' -sbo %{__signature_filename} %{__plaintext_filename}\" \
				"
			;;
		*)
			signcmd="$(dirname $0)/rpm-sign.exp \
				--define \"_signature gpg\" \
				--define \"_gpg_name ${GPG_KEY}\" \
				"
			;;
	esac

	for package in $resultdir/*.rpm
	do
		eval $signcmd $package
	done
fi

if [ "$TEST_PACKAGES" = "test" ]
then
	mock -r ${MOCK_BUILDER} --init
	mock -r ${MOCK_BUILDER} --install $(GLOBIGNORE='*.src.rpm:*-debug*rpm' ; ls  repo/${MOCK_BUILDER}*/*.rpm)
	mock -r ${MOCK_BUILDER} --copyin tests/ /builddir/build/tests/
	mock -r ${MOCK_BUILDER} --shell "cd /builddir/build/tests && ./run.sh"
fi

case "$MOCK_BUILDER" in
	$MOCK_BUILDER_EL5)
		createrepo -s sha $resultdir
		;;
	*)
		createrepo $resultdir
		;;
esac

echo "
[local-devel-$n-$MOCK_BUILDER]
name=CI build of $n on $MOCK_BUILDER builder
enabled=1
gpgcheck=0
baseurl=${REPO_URL_PREFIX}/$n/${resultdir#repo/}/
proxy=_none_
" > $resultdir/local-devel-$n-${resultdir#repo/}.repo

