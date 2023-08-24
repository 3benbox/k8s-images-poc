#!/bin/sh
set -e

cd /data
rm -Rf .git || true
git init
git remote add origin "$GIT_URL"
git fetch origin "$GIT_REVISION"
git checkout "$GIT_REVISION"
ls -l