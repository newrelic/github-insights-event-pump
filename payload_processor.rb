
module PayloadProcessor

  def process(event)

    payload = find(event, 'payload')

    event_name = breakdown(find(event, 'type'), payload)

    repo = find(event, 'repo/name')
    user = find(event, 'actor/login') ||
           find(payload, 'pusher/name')
    org =  find(event, 'org/login')
    sha =  find(payload, 'sha') ||
    text = find(payload, 'issue/body') ||
           find(payload, 'comment/body') ||
           find(payload, 'pull_request/body') ||
           find(payload, 'message')

    events = []
    event_attrs = { }
    event_attrs['eventType'] = 'GithubEvent'
    event_attrs['gitEventType'] = event_name
    event_attrs['user'] = user if user
    event_attrs['repo'] = repo if repo
    event_attrs['org'] = org if org
    event_attrs['text'] = text if text
    merge_counts(event_attrs, payload)

    events << event_attrs

    commits = find(payload, "commits")
    # Should read the integration or default branch, not master
    if commits
      events += process_commits(commits, event_attrs)
    end
    events
  end

  # Not used yet -- for later cleanup -- whk
  def merge_property(attrs, root, key, *paths)
    for path in paths do
      val = find(root, path)
      if val
        attrs[key] = val.to_s[0..2046]
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

  def merge_counts counts, payload

    counts.merge! count('wtf', payload, /wtf/i, 'issue/body','comment/body', 'pull_request/body', 'message')
    counts.merge! count('fix', payload, /\bfix/i, 'issue/body','comment/body', 'pull_request/body', 'message')
    counts.merge! count('bug', payload, /\bbugs?\b/i, 'issue/body','comment/body', 'pull_request/body', 'message')
  end

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

  def process_commits(commits, default_attrs={})
    events = []
    commits.each do | commit |
      author = find(commit, 'author/username') || find(commit, 'author/email')
      name = find(commit, 'author/name')
      sha = find(commit, 'id') || find(commit, 'sha')
      event = default_attrs.dup
      event['userName'] = name if author
      event['sha'] = sha
      event['user'] = author if author
      event['gitEventType'] = 'Commit'
      merge_counts(event, commit)
      events << event
    end
    events
  end
end

