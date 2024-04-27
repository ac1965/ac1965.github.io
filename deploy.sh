#!/bin/bash

ICLOUD_USE=${ICLOUD_USE:-"~/Documents/devel/repos"}
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

test -d ${hugo} && cd ${hugo} || abort "${hogo} directory not found."
# clean public
rm -fr public

info "Deploying updates to GitHub..."

# Build the project.
hugo # if using a theme, replace with `hugo -t <YOURTHEME>`

# Go To Public folder
test -d ${public} && cd ${public} || abort "${public} not found."
info "rsync.."
rsync -at --delete --exclude=".git" ${hugo}/public/. .

# Add changes to git.
git add .
git commit -avm "update:$(env LANG=C date)" && git push
