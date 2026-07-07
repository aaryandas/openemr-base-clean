# ============================================================================
# Railway deploy Dockerfile for this OpenEMR fork
# ============================================================================
# Railway builds this from the GitHub repo on every push. It bases on the
# official OpenEMR "flex" image, which fetches OpenEMR source at *runtime*
# from a configurable git repository (FLEX_REPOSITORY / FLEX_REPOSITORY_BRANCH)
# and then builds composer + npm dependencies and runs the database install.
#
# By pointing FLEX_REPOSITORY at THIS fork (set as a Railway variable), the
# running container clones and installs this fork's code. A redeploy re-clones
# the branch, so pushing to the fork + redeploying picks up new commits.
#
# Base image is pinned by digest to match docker/development-easy/docker-compose.yml.
# ============================================================================
FROM openemr/openemr:flex@sha256:1d2c8345a320cf2985c9d02138951267739ec498559ca724b3d5397e4568482e

# All runtime configuration (FLEX_REPOSITORY, MYSQL_*, OE_*) is supplied as
# Railway service variables — see railway.json and RAILWAY_DEPLOY.md.
