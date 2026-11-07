# audiobookshelf-xHE-AAC

A Dockerfile that builds the official [Audiobookshelf](https://github.com/advplyr/audiobookshelf) image with an FFmpeg compiled against **[Fraunhofer fdk-aac](https://github.com/mstorsjo/fdk-aac)**, so **xHE-AAC (USAC)** audiobooks play correctly, like the ones from [Libation](https://getlibation.com/).

The stock image's FFmpeg can read xHE-AAC files, but its built-in decoder is still incomplete, and transcoded playback can sound distorted. The [Audiobookshelf FAQ](https://audiobookshelf.org/docs/faq/server/#xhe-aac-codec-support) recommends using your own FFmpeg built with fdk-aac. This repo does that for you, on top of the official image.

> [!WARNING]
> **Build this image yourself. Do not publish it.**
> FFmpeg built with `--enable-nonfree` (required for fdk-aac) is not redistributable. You can share this Dockerfile, but don't push the built image to Docker Hub, GHCR or any other registry, and don't set up CI that publishes it.

## Quick start

```sh
git clone https://github.com/hexadecimaldev/audiobookshelf-xhe-aac
cd audiobookshelf-xhe-aac
docker build --pull -t audiobookshelf:latestfdk .
```

Then run `audiobookshelf:latestfdk` exactly as you would the official image.

### Docker Compose

```yaml
services:
  audiobookshelf:
    build:
      context: ./audiobookshelf-xhe-aac
      pull: true
    image: audiobookshelf:latestfdk
    container_name: audiobookshelf
    ports:
      - 13378:80
    volumes:
      - ./config:/config
      - ./metadata:/metadata
      - /path/to/audiobooks:/audiobooks
      - /path/to/podcasts:/podcasts
    restart: unless-stopped
```

```sh
docker compose build && docker compose up -d
```

## Updating

Rebuild whenever you want the latest Audiobookshelf release:

```sh
docker build --pull -t audiobookshelf:latestfdk .
# then recreate the container, or with Compose:
docker compose build && docker compose up -d
```

`--pull` (or `pull: true` in Compose) matters. Without it, Docker reuses the copy of `latest` it downloaded last time, and you stay on the old version.

FFmpeg is compiled inside the Audiobookshelf image, so each new Audiobookshelf release also recompiles FFmpeg. That takes a few minutes.

## Build options

| Build arg | Default | Purpose |
|---|---|---|
| `AUDIOBOOKSHELF_TAG` | `latest` | Audiobookshelf image tag, e.g. `2.34.0` or `edge` |
| `FFMPEG_VERSION` | `8.1.3` | FFmpeg release (git tag without the `n`) |
| `FDK_AAC_VERSION` | `v2.0.3` | fdk-aac git tag |

Example:

```sh
docker build --pull --build-arg AUDIOBOOKSHELF_TAG=2.34.0 -t audiobookshelf:latestfdk .
```

To see the newest versions:

```sh
git ls-remote --tags https://github.com/FFmpeg/FFmpeg 'refs/tags/n8*' | grep -o 'n8[0-9.]*$' | sort -V | tail -1
git ls-remote --tags https://github.com/mstorsjo/fdk-aac | grep -o 'v2[0-9.]*$' | sort -V | tail -1
```

The default FFmpeg tracks the same major version the official image ships. Newer major versions may work, but Audiobookshelf may not have been tested against them.

## How it works

- **The builder stage is the Audiobookshelf image itself.** FFmpeg is compiled against exactly the Alpine/musl libraries the final image has.
- **fdk-aac is linked in statically.** The other libraries FFmpeg needs are detected after the build (`scanelf`) and installed with `apk` in the final stage, so no package names are hard-coded.
- **FFmpeg's native AAC decoders are disabled** (`aac`, `aac_fixed`, `aac_latm`). FFmpeg picks its own decoder before external libraries, so this is what makes all AAC input go through fdk-aac. The native AAC **encoder** stays enabled, so Audiobookshelf's `-c:a aac` transcodes work unchanged.
- **Alpine's stock `ffmpeg` package is removed** and replaced with this build at `/usr/bin/ffmpeg` and `/usr/bin/ffprobe`.
- **The image sets** `FFMPEG_PATH`, `FFPROBE_PATH` and `SKIP_BINARIES_CHECK=1`, the [documented way](https://audiobookshelf.org/docs/documentation/install/configuration#external-tools) to use custom binaries.
- **The build checks itself.** The last step fails the build if the fdk decoder or the AAC encoder is missing, or if a binary won't run, so a broken build never replaces a working container.

## Checking it works

```sh
docker exec audiobookshelf ffmpeg -hide_banner -decoders | grep fdk
# A....D libfdk_aac           Fraunhofer FDK AAC (codec aac)
```

To check that a whole file decodes cleanly:

```sh
docker exec audiobookshelf ffmpeg -v error -i "/audiobooks/path/to/book.m4b" -f null -
```

No output means no errors.

## Expected log messages

These appear in the Audiobookshelf log when playing xHE-AAC files and are harmless:

- `MPEG-4 AOT 42 is not allowed in ADTS` … `Re-attempting stream with AAC encode`
  Audiobookshelf first tries to stream without re-encoding, which xHE-AAC doesn't allow. It then retries with transcoding. This adds about 10 seconds at the start of playback.
- `aacDecoder_DecodeFrame() failed: 5` (a short burst right after starting)
  Resuming mid-book seeks into frames that depend on earlier ones. The decoder skips them until the next independent frame, losing a fraction of a second at most.


## License

The Dockerfile and docs in this repo are released under the [MIT License](LICENSE).

This license covers only the files in this repo. The software the Dockerfile downloads and builds keeps its own license: [Audiobookshelf](https://github.com/advplyr/audiobookshelf) (GPL-3.0), [FFmpeg](https://ffmpeg.org/legal.html) (LGPL/GPL) and [fdk-aac](https://github.com/mstorsjo/fdk-aac) (Fraunhofer FDK AAC license). The resulting image combines non-free and GPL-family code and must not be redistributed.
