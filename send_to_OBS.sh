#!/bin/bash

set -x
set -e

require_clean_work_tree () {
    # Update the index
    git update-index -q --ignore-submodules --refresh
    err=0

    # Disallow unstaged changes in the working tree
    if ! git diff-files --quiet --ignore-submodules --
    then
        echo >&2 "cannot $1: you have unstaged changes."
        git diff-files --name-status -r --ignore-submodules -- >&2
        err=1
    fi

    # Disallow uncommitted changes in the index
    if ! git diff-index --cached --quiet HEAD --ignore-submodules --
    then
        echo >&2 "cannot $1: your index contains uncommitted changes."
        git diff-index --cached --name-status -r --ignore-submodules HEAD -- >&2
        err=1
    fi

    if [ $err = 1 ]
    then
        echo >&2 "Please commit or stash them."
        exit 1
    fi
}

add_sha1_to_version() {
    sed -i "1s/)/git${HEADSHA1})/" debian/changelog
    sed -i "/Release:/s/$/git${HEADSHA1}/" rpm/*.spec
    git branch -f tmp_sha1
    git checkout tmp_sha1
    git add rpm/*.spec debian/changelog
    git commit -m"Temporary sha1 version"
}

rm_sha1_from_version() {
    git checkout -f $BRANCH
    git branch -D tmp_sha1
    git branch -D patch-queue/tmp_sha1
}

usage()
{
    cat <<EOF
    usage: $1 [-r] -p project [pkg]
       -p specifies the project
       -r specifies a 'real' release (no sha1)
       Send the current package to OBS
       if pkg is omitted uses the CWD name.

git can be setup to have a pristine branch and a packaging branch

There should be a debian/gbp.conf file specifing
debian-branch     (typically pkg or debian)
upstream-branch   (typically master)

In this case the .spec will use the .orig tarball and the .spec from
the rpm/ directory. Patches should be extracted from the debian/patches dir 
and applied with the .spec too.

You should be on the pkg branch to build a 'real' build.

If you do not specify -r then the debian-branch and upstream-branch
will be ignored and both will be force-set to the current branch.

If you are on any other branch then the current sha1 will be appended
to the Release.

EOF
    return 0
}

# Local config
# Base directory where project checkouts are placed
OBSBASE="~/obs/"
# Where git-buidlpackage is setup to produce builds, configured in
# /etc/git-buildpackage
BUILDAREA=/some/tmp/build-area
# NAMESPACE is optional dir under OBSBASE also used as apiurl alias with osc
# (setup in oscrc)
#NAMESPACE=

# Override above with personal values
if [ -e  "$HOME/.send_to_OBS.conf" ]; then
	. $HOME/.send_to_OBS.conf
else
	cat <<EOF >>$HOME/.send_to_OBS.conf
# Base directory where project checkouts are placed
OBSBASE=
# Where git-buidlpackage is setup to produce builds, configured in
# /etc/git-buildpackage
BUILDAREA=
# NAMESPACE is an apiurl alias with osc which is also used as a dir under OBSBASE
# (setup in oscrc)
NAMESPACE=
EOF
	echo "Please set the required configuration values in $HOME/.send_to_OBS.conf"
	exit 1
fi

if [[ ! -e $NAMESPACE ]] ; then
    OBSBASE=$OBSBASE/$NAMESPACE/
fi

OSC()
{
if [[ $NAMESPACE ]] ; then
    osc  -A $NAMESPACE $@
else
    osc $@
fi
}

# We need to be in a git repo
[[ ! -d .git ]] && { echo Not in a .git project ; exit 1 ; }

require_clean_work_tree

GITWD=$(pwd)

HEAD=$(git rev-parse HEAD)

BRANCH=$(git rev-parse --abbrev-ref HEAD)

trap "git checkout -f $BRANCH; exit" INT TERM EXIT

HEADSHA1=$(git rev-parse --short HEAD)

# Override the upstream/debian specified in gbp.conf (unless -r later)
USING_BRANCHES=" --git-debian-branch=$BRANCH --git-upstream-branch=$BRANCH "

REAL=no
while getopts "p:r" opt; do
    case $opt in
	p ) 
	    [[ -d $OBSBASE ]] || { echo no such dir $OBSBASE; exit 1; }
	    [[ -d $OBSBASE/$OPTARG ]] || { 
		echo attempt to get $OPTARG
		cd $OBSBASE
		OSC co $OPTARG
	    }

	    OBSPROJ=$(cd $OBSBASE/$OPTARG;pwd)
	    ;;
	r ) REAL=yes
	    # This is real - don't override the upstream/debian specified in gbp.conf
	    USING_BRANCHES=""
	    ;;
	\? ) usage
            exit 1;;
	* ) usage
            exit 1;;
    esac
done
shift $(($OPTIND - 1))

PACKAGE=${1:-$(basename $(pwd))}
OBSDIR=$OBSPROJ/$PACKAGE

[[ -d $OBSDIR ]] || { 
    echo attempt to get $PACKAGE from OBS
    cd $OBSPROJ
    OSC co $PACKAGE || OSC mkpac $PACKAGE
}
[[ ! -d $OBSDIR ]] && { echo $OBSDIR not present ; exit 1 ; }

[[ ! -d $BUILDAREA ]] && mkdir $BUILDAREA

BUILD=$(readlink -e $BUILDAREA)

cd $GITWD

VERSION=$(dpkg-parsechangelog -c1 | grep Version | cut -f2 -d" ")

# Check and tidy up hangover branches
git rev-parse -q --verify tmp_sha1 > /dev/null &&  git branch -D tmp_sha1
git rev-parse -q --verify patch-queue/tmp_sha1 > /dev/null &&  git branch -D patch-queue/tmp_sha1

echo "################################################################"
echo Make debian package
echo Debian : $VERSION

# Clean any old build stuff
if [[ -f debian/gbp.conf ]]; then
    GBP="yes"
    UP_BRANCH=$(grep upstream-branch= debian/gbp.conf | cut -f2 -d=)
    #PKG_BRANCH=$(grep debian-branch= debian/gbp.conf | cut -f2 -d=)
    PKG_BRANCH=${PKG_BRANCH:-${BRANCH}}
    [[ -d $BUILD ]] || mkdir $BUILD
    rm -rf $BUILD/*
    echo About to build
    # Make the debian.tar.gz and dsc
    git checkout $PKG_BRANCH
    if [[ $REAL == "no" ]]; then
	add_sha1_to_version
    fi
    git-buildpackage --git-ignore-new -S -uc -us -tc $USING_BRANCHES
else
    GBP="no"
    if [[ $REAL == "no" ]]; then
	add_sha1_to_version
    fi
    dpkg-buildpackage -S -uc -us -tc
fi

# If we have GBP then apply patches (in debian/) for any gem build
if [[ $GBP == "yes" ]]; then
    if [ -d "debian/patches" ] ; then
		gbp-pq import
	fi
fi

# See if we're ruby
RUBY=no
if [[ -n "$(find . -maxdepth 1 -name '*.gemspec' -print -quit)" ]]; then
    echo Building *.gemspec
    for i in *.gemspec; do
	gem build $i
	RUBY=yes
    done
elif [[ -n "$(find . -maxdepth 1 -name '*.yml' -print -quit)" ]]; then
    echo Building *.yml
    for i in *.yml; do
	gem build $i
	RUBY=yes
    done
elif [[ -e Rakefile ]]; then
    # Try a rake gem
    rake gem
    RUBY=yes
fi

# And restore us to the debian branch
if [[ $GBP == "yes" ]]; then
    git checkout $PKG_BRANCH
    gbp-pq drop || true
fi

echo "################################################################"
echo Sending to OBS

# Update to ensure we can overwrite - git is master
(cd $OBSDIR; OSC up) || true

# Build succeeded - clean out the OBS dir and use new tarballs
find $OBSDIR -mindepth 1 -maxdepth 1 -type f -name "[^_]*" -print0 | xargs -0 rm -f 

if [[ $GBP == "yes" ]]; then
    mv $BUILD/* $OBSDIR/
else
    # Move any version specifics
    mv ../*$VERSION* $OBSDIR
    # copy any orig tarballs
    cp -a ../*orig* $OBSDIR || true
fi

# Copy over anything in rpm/
cp rpm/* $OBSDIR/ 2>/dev/null || true

# and over any gem file, possibly in pkg/
mv *.gem $OBSDIR/ 2>/dev/null || true
mv pkg/*.gem $OBSDIR/ 2>/dev/null || true

# Send it to the OBS (should this use the changelog entry?)
dpkg-parsechangelog -c1 | (
    cd $OBSDIR
    # Rename symlinks to truename for OBS
    (l=$(find . -maxdepth 1 -type l -print -quit) && t=$(readlink $l) && rm $l && mv $t $l) || true
    OSC ar
    OSC ci --skip-validation
)

if [[ $REAL == "no" ]]; then
    rm_sha1_from_version
fi    


# Debian Package Dependencies
# git-buildpackage
# gem2deb

# Using send_to_OBS.sh to update a gem
######################################
# Checkout master
# pull from remote
# git pull master
# git checkout debian
# git merge master
# Go to debian/
## Edit changelog, increase version
## include upstream change comments
## Update control if Rakefile changed deps
# Go to rpm/
## Manually update rpm Version
## include upstream change comments
# Commit changelog/spec changes
# Stay on debian/pkg branch
# run /maemo/devel/BOSS/send_to_OBS.sh -p home:lbt:MINT
