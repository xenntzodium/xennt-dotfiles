#!/bin/bash

#----------------------------------------------------------------
#   Proje Sahibi: xenntzodium
#   GitHub      : https://github.com/xenntzodium
#   Yıl         : 2025
#   Açıklama	: Bu script, Firefox PWA ID'lerini tarar,
#             	  Hyprland Keybinds.conf dosyasına kısayollar ekler.
#             	  Var olan kısayolları atlar ve kullanıcıdan tuş girişi alır.
#-----------------------------------------------------------------

# Renkli çıktılar için tanımlamalar
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PWA_DIR="$HOME/.local/share/applications"
HYPR_KEYBINDS_FILE="$HOME/.config/hypr/configs/Keybinds.conf"
TEMP_FILE=$(mktemp) # Geçici dosya oluştur

# --- Fonksiyon Tanımlamaları ---

# Root yetkisi kontrolü ve şifre isteme
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Bu script root yetkisi gerektiriyor.${NC}"
        echo -e "${YELLOW}Devam etmek için şifrenizi girin:${NC}"
        sudo -v || { echo -e "${RED}Hatalı şifre veya yetki verilmedi. Çıkılıyor.${NC}"; exit 1; }
        echo -e "${GREEN}Root yetkisi alındı.${NC}"
    fi
}

# Mesajları ve seçenekleri temiz bir şekilde göstermek için fonksiyon
display_prompt_and_wait_input() {
    local prompt_text="$1"
    local default_value="$2"
    local user_input

    read -r -p "$(echo -e "${BLUE}${prompt_text}${NC} ${YELLOW}(Örn: $default_value, iptal için 'iptal' yazın): ${NC}")" user_input
    
    echo "$user_input"
}


# --- Ana Script Başlangıcı ---

echo -e "${BLUE}Hyprland Firefox PWA Kısayol Atama Scripti Başlatılıyor...${NC}"

# Root yetkisini kontrol et
check_root

# Keybinds.conf dosyasının varlığını kontrol et
if [[ ! -f "$HYPR_KEYBINDS_FILE" ]]; then
    echo -e "${RED}Hata: Hyprland Keybinds dosyası bulunamadı: $HYPR_KEYBINDS_FILE${NC}"
    echo -e "${YELLOW}Lütfen dosya yolunu kontrol edin veya oluşturun.${NC}"
    exit 1
fi

echo -e "${BLUE}PWA kısayol dosyaları taranıyor: $PWA_DIR${NC}"

PWA_IDS=()
for desktop_file in "$PWA_DIR"/FFPWA-*.desktop; do
    if [[ ! -f "$desktop_file" ]]; then
        continue
    fi
    filename=$(basename "$desktop_file")
    pwa_id=$(echo "$filename" | sed -E 's/FFPWA-(.*)\.desktop/\1/')
    if [[ -n "$pwa_id" ]]; then
        PWA_IDS+=("$pwa_id")
    fi
done

