#!/usr/bin/env bash

telegram_api_call() {
    local method="$1" response_file="$2" label="$3"; shift 3
    local err_file http_code curl_err attempt=1 sleep_secs
    err_file="$(mktemp)"

    while [ "$attempt" -le "${TELEGRAM_MAX_RETRIES:-3}" ]; do
        http_code=$(curl -s -o "$response_file" -w "%{http_code}" \
            --max-time "${TELEGRAM_API_TIMEOUT:-60}" \
            --retry 0 \
            -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/${method}" \
            "$@" 2>"$err_file") || http_code="000"

        TG_RESPONSE=$(cat "$response_file" 2>/dev/null || echo "")

        if [ "$http_code" = "200" ] && echo "$TG_RESPONSE" | grep -q '"ok":true'; then
            rm -f "$err_file"
            return 0
        fi

        curl_err=$(cat "$err_file" 2>/dev/null || echo "")
        case "$http_code" in
            000|429|500|502|503|504)
                warn "${label} failed: HTTP ${http_code} — will retry. ${curl_err}"
                ;;
            *)
                warn "${label} FAILED: HTTP ${http_code} (non-retryable). Response: ${TG_RESPONSE}"
                rm -f "$err_file"
                return 1
                ;;
        esac

        if [ "$attempt" -lt "${TELEGRAM_MAX_RETRIES:-3}" ]; then
            sleep_secs=$(( 2 ** attempt ))
            log "⏳ Retrying in ${sleep_secs}s..."
            sleep "$sleep_secs"
        fi
        attempt=$(( attempt + 1 ))
    done

    rm -f "$err_file"
    return 1
}
