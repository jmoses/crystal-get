require "option_parser"
require "http/client"
require "xml"
require "uri"
require "logger"
require "random"
require "dir"
require "file"

unmatched = [] of String
OptionParser.parse! do |parser|
  parser.banner = "Usage: stuff"
  parser.unknown_args do |before, after|
    unmatched.concat before
    unmatched.concat after
  end
end

def valid?(uri : String)
  return ! uri.starts_with?("?")
end

def dir?(uri : String)
  return uri.ends_with?("/")
end

def logger
  logger = Logger.new(STDOUT)
  logger.level = Logger::DEBUG

  return logger
end
  
if unmatched.size != 1
  puts "You must supply a URL"
  exit 1
end

def fetch(url : String)
  uri = URI.parse(url)
  body = HTTP::Client.get(url).body
  doc = XML.parse_html(body)

  links = [] of String
  puts "Fetched #{url}"
  doc.xpath_nodes("//a").each do |node|
    target = node["href"]

    if !valid?(target)
      logger.debug "Invalid: #{target}"
      next
    elsif uri.path.try {|u| u.starts_with?(target) }
      logger.debug "Parent: #{target}"
      next
    end
    
    if target.starts_with?("/")
      absolute = (uri.scheme || "http") + "://" + (uri.host || "<no host>") + target
    else
      absolute = url + target
    end

    if dir?(absolute)
      logger.info("#{target} => descend into #{absolute}")
      links.concat(fetch(absolute))
    else
      logger.info "#{target} => fetch #{absolute}"
      links << absolute
    end
  end

  return links
end

all_links = unmatched.map {|u| fetch u}.flatten.sort
puts all_links

url_chan = Channel(String).new
done_chan = Channel(Bool).new

threads = 5

def local_target(url : String)
  uri = URI.parse(url)
  if ! uri.host || ! uri.path
    raise "Invalid url: #{url}"
  end

  # This is a bad way to trick the compiler, I'm certain
  host = uri.host || "foo"
  path = uri.path.try {|u| u.split("/") } || [] of String

  path.unshift host
  fname = path.pop
  str_path = File.join path
  full_path = File.join str_path, fname

  return str_path, fname
end



  
def fetch_single(url : String)
  path, fname = local_target url
  full_path = File.join(path, fname)

  if File.exists?(full_path)
    logger.debug "exists #{full_path}"
    return
  end

  logger.debug("fetching #{url}")

  if ! Dir.exists?(path)
    Dir.mkdir_p(path)
  end

  File.open(full_path, "wb") do |file|
    HTTP::Client.get(url) do |response|
      IO.copy(response.body_io, file)
    end
  end
end

threads.times do 
  spawn do
    loop do
      url = url_chan.receive
      break if url == "::done::"

      fetch_single url
    end

    done_chan.send true
  end
end

all_links.each do |l|
  logger.info "Sending #{l}"
  url_chan.send(l)
end
logger.debug("Sending done")
threads.times { url_chan.send "::done::" }

logger.debug("Waiting for completion")
threads.times { done_chan.receive }

logger.debug "Done"
