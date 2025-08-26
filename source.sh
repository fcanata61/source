#!/bin/sh
# Source LFS Manager - Completo

. ./config

# ---- cores e spinner ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

spinner() {
    text="$1"
    while :; do
        for s in / - \\ \|; do
            printf "\r$s $text"
            sleep 0.1
        done
    done
}

# ---- utilitários ----
mkdir_p() { [ ! -d "$1" ] && mkdir -p "$1"; }

find_recipe() {
    pkg="$1"
    for dir in "${RECIPE_PATHS[@]}"; do
        [ -f "$dir/$pkg.src" ] && echo "$dir/$pkg.src" && return
    done
    return 1
}

load_recipe() { . "$1"; }
get_depends() { grep '^DEPENDS=' "$1" | cut -d'"' -f2; }

fetch_sources() {
    url="$1"; patch="$2"; pkg="$3"
    mkdir_p "$SRC_CACHE"

    tarfile="$SRC_CACHE/$(basename $url)"
    [ ! -f "$tarfile" ] && echo "${YELLOW}Baixando $url...${NC}" && curl -L "$url" -o "$tarfile"

    patchfile=""
    case "$patch" in
        http*) patchfile="$SRC_CACHE/$(basename $patch)"
               [ ! -f "$patchfile" ] && echo "${YELLOW}Baixando patch $patch...${NC}" && curl -L "$patch" -o "$patchfile" ;;
        "") patchfile="" ;;
        *) patchfile="$patch" ;;
    esac

    echo "$tarfile" "$patchfile"
}

# ---- dependências recursivas ----
resolve_depends() {
    pkg="$1"
    srcfile=$(find_recipe "$pkg") || { echo "${RED}Receita não encontrada: $pkg${NC}"; return 1; }
    deps=$(get_depends "$srcfile")
    for dep in $deps; do
        [ ! -d "$INSTALLED/$dep" ] && install_package "$dep"
    done
}

# ---- build básico ----
build_package() {
    pkg="$1"
    srcfile=$(find_recipe "$pkg") || { echo "${RED}Receita não encontrada: $pkg${NC}"; return 1; }
    load_recipe "$srcfile"
    resolve_depends "$pkg"

    mkdir_p "$WORKDIR/$NAME-$VERSION"
    cd "$WORKDIR" || exit

    tarfile=$(fetch_sources "$URL" "$PATCH" "$NAME" | awk '{print $1}')
    patchfile=$(fetch_sources "$URL" "$PATCH" "$NAME" | awk '{print $2}')

    tar -xf "$tarfile"
    cd "$NAME-$VERSION" || exit
    [ -n "$patchfile" ] && patch -Np1 < "$patchfile"

    echo "${GREEN}Compilando $NAME-$VERSION...${NC}"
    build &> "$LOGDIR/$NAME-$VERSION.log"
}

# ---- install completo ----
install_package() {
    pkg="$1"
    srcfile=$(find_recipe "$pkg") || { echo "${RED}Receita não encontrada: $pkg${NC}"; return 1; }
    load_recipe "$srcfile"

    mkdir_p "$INSTALLED/$pkg" "$PKGDIR" "$DESTDIR" "$LOGDIR"

    [ ! -d "$WORKDIR/$NAME-$VERSION" ] && build_package "$pkg"
    cd "$WORKDIR/$NAME-$VERSION" || exit

    echo "${GREEN}Instalando $NAME-$VERSION...${NC}"
    build &>> "$LOGDIR/$NAME-$VERSION.log"
    make DESTDIR="$DESTDIR" install &>> "$LOGDIR/$NAME-$VERSION.log"

    [ "$STRIP" = true ] && find "$DESTDIR" -type f -exec strip {} \; 2>/dev/null

    cp -a "$DESTDIR"/* "$PKGDIR/"
    find "$DESTDIR" -type f > "$INSTALLED/$pkg/files.list"
    echo "${GREEN}$pkg instalado${NC}"
}

# ---- remove ----
remove_package() {
    pkg="$1"
    srcfile=$(find_recipe "$pkg") || { echo "${RED}Receita não encontrada: $pkg${NC}"; return 1; }
    load_recipe "$srcfile"

    [ -f "$INSTALLED/$pkg/files.list" ] && xargs rm -f < "$INSTALLED/$pkg/files.list"
    [ -d "$INSTALLED/$pkg" ] && rmdir "$INSTALLED/$pkg" 2>/dev/null
    remove
    echo "${YELLOW}$pkg removido${NC}"
}

# ---- update ----
update_package() {
    pkg="$1"
    srcfile=$(find_recipe "$pkg") || { echo "${RED}Receita não encontrada: $pkg${NC}"; return 1; }
    load_recipe "$srcfile"
    fetch_sources "$URL" "$PATCH" "$NAME"
    echo "${GREEN}$pkg atualizado${NC}"
}

update_all() {
    for dir in "${RECIPE_PATHS[@]}"; do
        for r in "$dir"/*.src; do
            pkg=$(basename "$r" .src)
            update_package "$pkg"
        done
    done
}

# ---- rebuild ----
rebuild_system() {
    for pkgdir in "$INSTALLED"/*; do
        pkg=$(basename "$pkgdir")
        echo "${YELLOW}Recompilando $pkg...${NC}"
        install_package "$pkg"
    done
}

# ---- search/info ----
search_package() {
    term="$1"
    for dir in "${RECIPE_PATHS[@]}"; do
        find "$dir" -name "*.src" -exec basename {} .src \; | grep "$term"
    done
}

info_package() {
    pkg="$1"
    srcfile=$(find_recipe "$pkg") || { echo "${RED}Receita não encontrada${NC}"; return 1; }
    load_recipe "$srcfile"
    echo "Nome: $NAME"
    echo "Versão: $VERSION"
    echo "URL: $URL"
    echo "Patch: $PATCH"
    echo "Dependências: $DEPENDS"
}

# ---- clean workdir ----
clean_work() { rm -rf "$WORKDIR"; echo "${YELLOW}Workdir limpo${NC}"; }

# ---- pacotes órfãos ----
orphans() {
    for pkgdir in "$INSTALLED"/*; do
        pkg=$(basename "$pkgdir")
        # simplificado: sem dependência, não instalado por outro
        # apenas lista todos
        echo "$pkg"
    done
}

# ---- CLI principal ----
cmd="$1"
pkg="$2"

case "$cmd" in
    build) build_package "$pkg" ;;
    install) install_package "$pkg" ;;
    remove) remove_package "$pkg" ;;
    update) [ "$pkg" = "--all" ] && update_all || update_package "$pkg" ;;
    rebuild) rebuild_system ;;
    clean) clean_work ;;
    search) search_package "$pkg" ;;
    info) info_package "$pkg" ;;
    orphans) orphans ;;
    *) echo "Comandos: build, install, remove, update, rebuild, clean, search, info, orphans" ;;
esac
