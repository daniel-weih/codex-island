#!/bin/bash

set -euo pipefail

: "${GH_REPO:?Expected the repository name}"
: "${RELEASE_TAG:?Expected the existing release tag}"
: "${RUNNER_TEMP:?Expected a temporary working directory}"
cd "$(dirname "$0")/.."

notes="$RUNNER_TEMP/release-notes.md"
git for-each-ref --format='%(contents:subject)%0a%0a%(contents:body)' "refs/tags/$RELEASE_TAG" > "$notes"
python3 - "$notes" <<'PY'
import hashlib, pathlib, sys
asset = pathlib.Path('dist/Codex-Island.dmg')
digest = hashlib.sha256(asset.read_bytes()).hexdigest()
with open(sys.argv[1], 'a', encoding='utf-8') as stream:
    stream.write(f'\nSHA-256: `{digest}`\n')
PY

# The tag endpoint only finds published releases. Authenticated listing also
# returns drafts, which must be addressed by ID until they are published.
gh api --paginate --slurp "repos/$GH_REPO/releases?per_page=100" > "$RUNNER_TEMP/releases.json"
python3 - "$RUNNER_TEMP/releases.json" > "$RUNNER_TEMP/release-selection" <<'PY'
import json, os, pathlib, sys
pages = json.loads(pathlib.Path(sys.argv[1]).read_text())
matches = [item for page in pages for item in page if item['tag_name'] == os.environ['RELEASE_TAG']]
assert len(matches) <= 1, 'Multiple releases use this tag; refusing an ambiguous update'
if matches:
    release = matches[0]
    print(release['id'], 'draft' if release['draft'] else 'published')
else:
    print(0, 'absent')
PY
read -r release_id state < "$RUNNER_TEMP/release-selection"
if [[ "$state" == published ]]; then
    echo "Release is already published; existing assets are unchanged."
    exit 0
fi
if [[ "$state" == draft ]]; then
    gh api --method PATCH "repos/$GH_REPO/releases/$release_id" \
        -f name="Codex Island $RELEASE_TAG" -F body=@"$notes" > "$RUNNER_TEMP/release.json"
else
    gh api --method POST "repos/$GH_REPO/releases" \
        -f tag_name="$RELEASE_TAG" -f name="Codex Island $RELEASE_TAG" \
        -F body=@"$notes" -F draft=true -F prerelease=false > "$RUNNER_TEMP/release.json"
    release_id="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["id"])' "$RUNNER_TEMP/release.json")"
fi

python3 - "$RUNNER_TEMP/release.json" > "$RUNNER_TEMP/replace-assets" <<'PY'
import json, os, pathlib, sys
release = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert release['tag_name'] == os.environ['RELEASE_TAG'] and release['draft']
for asset in release['assets']:
    if asset['name'] == 'Codex-Island.dmg':
        assert isinstance(asset['id'], int)
        print(asset['id'])
PY
while read -r asset_id; do
    gh api --method DELETE "repos/$GH_REPO/releases/assets/$asset_id" > /dev/null
done < "$RUNNER_TEMP/replace-assets"

gh api --method POST \
    "https://uploads.github.com/repos/$GH_REPO/releases/$release_id/assets?name=Codex-Island.dmg" \
    -H 'Content-Type: application/octet-stream' --input dist/Codex-Island.dmg > "$RUNNER_TEMP/upload.json"
gh api "repos/$GH_REPO/releases/$release_id" > "$RUNNER_TEMP/release.json"
python3 - "$RUNNER_TEMP/release.json" <<'PY'
import hashlib, json, os, pathlib, sys
release = json.loads(pathlib.Path(sys.argv[1]).read_text())
asset = pathlib.Path('dist/Codex-Island.dmg')
assert release['tag_name'] == os.environ['RELEASE_TAG'] and release['draft']
matches = [item for item in release['assets'] if item['name'] == asset.name]
assert len(matches) == 1 and matches[0]['state'] == 'uploaded'
assert matches[0]['size'] == asset.stat().st_size
assert matches[0]['digest'] == 'sha256:' + hashlib.sha256(asset.read_bytes()).hexdigest()
PY

gh api --method PATCH "repos/$GH_REPO/releases/$release_id" \
    -F draft=false -f make_latest=true > "$RUNNER_TEMP/published-release.json"
python3 - "$RUNNER_TEMP/published-release.json" <<'PY'
import json, os, pathlib, sys
release = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert release['tag_name'] == os.environ['RELEASE_TAG'] and not release['draft']
print(release['html_url'])
PY
