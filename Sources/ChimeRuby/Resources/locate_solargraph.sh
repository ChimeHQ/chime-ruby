#!/usr/bin/env bash

set -xo pipefail

# can we bundle-exec?
SERVER_VERSION=`bundle exec --no-color solargraph -v`
STATUS=$?
if [ -n "$SERVER_VERSION" ] && [ $STATUS -eq 0 ]; then
    echo "{\"command\": \"bundle\", \"arguments\": [\"exec\", \"--no-color\", \"solargraph\"], \"version\":\"$SERVER_VERSION\"}"
    exit 0
fi

# is it in our path?
SERVER_VERSION=`solargraph -v`
STATUS=$?
if [ -n "$SERVER_VERSION" ] && [ $STATUS -eq 0  ]; then
    echo "{\"command\": \"solargraph\", \"arguments\": [], \"version\":\"$SERVER_VERSION\"}"
    exit 0
fi

# determine ruby version
RUBY_VERSION=`ruby -e "puts RUBY_VERSION"`
STATUS=$?
if [ -z "$RUBY_VERSION" ] || [ $STATUS -ne 0 ]; then
    exit 1
fi

GEM_PATH=`gem environment gempath`

# we're going to attempt to install a private copy of the gem
CHIME_RUBY_PATH="${HOME}/Library/Caches/com.chimehq.Edit/Ruby/$RUBY_VERSION"
CHIME_GEM_HOME="${CHIME_RUBY_PATH}/gems"
CHIME_GEM_PATH="$CHIME_GEM_HOME:$GEM_PATH"

export GEM_HOME=$CHIME_GEM_HOME
export GEM_PATH=$CHIME_GEM_PATH

SERVER_VERSION=`${CHIME_GEM_HOME}/bin/solargraph -v`
STATUS=$?
if [ -z "$SERVER_VERSION" ] || [ "$1" == "-u" ] || [ $STATUS -ne 0 ]; then
    mkdir -p $CHIME_RUBY_PATH

    gem install -N solargraph -v '>= 0.44.3' 1>&2
    gem cleanup 1>&2

    # reload the version
    SERVER_VERSION=`${CHIME_GEM_HOME}/bin/solargraph -v`
fi

echo "{\"command\": \"${CHIME_GEM_HOME}/bin/solargraph\", \"arguments\": [], \"version\":\"$SERVER_VERSION\", \"environment\": {\"GEM_HOME\": \"$CHIME_GEM_HOME\", \"GEM_PATH\": \"$CHIME_GEM_PATH\"}}"
