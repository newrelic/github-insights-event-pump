module CommitsProcessor

  def filetypes
    return @filetypes if @filetypes
    filetypes = {}
    File.open(File.expand_path("../file_types.tsv", __FILE__), "r") do | input |
      while !input.eof?
        extension, language = input.readline.chomp.split(/\t/)
        filetypes[extension] = language if extension
      end
    end
    @filetypes = filetypes
  end

  def process_commits(commits, default_attrs={})
    commits.each do | commit |
      process_commit commit, default_attrs
    end
  end

  def process_commit commit, default_attrs={}
    event = default_attrs.dup
    sha = find commit, 'sha'
    url = find commit, 'url'

    commit_payload = get url

    event['gitEventType'] = 'Commit'
    merge_property(event, commit, 'domain', 'author/email') do | address |
      domain = address.split('@').last
      domain unless domain =~ /(gmail|hotmail)\.com$/i
    end
#    merge_property(event, commit, 'text', 'message') { | comment |
#      event['textLength'] = comment.length
#      comment
#    }
    merge_property(event, commit, 'userName', 'author/name')
    merge_property(event, commit, 'user', 'author/name', 'author/email')

    files = find(commit_payload,'files')
    files.each do | file |
      process_file(file, event)
    end

    merge_property(event, commit, 'sha', 'sha') do | sha |
      sha[0..6]
    end
    merge_property(event, commit_payload, 'addedLines', 'stats/additions')
    merge_property(event, commit_payload, 'deletedLines', 'stats/deletions')
    url = find commit, 'url'
    if url
      link = url.gsub(%r{api\.github\.com}, 'github.com').gsub('repos/','')
      event['link'] = link
    end
    add event
  end

  def process_file file_payload, default_attrs={}
    event = default_attrs.dup
    event['gitEventType'] = 'Change'
    lines_deleted = find file_payload, "deletions"
    lines_changed = find file_payload, "changes"
    lines_added = find file_payload, "additions"
    event["changedLines"] = lines_changed + [ lines_added, lines_deleted ].max
    event["netLines"] = lines_added - lines_deleted
    if filename = file_payload["filename"]
      event["fileName"] = filename
      # Get the file extension.  Exclude dotfiles.
      extension = filename[/[^\/]\.([^\/.]+$)/, 1]
      if extension
        extension = extension.downcase
        event["extension"] = extension
        if filetype = filetypes[extension]
          event["language"] = filetype
        end
      end
    end
    add event
  end

end
