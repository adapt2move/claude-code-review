#!/usr/bin/env bash
# gh-review.sh — GitHub PR review tooling for the code-review plugin.
#
# One script, flat subcommands. Wraps the GitHub GraphQL API via `gh` so that
# creating reviews, managing inline threads, and gathering comment context are
# scriptable and stable across projects.
#
# Requirements: `gh` (authenticated) and `jq` on PATH.
# Usage: gh-review.sh <subcommand> [args]   (run with no args for help)

set -euo pipefail

REPO_INFO=$(gh repo view --json owner,name -q '"\(.owner.login)/\(.name)"' 2>/dev/null || echo "")
if [[ -z "$REPO_INFO" ]]; then
  echo "Error: not in a GitHub repository or gh is not authenticated" >&2
  exit 1
fi
OWNER=${REPO_INFO%%/*}
REPO=${REPO_INFO##*/}

usage() {
  cat <<'EOF'
Usage: gh-review.sh <subcommand> [args]

Reviews:
  create-review <pr>                                  Create a pending review, prints review ID
  add-comment <review_id> <path> <line> <body>        Add an inline comment to a pending review
  add-comment-multi <review_id> <path> <start> <end> <body>
                                                      Add a multi-line inline comment
  submit-review <review_id> <event> [body]            Submit (COMMENT | APPROVE | REQUEST_CHANGES)
  list-reviews <pr>                                   List top-level reviews with bodies (JSON)
  update-review <review_id> <body>                    Replace a review's top-level body

Threads:
  list-threads <pr>                                   List inline review threads (JSON)
  reply <thread_id> <body>                            Reply to a thread
  resolve <thread_id>                                 Resolve a thread
  reply-resolve <thread_id> <body>                    Reply and resolve in one step

Context:
  comment-context <pr> <comment_node_id>              Gather full context for one PR comment/thread

Examples:
  ID=$(gh-review.sh create-review 182)
  gh-review.sh add-comment "$ID" src/file.ts 42 "Nullable value dereferenced here"
  gh-review.sh submit-review "$ID" REQUEST_CHANGES "See inline comments."
  gh-review.sh reply-resolve PRT_abc "Fixed in a1b2c3d."
EOF
}

require_args() {
  local n=$1; shift
  local got=$#
  if (( got < n )); then
    echo "Error: expected $n argument(s), got $got" >&2
    exit 1
  fi
}

pr_node_id() {
  gh api graphql -f query='
    query($prNumber: Int!, $owner: String!, $repo: String!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $prNumber) { id }
      }
    }' -f owner="$OWNER" -f repo="$REPO" -F prNumber="$1" \
    | jq -r '.data.repository.pullRequest.id'
}

create_review() {
  require_args 1 "$@"
  local pr_id; pr_id=$(pr_node_id "$1")
  if [[ -z "$pr_id" || "$pr_id" == "null" ]]; then
    echo "Error: could not find PR #$1" >&2; exit 1
  fi
  gh api graphql -f query='
    mutation($prId: ID!) {
      addPullRequestReview(input: { pullRequestId: $prId }) {
        pullRequestReview { id }
      }
    }' -f prId="$pr_id" \
    | jq -r '.data.addPullRequestReview.pullRequestReview.id'
}

add_comment() {
  require_args 4 "$@"
  gh api graphql -f query='
    mutation($reviewId: ID!, $path: String!, $line: Int!, $body: String!) {
      addPullRequestReviewThread(input: {
        pullRequestReviewId: $reviewId, path: $path, line: $line, side: RIGHT, body: $body
      }) { thread { id } }
    }' -f reviewId="$1" -f path="$2" -F line="$3" -f body="$4" \
    | jq -r '.data.addPullRequestReviewThread.thread.id'
}

add_comment_multi() {
  require_args 5 "$@"
  gh api graphql -f query='
    mutation($reviewId: ID!, $path: String!, $startLine: Int!, $line: Int!, $body: String!) {
      addPullRequestReviewThread(input: {
        pullRequestReviewId: $reviewId, path: $path,
        startLine: $startLine, startSide: RIGHT, line: $line, side: RIGHT, body: $body
      }) { thread { id } }
    }' -f reviewId="$1" -f path="$2" -F startLine="$3" -F line="$4" -f body="$5" \
    | jq -r '.data.addPullRequestReviewThread.thread.id'
}

submit_review() {
  require_args 2 "$@"
  local review_id=$1 event=$2 body=${3:-""}
  if [[ "$event" != "COMMENT" && "$event" != "APPROVE" && "$event" != "REQUEST_CHANGES" ]]; then
    echo "Error: event must be COMMENT, APPROVE, or REQUEST_CHANGES" >&2; exit 1
  fi
  if [[ -n "$body" ]]; then
    gh api graphql -f query='
      mutation($reviewId: ID!, $event: PullRequestReviewEvent!, $body: String!) {
        submitPullRequestReview(input: { pullRequestReviewId: $reviewId, event: $event, body: $body }) {
          pullRequestReview { state }
        }
      }' -f reviewId="$review_id" -f event="$event" -f body="$body" \
      | jq -r '.data.submitPullRequestReview.pullRequestReview.state'
  else
    gh api graphql -f query='
      mutation($reviewId: ID!, $event: PullRequestReviewEvent!) {
        submitPullRequestReview(input: { pullRequestReviewId: $reviewId, event: $event }) {
          pullRequestReview { state }
        }
      }' -f reviewId="$review_id" -f event="$event" \
      | jq -r '.data.submitPullRequestReview.pullRequestReview.state'
  fi
}

