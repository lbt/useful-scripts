#!/bin/bash -x

set -e

usage()
{
    cat <<EOF
    usage: $1 -p project pkg
       Send the current package to OBS
EOF
    return 0
}

OBSPROJ="/maemo/devel/BOSS/home:lbt"

while getopts "p:" opt; do
    case $opt in
	p ) OBSPROJ=$(cd $OPTARG;pwd);;
	\? ) usage
            exit 1;;
	* ) usage
            exit 1;;
    esac
done
shift $(($OPTIND - 1))

PACKAGE=$1
OBSDIR=$OBSPROJ/$PACKAGE
BUILD=$(readlink -e ../build-area)

[[ ! -n $PACKAGE ]] && { echo Specify a package ; exit 1 ; }
[[ ! -d $OBSDIR ]] && { echo $OBSDIR not present ; exit 1 ; }

VERSION=$(dpkg-parsechangelog -c1 | grep Version | cut -f2 -d" ")

echo "################################################################"
echo Make debian package
echo Debian : $VERSION

# Clean any old build stuff
if [[ -f debian/gbp.conf ]]; then
    GBP="yes"
    [[ -d $BUILD ]] || mkdir $BUILD
    rm -rf $BUILD/*
    echo About to build
    # Make the debian.tar.gz and dsc
    git checkout debian
    git-buildpackage --git-ignore-new -S -uc -us -tc
else
    GBP="no"
    dpkg-buildpackage -S -uc -us -tc
fi

# Make the gem
echo "################################################################"
echo Make gem
# If we have GBP then apply patches (in debian/) for any gem build
if [[ $GBP == "yes" ]]; then
    gbp-pq import
fi
if [[ -n "$(find . -maxdepth 1 -name '*.gemspec' -print -quit)" ]]; then
    echo Building *.gemspec
    for i in *.gemspec; do
	gem build $i
    done
elif [[ -n "$(find . -maxdepth 1 -name '*.yml' -print -quit)" ]]; then
    echo Building *.yml
    for i in *.yml; do
	gem build $i
    done
else
    # Try a rake gem
    rake gem || true
fi
# And restore us to the debian branch
if [[ $GBP == "yes" ]]; then
    git checkout debian
    gbp-pq drop 
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
    mv ../*$VERSION* $OBSDIR
    cp ../*orig* $OBSDIR || true
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
