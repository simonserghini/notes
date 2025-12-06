#!/bin/bash

C_RESET="\e[0m"
C_BOLD="\e[1m"
C_DIM="\e[2m"
C_BLUE="\e[34m"
C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_CYAN="\e[36m"
C_RED="\e[31m"
C_MAGENTA="\e[35m"
C_SELECTED="\e[7m"

if [ -t 0 ] && [ -t 1 ]; then
    RUN_APP=true
else
    RUN_APP=false
fi

install_notes() {
    echo -e "${C_BLUE}╔════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_BLUE}║${C_RESET}       ${C_GREEN}Installing Notes Manager (Local)${C_RESET}          ${C_BLUE}║${C_RESET}"
    echo -e "${C_BLUE}╚════════════════════════════════════════════════════════════╝${C_RESET}"
    echo

    SHELL_CONFIG=""
    if [ -n "$BASH_VERSION" ]; then
        SHELL_CONFIG="$HOME/.bashrc"
    elif [ -n "$ZSH_VERSION" ]; then
        SHELL_CONFIG="$HOME/.zshrc"
    else
        case "$SHELL" in
            */bash) SHELL_CONFIG="$HOME/.bashrc" ;;
            */zsh) SHELL_CONFIG="$HOME/.zshrc" ;;
            *) SHELL_CONFIG="$HOME/.profile" ;;
        esac
    fi

    echo -e "${C_YELLOW}→${C_RESET} Detected shell config: $SHELL_CONFIG"

    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR"
    echo -e "${C_GREEN}✓${C_RESET} Created $INSTALL_DIR"

    echo -e "${C_YELLOW}→${C_RESET} Installing notes manager (copying local file)..."

    # Copy this running script to the install location
    cp "$0" "$INSTALL_DIR/notes"
    chmod +x "$INSTALL_DIR/notes"
    echo -e "${C_GREEN}✓${C_RESET} Installed notes manager"

    if ! command -v notes &>/dev/null || [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo -e "${C_YELLOW}→${C_RESET} Adding to PATH"
        if ! grep -q 'export PATH=.*\.local/bin' "$SHELL_CONFIG" 2>/dev/null; then
            echo "" >> "$SHELL_CONFIG"
            echo "# Added by notes manager" >> "$SHELL_CONFIG"
            echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$SHELL_CONFIG"
        fi
        echo -e "${C_GREEN}✓${C_RESET} Added to PATH"
        export PATH="$HOME/.local/bin:$PATH"
    else
        echo -e "${C_GREEN}✓${C_RESET} Already in PATH"
    fi

    mkdir -p "$HOME/.notes" "$HOME/.notes/.archive" "$HOME/.config"
    echo -e "${C_GREEN}✓${C_RESET} Created notes directory"

    CONFIG_FILE="$HOME/.config/arch-notes"
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << 'EOF'
export APP_EDITOR="${EDITOR:-vim}"
export SORT_MODE="date"
export SHOW_PREVIEW_LINES=1
EOF
        echo -e "${C_GREEN}✓${C_RESET} Created configuration"
    fi

    echo
    echo -e "${C_BLUE}╔════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_BLUE}║${C_RESET}             ${C_GREEN}Installation Complete!${C_RESET}               ${C_BLUE}║${C_RESET}"
    echo -e "${C_BLUE}╚════════════════════════════════════════════════════════════╝${C_RESET}"
    echo
    echo -e "Run ${C_GREEN}${C_BOLD}notes${C_RESET} to start in a new terminal."
    echo
}

