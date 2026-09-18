#!/usr/bin/env bash
# Behavior tests for bin/fm-upstream-pre-sync.sh.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCRIPT="$ROOT/bin/fm-upstream-pre-sync.sh"
TMP_ROOT=$(fm_test_tmproot fm-upstream-pre-sync)
fm_git_identity fmtest fmtest@example.invalid

make_repo_without_upstream() {
  local repo=$1
  fm_git_init_commit "$repo"
  git -C "$repo" remote add origin "file://$TMP_ROOT/origin-only.git"
}

make_diverged_pair() {  # <name> <upstream-file> <local-file>
  local name=$1 upstream_file=$2 local_file=$3 base upstream_bare upstream_work local_repo
  base="$TMP_ROOT/$name-base"
  upstream_bare="$TMP_ROOT/$name-upstream.git"
  upstream_work="$TMP_ROOT/$name-upstream-work"
  local_repo="$TMP_ROOT/$name-local"

  fm_git_init_commit "$base"
  git clone --quiet --bare "$base" "$upstream_bare"
  git clone --quiet "$upstream_bare" "$upstream_work"
  git clone --quiet "$upstream_bare" "$local_repo"
  git -C "$local_repo" remote add upstream "file://$upstream_bare"

  printf 'upstream\n' > "$upstream_work/$upstream_file"
  git -C "$upstream_work" add "$upstream_file"
  git -C "$upstream_work" commit -qm "upstream change"
  git -C "$upstream_work" push --quiet origin main

  printf 'local\n' > "$local_repo/$local_file"
  git -C "$local_repo" add "$local_file"
  git -C "$local_repo" commit -qm "local change"

  printf '%s\n' "$local_repo"
}

test_requires_upstream_remote() {
  local repo out rc
  repo="$TMP_ROOT/no-upstream"
  make_repo_without_upstream "$repo"
  set +e
  out=$(cd "$repo" && "$SCRIPT" --no-fetch 2>&1)
  rc=$?
  set -e
  expect_code 2 "$rc" "script should refuse when remote is missing"
  assert_contains "$out" "remote 'upstream' is not configured" "missing-remote error should be explicit"
  assert_contains "$out" "git remote add upstream <source-repo-url>" "missing-remote hint should include add command"
  pass "upstream pre-sync: refuses cleanly without configured upstream remote"
}

test_reports_overlap_and_manual_reconcile() {
  local repo out
  repo=$(make_diverged_pair overlap-case calm.txt calm.txt)
  out=$(cd "$repo" && "$SCRIPT")
  assert_contains "$out" "incoming-commits: 1" "overlap case should detect one incoming commit"
  assert_contains "$out" "overlap-files: 1" "overlap case should detect changed file overlap"
  assert_contains "$out" "calm-overlap-files: 1" "calm overlap counter should flag calm-related conflicts"
  assert_contains "$out" "result: manual reconcile required before merge or cherry-pick." \
    "overlap case should recommend manual reconcile"
  pass "upstream pre-sync: reports overlap risk and manual reconcile recommendation"
}

test_reports_low_risk_when_no_overlap() {
  local repo out
  repo=$(make_diverged_pair safe-case upstream.txt local.txt)
  out=$(cd "$repo" && "$SCRIPT")
  assert_contains "$out" "incoming-commits: 1" "safe case should detect one incoming commit"
  assert_contains "$out" "overlap-files: 0" "safe case should show no overlap"
  assert_contains "$out" "result: low-risk fast-forward candidate after commit review." \
    "safe case should recommend low-risk fast-forward"
  pass "upstream pre-sync: marks non-overlapping updates as low-risk"
}

test_requires_upstream_remote
test_reports_overlap_and_manual_reconcile
test_reports_low_risk_when_no_overlap

echo "ALL TESTS PASSED"
