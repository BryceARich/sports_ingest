# frozen_string_literal: true

# Shared helpers for the script/claude/* tools. Plain Ruby stdlib plus the `gh` and `git` CLIs,
# compatible with macOS system Ruby (2.6) so it works before the gem skeleton exists.
require "json"
require "open3"

module ClaudeScripts
  REPO = "BryceARich/sports_ingest"
  OWNER = "BryceARich"
  PROJECT = "1"
  BOT = "BryceAIRich"
  BOT_EMAIL = "360013208+BryceAIRich@users.noreply.github.com"
  # The repo is public, so anyone can open an issue. Only the maintainer's issues are worked on,
  # so a stranger can't get a session (holding the bot's token) to follow their text.
  TRUSTED_ISSUE_AUTHORS = [OWNER].freeze
  UNSCHEDULED_MILESTONE = 8 # M8 "Later" is never started automatically
  TITLE_RE = /\A\[M(\d+)-(\d+)\]\s*(.*)\z/.freeze

  module_function

  def run(*cmd, env: {}, allow_fail: false)
    out, err, status = Open3.capture3(env, *cmd)
    return out if status.success?
    return nil if allow_fail

    abort "error: `#{cmd.first(4).join(" ")} ...` failed:\n#{err.strip}"
  end

  # Runs gh with a --jq filter that emits one compact JSON value per line.
  def gh_lines(*args, env: {})
    run("gh", *args, env: env).each_line.map { |l| JSON.parse(l) }
  end

  def bot_env
    @bot_env ||= { "GH_TOKEN" => run("gh", "auth", "token", "--user", BOT).strip }
  end

  def main_clone
    File.dirname(run("git", "rev-parse", "--path-format=absolute", "--git-common-dir").strip)
  end

  def worktree_root
    File.join(File.dirname(main_clone), "sports_ingest-worktrees")
  end

  # [milestone, item] from "[M3-05] Title", or nil.
  def build_order(title)
    m = TITLE_RE.match(title)
    m && [m[1].to_i, m[2].to_i]
  end

  def label(issue)
    ms, item = build_order(issue["title"])
    format("M%d-%02d", ms, item)
  end

  def branch_name(issue)
    ms, item = build_order(issue["title"])
    words = TITLE_RE.match(issue["title"])[3].downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
    format("m%d-%02d-%s", ms, item, words)[0, 40].sub(/-+\z/, "")
  end

  # All issues (no PRs), trimmed to the fields we use. One paginated REST call.
  def all_issues
    gh_lines("api", "repos/#{REPO}/issues?state=all&per_page=100", "--paginate",
      "--jq", ".[] | select(.pull_request | not) | {number, title, state, body, author: .user.login}")
  end

  # True when the issue was opened by someone in TRUSTED_ISSUE_AUTHORS.
  def trusted?(issue)
    TRUSTED_ISSUE_AUTHORS.include?(issue["author"])
  end

  # Issue numbers listed under "## Blocked by" in the body (HTML comments ignored).
  def body_blockers(issue)
    body = (issue["body"] || "").gsub(/<!--.*?-->/m, "")
    section = body[/^##\s*Blocked by\s*$(.*?)(?=^##\s|\z)/m, 1] || ""
    section.scan(/#(\d+)/).flatten.map(&:to_i)
  end

  # GitHub's native "blocked by" links: { number => state }.
  def native_blockers(number)
    gh_lines("api", "repos/#{REPO}/issues/#{number}/dependencies/blocked_by",
      "--jq", ".[] | {number, state}").map { |h| [h["number"], h["state"]] }.to_h
  end

  # Open blockers of one issue, from both sources. `states` maps number => state.
  def open_blockers(issue, states)
    from_body = body_blockers(issue).reject { |n| states[n] == "closed" }
    return from_body unless from_body.empty?

    native_blockers(issue["number"]).reject { |_n, s| s == "closed" }.keys
  end

  # { issue number => { "status" => "Todo", "id" => item id } } for this repo's board items.
  def board_items
    gh_lines("project", "item-list", PROJECT, "--owner", OWNER, "--format", "json", "--limit", "500",
      "--jq", '.items[] | select(.content.type == "Issue") | ' \
              "{n: .content.number, repo: .content.repository, status: .status, id: .id}")
      .select { |h| h["repo"].nil? || h["repo"].casecmp?(REPO) }
      .map { |h| [h["n"], h] }.to_h
  end

  # Issue numbers that an open PR says it closes.
  def issues_with_open_prs
    bodies = gh_lines("pr", "list", "-R", REPO, "--state", "open", "--limit", "200",
      "--json", "body", "--jq", ".[] | {body}")
    bodies.flat_map { |h| (h["body"] || "").scan(/\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)/i) }
      .flatten.map(&:to_i)
  end

  def existing_branches
    remote = run("git", "-C", main_clone, "ls-remote", "--heads", "origin").to_s
      .scan(%r{refs/heads/(\S+)}).flatten
    local = run("git", "-C", main_clone, "branch", "--format=%(refname:short)").to_s.split("\n")
    remote + local
  end

  # Returns [ready, skipped]; each entry is { issue:, branch:, reason: }.
  def classify
    issues = all_issues
    states = issues.map { |i| [i["number"], i["state"]] }.to_h
    open_sched = issues.select do |i|
      i["state"] == "open" && build_order(i["title"]) && build_order(i["title"])[0] != UNSCHEDULED_MILESTONE
    end
    open_sched.sort_by! { |i| build_order(i["title"]) }
    current_ms = open_sched.map { |i| build_order(i["title"])[0] }.min

    board = board_items
    pr_issues = issues_with_open_prs
    branches = existing_branches
    ready = []
    skipped = []

    open_sched.each do |issue|
      n = issue["number"]
      branch = branch_name(issue)
      prefix = branch[/\Am\d+-\d+-/]
      status = board.dig(n, "status")
      blockers = open_blockers(issue, states)
      no_blockers = body_blockers(issue).empty?

      reason =
        if !trusted?(issue) then "opened by #{issue["author"]}, not a trusted author"
        elsif !blockers.empty? then "blocked by #{blockers.map { |b| "##{b}" }.join(", ")}"
        elsif no_blockers && build_order(issue["title"])[0] > current_ms then "milestone not open yet"
        elsif status && status != "Todo" then "status is #{status}"
        elsif pr_issues.include?(n) then "has an open PR"
        elsif branches.any? { |b| b.sub(%r{\A(?:[\w-]+/)+}, "").start_with?(prefix) } then "branch #{prefix}* exists"
        elsif File.exist?(File.join(worktree_root, branch)) then "worktree exists"
        end

      (reason ? skipped : ready) << { issue: issue, branch: branch, reason: reason }
    end
    [ready, skipped]
  end
end
