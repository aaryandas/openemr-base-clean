# ============================================================================
# Railway deploy Dockerfile for this OpenEMR fork
# ============================================================================
# Railway builds this from the GitHub repo on every push, so the image contains
# this fork's exact committed source.
#
# Base is the official OpenEMR "flex" image. Flex normally *clones* OpenEMR
# source at runtime, but that path assumes the git repo directory is named
# "openemr" (true only for github.com/openemr/openemr). For a differently-named
# fork the clone lands in "openemr-base-clean/" and flex's hard-coded
# `rsync openemr ...` / `rm -fr openemr` miss, crashing under `set -euo pipefail`.
#
# Instead we bake the source at /openemr and use flex's LOCAL-source path
# (EASY_DEV_MODE_NEW=yes), which skips the clone and rsyncs /openemr into the
# document root, then builds Composer + npm deps and runs the DB install at boot.
#
# Base image is pinned by digest to match docker/development-easy/docker-compose.yml.
# ============================================================================
FROM openemr/openemr:flex@sha256:1d2c8345a320cf2985c9d02138951267739ec498559ca724b3d5397e4568482e

# Bake this fork's source where flex's local-source path expects it.
COPY . /openemr

# EASY_DEV_MODE_NEW=yes makes the flex entrypoint use /openemr instead of
# cloning. That same path also rsyncs /couchdb/data (a dev convenience) under
# `set -e`; Railway has no CouchDB, so pre-create the dirs to keep it a no-op
# rather than a fatal error.
RUN mkdir -p /couchdb/data /couchdb/original
ENV EASY_DEV_MODE_NEW=yes

# Remaining runtime config (MYSQL_*, OE_*) is supplied as Railway service
# variables — see railway.json and SETUP.md.
