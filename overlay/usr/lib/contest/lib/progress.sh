#!/usr/bin/env bash

# Copy one file while rendering byte-based progress on stderr.
copy_file_with_progress() {
    local source="$1"
    local destination="$2"
    local label="${3:-${source##*/}}"
    local total_bytes copied_bytes copy_pid
    local interval="${COPY_PROGRESS_INTERVAL:-0.2}"

    total_bytes="$(stat -c '%s' -- "${source}")" || return 1
    rm -f -- "${destination}"

    cp -- "${source}" "${destination}" &
    copy_pid=$!

    while kill -0 "${copy_pid}" 2>/dev/null; do
        copied_bytes="$(stat -c '%s' -- "${destination}" 2>/dev/null || printf '0')"
        render_copy_progress "${label}" "${copied_bytes}" "${total_bytes}"
        sleep "${interval}"
    done

    if ! wait "${copy_pid}"; then
        printf '\n' >&2
        return 1
    fi

    render_copy_progress "${label}" "${total_bytes}" "${total_bytes}"
    printf '\n' >&2
}

render_copy_progress() {
    local label="$1"
    local copied_bytes="$2"
    local total_bytes="$3"
    local width=30
    local percent filled empty filled_bar empty_bar

    if [ "${total_bytes}" -gt 0 ]; then
        [ "${copied_bytes}" -le "${total_bytes}" ] || copied_bytes="${total_bytes}"
        percent=$((copied_bytes * 100 / total_bytes))
    else
        percent=100
    fi

    filled=$((percent * width / 100))
    empty=$((width - filled))
    printf -v filled_bar '%*s' "${filled}" ''
    printf -v empty_bar '%*s' "${empty}" ''
    filled_bar="${filled_bar// /#}"

    printf '\r  [%s%s] %3d%% %s' \
        "${filled_bar}" "${empty_bar}" "${percent}" "${label}" >&2
}
