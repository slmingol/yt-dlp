# Fork operations for slmingol/yt-dlp
# Usage: make -f Fork.mk <target>

UPSTREAM_REMOTE := upstream
UPSTREAM_BRANCH := master
FORK_REMOTE     := origin
FORK_BRANCH     := main
DEBUG_BRANCH    := debug
GH_REPO         := slmingol/yt-dlp

.PHONY: help status sync release debug-push debug-fetch debug-run drop-patch staleness

help:
	@echo "Fork.mk -- fork ops for $(GH_REPO)"
	@echo ""
	@echo "  status        Show fork state: version, patches, tags"
	@echo "  sync          Rebase fork patches onto upstream/master and push"
	@echo "  release       Tag and push next fork.N release for current version"
	@echo "  debug-push    Reset debug branch to main + push (triggers CI build)"
	@echo "  debug-fetch   Download latest debug CI artifact (macOS)"
	@echo "  staleness     Check if upstream has touched patched files"
	@echo "  drop-patch    List fork-only commits for manual review/drop"

# ── Status ────────────────────────────────────────────────────────────────────

status:
	@echo "=== Upstream version ==="
	@python3 -c "import re; print(re.search(r\"__version__ = '(.+)'\", open('yt_dlp/version.py').read()).group(1))"
	@echo ""
	@echo "=== Fork patches (commits ahead of upstream) ==="
	@git log $(UPSTREAM_REMOTE)/$(UPSTREAM_BRANCH)..HEAD --oneline --no-merges
	@echo ""
	@echo "=== Fork release tags ==="
	@git tag --list 'v*-fork.*' | sort -V | tail -5
	@echo ""
	@echo "=== Patched files upstream activity (last 10 upstream commits) ==="
	@echo "-- pbs.py --"
	@git log $(UPSTREAM_REMOTE)/$(UPSTREAM_BRANCH) --oneline -5 -- yt_dlp/extractor/pbs.py
	@echo "-- odnoklassniki.py --"
	@git log $(UPSTREAM_REMOTE)/$(UPSTREAM_BRANCH) --oneline -5 -- yt_dlp/extractor/odnoklassniki.py

# ── Sync ──────────────────────────────────────────────────────────────────────

sync:
	git fetch $(UPSTREAM_REMOTE) $(UPSTREAM_BRANCH)
	git checkout $(FORK_BRANCH)
	git rebase $(UPSTREAM_REMOTE)/$(UPSTREAM_BRANCH)
	git push $(FORK_REMOTE) $(FORK_BRANCH) --force-with-lease

# ── Release ───────────────────────────────────────────────────────────────────

release:
	$(eval VER := $(shell python3 -c "import re; print(re.search(r\"__version__ = '(.+)'\", open('yt_dlp/version.py').read()).group(1))"))
	$(eval N   := $(shell n=1; while git ls-remote --tags $(FORK_REMOTE) "refs/tags/v$(VER)-fork.$$n" | grep -q .; do n=$$((n+1)); done; echo $$n))
	$(eval TAG := v$(VER)-fork.$(N))
	@echo "Tagging $(TAG)"
	git tag "$(TAG)"
	git push $(FORK_REMOTE) "$(TAG)"
	@echo "Release workflow triggered: https://github.com/$(GH_REPO)/actions/workflows/release-fork.yml"

# ── Debug branch ──────────────────────────────────────────────────────────────

debug-push:
	git checkout $(DEBUG_BRANCH)
	git reset --hard $(FORK_BRANCH)
	git push $(FORK_REMOTE) $(DEBUG_BRANCH) --force-with-lease
	git checkout $(FORK_BRANCH)
	@echo "Debug build triggered: https://github.com/$(GH_REPO)/actions/workflows/debug-build.yml"

debug-fetch:
	@RUN_ID=$$(gh run list --repo $(GH_REPO) --workflow debug-build.yml --limit 1 --json databaseId -q '.[0].databaseId'); \
	SHA=$$(gh run view "$$RUN_ID" --repo $(GH_REPO) --json headSha -q '.headSha'); \
	OS_KEY=$$(uname | tr '[:upper:]' '[:lower:]' | sed 's/darwin/macos/'); \
	ARTIFACT="yt-dlp-debug-$${OS_KEY}-latest-$${SHA}"; \
	DEST=~/yt-dlp-debug/"$$ARTIFACT"; \
	if [[ -d "$$DEST" ]]; then echo "Already downloaded: $$ARTIFACT"; exit 0; fi; \
	gh run download "$$RUN_ID" --repo $(GH_REPO) --dir ~/yt-dlp-debug --name "$$ARTIFACT"; \
	echo "Downloaded: $$ARTIFACT"

# ── Staleness ─────────────────────────────────────────────────────────────────

staleness:
	@git fetch $(UPSTREAM_REMOTE) $(UPSTREAM_BRANCH) -q
	@echo "=== Upstream commits touching pbs.py ==="
	@git log $(UPSTREAM_REMOTE)/$(UPSTREAM_BRANCH) --oneline -10 -- yt_dlp/extractor/pbs.py
	@echo ""
	@echo "=== Upstream commits touching odnoklassniki.py ==="
	@git log $(UPSTREAM_REMOTE)/$(UPSTREAM_BRANCH) --oneline -10 -- yt_dlp/extractor/odnoklassniki.py

# ── Patch management ──────────────────────────────────────────────────────────

drop-patch:
	@echo "Fork-only commits (candidates to drop when upstream fixes the bug):"
	@git log $(UPSTREAM_REMOTE)/$(UPSTREAM_BRANCH)..HEAD --oneline --no-merges
	@echo ""
	@echo "To drop a patch:"
	@echo "  git rebase -i $(UPSTREAM_REMOTE)/$(UPSTREAM_BRANCH)"
	@echo "  # mark the commit 'drop', save"
	@echo "  git push $(FORK_REMOTE) $(FORK_BRANCH) --force-with-lease"
	@echo "  make -f Fork.mk release"
