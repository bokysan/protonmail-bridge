#!/usr/bin/env bash
set -Eeuo pipefail

# Initialize
if [[ $1 == init ]]; then
    echo "Initializing ProtonMail Bridge..."
    cd /home/protonmail
    gosu protonmail:protonmail gpg --generate-key --batch /protonmail/gpgparams
    gosu protonmail:protonmail pass init pass-key
    gosu protonmail:protonmail /bin/protonmail-bridge --cli "${@:2}"
elif [[ $# -eq 0 ]]; then
    # No arguments, run supervisord to manage all processes
    echo "Starting ProtonMail Bridge with supervisord..."
    exec /usr/local/bin/supervisord -c /etc/supervisord.conf
else
    # Pass all arguments directly to protonmail-bridge --cli
    echo "Running ProtonMail Bridge with provided arguments: $*"
    cd /home/protonmail
    exec gosu protonmail:protonmail /bin/protonmail-bridge --cli "$@"
fi