#!/bin/bash
[ "$DEBUG" = "YES" ] && set -x
set -e

# match nothing when glob does not matches any file
shopt -s nullglob

# defaults
REPO_URL_PREFIX="http://reposerver/repo"
GPG_KEY="GPG KEY FOR EL6 SIGNING"
GPG_KEY_EL5="GPG KEY FOR EL5 SIGNING"
MOCK_BUILDER_DEFAULT="epel-6-x86_64"

SNAP_BUILD_DEFAULT="nosnap"
TAGGED_BUILD_DEFAULT="tag"
SIGN_PACKAGES_DEFAULT="sign"
TEST_PACKAGES_DEFAULT="notest"
OUTOFDIR_BUILD_DEFAULT="nooutofdir"
GETSRC_DEFAULT="nogetsrc"

MOCK_BUILDER_EL6_DEFAULT=epel-6-x86_64
MOCK_BUILDER_EL5_DEFAULT=epel-5-x86_64

# source all possible conf file locations
for conffile in /etc/jenkins-rpm-builder.conf $HOME/.jenkins-rpm-builder.conf $(dirname $0)/jenkins-rpm-builder.conf
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

# enable building outside of current repo workdir
[ -z "$OUTOFDIR_BUILD" ] && OUTOFDIR_BUILD="$6" || true

# enable downloading sources referenced in spec
[ -z "$GETSRC" ] && GETSRC="$7" || true

# rpm pipe builder for re-signing only and filtered repo mirroring
# ex. 'http://downloads-distro.mongodb.org/repo/redhat/os/x86_64/RPMS/'
[ -z "$PIPEBUILD_REPO_URL" ] && PIPEBUILD_REPO_URL="$8" || true
# ex. '2.4.6-mongodb_1'
[ -z "$PIPEBUILD_RPM_VERSION" ] && PIPEBUILD_RPM_VERSION="$9" || true

# defaults when not defined
[ -z "$MOCK_BUILDER" ] && MOCK_BUILDER="$MOCK_BUILDER_DEFAULT" || true
[ -z "$SNAP_BUILD" ] && SNAP_BUILD="$SNAP_BUILD_DEFAULT" || true
[ -z "$TAGGED_BUILD" ] && TAGGED_BUILD="$TAGGED_BUILD_DEFAULT" || true
[ -z "$SIGN_PACKAGES" ] && SIGN_PACKAGES="$SIGN_PACKAGES_DEFAULT" || true
[ -z "$TEST_PACKAGES" ] && TEST_PACKAGES="$TEST_PACKAGES_DEFAULT" || true
[ -z "$OUTOFDIR_BUILD" ] && OUTOFDIR_BUILD="$OUTOFDIR_BUILD_DEFAULT" || true
[ -z "$GETSRC" ] && GETSRC="$GETSRC_DEFAULT" || true

[ -z "$MOCK_BUILDER_EL6" ] && MOCK_BUILDER_EL6="$MOCK_BUILDER_EL6_DEFAULT" || true
[ -z "$MOCK_BUILDER_EL5" ] && MOCK_BUILDER_EL5="$MOCK_BUILDER_EL5_DEFAULT" || true

echo ":::::"
echo "::::: MOCK_BUILDER:  $MOCK_BUILDER"
echo "::::: SNAP_BUILD:    $SNAP_BUILD"
echo "::::: TAGGED_BUILD:  $TAGGED_BUILD"
echo "::::: SIGN_PACKAGES: $SIGN_PACKAGES"
echo "::::: TEST_PACKAGES: $TEST_PACKAGES"
echo "::::: OUTOFDIR_BUILD:$OUTOFDIR_BUILD"
echo "::::: GETSRC:        $GETSRC"
echo "::::: PIPEBUILD_REPO_URL:    $PIPEBUILD_REPO_URL"
echo "::::: PIPEBUILD_RPM_VERSION: $PIPEBUILD_RPM_VERSION"
echo ":::::"

