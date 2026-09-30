#!/bin/zsh
set -e
cd "${0:A:h}"
if [[ ! -x 'Candlepoint Menu.app/Contents/MacOS/CandlepointMenu' ]]; then
  ./build_app.command
fi
open "Candlepoint Menu.app"
