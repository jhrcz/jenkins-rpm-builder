jenkins-rpm-builder
===================

wrapper for easy building of rpm packages in jenkins ci server

![screenshot](https://github.com/jhrcz/jenkins-rpm-builder/raw/github/screenshot.png)

integrates all components usualy used for rpm packaging
  * **git** for verioning all the packaging data
  * **mock** for building in clean enviroment

source packages could have multiple forms
  * **make** - using Makefile in source root with support for install target and DESTDIR param
  * **tito** - package versioning managed by tito tool
  * **fpm** - package building managed by fpm tool. params could defined by dotfiles named after param.

this all **managed by jenkins ci server** and his gui.

advanced configuratin like matrix projects is supported. this enables building release ready and snapshot packages from the same source repositories to common rpm yum repos with only successfuly finished build jobs.

usage
-----

in jenkins, define build by executable command

	bash /usr/libexec/jenkins-rpm-builder/jenkins-rpm-builder.sh \
		<epel-5-x86_64|epel-6-x86_64> <snap|nosnap> <tag|notag> <sign|nosign>

where the params mean
  * **snap|nosnap** - build release readu or snapshot packages
  * **tag|notag** - base the snap build version on tag or on latest spec
  * **sign|nosign** - choose generating gpg signed or unsigned packages
  * **test|notest** - enable bats based functional test cases
  * **outofdir|nooutofdir** - create clone of the repo in tmpbuild dir to not interferre with the main vcs tree
  
examples of snapshot versions depending on combination of params
  * **snap+notag**: etnpol-tomcat-7.0-7.0.35.00.snap.20130117.154830.git.466b173-0.el6.noarch.rpm
  * **snap+tag**: etnpol-tomcat-7.0-7.0.27.99.snap.20130117.151837.git.466b173-0.el6.noarch.rpm
  * **nosnap+notag**: etnpol-tomcat-7.0-7.0.35-0.el5.noarch.rpm
  * **nosnap+tag**: etnpol-tomcat-7.0-7.0.27-0.el6.noarch.rpm

because tito is special tool for managing rpm release process with tags, snap build of tito base package
uses slightly modified versioning:
  * packag-name-x.y-0.00.snap.YYYYMMDD.HHMMSS.git.HASH.el6.ARCH.rpm
this differentiates snap build from regular package release a makes them upgradeable. snap suffix in release section does not
require modification of upstream source in tito controlled repository.

configuration file (for overriding for example gpg keys and default params when used without params) is searched in
  * /etc/jenkins-rpm-builder.conf
  * $HOME/.jenkins-rpm-builder.conf
  * {main tool executable location}/jenkins-rpm-builder.conf

when using tag parameter and having .spec.in in repository source root, it is used and @@version@@ tag is replaced by current version

wrapper could be used for building snapshot packages on packagers machine too. then not all the changes must be pushed to the upstream repo, they must be only localy commited.

currently the tool is used for building of rpm itself