echo ":::::"
echo "::::: MOCK_BUILDER_EL6: $MOCK_BUILDER_EL6"
echo "::::: MOCK_BUILDER_EL5: $MOCK_BUILDER_EL5"
echo ":::::"

if [ "$OUTOFDIR_BUILD" = "outofdir" ]
then
	prevbranch=$(git rev-parse --abbrev-ref HEAD)

	echo ":::::"
	echo "::::: building out of checkout dir with branch $prevbranch"
	echo ":::::"

	rm -rf tmpbuild
	mkdir -p tmpbuild
	cd tmpbuild
	git clone ../ repoclone
	cd repoclone
	git checkout "$prevbranch"
fi

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
[ -f pipebuilder.conf -o -n "$PIPEBUILD_REPO_URL" ] \
	&& BUILDER=pipebuild
# make it possible to override builder detection
[ -f .builder ] \
	&& BUILDER=$(head -n 1 .builder)

echo ":::::"
echo "::::: BUILDER: $BUILDER"
echo ":::::"

#fallback to make-like build method
[ -z "$BUILDER" ] \
	&& BUILDER=make

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
echo ":::::"
echo "::::: getting version info from vcs based on 'rpm-release-' tag"
echo ":::::"
tag="$(git describe --tags --match 'rpm-release*' --abbrev=0 || true)"
tagversion="${tag#rpm-release-}"
tagversionmajor="${tagversion%%-*}"

if [ -z "$tagversionmajor" ]
then
    echo ":::::"
    echo "::::: version not found, trying 'release-' tag"
    echo ":::::"
    tag="$(git describe --tags --match 'release*' --abbrev=0 || true)"
    tagversion="${tag#release-}"
    tagversionmajor="${tagversion%%-*}"
fi

if [ -z "$tagversionmajor" ]
then
	echo ":::::"
	echo "::::: version not found, trying 'v' tag "
	echo ":::::"
	tag="$(git describe --tags --match 'v*' --abbrev=0 || true)"
	tagversion="${tag#v}"
	tagversionmajor="${tagversion%%-*}"
fi

# be safe when no tag exists
if [ -z "$tagversionmajor" ]
then
	if [ "$SNAP_BUILD" = "nosnap" -a "$BUILDER" != "tito" -a "$BUILDER" != "fpm" ]
	then
		echo "ERROR: nosnap build requires tagged release"
		exit 1
	fi
	tagversion="0.0"
	tagversionmajor="$tagversion"
fi

# reset workdir to get all files as are in git
# removes local changes in snap spec files for example
echo ":::::"
echo "::::: reseting git repo to start with unmodified files"
echo ":::::"
git reset --hard

# by default building from HEAD of the branch
# but for many cases it's better to use "tag" param
# specialy when doing snap build for update possibility to next major version
if [ "$SNAP_BUILD" = "nosnap" ]
then
	if [ "$TAGGED_BUILD" = "tag" ]
	then
		echo ":::::"
		echo "::::: checking out tag: $tag"
		echo ":::::"
		git checkout "$tag"
	else
		echo "ERROR: nosnap build requires tagged build"
		exit 1
	fi
fi

# when only spec template is prepared, then use it
for specfilein in *.spec.in
do
	echo ":::::"
	echo "::::: using spec.in as a spec template"
	echo "::::: @@version@@ string will be replaced with: $tagversionmajor"
	echo ":::::"

	specfile=${specfilein%.in}
	cp $specfilein $specfile

	# for templated spec, replace version with version from tag
	sed -r -i -e 's/@@version@@/'"$tagversionmajor"'/g' $specfile
done

# by default all versions are based on tagged version
# later this could be overriden when doing snap build
version=${tagversion}

