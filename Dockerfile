# Audiobookshelf + FFmpeg built with fdk-aac, for xHE-AAC / USAC audiobooks.
#
# FFmpeg is compiled inside the Audiobookshelf image itself, so it always
# matches that image's Alpine/musl libraries. A new Audiobookshelf release
# also triggers an FFmpeg recompile (a few minutes).

ARG AUDIOBOOKSHELF_TAG=latest
ARG FFMPEG_VERSION=8.1.3
ARG FDK_AAC_VERSION=v2.0.3

############################ builder ############################
FROM ghcr.io/advplyr/audiobookshelf:${AUDIOBOOKSHELF_TAG} AS builder
ARG FFMPEG_VERSION
ARG FDK_AAC_VERSION

RUN apk add --no-cache \
        build-base autoconf automake libtool pkgconf nasm git pax-utils \
        lame-dev libwebp-dev zlib-dev bzip2-dev

# fdk-aac, linked statically into ffmpeg (so no runtime package is needed)
RUN git clone --depth 1 --branch ${FDK_AAC_VERSION} https://github.com/mstorsjo/fdk-aac /src/fdk-aac && \
    cd /src/fdk-aac && \
    autoreconf -fi && \
    ./configure --prefix=/opt/fdk --disable-shared --enable-static --with-pic && \
    make -j"$(nproc)" && make install

# FFmpeg source. .git is removed so ffmpeg reports a plain "8.1.3" version
# string, like a release tarball (Audiobookshelf checks the version).
RUN git clone --depth 1 --branch n${FFMPEG_VERSION} https://github.com/FFmpeg/FFmpeg /src/ffmpeg && \
    rm -rf /src/ffmpeg/.git

# Native AAC *decoders* are disabled so all AAC input, including xHE-AAC,
# is decoded by fdk-aac. The native AAC *encoder* stays enabled, so
# Audiobookshelf's "-c:a aac" transcode works with no wrapper script.
RUN cd /src/ffmpeg && \
    PKG_CONFIG_PATH=/opt/fdk/lib/pkgconfig ./configure \
        --prefix=/opt/ffmpeg \
        --pkg-config-flags="--static" \
        --disable-debug --disable-doc --disable-ffplay \
        --enable-nonfree --enable-libfdk_aac \
        --enable-libmp3lame --enable-libwebp \
        --enable-zlib --enable-bzlib \
        --disable-decoder=aac,aac_fixed,aac_latm && \
    make -j"$(nproc)" ffmpeg ffprobe && \
    strip ffmpeg ffprobe && \
    mkdir /out && cp ffmpeg ffprobe /out/ && \
    scanelf --needed --nobanner --format '%n#p' /out/ffmpeg /out/ffprobe \
         | tr ',' '\n' | sort -u | sed 's/^/so:/' > /out/runtime-deps
############################ final ############################
FROM ghcr.io/advplyr/audiobookshelf:${AUDIOBOOKSHELF_TAG}

# Official way to point Audiobookshelf at custom binaries
# (https://audiobookshelf.org/docs/documentation/install/configuration#external-tools)
ENV FFMPEG_PATH=/usr/bin/ffmpeg \
    FFPROBE_PATH=/usr/bin/ffprobe \
    SKIP_BINARIES_CHECK=1

# Swap Alpine's stock ffmpeg for ours, install exactly the libraries it
# links against, and fail the build if anything is wrong.
RUN --mount=type=bind,from=builder,source=/out,target=/tmp/ffmpeg-fdk \
    (apk del --no-cache ffmpeg || true) && \
    apk add --no-cache $(cat /tmp/ffmpeg-fdk/runtime-deps) && \
    install -m 755 /tmp/ffmpeg-fdk/ffmpeg /tmp/ffmpeg-fdk/ffprobe /usr/bin/ && \
    ffmpeg -hide_banner -decoders | grep -q libfdk_aac && \
    ffmpeg -hide_banner -encoders | grep -qE '^ A.{5} aac ' && \
    ffprobe -hide_banner -version >/dev/null
