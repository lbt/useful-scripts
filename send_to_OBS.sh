#!/bin/bash -x

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

usage()
{
    cat <<EOF
    usage: $1 -p project [pkg]
       Send the current package to OBS
       if pkg is omitted uses the CWD name.

git should be setup to have a pristine branch and a packaging branch
There should be a debian/gbp.conf file specifing
debian-branch     (typically pkg or debian)
upstream-branch   (typically master)

You should be on the pkg branch to build a proper build

If you are on any other branch then the current sha1 will be appended
to the Release.

EOF
    return 0
}

# Local config
OBSBASE="~/obs/"
BUILDAREA=/some/tmp/build-area

# Override above with personal values
. ~/.send_to_OBS.conf

# We need to be in a git repo
[[ ! -d .git ]] && { echo Not in a .git project ; exit 1 ; }

require_clean_work_tree

BRANCH=$(git status -bs | grep '##' | cut -d' ' -f2)

HEAD=$(git show-ref -s HEAD --abbrev)

while getopts "p:" opt; do
    case $opt in
	p ) 
	    [[ -d $OBSBASE ]] || { echo no such dir $OBSBASE; exit 1; }
	    [[ -d $OBSBASE/$OPTARG ]] || { 
		echo attempt to get $OPTARG
		cd $OBSBASE
		osc co $OPTARG
	    }
	    OBSPROJ=$(cd $OBSBASE/$OPTARG;pwd)
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
    osc co $PACKAGE
}
[[ ! -d $OBSDIR ]] && { echo $OBSDIR not present ; exit 1 ; }

BUILD=$(readlink -e $BUILDAREA)

VERSION=$(dpkg-parsechangelog -c1 | grep Version | cut -f2 -d" ")

echo "################################################################"
echo Make debian package
echo Debian : $VERSION

# Clean any old build stuff
if [[ -f debian/gbp.conf ]]; then
    GBP="yes"
    UP_BRANCH=$(grep upstream-branch= debian/gbp.conf | cut -f2 -d=)
    DEB_BRANCH=$(grep debian-branch= debian/gbp.conf | cut -f2 -d=)
    DEB_BRANCH=${DEB_BRANCH:-${BRANCH}}
    [[ -d $BUILD ]] || mkdir $BUILD
    rm -rf $BUILD/*
    echo About to build
    # Make the debian.tar.gz and dsc
    git checkout $DEB_BRANCH
    git-buildpackage --git-ignore-new -S -uc -us -tc
else
    GBP="no"
    dpkg-buildpackage -S -uc -us -tc
fi

# If we have GBP then apply patches (in debian/) for any gem build
if [[ $GBP == "yes" ]]; then
    gbp-pq import
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
    git checkout $DEB_BRANCH
    gbp-pq drop || true
fi

echo "################################################################"
echo Sending to OBS

# Update to ensure we can overwrite - git is master
(cd $OBSDIR; osc up)

# Build succeeded - clean out the OBS dir and use new tarballs
rm -f $OBSDIR/*

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
    osc ar
    osc ci
)

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