# customizing version in spec for snapshot building
# notice: rpm release number is appended after the version
if [ "$SNAP_BUILD" = "snap" -a "$KEEP_VERSION" != "keepversion" ]
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
	echo ":::::"
	echo "::::: building snap package with version suffix: $versionsnapsuffix"
	echo ":::::"

	if [ "$TAGGED_BUILD" = "tag" ]
	then
		versionmajor="$tagversionmajor.$versionsnapsuffix"
		# replace version with version based on previous tagged and snap suffix
		sed -r -i -e 's/^Version:.*$/Version: '"${versionmajor}/" *.spec
	else
		versionmajor="$( rpm -q --queryformat="%{version}\n" --specfile *.spec | head -n 1 | awk '{print $1}').$versionsnapsuffix"
		# append snap suffix to version
		sed -r -i -e '/^Version:/s/\s*$/'".$versionsnapsuffix/" *.spec
	fi
else
	versionmajor="$(rpm -q --queryformat="%{version}\n" --specfile *.spec | head -n 1)"
fi

# we need to know the package name for generating source tarball
name="$(rpm -q --queryformat="%{name}\n" --specfile *.spec | head -n 1)"

# clean mock environment before builds and tests
#mock -r ${MOCK_BUILDER} --clean

case $BUILDER in
	make)
		# prepare for next automated steps
		#make dist
		if [ "$SNAP_BUILD" = "snap" ]
		then
			echo ":::::"
			echo "::::: building snap package from HEAD"
			echo ":::::"
			
			sourcerevision="HEAD"
		else
			echo ":::::"
			echo "::::: building nosnap package with tag: $tag"
			echo ":::::"
			
			sourcerevision="$tag"
		fi

		if [ "$GETSRC" = "getsrc" ]
		then
			echo ":::::"
			echo "::::: downloading all files reference in spec with url"
			echo ":::::"
			spectool --define '%_topdir '"`pwd`" --define '%_sourcedir %{_topdir}' --define "%dist $pkg_dist_suffix" -A -g *.spec

			# for compatibility with github and spectool on el6
			# rename downloaded file to requested name befored github redirects
			s=$(spectool -l *.spec  | grep Source0: | cut -d : -f 2- | tr -d " ")
			if [ "$SOURCE_TGZ_RENAME_HACK" = "YES" ]
			then
				s=$(basename "$s" ".tar.gz")
				if [ -f "$s" ]
				then
					mv "$s" "$s".tar.gz
				fi
				s=${s/${name}-}
				if [ -f "$s" ]
				then
					mv "$s" "$name-$s".tar.gz
				fi
			fi
		else
			echo ":::::"
			echo "::::: building upstream source tarball from vcs repo"
			echo ":::::"
			git archive --format=tar --prefix="${name}-${versionmajor}/" -o ${name}-${versionmajor}.tar $sourcerevision
			rm ${name}-${versionmajor}.tar.gz || true
			gzip ${name}-${versionmajor}.tar
		fi

		rm -f SRPMS/*.src.rpm
		rpmbuild -bs --define '%_topdir '"`pwd`" --define '%_sourcedir %{_topdir}' --define "%dist $pkg_dist_suffix" --define "_source_filedigest_algorithm md5" --define "_binary_filedigest_algorithm md5" *.spec
		#sample output: Wrote: /tmp/rctc-repo/SRPMS/rctc-1.10-0.el6.src.rpm

		echo ":::::"
		echo "::::: building in mock"
		echo ":::::"
		# build
		eval $mock_cmd -r $MOCK_BUILDER ${KEEP_MOCK_ENV:+--no-cleanup-after} --resultdir \"$resultdir\" -D \"dist $pkg_dist_suffix\" SRPMS/*.src.rpm
		;;
	tito)
		# override path to use mock from /usr/bin and not /usr/sbin
		export PATH=/usr/bin:$PATH

			# --rpmbuild-options="-D Version $versionmajor" 
		if [ "$SNAP_BUILD" = "snap" ]
		then
			echo ":::::"
			echo "::::: building snap package with tito"
			echo ":::::"

			prevbranch=$(git rev-parse --abbrev-ref HEAD)
			
			echo ":::::"
			echo "::::: spec based on tito version with tag $prevbranch"
			echo "::::: with release suffix: 0.$versionsnapsuffix"
			echo ":::::"

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
			
			# move resulting packages in one directory for next steps
			tito build --test --dist $pkg_dist_suffix --debug -o tmp-tito/$MOCK_BUILDER --builder mock --builder-arg mock=$MOCK_BUILDER --rpm

			git checkout -- *.spec
			git checkout $prevbranch
			git branch -D tmp-build
			git tag -d $name-$(rpm -q --queryformat="%{version}\n" --specfile *.spec | head -n 1 | awk '{print $1}')-0.$versionsnapsuffix
		else
			echo ":::::"
			echo "::::: building nosnap with tito"
			echo ":::::"
			
			# move reulting packages in one directory for next steps
			tito build --dist $pkg_dist_suffix --debug -o tmp-tito/$MOCK_BUILDER --builder mock --builder-arg mock=$MOCK_BUILDER --rpm
		fi
		
		# create repository (all files from this repo should be saved as artifacts)
		find tmp-tito/$MOCK_BUILDER -maxdepth 1 -type f -exec mv '{}' $resultdir/ \;
		;;
	fpm)
		echo ":::::"
		echo "::::: building with fpm"
		echo ":::::"
		
		FPM_PARAMS=$(ls .fpm.* | grep -v .fpm.depends | grep -v .fpm.config-files| grep -v .builder | while read param ; do param=${param##.fpm.} ; echo "--${param} '$(head -n 1 .fpm.${param})' " ; done)
		FPM_PARAMS_DEPENDS=$(while read dep ; do echo "--depends $dep " ; done < .fpm.depends )
		FPM_PARAMS_CONFIG_FILES=$(while read conffile_wild ; do for conffile in ./$conffile_wild ; do echo "--config-files ${conffile#./} " ; done ; done < .fpm.config-files || true )
		rpmarch=noarch
		#rpmarch=${MOCK_BUILDER##*-}
		rpmout=$(head -n1 .fpm.name)-$(head -n1 .fpm.version)$([ -f .fpm.iteration ] && echo -n "-" && head -n1 .fpm.iteration || true)$([ -f .fpm.iteration ] && echo -n "$pkg_dist_suffix")-${rpmarch}.rpm
		name="$(head -n1 .fpm.name)"
		
		echo ":::::"
		echo "::::: fpm params: $FPM_PARAMS"
		echo "::::: depends: $FPM_PARAMS_DEPENDS"
		echo "::::: detected conf files: $FPM_PARAMS_CONFIG_FILES"
		echo ":::::"
		eval fpm -s dir -x \'.fpm.\*\' -x repo -x \'tmp-\*\' -x .git -t rpm -p $resultdir/$rpmout $FPM_PARAMS $FPM_PARAMS_DEPENDS $FPM_PARAMS_CONFIG_FILES .
		;;
	pipebuild)
		#PIPEBUILD_REPO_URL='http://downloads-distro.mongodb.org/repo/redhat/os/x86_64/RPMS/'
		#PIPEBUILD_RPM_VERSION='2.4.6-mongodb_1'

		[ -f "pipebuilder.conf" ] \
			&& source pipebuilder.conf
		echo "pipebuilder config:"
		cat pipebuilder.conf
		echo ""
		if [ "$TAGGED_BUILD" = "tag" ]
		then
			[ -z "$PIPEBUILD_RPM_VERSION" -a -n "$version" ] \
				&& PIPEBUILD_RPM_VERSION="${version%%#*}"
			# be strinct and require tag to be in sync with requested version
			echo "$version" | grep -q "^$PIPEBUILD_RPM_VERSION[-_:#]"
		fi
		[ -n "$PIPEBUILD_RPM_VERSION" ]

		function list_pkgs_in_repo_url
		{
			local repo_url="$1"
			local rpm_version="$2"

			# links has to much differences in parametrs support betwen rhel/fedora to keep it in sync
			#links -dump -http-proxy "${http_proxy##http://}" -no-numbering -no-references  "$repo_url" | grep -o '[^ ]*'"$rpm_version"'[^ ]*.rpm'
			#links -dump -http-proxy "${http_proxy##http://}" "$repo_url" | grep -o '[^ ]*'"$rpm_version"'[^ ]*.rpm'
			#curl -s "$repo_url" | grep -o '>[^ ]*.rpm<' | tr -d "<>" | grep -o '[^ "]*'"$rpm_version"'[^ "]*.rpm'
			curl -s "$repo_url" | grep -o '>[^ "]*'"$rpm_version"'[^ "]*.rpm<' | tr -d '<>'
		}

		function getmatching_from_repo
		{
			local repo_url="$1"
			local rpm_version="$2"

			# debug
			#list_pkgs_in_repo_url "$repo_url" "$rpm_version"

			while read pkg
			do
				echo "downloading $pkg..."
				
				# allow injecting cached files instead of downloading them
				for cachedir in "../../cachedir/" "cachedir/"
				do
					[ -f "$cachedir/$pkg" ] \
						&& cp $cachedir/$pkg $resultdir/
				done
				# download them if they are not injected from cache
				[ -f "$resultdir/$pkg" ] \
					|| 	wget -P $resultdir/ -cnv "$repo_url""$pkg"
				[ -f "$resultdir/$pkg" ]
				echo "download done."

			done < <(
				list_pkgs_in_repo_url "$repo_url" "$rpm_version"
			)
			[ -n "$( find $resultdir/ -name '*.rpm' )" ]
		}

		echo "mirroring packages from repository"
		echo "  repo: $PIPEBUILD_REPO_URL"
		echo "  version: $PIPEBUILD_RPM_VERSION"
		getmatching_from_repo "$PIPEBUILD_REPO_URL" "$PIPEBUILD_RPM_VERSION"

		ls $resultdir/*.rpm
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

	echo ":::::"
	echo "::::: signing packages"
	echo "::::: with command: $signcmd"
	echo ":::::"
	for package in $resultdir/*.rpm
	do
		eval $signcmd $package
	done
fi

if [ "$TEST_PACKAGES" = "test" ]
then
	echo ":::::"
	echo "::::: running test cases"
	echo ":::::"
	mock -r ${MOCK_BUILDER} --init
	mock -r ${MOCK_BUILDER} --install bats
	mock -r ${MOCK_BUILDER} --install $(GLOBIGNORE='*.src.rpm:*-debug*rpm' ; ls  repo/${MOCK_BUILDER}*/*.rpm)
	mock -r ${MOCK_BUILDER} --copyin tests/ /builddir/build/tests/
	mock -r ${MOCK_BUILDER} --shell "cd /builddir/build/tests && ./run.sh"
fi

echo ":::::"
echo "::::: generating repofiles: $resultdir"
echo ":::::"
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
cat $resultdir/local-devel-$n-${resultdir#repo/}.repo

echo ":::::"
echo ":::::"
echo ":::::"

find repo/

echo ":::::"
echo ":::::"
echo ":::::"

if [ -n "$SYNC_TRG_SERVER" -a -n "$SYNC_TRG_PATH" -a -n "$name" ]
then
	# some sanity check
	echo "$name" | grep '/' && exit 1
	echo "$name" | grep '\.\.' && exit 1

	echo "Syncing repo to: $SYNC_TRG_SERVER:$SYNC_TRG_PATH/$name/"
	rsync -ave ssh repo/ "$SYNC_TRG_SERVER":"$SYNC_TRG_PATH"/"$name"/
fi

echo ":::::"
echo "::::: DONE"
echo ":::::"
