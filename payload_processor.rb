
module PayloadProcessor

  def process(payload, app_id, event_name)

    event = breakdown(event, payload)

    repo = find(payload, 'repository/name')
    user = find(payload, 'sender/login') ||
    find(payload, 'pusher/name')
    org =  find(payload, 'repository/organization')
    sha =  find(payload, 'sha') ||
    find(payload, 'pull_request/head/sha')
    ref =  find(payload, "ref")
    commits = find(payload, "commits")

    events = []
    event_attrs = { }
    event_attrs['eventType'] = 'GithubEvent'
    event_attrs['gitEventType'] = event_name
    event_attrs['appId'] = app_id if app_id
    event_attrs['user'] = user if user
    event_attrs['repo'] = repo if repo
    event_attrs['org'] = org if org
    events << event_attrs

    commits = find(payload, "commits")
    # Should read the integration or default branch, not master
    if (commits && ref =~ %r{/master$})
      events += process_commits(commits, event_attrs)
    end
    events
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

  def breakdown(event, payload)
    # With pull requests we distinguish between each of the PR
    # actions by appending them to the event key
    case event
    when 'pull_request'
      action = find(payload, 'action')
      # With closed actions we distinguish between PR's that were merged
      # and those that were closed without merging (cancelled).
      if (action == 'closed')
        merged = find(payload, 'pull_request/merged')
        action = (merged == 'true') ? 'merged' : 'cancelled'
      end
      event = "pull_request_#{action}"
    when 'create'
      ref_type = find(payload, 'ref_type')
      event = "create_#{ref_type}"

    when 'status'
      state  = find(payload, 'state')
      event = "commit_#{state}"
    end
    return event
  end

  def process_commits(commits, default_attrs={})
    events = []
    commits.each do | commit |
      author = find(commit, 'author/username') || find(commit, 'author/email')
      name = find(commit, 'author/name')
      sha = find(commit, 'id') || find(commit, 'sha')
      files = (commit['added']||[]) + (commit['modified']||[])
      files.each do | file |
        event = default_attrs.dup
        event['userName'] = name if author
        event['sha'] = sha
        event['user'] = author if author
        event['file'] = file
        event['gitEventType'] = 'change'
        events << event
      end
    end
    events
  end
end