if [[ ${#PWA_IDS[@]} -eq 0 ]]; then
    echo -e "${YELLOW}Firefox PWA ID'si bulunamadı: $PWA_DIR dizininde FFPWA-*.desktop dosyası yok.${NC}"
    echo -e "${GREEN}Script tamamlandı.${NC}"
    exit 0
fi

# Dosyayı satır satır okuyup PWA bloklarını ayıralım
PWA_BLOCK_START_MARKER="# ---------------------- PWAs ----------------------------------"
PWA_BLOCK_END_MARKER="# --------------------------------------------------------------"

CONTENT_BEFORE_PWA_BLOCK=""
EXISTING_PWA_KEYBINDS=""
CONTENT_AFTER_PWA_BLOCK=""
CURRENT_BLOCK="BEFORE"
LAST_LINE=""

while IFS= read -r line; do
    if [[ "$line" == "$PWA_BLOCK_START_MARKER" ]]; then
        CONTENT_BEFORE_PWA_BLOCK+="$line"$'\n' # Başlangıç marker'ını da ekle
        CURRENT_BLOCK="PWA_BLOCK"
        continue
    fi

    if [[ "$line" == "$PWA_BLOCK_END_MARKER" ]]; then
        EXISTING_PWA_KEYBINDS+="$line"$'\n' # Bitiş marker'ını da ekle (geçici olarak)
        CURRENT_BLOCK="AFTER"
        continue
    fi

    if [[ "$CURRENT_BLOCK" == "BEFORE" ]]; then
        CONTENT_BEFORE_PWA_BLOCK+="$line"$'\n'
    elif [[ "$CURRENT_BLOCK" == "PWA_BLOCK" ]]; then
        # PWA bloğunun içindeki existing kısayolları alalım (ancak marker'lar hariç)
        if [[ ! "$line" =~ ^# ]]; then # Yorum satırlarını veya boş satırları atla
            # Mevcut PWA kısayollarını temiz bir şekilde topluyoruz, marker'lar hariç
            EXISTING_PWA_KEYBINDS+="$line"$'\n'
        fi
    elif [[ "$CURRENT_BLOCK" == "AFTER" ]]; then
        CONTENT_AFTER_PWA_BLOCK+="$line"$'\n'
    fi
    LAST_LINE="$line"
done < "$HYPR_KEYBINDS_FILE"

# Şimdi asıl existing PWA keybind'leri içeriğinden, marker'ları çıkararak alalım
# Bu, sadece "bind = ..." satırlarını tutacak
EXISTING_PWA_KEYBINDS_CLEANED=$(echo "$EXISTING_PWA_KEYBINDS" | grep -vF "$PWA_BLOCK_START_MARKER" | grep -vF "$PWA_BLOCK_END_MARKER" | grep -vE '^\s*#|^$') # Yorum ve boş satırları da atla

echo -e "${BLUE}Hyprland Keybinds dosyasındaki mevcut PWA kısayolları kontrol ediliyor...${NC}"

NEW_KEYBINDS_TO_ADD=()
for id in "${PWA_IDS[@]}"; do
    PWA_COMMAND="/usr/bin/firefoxpwa site launch $id"
    
    # Mevcut PWA kısayollarında zaten var mı diye kontrol et
    if echo "$EXISTING_PWA_KEYBINDS_CLEANED" | grep -qF "exec, $PWA_COMMAND"; then
        echo -e "${YELLOW}PWA ID '$id' için kısayol zaten mevcut. Atlanıyor.${NC}"
        continue
    fi

    echo -e "\n${BLUE}Yeni PWA Kısayolu Oluşturuluyor: ID = ${GREEN}$id${NC}"

    MODIFIERS_INPUT=$(display_prompt_and_wait_input "Modifikasyon tuşları ne olsun? (örn: CTRL SHIFT, SUPER ALT, boş bırakılabilir)" "CTRL SHIFT")
    
    if [[ "$MODIFIERS_INPUT" == "iptal" ]]; then
        echo -e "${YELLOW}PWA ID '$id' için kısayol ataması iptal edildi.${NC}"
        continue
    fi

    KEY_INPUT=""
    while true; do
        KEY_INPUT=$(display_prompt_and_wait_input "Anahtar tuşu ne olsun? (örn: Y, A, F1)" "Y")
        
        if [[ "$KEY_INPUT" == "iptal" ]]; then
            echo -e "${YELLOW}PWA ID '$id' için kısayol ataması iptal edildi.${NC}"
            KEY_INPUT="iptal_edildi"
            break
        elif [[ -z "$KEY_INPUT" ]]; then
            echo -e "${RED}Anahtar tuşu boş bırakılamaz. Lütfen bir tuş girin veya 'iptal' yazın.${NC}"
        else
            break
        fi
    done

    if [[ "$KEY_INPUT" == "iptal_edildi" ]]; then
        continue
    fi

    BIND_LINE="bind = "
    if [[ -n "$MODIFIERS_INPUT" ]]; then
        BIND_LINE+="$MODIFIERS_INPUT, "
    fi
    BIND_LINE+="$KEY_INPUT, exec, $PWA_COMMAND"
    NEW_KEYBINDS_TO_ADD+=("$BIND_LINE")
    echo -e "${GREEN}Oluşturulan Kısayol Satırı: ${BIND_LINE}${NC}"
done

# Yeni kısayolları dosyaya yazma
if [[ ${#NEW_KEYBINDS_TO_ADD[@]} -gt 0 ]]; then
    echo -e "${BLUE}Yeni kısayollar '$HYPR_KEYBINDS_FILE' dosyasına ekleniyor...${NC}"
    
    # Geçici dosyaya yeni içeriği yaz
    echo -n "$CONTENT_BEFORE_PWA_BLOCK" > "$TEMP_FILE"
    echo "$EXISTING_PWA_KEYBINDS_CLEANED" >> "$TEMP_FILE" # Mevcut temizlenmiş kısayolları ekle
    for line_to_add in "${NEW_KEYBINDS_TO_ADD[@]}"; do
        echo "$line_to_add" >> "$TEMP_FILE" # Yeni kısayolları ekle
    done
    echo "$PWA_BLOCK_END_MARKER" >> "$TEMP_FILE" # Bitiş markerını ekle
    echo -n "$CONTENT_AFTER_PWA_BLOCK" >> "$TEMP_FILE" # Bloğun sonraki içeriği ekle

    # Orijinal dosyayı yedekleyip yeni içerikle değiştir
    sudo cp "$HYPR_KEYBINDS_FILE" "$HYPR_KEYBINDS_FILE.bak" # Yedek al
    sudo mv "$TEMP_FILE" "$HYPR_KEYBINDS_FILE" # Geçici dosyayı ana dosya yerine taşı

    echo -e "${GREEN}Kısayollar başarıyla eklendi.${NC}"

    echo -e "${BLUE}Hyprland yapılandırması yeniden yükleniyor...${NC}"
    hyprctl reload
    echo -e "${GREEN}Hyprland yeniden yüklendi.${NC}"
else
    echo -e "${YELLOW}Eklenecek yeni PWA kısayolu bulunamadı.${NC}"
fi

# Geçici dosyayı temizle
rm -f "$TEMP_FILE"

echo -e "${GREEN}Script tamamlandı.${NC}"

exit 0
