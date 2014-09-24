require 'payload_utils'
class CommitsProcessor

  include PayloadUtils

  def initialize(insights_queue, commits_queue, config)
    @insights_event_queue = insights_queue
    @commits_queue = commits_queue
    @event_io = EventIO.new config
  end

  def run
    Thread.new do
      while (true) do
        begin
          next_job = @commits_queue.pop
          commits = next_job[:commits]
          common_attrs = next_job[:common_attrs]
          commits.each do | commit |
            process_commit commit, common_attrs
          end
          if (@commits_queue.size > 500)
            $stderr.puts "Error: commits queue length exceeded 10000; dumping 2000"
            300.times { @commits_queue.pop }
          end
        rescue => e
          $stderr.puts "#{e}: #{e.backtrace.join("\n  ")}"
        end
      end
    end
  end

private

  def add event
    @insights_event_queue << event
  end

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

  def process_commit commit, common_attrs
    event = common_attrs.dup
    sha = find commit, 'sha'
    url = find commit, 'url'

    begin
      commit_payload = @event_io.github_get url
    rescue => e
      $stderr.puts "\nProblem getting commit payload: #{e}: #{e.backtrace.join("\n   ")}"
      return
    end
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
    end if files

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

  def process_file file_payload, common_attrs={}
    event = common_attrs.dup
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
