#!/bin/bash
# Launch Ventoy WebUI — close the terminal window when done
kitty --title "Ventoy Server" -e bash -c '
    sudo bash ~/bin/ventoy/VentoyWeb.sh &
    SERVER_PID=$!
    sleep 2
    xdg-open http://127.0.0.1:24680
    echo ""
    echo "Ventoy WebUI running at http://127.0.0.1:24680"
    echo "Press Enter or close this window to stop the server."
    read -r
    sudo kill $SERVER_PID 2>/dev/null
'
