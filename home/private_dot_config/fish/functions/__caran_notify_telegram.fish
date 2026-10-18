function __caran_notify_telegram --description 'Send a message through the Telegram bot of NOTIFY_TELEGRAM_BOT_TOKEN'
    # Set both in secret.fish or per_machine.fish; nothing is sent without them
    set -q NOTIFY_TELEGRAM_BOT_TOKEN NOTIFY_TELEGRAM_CHAT_ID; or return 0
    type -q curl; or return 0
    # The URL holding the token goes through stdin, so it never shows in `ps`
    printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' $NOTIFY_TELEGRAM_BOT_TOKEN \
        | command curl -fsS -m 10 -K - \
        --data-urlencode "chat_id=$NOTIFY_TELEGRAM_CHAT_ID" \
        --data-urlencode "text=$argv[1]" >/dev/null 2>&1 &
    disown 2>/dev/null
end
