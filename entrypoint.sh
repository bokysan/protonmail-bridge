#!/usr/bin/env bash
set -Eeuo pipefail

# Initialize
if [[ $# -gt 0 ]] && [[ $1 == init ]]; then
    echo "Initializing ProtonMail Bridge..."
    cd /home/protonmail
    gosu protonmail:protonmail gpg --generate-key --batch /protonmail/gpgparams
    gosu protonmail:protonmail pass init pass-key
    gosu protonmail:protonmail /usr/local/bin/proton-bridge --cli "${@:2}"
elif [[ $# -eq 0 ]]; then
    # No arguments, run supervisord to manage all processes
    echo "Starting ProtonMail Bridge with supervisord..."
    exec /usr/local/bin/supervisord -c /etc/supervisord.conf
else
    # Pass all arguments directly to proton-bridge --cli
    echo "Running ProtonMail Bridge with provided arguments: $*"
    cd /home/protonmail
    exec gosu protonmail:protonmail /usr/local/bin/proton-bridge --cli "$@"
fi