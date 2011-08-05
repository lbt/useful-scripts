#!/bin/bash -x

set -e

usage()
{
    cat <<EOF
    usage: $1 -p project [pkg]
       Send the current package to OBS
       if pkg is omitted uses the CWD name.

git should be setup to have a pristine branch and a packaging branch
There should be a debian/gbp.conf file specifing
debian-branch     (typically...)
upstream-branch   (typically master)

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

BRANCH=$(git status -bs | grep '##' | cut -d' ' -f2)

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
# Build succeeded - clean out the OBS dir and use new tarballs
rm -f $OBSDIR/*

# is there a gem here?
if [[ -n "$(find . -maxdepth 1 -name '*.gem' -print -quit)" ]]; then
    rm -f $OBSDIR/*gem
fi


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

# Update to ensure we can overwrite - git is master
(cd $OBSDIR; osc up)

# Send it to the OBS (should this use the changelog entry?)
dpkg-parsechangelog -c1 | (
    cd $OBSDIR
    # Rename symlinks to truename for OBS
    (l=$(find . -maxdepth 1 -type l -print -quit) && t=$(readlink $l) && rm $l && mv $t $l) || true
    osc ar
    osc ci
)
