require "option_parser"
require "http/client"
require "xml"
require "uri"
require "logger"

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

def logger
  logger = Logger.new(STDOUT)
  logger.level = Logger::DEBUG

  return logger
end
  

url = ""
if unmatched.size != 1
  puts "You must supply a URL"
  exit 1
end

url = unmatched.first
uri = URI.parse(url)

body = HTTP::Client.get(url).body

doc = XML.parse_html(body)

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

  logger.info "#{target} => #{absolute}"
end
