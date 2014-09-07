require "commits_processor"
module PayloadProcessor
  include CommitsProcessor

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
#    merge_property(event_attrs, payload, 'text',
#                   'issue/body', 'comment/body', 'pull_request/body', 'message') { | comment |
#      event['textLength'] = comment.length
#      comment[0..4094]
#    }

    add event_attrs
    commits = find(payload, "commits")
    process_commits(commits, event_attrs) if commits
    # events.each { |e|
    #   ap e, multiline: false
    # }
  end

  def merge_property(attrs, root, key, *paths)
    paths = [key] if paths.empty?
    for path in paths do
      val = find(root, path)
      if val
        if block_given?
          val = yield val.to_s[0..2046]
          attrs[key] = val if val
        else
          attrs[key] = val.is_a?(String) ? val[0..2046] : val
        end
        break
      end
    end
  end


  # Traverse the hash via '/' separated keys, returning nil if any part is missing
  def find(hash, path)
    return hash if path.nil?
    segment, remainder = path.split('/', 2)
    if hash.include? segment
      find hash[segment], remainder
    else
      nil
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
        merged = find(payload, 'pull_request/merged')
        action = (merged == 'true') ? 'Merged' : 'Cancelled'
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

end

