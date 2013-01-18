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

define build by executable command

	bash /opt/jenkins-rpm-builder.sh <epel-5-x86_64|epel-6-x86_64> <snap|nosnap> <tag|notag> <sign|nosign>

where the params mean
  * **snap|nosnap** - build release readu or snapshot packages
  * **tag|notag** - base the snap build version on tag or on latest spec
  * **sign|nosign** - choose generating gpg signed or unsigned packages

examples of snapshot versions depending on combination of params
  * **snap+notag**: etnpol-tomcat-7.0-7.0.35.00.snap.20130117.154830.git.466b173-0.el6.noarch.rpm
  * **snap+tag**: etnpol-tomcat-7.0-7.0.27.99.snap.20130117.151837.git.466b173-0.el6.noarch.rpm
  * **nosnap+notag**: etnpol-tomcat-7.0-7.0.35-0.el5.noarch.rpm
  * **nosnap+tag**: etnpol-tomcat-7.0-7.0.27-0.el6.noarch.rpm

when using tag parameter and having .spec.in in repository source root, it is used and @@version@@ tag is replaced by current version




