require "commits_processor"
require "time"
class PayloadProcessor

  include PayloadUtils

  def initialize(config, insights_event_queue)
    @commits_queue = Queue.new
    @insights_event_queue = insights_event_queue
    CommitsProcessor.new(insights_event_queue, @commits_queue, config).run
    CommitsProcessor.new(insights_event_queue, @commits_queue, config).run
    CommitsProcessor.new(insights_event_queue, @commits_queue, config).run
    CommitsProcessor.new(insights_event_queue, @commits_queue, config).run
  end

  def process(event)

    payload = find(event, 'payload')

    event_name = breakdown(find(event, 'type'), payload)

    event_attrs = { }
    event_attrs['eventType'] = 'GithubEvent'
    event_attrs['gitEventType'] = event_name
    merge_property(event_attrs, event, 'repo', 'repo/name')
    merge_property(event_attrs, event, 'repoName', 'repo/name') { | val |
      val.split('/').last
    }
    merge_property(event_attrs, event, 'account', 'repo/name') { | val |
      val.split('/').first
    }

    merge_property(event_attrs, event, 'user', 'actor/login', 'payload/pusher/name')

    merge_property(event_attrs, event, 'org', 'org/login')
    merge_property(event_attrs, payload, 'sha', 'sha') { |sha| sha[0..6] }

    opened = find(payload, "pull_request/created_at")
    closed = find(payload, "pull_request/merged_at")
    merge_property(event_attrs, payload, 'pullRequestId', 'pull_request/id', )
    merge_property(event_attrs, payload, 'title', 'pull_request/title')
    merge_property(event_attrs, payload, 'ref', 'pull_request/head/ref', )
    merge_property(event_attrs, payload, 'link', 'pull_request/html_url', )

    if (opened && closed)
      event_name = 'PullRequestMerged'
      age_in_hours = (Time.parse(closed) - Time.parse(opened)).to_f / (60.0 * 60.0)
      event_attrs['ageOfPullRequest'] = age_in_hours
      merge_property(event_attrs, payload, 'changedFiles', 'pull_request/changed_files')
      merge_property(event_attrs, payload, 'reviewComments', 'pull_request/review_comments')
      merge_property(event_attrs, payload, 'commits', 'pull_request/commits')
      additions = find(payload, 'pull_request/additions')
      deletions = find(payload, 'pull_request/deletions')
      event_attrs['netLinesAdded'] = additions.to_i - deletions.to_i if (additions && deletions)
    end

    add event_attrs
    commits = find(payload, "commits")
    if commits
      ref = find(payload, "ref")
      if ref =~ %r{refs/heads/(.*)$}
        event_attrs['ref'] = $1
      end
      @commits_queue << { common_attrs: event_attrs, commits: commits }
      if @commits_queue.size > 100
        $stderr.puts "Commits backlog: #{@commits_queue.size}"
      end
    end
  end

  private

  def count(name, payload, regex, *paths)
    count = 0
    paths.each do | path |
      if (text = find(payload, path))
        count += text.scan(regex).count
      end
    end
    count > 0 ? { name => count } : {}
  end

  def breakdown(event_name, payload)
    # With pull requests we distinguish between each of the PR
    # actions by appending them to the event_name key
    case event_name
    when 'PullRequestEvent'
      action = find(payload, 'action')
      # With closed actions we distinguish between PR's that were merged
      # and those that were closed without merging (cancelled).
      if (action == 'closed')
        merged = find(payload, 'pull_request/merged_at')
        action = !merged.nil? ? 'Merged' : 'Cancelled'
      else
        action = action.capitalize
      end
      event_name = "PullRequest#{action}"
    when 'CreateEvent'
      ref_type = find(payload, 'ref_type')
      event_name = "Create#{ref_type.capitalize}"

    when 'StatusEvent'
      state  = find(payload, 'state')
      event_name = "Commit#{state.capitalize}"
    end
    return event_name
  end

  def add event
    @insights_event_queue << event
  end

end

