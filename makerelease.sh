#!/bin/zsh

if [ -z "$1" ]; then
    echo "Syntax: $0 <version>"
    exit 1
fi
VERSION=$1

DEST=`basename $PWD`

rm -rf ~/${DEST}/ ~/${DEST}-$VERSION.zip
cp -a . ~/${DEST}/
cd ~/
rm -rf ${DEST}/Libs/GeminiGUI/examples
find ${DEST} -name '.git*' -o -name "*~" -o -name "makerelease.sh" -o -name '#*#' |xargs rm -rf

zip -r ${DEST}-$VERSION.zip $DEST
rm -rf $DEST
