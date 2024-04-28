#!/bin/bash

ICLOUD_USE=${ICLOUD_USE:-~/Documents/devel/repos}
hugo=${ICLOUD_USE}/mysite
public=${ICLOUD_USE}/deploy

abort ()
{
    echo -e "\033[1;30m>\033[0;31m>\033[1;31m> ERROR:\033[0m${@}\n" && exit
}

info ()
{
    echo -e "\033[1;30m>\033[0;36m>\033[1;36m> \033[0m${@}\n"
}

warn ()
{
    echo -e "\033[1;30m>\033[0;33m>\033[1;33m> \033[0m${@}\n"
}

cover ()
{
    case ${m} in
        01|05|09)
            echo 01 05 09;;
        02|06|10)
            echo 02 06 10;;
        03|07|11)
            echo 03 07 11;;
        04|08|12)
            echo 04 08 12;;
    esac
}

test -d ${hugo} && cd ${hugo} || abort "${hogo} directory not found."
# clean public
rm -fr public

# set cover
m=$(date "+%m")
info "Put cover image post directory"
cd ${hugo}/content/post && \
    for f in $(ls --color=none *.md)
    do
        d=$(basename $f .md)
        if [ -d ${d} ]; then
            test -f ${d}/cover.* || cp ${hugo}/assets/img/cover/${m}.jpg ${d}
        else
            mkdir ${d}
            cp ${hugo}/assets/img/cover/${m}.jpg ${d}
        fi
    done

info "Deploying updates to GitHub..."
cd ${hugo}
# Build the project.
hugo # if using a theme, replace with `hugo -t <YOURTHEME>`

# Go To Public folder
test -d ${public} && cd ${public} || abort "${public} not found."
info "rsync.."
rsync -at --delete --exclude=".git" ${hugo}/public/. .

# Add changes to git.
git add .
git commit -avm "update:$(env LANG=C date)" && git push
