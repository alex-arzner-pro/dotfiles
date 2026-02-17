#!/bin/bash
# Launch Ventoy WebUI — close the terminal window when done
kitty --title "Ventoy Server" -e bash -c '
    # Get sudo credentials first
    sudo -v || exit 1
    echo "Starting Ventoy WebUI..."
    sudo bash ~/bin/ventoy/VentoyWeb.sh &
    SERVER_PID=$!
    # Wait for server to be ready
    for i in $(seq 1 10); do
        curl -s http://127.0.0.1:24680 >/dev/null 2>&1 && break
        sleep 1
    done
    xdg-open http://127.0.0.1:24680
    echo ""
    echo "Ventoy WebUI running at http://127.0.0.1:24680"
    echo "Press Enter or close this window to stop the server."
    read -r
    sudo kill $SERVER_PID 2>/dev/null
'
