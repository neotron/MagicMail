#!/bin/zsh

if [ -z "$1" ]; then
    echo "Syntax: $0 <version>"
    exit 1
fi
VERSION=$1

DEST=MagicMail-$VERSION

rm -rf ~/${DEST}/ ~/${DEST}.zip
cp -a . ~/${DEST}/
cd ~/
rm -rf ${DEST}/Libs/GeminiGUI/examples
find ${DEST} -name '.git*' -o -name "*~" -o -name "makerelease.sh" |xargs rm -rf

zip -r ${DEST}.zip $DEST
rm -rf $DEST
