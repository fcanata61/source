#!/bin/sh
# Minimal LFS source manager

. ./config

# busca receita pelo nome
find_recipe() {
    pkg="$1"
    for dir in "${RECIPE_PATHS[@]}"; do
        [ -f "$dir/$pkg.src" ] && echo "$dir/$pkg.src" && return
    done
    return 1
}

# lê DEPENDS de uma receita
get_depends() {
    src="$1"
    grep '^DEPENDS=' "$src" | cut -d'"' -f2
}

# carrega a receita
load_recipe() {
    src="$1"
    . "$src"
}

# baixa tarball e patch remoto
fetch_sources() {
    url="$1"
    patch="$2"
    pkg="$3"

    mkdir -p "$SRC_CACHE"

    tarfile="$SRC_CACHE/$(basename $url)"
    [ ! -f "$tarfile" ] && echo "Baixando $url..." && curl -L "$url" -o "$tarfile"

    patchfile=""
    case "$patch" in
        http* )
            patchfile="$SRC_CACHE/$(basename $patch)"
            [ ! -f "$patchfile" ] && echo "Baixando patch $patch..." && curl -L "$patch" -o "$patchfile"
            ;;
        "") patchfile="" ;;
        *) patchfile="$patch" ;;
    esac

    echo "$tarfile" "$patchfile"
}

# build: apenas compila
build_package() {
    pkg="$1"
    srcfile=$(find_recipe "$pkg") || { echo "Receita não encontrada"; return 1; }
    load_recipe "$srcfile"

    # resolver dependências
    for dep in $DEPENDS; do
        [ ! -d "$INSTALLED/$dep" ] && install_package "$dep"
    done

    # preparar diretório de trabalho
    mkdir -p "$WORKDIR/$NAME-$VERSION"
    cd "$WORKDIR" || exit
    tarfile=$(fetch_sources "$URL" "$PATCH" "$NAME" | awk '{print $1}')
    patchfile=$(fetch_sources "$URL" "$PATCH" "$NAME" | awk '{print $2}')

    tar -xf "$tarfile"
    cd "$NAME-$VERSION" || exit
    [ -n "$patchfile" ] && patch -Np1 < "$patchfile"

    echo "Compilando $NAME-$VERSION..."
    build
}

# install: build + instalar
install_package() {
    pkg="$1"
    srcfile=$(find_recipe "$pkg") || { echo "Receita não encontrada"; return 1; }
    load_recipe "$srcfile"

    mkdir -p "$INSTALLED/$pkg" "$PKGDIR" "$DESTDIR"

    [ ! -d "$WORKDIR/$NAME-$VERSION" ] && build_package "$pkg"

    cd "$WORKDIR/$NAME-$VERSION" || exit
    build
    make DESTDIR="$DESTDIR" install

    cp -a "$DESTDIR"/* "$PKGDIR/"
    find "$DESTDIR" -type f > "$INSTALLED/$pkg/files.list"
    echo "$pkg instalado com sucesso"
}

# remove
remove_package() {
    pkg="$1"
    srcfile=$(find_recipe "$pkg") || { echo "Receita não encontrada"; return 1; }
    load_recipe "$srcfile"

    [ -f "$INSTALLED/$pkg/files.list" ] && xargs rm -f < "$INSTALLED/$pkg/files.list"
    [ -d "$INSTALLED/$pkg" ] && rmdir "$INSTALLED/$pkg" 2>/dev/null
    remove
    echo "$pkg removido"
}

# update: baixar tarball/patch
update_package() {
    pkg="$1"
    srcfile=$(find_recipe "$pkg") || { echo "Receita não encontrada"; return 1; }
    load_recipe "$srcfile"
    fetch_sources "$URL" "$PATCH" "$NAME"
    echo "$pkg atualizado no cache"
}

# search
search_package() {
    term="$1"
    for dir in "${RECIPE_PATHS[@]}"; do
        find "$dir" -name "*.src" -exec basename {} .src \; | grep "$term"
    done
}

# info
info_package() {
    pkg="$1"
    srcfile=$(find_recipe "$pkg") || { echo "Receita não encontrada"; return 1; }
    load_recipe "$srcfile"
    echo "Nome: $NAME"
    echo "Versão: $VERSION"
    echo "URL: $URL"
    echo "Patch: $PATCH"
    echo "Dependências: $DEPENDS"
}

# CLI
cmd="$1"
pkg="$2"

case "$cmd" in
    build) build_package "$pkg" ;;
    install) install_package "$pkg" ;;
    remove) remove_package "$pkg" ;;
    update) update_package "$pkg" ;;
    search) search_package "$pkg" ;;
    info) info_package "$pkg" ;;
    *) echo "Comandos: build, install, remove, update, search, info" ;;
esac