run_notes_app() {
    NOTES_DIR="$HOME/.notes"
    ARCHIVE_DIR="$HOME/.notes/.archive"
    CONFIG_FILE="$HOME/.config/arch-notes"
    
    mkdir -p "$NOTES_DIR" "$ARCHIVE_DIR" "$HOME/.config"

    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE" 2>/dev/null
    fi
    
    APP_EDITOR="${APP_EDITOR:-vim}"
    SORT_MODE="${SORT_MODE:-date}"
    SHOW_PREVIEW_LINES="${SHOW_PREVIEW_LINES:-1}"

    PINNED_NOTES=()
    FILTER=""
    VIEW_MODE="all"

    list_notes() {
        local ALL_NOTES=()
        case "$SORT_MODE" in
            date) mapfile -t ALL_NOTES < <(ls -1t "$NOTES_DIR" 2>/dev/null | grep -v "^\.") ;;
            name) mapfile -t ALL_NOTES < <(ls -1 "$NOTES_DIR" 2>/dev/null | grep -v "^\.") ;;
            size) mapfile -t ALL_NOTES < <(ls -1S "$NOTES_DIR" 2>/dev/null | grep -v "^\.") ;;
        esac
        
        if [ -n "$FILTER" ]; then
            mapfile -t NOTES < <(printf '%s\n' "${ALL_NOTES[@]}" | grep -i "$FILTER")
        else
            NOTES=("${ALL_NOTES[@]}")
        fi
        
        TOTAL=${#NOTES[@]}
    }

    is_pinned() {
        local file="$1"
        for pinned in "${PINNED_NOTES[@]}"; do
            [[ "$pinned" == "$file" ]] && return 0
        done
        return 1
    }

    note_preview() {
        local file="$1"
        local filepath="$NOTES_DIR/$file"
        
        local preview=""
        if [ "$SHOW_PREVIEW_LINES" -eq 1 ]; then
            preview=$(head -n1 "$filepath" 2>/dev/null | sed 's/[[:space:]]*$//' | cut -c1-50)
        else
            preview=$(head -n"$SHOW_PREVIEW_LINES" "$filepath" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//' | cut -c1-50)
        fi
        [ -z "$preview" ] && preview="(empty)"
        
        local date_stat=$(stat -c "%y" "$filepath" 2>/dev/null)
        local date_short=$(date -d "${date_stat%%.*}" "+%b %d %H:%M" 2>/dev/null)
        local size=$(stat -c "%s" "$filepath" 2>/dev/null)
        local size_str="${size}B"
        [ $size -gt 1048576 ] && size_str="$((size/1048576))MB"
        [ $size -gt 1024 ] && [ $size -le 1048576 ] && size_str="$((size/1024))KB"
        local words=$(wc -w < "$filepath" 2>/dev/null | awk '{print $1}')
        
        local pin_icon=""
        is_pinned "$file" && pin_icon="${C_YELLOW}P${C_RESET} "
        
        printf "%s%s | %s | %sw | %s" "$pin_icon" "$date_short" "$size_str" "$words" "$preview"
    }

    show_menu() {
        tput reset
        tput cup 0 0
        HEIGHT=$(tput lines)
        WIDTH=$(tput cols)
        
        local view_label="ALL NOTES"
        
        echo -e "${C_BOLD}${C_CYAN}╔$(printf '%*s' $((WIDTH-2)) | tr ' ' '═')╗${C_RESET}"
        echo -e "${C_BOLD}${C_CYAN}║${C_RESET}  $(printf '%*s' $(((WIDTH-22)/2)))${C_BOLD}${C_GREEN}$view_label${C_RESET}$(printf '%*s' $(((WIDTH-22)/2)))${C_BOLD}${C_CYAN}║${C_RESET}"
        echo -e "${C_BOLD}${C_CYAN}╚$(printf '%*s' $((WIDTH-2)) | tr ' ' '═')╝${C_RESET}"
        
        echo -e "${C_DIM}j/k:nav o:open i:preview n:new r:rename d:del p:pin t:sort f:filter a:stats e:editor m:menu q:quit${C_RESET}"
        echo -e "${C_BOLD}${C_BLUE}$(printf '%*s' $WIDTH | tr ' ' '─')${C_RESET}"
        echo
        
        HEADER=7
        FOOTER=3
        WIN_HEIGHT=$((HEIGHT-HEADER-FOOTER))
        [ $WIN_HEIGHT -lt 1 ] && WIN_HEIGHT=1
        
        START=$((CUR-WIN_HEIGHT/2))
        [ $START -lt 0 ] && START=0
        END=$((START+WIN_HEIGHT))
        [ $END -gt $TOTAL ] && END=$TOTAL
        [ $((END-START)) -lt $WIN_HEIGHT ] && START=$((END-WIN_HEIGHT))
        [ $START -lt 0 ] && START=0
        
        if [ $TOTAL -eq 0 ]; then
            echo -e "${C_DIM}  No notes. Press 'n' to create one or 'm' for menu!${C_RESET}"
            for ((i=1; i<WIN_HEIGHT; i++)); do 
                tput el; echo
            done
        else
            local displayed=0
            for i in $(seq $START $((END-1))); do
                local line_content="$(note_preview "${NOTES[$i]}")"
                if [[ $i -eq $CUR ]]; then
                    printf "${C_SELECTED}${C_BOLD} ► %-${WIDTH}s${C_RESET}\n" "$line_content"
                else
                    printf "${C_DIM}  %-${WIDTH}s${C_RESET}\n" "$line_content"
                fi
                tput el
                ((displayed++))
            done
            for ((i=displayed; i<WIN_HEIGHT; i++)); do
                tput el; echo
            done
        fi
        
        echo
        echo -e "${C_BOLD}${C_BLUE}$(printf '%*s' $WIDTH | tr ' ' '─')${C_RESET}"
        echo -e "${C_DIM}Notes:${C_RESET}${C_BOLD}$TOTAL${C_RESET} ${C_DIM}Sort:${C_RESET}${C_BOLD}$SORT_MODE${C_RESET} ${C_DIM}Editor:${C_RESET}${C_BOLD}$APP_EDITOR${C_RESET} ${C_DIM}Filter:${C_RESET}${C_BOLD}${FILTER:-none}${C_RESET}"
        tput el
    }

    read_key() {
        IFS= read -rsn1 key
        if [[ $key == $'\x1b' ]]; then
            read -rsn2 -t 0.1 key
            case "$key" in
                '[A') echo "k" ;;
                '[B') echo "j" ;;
                *) echo "$key" ;;
            esac
        else
            echo "$key"
        fi
    }

    new_note() {
        clear
        echo -e "${C_BOLD}${C_GREEN}=== Create New Note ===${C_RESET}"
        echo
        echo -ne "Note name (optional): "
        read -r name
        
        FILENAME="$(date +%Y-%m-%d_%H-%M-%S)"
        [ -n "$name" ] && FILENAME="${FILENAME}_${name//[^a-zA-Z0-9_-]/_}"
        FILENAME="${FILENAME}.txt"
        
        $APP_EDITOR "$NOTES_DIR/$FILENAME"
        
        if [ -s "$NOTES_DIR/$FILENAME" ]; then
            echo -e "${C_GREEN}✓ Note created and saved!${C_RESET}"
        else
            rm -f "$NOTES_DIR/$FILENAME"
            echo -e "${C_YELLOW}Note discarded (empty).${C_RESET}"
        fi
        sleep 1
        clear
    }

    open_note() {
        [ -n "${NOTES[$CUR]}" ] || return
        [ $TOTAL -eq 0 ] && return
        clear
        $APP_EDITOR "$NOTES_DIR/${NOTES[$CUR]}"
        clear
    }

    preview_note() {
        [ -n "${NOTES[$CUR]}" ] || return
        clear
        local file="${NOTES[$CUR]}"
        
        echo -e "${C_BOLD}${C_CYAN}╔$(printf '%*s' $((WIDTH-2)) | tr ' ' '═')╗${C_RESET}"
        echo -e "${C_BOLD}${C_CYAN}║${C_RESET} ${C_BOLD}Preview: $file${C_RESET}"
        echo -e "${C_BOLD}${C_CYAN}╚$(printf '%*s' $((WIDTH-2)) | tr ' ' '═')╝${C_RESET}"
        echo
        
        if command -v less &>/dev/null; then
            less -F -X -R -P "Press 'q' to return..." "$NOTES_DIR/$file"
        else
            head -n $((HEIGHT-5)) "$NOTES_DIR/$file"
            echo
            echo -e "${C_DIM}Press any key to return...${C_RESET}"
            read -rsn1
        fi
        clear
    }

    rename_note() {
        [ -n "${NOTES[$CUR]}" ] || return
        local OLD="${NOTES[$CUR]}"
        clear
        echo -ne "${C_YELLOW}New name (without extension):${C_RESET} "
        read -r NEWNAME
        
        if [ -n "$NEWNAME" ]; then
            local TS=$(echo "$OLD" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}')
            local EXT="${OLD##*.}"
            local NEWFILE="${TS}_${NEWNAME//[^a-zA-Z0-9_-]/_}.${EXT}"
            mv "$NOTES_DIR/$OLD" "$NOTES_DIR/$NEWFILE" 2>/dev/null
            echo -e "${C_GREEN}✓ Renamed to $NEWFILE${C_RESET}"
            sleep 1
        fi
        clear
    }

    delete_note() {
        [ -n "${NOTES[$CUR]}" ] || return
        local file="${NOTES[$CUR]}"
        clear
        echo -ne "${C_RED}Delete '${file}'? (y/N/a for archive):${C_RESET} "
        read -r confirm
        
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            rm "$NOTES_DIR/$file"
            echo -e "${C_GREEN}✓ Deleted${C_RESET}"
            sleep 1
        elif [[ "$confirm" =~ ^[Aa]$ ]]; then
            mv "$NOTES_DIR/$file" "$ARCHIVE_DIR/"
            echo -e "${C_GREEN}✓ Archived${C_RESET}"
            sleep 1
        fi
        clear
    }

    toggle_pin() {
        [ -n "${NOTES[$CUR]}" ] || return
        local file="${NOTES[$CUR]}"
        
        if is_pinned "$file"; then
            local temp_array=()
            for item in "${PINNED_NOTES[@]}"; do
                [[ "$item" != "$file" ]] && temp_array+=("$item")
            done
            PINNED_NOTES=("${temp_array[@]}")
            echo -e "${C_YELLOW}Unpinned ${file}${C_RESET}"
        else
            PINNED_NOTES+=("$file")
            echo -e "${C_YELLOW}Pinned ${file}${C_RESET}"
        fi
        sleep 0.5
    }

    filter_notes() {
        clear
        echo -ne "${C_CYAN}Filter (Case-Insensitive Regex):${C_RESET} "
        read -r NEW_FILTER
        FILTER="$NEW_FILTER"
        clear
    }

    cycle_sort() {
        case "$SORT_MODE" in
            date) SORT_MODE="name" ;;
            name) SORT_MODE="size" ;;
            size) SORT_MODE="date" ;;
        esac
        sed -i "s|^export SORT_MODE=.*|export SORT_MODE=\"$SORT_MODE\"|" "$CONFIG_FILE" 2>/dev/null
    }

    show_stats() {
        clear
        echo -e "${C_BOLD}${C_CYAN}╔$(printf '%*s' $((WIDTH-2)) | tr ' ' '═')╗${C_RESET}"
        echo -e "${C_BOLD}${C_CYAN}║${C_RESET}  $(printf '%*s' $(((WIDTH-14)/2)))${C_BOLD}${C_GREEN}STATISTICS${C_RESET}$(printf '%*s' $(((WIDTH-14)/2)))${C_BOLD}${C_CYAN}║${C_RESET}"
        echo -e "${C_BOLD}${C_CYAN}╚$(printf '%*s' $((WIDTH-2)) | tr ' ' '═')╝${C_RESET}"
        echo
        
        local total=$(ls -1 "$NOTES_DIR" 2>/dev/null | grep -v "^\." | wc -l)
        local total_size=$(du -sh "$NOTES_DIR" 2>/dev/null | cut -f1)
        local archived=$(ls -1 "$ARCHIVE_DIR" 2>/dev/null | wc -l)
        local today=$(find "$NOTES_DIR" -type f -newermt "today 00:00:00" 2>/dev/null | wc -l)
        local week=$(find "$NOTES_DIR" -type f -mtime -7 2>/dev/null | wc -l)
        local total_words=$(cat "$NOTES_DIR"/* 2>/dev/null | wc -w | awk '{print $1}')
        
        echo -e "${C_BOLD}Total Notes:${C_RESET} $total"
        echo -e "${C_BOLD}Total Size:${C_RESET} $total_size"
        echo -e "${C_BOLD}Archived:${C_RESET} $archived"
        echo -e "${C_BOLD}Created Today:${C_RESET} $today"
        echo -e "${C_BOLD}Modified This Week:${C_RESET} $week"
        echo -e "${C_BOLD}Total Words:${C_RESET} $total_words"
        echo -e "${C_BOLD}Pinned:${C_RESET} ${#PINNED_NOTES[@]}"
        echo
        echo -e "${C_DIM}Press any key...${C_RESET}"
        read -rsn1
        clear
    }

    show_full_menu() {
        clear
        echo -e "${C_BOLD}${C_CYAN}╔$(printf '%*s' $((WIDTH-2)) | tr ' ' '═')╗${C_RESET}"
        echo -e "${C_BOLD}${C_CYAN}║${C_RESET}  $(printf '%*s' $(((WIDTH-10)/2)))${C_BOLD}${C_GREEN}MENU${C_RESET}$(printf '%*s' $(((WIDTH-10)/2)))${C_BOLD}${C_CYAN}║${C_RESET}"
        echo -e "${C_BOLD}${C_CYAN}╚$(printf '%*s' $((WIDTH-2)) | tr ' ' '═')╝${C_RESET}"
        echo
        echo -e "${C_BOLD}Navigation:${C_RESET} j/k or ↓/↑"
        echo -e "${C_BOLD}Actions:${C_RESET} o:open i:preview n:new r:rename d:delete p:pin"
        echo -e "${C_BOLD}View:${C_RESET} t:cycle sort f:filter"
        echo -e "${C_BOLD}Settings:${C_RESET} e:editor c:config a:stats m:menu q:quit"
        echo
        echo -e "${C_DIM}Press any key...${C_RESET}"
        read -rsn1
        clear
    }

    change_editor() {
        clear
        echo -e "${C_BOLD}${C_CYAN}╔$(printf '%*s' $((WIDTH-2)) | tr ' ' '═')╗${C_RESET}"
        echo -e "${C_BOLD}${C_CYAN}║${C_RESET}  $(printf '%*s' $(((WIDTH-18)/2)))${C_BOLD}${C_MAGENTA}CHANGE EDITOR${C_RESET}$(printf '%*s' $(((WIDTH-18)/2)))${C_BOLD}${C_CYAN}║${C_RESET}"
        echo -e "${C_BOLD}${C_CYAN}╚$(printf '%*s' $((WIDTH-2)) | tr ' ' '═')╝${C_RESET}"
        echo
        echo -e "${C_DIM}Current editor: ${C_RESET}${C_BOLD}$APP_EDITOR${C_RESET}"
        echo
        echo -e "${C_BOLD}Available editors:${C_RESET}"
        
        local editors=("vim" "nvim" "nano" "emacs" "micro" "vi")
        for ed in "${editors[@]}"; do
            command -v "$ed" &>/dev/null && echo -e "  ${C_GREEN}✓${C_RESET} $ed"
        done
        
        echo
        echo -ne "${C_MAGENTA}Enter editor command:${C_RESET} "
        read -r EDIT
        
        if [ -n "$EDIT" ] && command -v "$EDIT" &>/dev/null; then
            APP_EDITOR="$EDIT"
            sed -i "s|^export APP_EDITOR=.*|export APP_EDITOR=\"$EDIT\"|" "$CONFIG_FILE" 2>/dev/null
            echo -e "${C_GREEN}✓ Editor changed to $EDIT${C_RESET}"
            sleep 1.5
        elif [ -n "$EDIT" ]; then
            echo -e "${C_RED}✗ Editor not found: $EDIT${C_RESET}"
            sleep 1.5
        fi
        clear
    }
    
    edit_config() {
        clear
        $APP_EDITOR "$CONFIG_FILE"
        clear
        source "$CONFIG_FILE" 2>/dev/null
    }

    CUR=0
    list_notes
    clear
    trap 'tput reset; exit 0' EXIT INT TERM

    while true; do
        list_notes
        [ $CUR -ge $TOTAL ] && ((CUR=TOTAL-1))
        [ $CUR -lt 0 ] && CUR=0
        
        show_menu
        KEY=$(read_key)
        
        case "$KEY" in
            j | $'\n') ((CUR < TOTAL-1)) && ((CUR++)) ;;
            k | $'\t') ((CUR > 0)) && ((CUR--)) ;;
            o) open_note ;;
            i) preview_note ;;
            n) new_note; CUR=0 ;;
            r) rename_note ;;
            d) delete_note; [ $CUR -ge $TOTAL ] && ((CUR=TOTAL-1)) ;;
            p) toggle_pin ;;
            f) filter_notes; CUR=0 ;;
            t) cycle_sort; CUR=0 ;;
            a) show_stats ;;
            e) change_editor ;;
            c) edit_config ;;
            m) show_full_menu ;;
            q) tput reset; exit 0 ;;
        esac
    done
}

if [ "$RUN_APP" = true ]; then
    # Check if this script is being executed as the installed 'notes' command
    if [[ "$0" =~ "$HOME/.local/bin/notes" ]]; then
        run_notes_app
    else
        # If run as the installer, install, then exit with instructions
        install_notes
        exit 0
    fi
else
    # Non-interactive run (e.g. piped or redirected) performs installation only.
    install_notes
    exit 0
fi
