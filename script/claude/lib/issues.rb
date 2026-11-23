# frozen_string_literal: true

# Shared helpers for the script/claude/* tools. Plain Ruby stdlib plus the `gh` and `git` CLIs,
# compatible with macOS system Ruby (2.6) so it works before the gem skeleton exists.
require "json"
require "open3"

module ClaudeScripts
  PROJECT = "1" # project board number, under the repo owner
  UNSCHEDULED_MILESTONE = 8 # M8 "Later" is never started automatically
  TITLE_RE = /\A\[M(\d+)-(\d+)\]\s*(.*)\z/
  # The repo is public, so anyone can open an issue or comment. Only text from people with a role
  # on the repo is acted on, so a stranger can't steer a session that holds a GitHub token.
  TRUSTED_ASSOCIATIONS = %w[OWNER MEMBER COLLABORATOR].freeze

  module_function

  def run(*cmd, env: {}, allow_fail: false)
    out, err, status = Open3.capture3(env, *cmd)
    return out if status.success?
    return nil if allow_fail

    abort "error: `#{cmd.first(4).join(" ")} ...` failed:\n#{err.strip}"
  end

  # "owner/name" of the GitHub repo this clone's origin points at.
  def repo
    @repo ||= run("gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner").strip
  end

  def owner
    repo.split("/").first
  end

  # Local (never committed) git config, or nil.
  def local_config(key)
    v = run("git", "config", "--get", key, allow_fail: true).to_s.strip
    v.empty? ? nil : v
  end

  # The GitHub account Claude works as, from `git config claude.botUser`; nil means "whoever
  # `gh` and git are already logged in as".
  def bot
    local_config("claude.botUser")
  end

  # Commit email for the bot: `git config claude.botEmail`, else its GitHub noreply address.
  def bot_email
    return nil unless bot

    @bot_email ||= local_config("claude.botEmail") || begin
      id = run("gh", "api", "users/#{bot}", "--jq", ".id").strip
      "#{id}+#{bot}@users.noreply.github.com"
    end
  end

  # Remote that Claude pushes to: `git config claude.botRemote`, else "bot" when a bot is set.
  def push_remote
    local_config("claude.botRemote") || (bot ? "bot" : "origin")
  end

  # Env for gh calls as the bot (empty when no bot is configured or GH_TOKEN is already set).
  def bot_env
    return {} if bot.nil? || ENV["GH_TOKEN"]

    @bot_env ||= {"GH_TOKEN" => run("gh", "auth", "token", "--user", bot).strip}
  end

  # Env for git commits as the bot (empty when no bot is configured).
  def bot_git_env
    return {} unless bot

    {"GIT_AUTHOR_NAME" => bot, "GIT_COMMITTER_NAME" => bot,
     "GIT_AUTHOR_EMAIL" => bot_email, "GIT_COMMITTER_EMAIL" => bot_email}
  end

  def trusted?(item)
    TRUSTED_ASSOCIATIONS.include?(item["association"])
  end

  # Runs gh with a --jq filter that emits one compact JSON value per line.
  def gh_lines(*args, env: {})
    run("gh", *args, env: env).each_line.map { |l| JSON.parse(l) }
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
    gh_lines("api", "repos/#{repo}/issues?state=all&per_page=100", "--paginate",
      "--jq", ".[] | select(.pull_request | not) | {number, title, state, body, author: .user.login, association: .author_association}")
  end

  # Issue numbers listed under "## Blocked by" in the body (HTML comments ignored).
  def body_blockers(issue)
    body = (issue["body"] || "").gsub(/<!--.*?-->/m, "")
    section = body[/^##\s*Blocked by\s*$(.*?)(?=^##\s|\z)/m, 1] || ""
    section.scan(/#(\d+)/).flatten.map(&:to_i)
  end

  # GitHub's native "blocked by" links: { number => state }.
  def native_blockers(number)
    gh_lines("api", "repos/#{repo}/issues/#{number}/dependencies/blocked_by",
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
    gh_lines("project", "item-list", PROJECT, "--owner", owner, "--format", "json", "--limit", "500",
      "--jq", '.items[] | select(.content.type == "Issue") | ' \
              "{n: .content.number, repo: .content.repository, status: .status, id: .id}")
      .select { |h| h["repo"].nil? || h["repo"].casecmp?(repo) }
      .map { |h| [h["n"], h] }.to_h
  end

  # Issue numbers that an open PR says it closes.
  def issues_with_open_prs
    bodies = gh_lines("pr", "list", "-R", repo, "--state", "open", "--limit", "200",
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
        if !trusted?(issue) then "opened by #{issue["author"]}, who has no role on the repo"
        elsif !blockers.empty? then "blocked by #{blockers.map { |b| "##{b}" }.join(", ")}"
        elsif no_blockers && build_order(issue["title"])[0] > current_ms then "milestone not open yet"
        elsif status && status != "Todo" then "status is #{status}"
        elsif pr_issues.include?(n) then "has an open PR"
        elsif branches.any? { |b| b.sub(%r{\A(?:[\w-]+/)+}, "").start_with?(prefix) } then "branch #{prefix}* exists"
        elsif File.exist?(File.join(worktree_root, branch)) then "worktree exists"
        end

      (reason ? skipped : ready) << {issue: issue, branch: branch, reason: reason}
    end
    [ready, skipped]
  end
end
