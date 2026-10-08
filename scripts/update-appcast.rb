#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "optparse"
require "time"

# Languages the app ships (Sources/StatusTrioCore/Resources/*.lproj). `en` must
# stay first: Sparkle's -bestNodeInNodes:name: falls back to the first node in
# document order when the user's preferred languages match nothing.
SUPPORTED_LANGUAGES = %w[en ar de es fr it ja ko pt-BR ru zh-Hans zh-Hant].freeze
RTL_LANGUAGES = %w[ar].freeze

def xml_escape(value)
  CGI.escapeHTML(value.to_s)
end

def notes_line_to_html(value)
  pattern = /\[([^\]]+)\]\((https:\/\/[^\s)]+)\)/
  html = +""
  cursor = 0
  value.to_enum(:scan, pattern).each do
    match = Regexp.last_match
    html << xml_escape(value[cursor...match.begin(0)])
    html << %(<a href="#{xml_escape(match[2])}">#{xml_escape(match[1])}</a>)
    cursor = match.end(0)
  end
  html << xml_escape(value[cursor..])
  html
end

def cdata_escape(value)
  value.to_s.gsub("]]>", "]]]]><![CDATA[>")
end

def notes_to_html(lines)
  html = []
  list_items = []

  flush_list = lambda do
    next if list_items.empty?

    html << "<ul>#{list_items.join}</ul>"
    list_items = []
  end

  lines.map(&:strip).each do |line|
    next if line.empty?
    next if line.match?(/\A#\s+/)

    if (heading = line.match(/\A(#+)\s+(.+)\z/)) && (2..6).cover?(heading[1].length)
      flush_list.call
      level = heading[1].length
      html << "<h#{level}>#{xml_escape(heading[2])}</h#{level}>"
    elsif (item = line.match(/\A(?:[-*+]|\d+\.)\s+(.+)\z/))
      list_items << "<li>#{notes_line_to_html(item[1])}</li>"
    else
      list_items << "<li>#{notes_line_to_html(line)}</li>"
    end
  end

  flush_list.call
  html.join
end

def load_notes(dir)
  raise "Release notes directory does not exist: #{dir}" unless File.directory?(dir)

  notes = {}
  Dir.children(dir).sort.each do |name|
    next if name.start_with?(".")
    next unless name.end_with?(".md")

    language = name.delete_suffix(".md")
    unless SUPPORTED_LANGUAGES.include?(language)
      raise "Unsupported release notes language file: #{name} " \
            "(expected one of: #{SUPPORTED_LANGUAGES.join(', ')})"
    end

    notes[language] = File.join(dir, name)
  end

  raise "Release notes directory has no language files: #{dir}" if notes.empty?

  notes
end

def notes_title(path, version, build)
  line = File.readlines(path, chomp: true).find { |candidate| candidate.strip.match?(/\A#\s+\S/) }
  raise "Missing a '# <title>' heading in #{path}." unless line

  title = line.strip.sub(/\A#\s+/, "")
  %w[%VERSION% %BUILD%].each do |token|
    raise "Title in #{path} must contain #{token}." unless title.include?(token)
  end

  title.gsub("%VERSION%", version).gsub("%BUILD%", build)
end

def notes_description(path, language)
  html = notes_to_html(File.readlines(path, chomp: true))
  raise "Release notes for #{language} are empty: #{path}" if html.empty?

  RTL_LANGUAGES.include?(language) ? %(<div dir="rtl">#{html}</div>) : html
end

# Returns [[language, title_line, description_line], ...] with `en` first.
def localized_lines(notes, version, build)
  languages = SUPPORTED_LANGUAGES.select { |language| notes.key?(language) }

  languages.map do |language|
    title = %(<title xml:lang="#{language}">) \
            "#{xml_escape(notes_title(notes[language], version, build))}</title>"
    body = cdata_escape(notes_description(notes[language], language))
    description = %(<description xml:lang="#{language}"><![CDATA[#{body}]]></description>)
    [language, title, description]
  end
end

def build_item(pub_date:, version:, build:, minimum_system_version:, enclosure_lines:, localized:)
  lines = []
  localized.each { |(_, title, _)| lines << title }
  lines << "<pubDate>#{pub_date}</pubDate>"
  lines << "<sparkle:version>#{xml_escape(build)}</sparkle:version>"
  lines << "<sparkle:shortVersionString>#{xml_escape(version)}</sparkle:shortVersionString>"
  lines << "<sparkle:minimumSystemVersion>#{xml_escape(minimum_system_version)}</sparkle:minimumSystemVersion>"
  localized.each { |(_, _, description)| lines << description }
  enclosure_lines.each { |line| lines << line }

  (["    <item>"] + lines.map { |line| "      #{line}" } + ["    </item>"]).join("\n")
end

def new_enclosure_lines(dmg_url:, ed_signature:, dmg_length:)
  [
    %(<enclosure url="#{xml_escape(dmg_url)}"),
    %(           type="application/octet-stream"),
    %(           sparkle:edSignature="#{xml_escape(ed_signature)}"),
    %(           length="#{xml_escape(dmg_length)}" />)
  ]
end

def existing_item(appcast, build)
  appcast.scan(%r{[ \t]*<item>.*?</item>}m).find do |block|
    block.match?(%r{<sparkle:version>\s*#{Regexp.escape(build)}\s*</sparkle:version>})
  end
end

def item_element(block, name, build)
  block[%r{<#{name}>(.*?)</#{name}>}m, 1] ||
    raise("Existing item for build #{build} has no <#{name}>.")
end

def item_enclosure_lines(block, build)
  match = block[%r{[ \t]*<enclosure\b.*?/>}m] ||
          raise("Existing item for build #{build} has no <enclosure>.")

  # Strip only the item-level indent so the enclosure is re-emitted byte for
  # byte; deeper continuation indentation must survive.
  indent = match[/\A[ \t]*/]
  match.lines.map { |line| line.chomp.sub(/\A#{Regexp.escape(indent)}/, "") }
end

def parse_options
  options = {}
  OptionParser.new do |parser|
    parser.banner = "Usage: ruby scripts/update-appcast.rb --version V --build N --notes-dir DIR [options]"
    parser.on("--version V") { |value| options[:version] = value }
    parser.on("--build N") { |value| options[:build] = value }
    parser.on("--minimum-system-version V") { |value| options[:minimum] = value }
    parser.on("--dmg-url URL") { |value| options[:dmg_url] = value }
    parser.on("--ed-signature SIG") { |value| options[:signature] = value }
    parser.on("--length N") { |value| options[:length] = value }
    parser.on("--notes-dir DIR") { |value| options[:notes_dir] = value }
    parser.on("--appcast PATH") { |value| options[:appcast] = value }
    parser.on("--output PATH") { |value| options[:output] = value }
    parser.on("--replace-existing") { options[:replace] = true }
  end.parse!

  options[:appcast] ||= File.expand_path("../appcast.xml", __dir__)
  options[:output] ||= options[:appcast]
  options[:minimum] ||= "15.0"

  raise "VERSION must not be empty." if options[:version].to_s.empty?
  raise "BUILD must contain only digits." unless options[:build].to_s.match?(/\A\d+\z/)
  raise "MINIMUM_SYSTEM_VERSION must not be empty." if options[:minimum].to_s.empty?
  raise "Release notes directory must be given with --notes-dir." if options[:notes_dir].to_s.empty?
  raise "Appcast file does not exist: #{options[:appcast]}" unless File.file?(options[:appcast])

  unless options[:replace]
    raise "DMG_URL must use HTTPS." unless options[:dmg_url].to_s.start_with?("https://")
    raise "ED_SIGNATURE must not be empty." if options[:signature].to_s.empty?
    raise "DMG_LENGTH must contain only digits." unless options[:length].to_s.match?(/\A\d+\z/)
  end

  options
end

options = parse_options
appcast = File.read(options[:appcast])
notes = load_notes(options[:notes_dir])
localized = localized_lines(notes, options[:version], options[:build])
raise "No release notes languages found in #{options[:notes_dir]}." if localized.empty?

existing = existing_item(appcast, options[:build])

updated =
  if options[:replace]
    raise "Build #{options[:build]} does not exist in #{options[:appcast]}." unless existing

    stored_version = item_element(existing, "sparkle:shortVersionString", options[:build])
    unless stored_version == options[:version]
      raise "Existing build #{options[:build]} has shortVersionString #{stored_version}, " \
            "expected #{options[:version]}."
    end

    replacement = build_item(
      pub_date: item_element(existing, "pubDate", options[:build]),
      version: stored_version,
      build: options[:build],
      minimum_system_version: item_element(existing, "sparkle:minimumSystemVersion", options[:build]),
      enclosure_lines: item_enclosure_lines(existing, options[:build]),
      localized: localized
    )

    # Block form avoids backreference interpretation in the replacement text.
    appcast.sub(existing) { replacement }
  else
    if existing
      raise "Build #{options[:build]} already exists in #{options[:appcast]}."
    end

    item = build_item(
      pub_date: Time.now.utc.strftime("%a, %d %b %Y %H:%M:%S +0000"),
      version: options[:version],
      build: options[:build],
      minimum_system_version: options[:minimum],
      enclosure_lines: new_enclosure_lines(
        dmg_url: options[:dmg_url],
        ed_signature: options[:signature],
        dmg_length: options[:length]
      ),
      localized: localized
    )

    first_item = appcast.match(/^[ \t]*<item\b/m)
    if first_item
      appcast.dup.insert(first_item.begin(0), "#{item}\n")
    else
      channel_end = appcast.rindex("</channel>")
      raise "Could not find </channel> in #{options[:appcast]}." unless channel_end

      closing_indent = appcast[0...channel_end][/[ \t]*\z/]
      indent_start = channel_end - closing_indent.length
      copy = appcast.dup
      copy[indent_start, closing_indent.length] = "#{item}\n#{closing_indent}"
      copy
    end
  end

File.write(options[:output], updated)
puts "Updated #{options[:output]} with build #{options[:build]} " \
     "(#{localized.length} languages: #{localized.map(&:first).join(', ')})."