list_reviews() {
  require_args 1 "$@"
  gh api graphql -f query='
    query($prNumber: Int!, $owner: String!, $repo: String!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $prNumber) {
          reviews(last: 10) {
            nodes { id author { login } state body submittedAt }
          }
        }
      }
    }' -f owner="$OWNER" -f repo="$REPO" -F prNumber="$1" \
    | jq '.data.repository.pullRequest.reviews.nodes | map(select(.body != null and .body != ""))'
}

update_review() {
  require_args 2 "$@"
  gh api graphql -f query='
    mutation($pullRequestReviewId: ID!, $body: String!) {
      updatePullRequestReview(input: { pullRequestReviewId: $pullRequestReviewId, body: $body }) {
        pullRequestReview { id body }
      }
    }' -f pullRequestReviewId="$1" -f body="$2"
}

list_threads() {
  require_args 1 "$@"
  gh api graphql -f query='
    query($prNumber: Int!, $owner: String!, $repo: String!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $prNumber) {
          reviewThreads(last: 50) {
            nodes {
              id isResolved path line
              comments(last: 20) { nodes { author { login } body createdAt } }
            }
          }
        }
      }
    }' -f owner="$OWNER" -f repo="$REPO" -F prNumber="$1" \
    | jq '.data.repository.pullRequest.reviewThreads.nodes'
}

reply_thread() {
  require_args 2 "$@"
  gh api graphql -f query='
    mutation($threadId: ID!, $body: String!) {
      addPullRequestReviewThreadReply(input: { pullRequestReviewThreadId: $threadId, body: $body }) {
        comment { id }
      }
    }' -f threadId="$1" -f body="$2"
}

resolve_thread() {
  require_args 1 "$@"
  gh api graphql -f query='
    mutation($threadId: ID!) {
      resolveReviewThread(input: { threadId: $threadId }) { thread { isResolved } }
    }' -f threadId="$1"
}

reply_resolve() {
  require_args 2 "$@"
  reply_thread "$1" "$2" > /dev/null
  resolve_thread "$1"
}

comment_context() {
  require_args 2 "$@"
  local pr_number=$1 node_id=$2
  local all_threads; all_threads=$(list_threads "$pr_number" 2>/dev/null || echo '[]')

  echo "## Repository"; echo "$OWNER/$REPO"; echo ""
  echo "## PR Context"
  gh pr view "$pr_number" --json headRefName,baseRefName,title,state \
    --jq '"Branch: \(.headRefName) -> \(.baseRefName)\nState: \(.state)\nTitle: \(.title)"'
  echo ""

  echo "## Triggering Comment"
  local data node_type thread_id=""
  data=$(gh api graphql \
    -f query='query($id: ID!) { node(id: $id) { __typename ... on PullRequestReviewComment { body path line diffHunk author { login } } ... on PullRequestReviewThread { path line } ... on IssueComment { body author { login } } } }' \
    -f id="$node_id" | jq '.data.node')
  node_type=$(echo "$data" | jq -r '.__typename // empty')

  if [[ "$node_type" == "PullRequestReviewThread" ]]; then
    thread_id="$node_id"
    data=$(echo "$all_threads" | jq --arg tid "$thread_id" '
      .[] | select(.id == $tid) |
      { body: .comments.nodes[0].body, path, line, diffHunk: null,
        author: .comments.nodes[0].author, pullRequestReviewThread: { id: .id } }')
  elif [[ "$node_type" == "PullRequestReviewComment" ]]; then
    local comment_body; comment_body=$(echo "$data" | jq -r '.body // empty')
    thread_id=$(echo "$all_threads" | jq -r --arg body "$comment_body" '
      [.[] | select(.comments.nodes | any(.body == $body))] | .[0].id // empty')
    if [[ -n "$thread_id" ]]; then
      data=$(echo "$data" | jq --arg tid "$thread_id" '. + {pullRequestReviewThread: {id: $tid}}')
    fi
  fi
  echo "$data"; echo ""

  if [[ -n "$thread_id" ]]; then
    echo "## Thread Conversation"
    echo "$all_threads" | jq --arg tid "$thread_id" '.[] | select(.id == $tid)'
    echo ""
  fi

  echo "## Unresolved Threads"
  echo "$all_threads" | jq '[.[] | select(.isResolved == false)]'
}

cmd=${1:-}
[[ $# -gt 0 ]] && shift || true
case "$cmd" in
  create-review)     create_review "$@" ;;
  add-comment)       add_comment "$@" ;;
  add-comment-multi) add_comment_multi "$@" ;;
  submit-review)     submit_review "$@" ;;
  list-reviews)      list_reviews "$@" ;;
  update-review)     update_review "$@" ;;
  list-threads)      list_threads "$@" ;;
  reply)             reply_thread "$@" ;;
  resolve)           resolve_thread "$@" ;;
  reply-resolve)     reply_resolve "$@" ;;
  comment-context)   comment_context "$@" ;;
  ""|-h|--help|help) usage ;;
  *) echo "Unknown subcommand: $cmd" >&2; echo >&2; usage >&2; exit 1 ;;
esac
