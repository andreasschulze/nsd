#!/bin/sh

# Build a NSD distribution tar from the SVN repository.

# Abort script on unexpected errors.
set -e

# Remember the current working directory.
cwd=`pwd`

# Utility functions.
usage () {
    cat >&2 <<EOF
Usage $0: [-h] [-s] [-d SVN_root]
Generate a distribution tar file for NSD.

    -h           This usage information.
    -s           Build a snapshot distribution file.  The current date is
                 automatically appended to the current NSD version number.
    -d SVN_root  Retrieve the NSD source from the specified repository.
EOF
    exit 1
}

info () {
    echo "$0: info: $1"
}

error () {
    echo "$0: error: $1" >&2
    exit 1
}

question () {
    printf "%s (y/n) " "$*"
    read answer
    case "$answer" in
        [Yy]|[Yy][Ee][Ss])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Only use cleanup and error_cleanup after generating the temporary
# working directory.
cleanup () {
    info "Deleting temporary working directory."
    cd $cwd && rm -rf $temp_dir
}

error_cleanup () {
    echo "$0: error: $1" >&2
    cleanup
    exit 1
}

replace_text () {
    (cp "$1" "$1".orig && \
        sed -e "s/$2/$3/g" < "$1".orig > "$1" && \
        rm "$1".orig) || error_cleanup "Replacement for $1 failed."
}

replace_all () {
    info "Updating '$1' with the version number."
    replace_text "$1" "@version@" "$version"
    info "Updating '$1' with today's date."
    replace_text "$1" "@date@" "`date +'%b %e, %Y'`"
}
    

SNAPSHOT="no"

# Parse the command line arguments.
while [ "$1" ]; do
    case "$1" in
        "-h")
            usage
            ;;
        "-d")
            SVNROOT="$2"
            shift
            ;;
        "-s")
            SNAPSHOT="yes"
            ;;
        *)
            error "Unrecognized argument -- $1"
            ;;
    esac
    shift
done

# Check if SVNROOT is specified.
if [ -z "$SVNROOT" ]; then
    error "SVNROOT must be specified (using -d)"
fi

# Start the packaging process.
info "SVNROOT  is $SVNROOT"
info "SNAPSHOT is $SNAPSHOT"

question "Do you wish to continue with these settings?" || error "User abort."


# Creating temp directory
info "Creating temporary working directory"
temp_dir=`mktemp -d nsd-dist-XXXXXX`
info "Directory '$temp_dir' created."
cd $temp_dir

info "Exporting source from SVN."
svn export "$SVNROOT" nsd || error_cleanup "SVN command failed"

cd nsd || error_cleanup "NSD not exported correctly from SVN"

info "Building configure script (autoconf)."
autoconf || error_cleanup "Autoconf failed."

info "Building config.h.in (autoheader)."
autoheader || error_cleanup "Autoheader failed."

rm -r autom4te* || error_cleanup "Failed to remove autoconf cache directory."

info "Building lexer and parser."
flex -i -ozlexer.c zlexer.lex || error_cleanup "Failed to create lexer."
bison -y -d -o zparser.c zparser.y || error_cleanup "Failed to create parser."

find . -name .c-mode-rc.el -exec rm {} \;
find . -name .cvsignore -exec rm {} \;
rm makedist.sh || error_cleanup "Failed to remove makedist.sh."

info "Determining NSD version."
version=`./configure --version | head -1 | awk '{ print $3 }'` || \
    error_cleanup "Cannot determine version number."

info "NSD version: $version"

if [ "$SNAPSHOT" = "yes" ]; then
    info "Building NSD snapshot."
    version="$version-`date +%Y%m%d`"
    info "Snapshot version number: $version"
fi

replace_all README
replace_all nsd.8
replace_all nsdc.8
replace_all nsd-notify.8
replace_all zonec.8

info "Renaming NSD directory to nsd-$version."
cd ..
mv nsd nsd-$version || error_cleanup "Failed to rename NSD directory."

tarfile="../nsd-$version.tar.gz"

if [ -f $tarfile ]; then
    (question "The file $tarfile already exists.  Overwrite?" \
        && rm -f $tarfile) || error_cleanup "User abort."
fi

info "Creating tar nsd-$version.tar.gz"
tar czf ../nsd-$version.tar.gz nsd-$version || error_cleanup "Failed to create tar file."

cleanup

case $OSTYPE in
        linux*)
                md5=`md5sum nsd-$version.tar.gz |  awk '{ print $1 }'`
                ;;
        freebsd*)
                md5=` md5  nsd-$version.tar.gz |  awk '{ print $5 }'`
                ;;
esac
cat $md5 > nsd-$version.tar.gz.md5

info "NSD distribution created successfully."
info "MD5sum: $md5"

