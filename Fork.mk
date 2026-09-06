# Fork operations for slmingol/yt-dlp
# Usage: make -f Fork.mk [target]

UPSTREAM_REMOTE := upstream
UPSTREAM_BRANCH := master
FORK_REMOTE     := origin
FORK_BRANCH     := main
DEBUG_BRANCH    := debug
GH_REPO         := slmingol/yt-dlp

# ANSI via printf %b so they work on both macOS and Linux BSD/GNU
B  := $(shell printf '\033[1m')
D  := $(shell printf '\033[2m')
R  := $(shell printf '\033[0m')
GR := $(shell printf '\033[32m')
YL := $(shell printf '\033[33m')
BL := $(shell printf '\033[34m')
CY := $(shell printf '\033[36m')
WH := $(shell printf '\033[97m')

.DEFAULT_GOAL := help
.PHONY: help status sync release debug-push debug-fetch drop-patch staleness

# ── Help ──────────────────────────────────────────────────────────────────────

help:
	@printf "\n$(B)$(WH)Fork.mk$(R) $(D)— ops for $(GH_REPO)$(R)\n\n"
	@printf "  $(B)$(CY)status$(R)       $(D)Version, patches, tags, upstream file activity$(R)\n"
	@printf "  $(B)$(CY)sync$(R)         $(D)Rebase fork patches onto upstream/master and push$(R)\n"
	@printf "  $(B)$(CY)release$(R)      $(D)Tag and push next fork.N for current version$(R)\n"
	@printf "  $(B)$(CY)debug-push$(R)   $(D)Reset debug to main + push (triggers CI)$(R)\n"
	@printf "  $(B)$(CY)debug-fetch$(R)  $(D)Download latest debug CI artifact for this OS$(R)\n"
	@printf "  $(B)$(CY)staleness$(R)    $(D)Check upstream activity on patched files$(R)\n"
	@printf "  $(B)$(CY)drop-patch$(R)   $(D)List fork-only commits + drop instructions$(R)\n\n"

# ── Status ────────────────────────────────────────────────────────────────────

