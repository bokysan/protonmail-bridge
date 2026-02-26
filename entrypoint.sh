#!/usr/bin/env bash
set -e

# Initialize
if [[ $1 == init ]]; then

    # Initialize pass
    gpg --generate-key --batch /protonmail/gpgparams
    pass init pass-key
    
    # Login
    /opt/protonmail/proton-bridge --cli "${@:2}"

elif [[ $# -eq 0 ]]; then
    # No arguments, run supervisord to manage all processes
    exec /usr/local/bin/supervisord -c /etc/supervisord.conf
else
    # Pass all arguments directly to protonmail-bridge --cli
    exec /opt/protonmail/proton-bridge --cli "$@"
fi