status:
	@printf "\n$(B)$(BL)══ STATUS ────────────────────────────────$(R)\n\n"
	@printf "$(B)  Upstream version$(R)\n"
	@printf "  $(GR)$(B)%s$(R)\n\n" "$$(python3 -c "import re; print(re.search(r\"__version__ = '(.+)'\", open('yt_dlp/version.py').read()).group(1))")"
	@printf "$(B)  Fork patches$(R) $(D)(ahead of upstream)$(R)\n"
	@git log $(UPSTREAM_REMOTE)/$(UPSTREAM_BRANCH)..HEAD --no-merges \
	  --format="  $(YL)%h$(R) %s" --color=never
	@printf "\n$(B)  Release tags$(R)\n"
	@git tag --list 'v*-fork.*' | sort -V | tail -5 | sed "s/^/  $(GR)/" | sed "s/$$/$(R)/"
	@printf "\n$(B)  Upstream activity on patched files$(R)\n"
	@printf "  $(D)pbs.py$(R)\n"
	@git log $(UPSTREAM_REMOTE)/$(UPSTREAM_BRANCH) --no-merges -5 \
	  --format="    $(D)%h$(R) %s" --color=never -- yt_dlp/extractor/pbs.py
	@printf "  $(D)odnoklassniki.py$(R)\n"
	@git log $(UPSTREAM_REMOTE)/$(UPSTREAM_BRANCH) --no-merges -5 \
	  --format="    $(D)%h$(R) %s" --color=never -- yt_dlp/extractor/odnoklassniki.py
	@printf "\n"

# ── Sync ──────────────────────────────────────────────────────────────────────

sync:
	@printf "\n$(B)$(BL)══ SYNC ────────────────────────────────$(R)\n\n"
	@printf "$(CY)  Fetching upstream...$(R)\n"
	@git fetch $(UPSTREAM_REMOTE) $(UPSTREAM_BRANCH)
	@git checkout $(FORK_BRANCH) -q
	@if ! git diff --quiet || ! git diff --cached --quiet; then \
	  printf "$(YL)  Stashing uncommitted changes...$(R)\n"; \
	  git stash push -u -m "fork-sync-stash"; \
	  git rebase $(UPSTREAM_REMOTE)/$(UPSTREAM_BRANCH); \
	  git stash pop; \
	  printf "$(YL)  ✔ stash restored$(R)\n"; \
	else \
	  git rebase $(UPSTREAM_REMOTE)/$(UPSTREAM_BRANCH); \
	fi
	@git push $(FORK_REMOTE) $(FORK_BRANCH) --force-with-lease -q
	@printf "$(GR)  ✔ main rebased and pushed$(R)\n\n"

# ── Release ───────────────────────────────────────────────────────────────────

release:
	@printf "\n$(B)$(BL)══ RELEASE ────────────────────────────────$(R)\n\n"
	$(eval VER := $(shell python3 -c "import re; print(re.search(r\"__version__ = '(.+)'\", open('yt_dlp/version.py').read()).group(1))"))
	$(eval N   := $(shell n=1; while git ls-remote --tags $(FORK_REMOTE) "refs/tags/v$(VER)-fork.$$n" | grep -q .; do n=$$((n+1)); done; echo $$n))
	$(eval TAG := v$(VER)-fork.$(N))
	@printf "$(CY)  Tagging $(B)$(TAG)$(R)\n"
	@git tag "$(TAG)"
	@git push $(FORK_REMOTE) "$(TAG)" -q
	@printf "$(GR)  ✔ $(TAG) pushed$(R)\n"
	@printf "$(D)  → https://github.com/$(GH_REPO)/actions/workflows/release-fork.yml$(R)\n\n"

# ── Debug branch ──────────────────────────────────────────────────────────────

debug-push:
	@printf "\n$(B)$(BL)══ DEBUG PUSH ────────────────────────────────$(R)\n\n"
	@git checkout $(DEBUG_BRANCH) -q
	@git reset --hard $(FORK_BRANCH) -q
	@git push $(FORK_REMOTE) $(DEBUG_BRANCH) --force-with-lease -q
	@git checkout $(FORK_BRANCH) -q
	@printf "$(GR)  ✔ debug reset to main and pushed$(R)\n"
	@printf "$(D)  → https://github.com/$(GH_REPO)/actions/workflows/debug-build.yml$(R)\n\n"

debug-fetch:
	@printf "\n$(B)$(BL)══ DEBUG FETCH ────────────────────────────────$(R)\n\n"
	@RUN_ID=$$(gh run list --repo $(GH_REPO) --workflow debug-build.yml --limit 1 --json databaseId -q '.[0].databaseId'); \
	SHA=$$(gh run view "$$RUN_ID" --repo $(GH_REPO) --json headSha -q '.headSha'); \
	OS_KEY=$$(uname | tr '[:upper:]' '[:lower:]' | sed 's/darwin/macos/'); \
	ARTIFACT="yt-dlp-debug-$${OS_KEY}-latest-$${SHA}"; \
	DEST=~/yt-dlp-debug/"$$ARTIFACT"; \
	if [[ -d "$$DEST" ]]; then \
	  printf "$(YL)  already downloaded: %s$(R)\n\n" "$$ARTIFACT"; exit 0; \
	fi; \
	printf "$(CY)  Downloading %s...$(R)\n" "$$ARTIFACT"; \
	mkdir -p "$$DEST"; \
	gh run download "$$RUN_ID" --repo $(GH_REPO) --dir "$$DEST" --name "$$ARTIFACT"; \
	printf "$(GR)  ✔ %s$(R)\n\n" "$$DEST"

# ── Staleness ─────────────────────────────────────────────────────────────────

staleness:
	@printf "\n$(B)$(BL)══ STALENESS CHECK ────────────────────────────────$(R)\n\n"
	@git fetch $(UPSTREAM_REMOTE) $(UPSTREAM_BRANCH) -q
	@printf "  $(B)pbs.py$(R)\n"
	@git log $(UPSTREAM_REMOTE)/$(UPSTREAM_BRANCH) --no-merges -10 \
	  --format="    $(D)%h$(R) %s" --color=never -- yt_dlp/extractor/pbs.py
	@printf "\n  $(B)odnoklassniki.py$(R)\n"
	@git log $(UPSTREAM_REMOTE)/$(UPSTREAM_BRANCH) --no-merges -10 \
	  --format="    $(D)%h$(R) %s" --color=never -- yt_dlp/extractor/odnoklassniki.py
	@printf "\n"

# ── Patch management ──────────────────────────────────────────────────────────

drop-patch:
	@printf "\n$(B)$(BL)══ DROP PATCH ────────────────────────────────$(R)\n\n"
	@printf "$(B)  Fork-only commits$(R) $(D)(candidates to drop)$(R)\n"
	@git log $(UPSTREAM_REMOTE)/$(UPSTREAM_BRANCH)..HEAD --no-merges \
	  --format="  $(YL)%h$(R) %s" --color=never
	@printf "\n$(B)  To drop a patch:$(R)\n"
	@printf "  $(D)git rebase -i $(UPSTREAM_REMOTE)/$(UPSTREAM_BRANCH)$(R)\n"
	@printf "  $(D)# mark the commit 'drop', save$(R)\n"
	@printf "  $(D)git push $(FORK_REMOTE) $(FORK_BRANCH) --force-with-lease$(R)\n"
	@printf "  $(D)make -f Fork.mk release$(R)\n\n"
