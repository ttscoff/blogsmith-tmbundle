#!/usr/bin/env ruby -wKU
DIALOG = ENV['DIALOG']
INPUT = STDIN.read
CLIPBOARD = %x{__CF_USER_TEXT_ENCODING=$UID:0x8000100:0x8000100 pbpaste}.strip
SELECTION = ENV['TM_SELECTED_TEXT']
WORD = ENV['TM_CURRENT_WORD']
LINE = ENV['TM_CURRENT_LINE']

%w[exit_codes escape ui osx/plist].each do |filename|
  require "#{ENV['TM_SUPPORT_PATH']}/lib/#{filename}"
end

%w[cooldialog yahoo].each do |filename|
  require "#{ENV['TM_BUNDLE_SUPPORT']}/lib/#{filename}"
end

%w[net/http rexml/document erb cgi].each do |filename|
  require filename
end

$KCODE = 'u'

class Linkage

  attr_reader :references, :input, :links

  def initialize
    # @references = INPUT.scan(/\[([^\]]+)\]\:\s/).sort
    if SELECTION.nil?
      @input = WORD.nil? || WORD =~ /^\s+$/ ? '' : WORD
    else
      @input = SELECTION
    end
    refs = []
    INPUT.scan(/\[([^\]]+)\]\:\s(.+)/).each { |res|
      refs << {'title' => res[0], 'link' => res[1] }
    }
    @references = refs.sort {|a,b| a['title'] <=> b['title']}
    if @input.empty?
      @links = CLIPBOARD.scan(/(?:\[([^\]]+)\]\: )?(https?:\/\/[^ \n"]+)/m)
    else
      @links = @input.scan(/(?:\[([^\]]+)\]\: )?(https?:\/\/[^ \n"]+)/m)
    end
  end

  def refs_menu
    input = SELECTION ? SELECTION : WORD
    refs = @references
    plist = { 'menuItems' => refs }.to_plist
    res = OSX::PropertyList.load(`#{e_sh DIALOG} -up #{e_sh plist}`)
    TextMate.exit_discard unless res.has_key? 'selectedMenuItem'
    return res['selectedMenuItem']['title']
  end

  def entity_escape(text)
    text.gsub(/&(?!([a-zA-Z0-9]+|#[0-9]+|#x[0-9a-fA-F]+);)/, '&amp;')
  end

  def make_link(text)
    case text
      when %r{\A(mailto:)?(.*?@.*\..*)\z}:
          "mailto:#{$2.gsub(/./) {sprintf("&#x%02X;", $&.unpack("U")[0])}}"
          when %r{http://www.(amazon.(?:com|co.uk|co.jp|ca|fr|de))/.+?/([A-Z0-9]{10})/[-a-zA-Z0-9_./%?=&]+}:
          "http://#{$1}/dp/#{$2}"
      when %r{\A[a-zA-Z][a-zA-Z0-9.+-]*://.*\z}:
          entity_escape(text)
      when %r{\A(www\..*|.*\.(com|uk|net|org|info|me))\z}:
          "http://#{entity_escape text}"
      when %r{\A.*\.(com|uk|net|org|info|me)\z}:
          "http://#{entity_escape text}"
        #  when %r{\A\S+\z}:
        #    entity_escape(text)
      else
        "http://some-site.com/"
    end
  end

  def ps(string)
    res = `ps Ao pid,comm|awk '{match($0,/[^\\/]+$/); print substr($0,RSTART,RLENGTH)}'|grep ^#{string}$|grep -v grep;`
    return res.empty? ? false : true
  end

  def scan_links(string)
    links = []
    matches = string.scan(/(https?:\/\/[^ \n"]+)/m)
    matches.each{ |match|
      links.push(match[0])
    }
    return links
  end

  def find_main_link
    linkmatch = nil
    tunelinks = INPUT.scan(/^\[itunes ([^\]]+)\]\:\s(\S+)\s/)
    unless tunelinks.empty?
      if tunelinks.length == 1
        linkmatch = tunelinks[0]
      else
        linklist = tunelinks.collect { |e| { 'title' => e[0].to_s, 'url' => e[1].to_s } }
        plist = { 'menuItems' => linklist }.to_plist
        res = OSX::PropertyList.load(`#{e_sh DIALOG} -up #{e_sh plist}`)
        TextMate.exit_discard unless res.has_key? 'selectedMenuItem'
        TextMate.exit_insert_text res['selectedMenuItem']['url']
      end
    else
      linkmatch = INPUT.match(/^\[link(?: [^\]]+)?\]\:\s(\S+)\s/) if linkmatch.nil?
      linkmatch = INPUT.match(/^\[[^\]]+\]\:\s(http:\/\/itunes.apple.com\S+)\s/) if linkmatch.nil?
      clipboardlinks = CLIPBOARD.scan(/(?:\[([^\]]+)\]\: )?(https?:\/\/[^ \n"]+)/m)
      if linkmatch.nil?
        refs = @references
        unless refs.empty? && clipboardlinks.empty?
          clipboardlinks.each {|link|
            title = link[0].nil? ? link[1] : link[0]
            skip = false
            refs.each {|ref| skip = true if ref['link'] == link[1] }
            refs.push([title,link[1]]) unless skip
          } unless clipboardlinks.empty?

          plist = { 'menuItems' => refs }.to_plist
          res = OSX::PropertyList.load(`#{e_sh DIALOG} -up #{e_sh plist}`)
          TextMate.exit_discard unless res.has_key? 'selectedMenuItem'
          TextMate.exit_insert_text res['selectedMenuItem']['link']
        end
      else
        TextMate.exit_insert_text linkmatch[1]
      end
    end
    TextMate::CoolDialog.cool_tool_tip("No links found",true)
  end


  def link_word(input)
    urls = scan_links(CLIPBOARD)
    unless @references.empty?
      urls.map! {|url|
        link = url.clone
        @references.each {|ref|
          link = "["+ref['title']+"]" if url == ref['link']
        }
        link
      }
    end
    return [INPUT,''] unless urls.length > 0
    if urls.length == 1
      url = urls[0]
    else
      linklist = []

      urls.each {|link|
        linklist << {'title' => link, 'url' => link }
      }
      plist = { 'menuItems' => linklist }.to_plist

      res = OSX::PropertyList.load(`#{e_sh DIALOG} -up #{e_sh plist}`)
      TextMate::CoolDialog.cool_tool_tip("Cancelled",true) unless res.has_key? 'selectedMenuItem'
      url = res['selectedMenuItem']['url']
    end
    return [INPUT,url]
  end

  def create_app_store_link()
    errormessage = ""
    itunes = []
    iturls = INPUT.scan(/^\[(itunes( ?[^\]]+)?)\]\:\s([^\s]+)\s/)
    errormessage += "Couldn't locate any iTunes urls. (e.g. [itunes linktitle]: http://...)\n" if iturls.empty?
    urls = INPUT.scan(/^\[(dev( ?[^\]]+)?)\]\:\s([^\s]+)\s/)
    errormessage += "Couldn't locate any Developer urls. (e.g. [dev linktitle]: http://...)\n" if urls.empty?
    return [nil,nil,errormessage] unless errormessage == ""
    itunesurl,devurl,itunesmatch = ""
    iturls.each {|itmatch|
      urls.each{|url|
        urlmatch = url[1] ? url[1].strip.downcase.to_s : "blank"
        itunesmatch = itmatch[1] ? itmatch[1].strip.downcase.to_s : "blank"
        devurl = url[0].strip if urlmatch === itunesmatch # || urlmatch.gsub(/ ?\d+$/,'') === itunesmatch.gsub(/ ?\d+$/,'')
      }
      if devurl.nil?
        errormessage += "Couldn't find a match for iTunes url #{itmatch[1].strip.downcase}"
      else
        itunes << { 'title' => itunesmatch, 'url' => itmatch[2].strip, 'ref' => itmatch[0], 'dev' => devurl }
      end
    }
    if itunes.length == 0
      url = nil
      iturl = nil
      errormessage += "No sets of dev/itunes links found"
    elsif itunes.length === 1
      return [nil,nil,"Selected iTunes link is not an App Store link"] if itunes[0]['url'] !~ /(itunes|phobos).apple.com/
      url = itunes[0]['dev']
      iturl = itunes[0]['ref']
    else
      plist = { 'menuItems' => itunes }.to_plist
      res = OSX::PropertyList.load(`#{e_sh DIALOG} -up #{e_sh plist}`)
      unless res.has_key? 'selectedMenuItem'
        iturl = nil
        url = nil
        errormessage = [nil,nil,"Cancelled"]
      else
        return [nil,nil,"Selected iTunes link is not an App Store link"] if res['selectedMenuItem']['url'] !~ /(itunes|phobos).apple.com/
        iturl = res['selectedMenuItem']['ref']
        url = res['selectedMenuItem']['dev']
      end
    end

    input = SELECTION || WORD
    replace_if_needed("[#{input}][#{url}] [[iTunes link][#{iturl}]]")
    exit
    # return [url,iturl,errormessage]

  end

  def do_web_search(offset,phrase)
    escapedUrl = "http://api.search.live.net/xml.aspx?Appid=6B9E3A4B9F0D8F963A24815A0317BF1DCA3B0E9A&query=#{e_url(phrase)}&sources=web&web.offset=#{offset}"

    xml_data = Net::HTTP.get_response(URI.parse(escapedUrl)).body
    doc = REXML::Document.new(xml_data)
    bings = []
    doc.elements.each('SearchResponse/web:Web/web:Results/web:WebResult') do |result|
      bings << {
        'title' => result.elements['web:Title'].text.gsub('"','&raquo;'),
        'url' => result.elements['web:Url'].text
      }
    end
    bings << {
      'title' => 'More results…',
      'url' => ''
    } unless bings.empty?

    TextMate::CoolDialog.cool_tool_tip("No matches",true) if bings.empty?

    plist = { 'menuItems' => bings }.to_plist
    res = OSX::PropertyList.load(`#{e_sh DIALOG} -up #{e_sh plist}`)
    unless res.has_key? 'selectedMenuItem'
      TextMate::CoolDialog.cool_tool_tip("Cancelled")
      TextMate.exit_insert_text "]: "
    end
    if res['selectedMenuItem']['title'] == "More results…"
      offset += 10
      do_web_search(offset,phrase)
    else
      return res
    end
  end


  def web_search(string = "")


    offset = 0
    if string.empty?
      phrase = TextMate::UI.request_string(:title => "Search Query",:prompt => "Enter terms to search for")
    else
      if LINE =~ /^\[([^\]]+)/
        phrase = $1
        phrase = phrase.sub(/dev /,'') + " iphone" if LINE =~ /^\[dev /
      else
        phrase = string
      end
    end

    res = do_web_search(offset,phrase)
    url = res['selectedMenuItem']['url']
    input = phrase # res['selectedMenuItem']['title']
    return [input,url]
  end

  def make_tag_link(string = "")
    blogsite = ENV['BLOG_SITE'] ? ENV['BLOG_SITE'] : "www.tuaw.com"
    blogsite = "www." + blogsite unless blogsite =~ /^www\./
    linktext = TextMate::UI.request_string(:title => "Search Query",:prompt => "Enter terms to create a tag link",:default => string)
    TextMate::CoolDialog.cool_tool_tip("Cancelled",true) unless linktext

    query = e_url(linktext + " site:#{blogsite}/tag")

    yahoo = WebSearch.new('TM_YAHOO', query, 'all', 20, 1, nil, 1)

    if yahoo.parse_results.length > 0
      ysuggest = []
      yahoo.parse_results.each {|result|
        unless (result['Url'] =~ /bloglines|page/)
          tag_title = result['Title'].gsub(/ -- TUAW/,'')
          ysuggest << {
            'title' => tag_title.gsub('"','&raquo;'),
          'url' => result['Url']}
        end
      }

      plist = { 'menuItems' => ysuggest }.to_plist

      res = OSX::PropertyList.load(`#{e_sh DIALOG} -up #{e_sh plist}`)
      TextMate::CoolDialog.cool_tool_tip("Cancelled",true) unless res.has_key? 'selectedMenuItem'
      url = res['selectedMenuItem']['url']
      title = "tag" + res['selectedMenuItem']['title']
      return [title,url]
    end
    return false
  end

  def make_search_link(string = "")
    blogsite = ENV['BLOG_SITE'] ? ENV['BLOG_SITE'] : "www.tuaw.com"
    blogsite = "www." + blogsite unless blogsite =~ /^www\./
    searchstring = string.empty? ? "Search terms" : string
    res = TextMate::UI.request_string(:title => "TUAW Search Query",:prompt => "Enter terms to create a search link",:default => searchstring)
    TextMate::CoolDialog.cool_tool_tip("Cancelled",true) unless res
    url = "http://#{blogsite}/supersearch/?q=#{CGI::escape(res)}"
    data = Net::HTTP.get_response(URI.parse(url)).body
    elegant_exit("No results returned for search") if data =~ /no results found/
    titles = data.scan(/id\="pt\d+">([^<]+)</)
    matches = titles.length
    # matches = data.scan(/class\="post"/).length
    title = ""
    if matches > 2
      matches = "#{matches}+" if matches == 15
      output = "<h5>#{matches} matches, including:</h5>\n<ul>"
      titles.each do |title|
        output += ("<li>" + title[0] + "</li>\n")
      end
      output += "</ul>"
      TextMate::CoolDialog.cool_tool_tip(output)
      title = string.empty? ? res : string
      return ["search" + title, url]

    else
      TextMate::CoolDialog.cool_tool_tip("Less than 3 links found for #{searchstring}, try another search phrase",false)
      return false
    end
  end

  def make_blog_link(string = "")
    blogsite = ENV['BLOG_SITE'] ? ENV['BLOG_SITE'] : "www.tuaw.com"
    # input = "Search text" if input.empty?
    answer = TextMate::UI.request_string(:title => "Enter keywords",:prompt => "Find TUAW posts relating to keywords:",:default => string)
    TextMate.exit_discard unless answer
    query = e_url(answer + " -inurl:tag -inurl:?q= -inurl:rss.xml -inurl:bloggers site:#{blogsite}")
    yahoo = WebSearch.new('TM_YAHOO', query, 'all', 25, 1, nil, 1)
    ysuggest = []
    yahoo.parse_results.each {|result|
      ysuggest << {
        'title' => result['Title'].gsub('"','&raquo;').gsub(/<\/?b>/,''),
      'url' => result['Url']}
    }
    plist = { 'menuItems' => ysuggest }.to_plist
    res = OSX::PropertyList.load(`#{e_sh DIALOG} -up #{e_sh plist}`)
    unless res.has_key? 'selectedMenuItem'
      TextMate::CoolDialog.cool_tool_tip("No links found or nothing selected",false)
      return false
    else
      url = res['selectedMenuItem']['url']
      blog = blogsite.split('.')[-2]
      title = string.empty? ? answer.chomp : string
      return [blog + title,url]
    end
  end

  def tabs_to_references(sel_or_word)
    input = sel_or_word
    urllist = %x{osascript <<-APPLESCRIPT
                 tell application "Safari"
                 set _tabs to every tab of window 1
                 set _urls to {}
                 repeat with _tab in _tabs
                 set end of _urls to {title:name of _tab, URL:URL of _tab}
                 end repeat
                 set output to ""
                 repeat with _item in _urls
                 if title of _item is not "Untitled" then
                   set output to output & (title of _item) & ">>>" & (URL of _item) & "|||"
                 end if
                 end repeat
                 return output
                 end tell
                 APPLESCRIPT }.chomp
    TextMate::CoolDialog.cool_tool_tip("No tabs returned by Safari. Is it open?",true) if urllist.empty?
    urls = urllist.split('|||')
    x = []
    urls.each {|url|
      url = url.split(">>>")
      x << { 'title' => url[0], 'tag' => url[1] }
    }
    plist = { 'tags' => x }.to_plist

    nib = input.empty? && LINE =~ /^(#{input})?(\s+)?$/ ? 'select_evernote' : 'select_single'

    res = OSX::PropertyList::load(`#{e_sh DIALOG} -mp #{e_sh plist} #{nib}`)
    TextMate::CoolDialog.cool_tool_tip("Cancelled",true) if res['returnButton'] == "Cancel"
    links = res['result']['returnArgument']

    TextMate::CoolDialog.cool_tool_tip("Cancelled",true) if links.empty?
    return links
  end

  def search_evernote(sel_or_word)
    input = sel_or_word
    searchterms = TextMate::UI.request_string(:title => "Search Evernote Notes", :prompt => "Enter search terms")

    urllist = %x{osascript <<-APPLESCRIPT
                 tell application "Evernote"
                 set _notes to find notes "#{searchterms} source:web.clip"
                 set _urls to {}
                 repeat with _note in _notes
                 if source URL of _note is not missing value then
                 set end of _urls to {title:title of _note, URL:source URL of _note}
                 end if
                 end repeat
                 set output to ""
                 repeat with _item in _urls
                 set output to output & (title of _item) & ">>>" & (URL of _item) & "|||"
                 end repeat
                 return output
                 end tell
                 APPLESCRIPT }.chomp
    TextMate.exit_show_tool_tip "No results" if urllist.empty?
    urls = urllist.split('|||')
    x = []
    urls.each {|url|
      url = url.split(">>>")
      x << { 'title' => url[0], 'tag' => url[1] }
    }
    plist = { 'tags' => x }.to_plist
    nib = input.empty? && LINE =~ /^(#{input})?(\s+)?$/ ? 'select_evernote' : 'select_single'
    res = OSX::PropertyList::load(`#{e_sh DIALOG} -mp #{e_sh plist} #{nib}`)
    TextMate::CoolDialog.cool_tool_tip("Cancelled",true) if res['returnButton'] == "Cancel"
    return res['result']['returnArgument']
  end

  def make_ref_list(linklist,prevline)
	# TODO: replace all references with sorted list
    norepeat = []
    linklist = scan_links(CLIPBOARD) if linklist.nil?
    unless SELECTION =~ /\[.*?\]:\s.*?$\n/
      @references.each {|ref|
        norepeat.push(ref['title'])
      }
    end
    output = []
    skipped = []
    linklist.each {|url|
      skip = false
      @references.each { |ref|
        if SELECTION.nil? || ! SELECTION =~ /\[#{ref['title']}\]:\s#{ref['link']}/
          if ref.has_value?(url[1])
            skipped.push(url[1])
            skip = true
          end
        end
      }
      next if skip == true
      if url[0].nil?
        domain = url[1].match(/https?:\/\/([^\/]+)/)
        parts = domain[1].split('.')
        name = case parts.length
          when 1: parts[0].to_s
          when 2: parts[0].to_s
          else parts[1].to_s
        end
      else
        name = url[0].to_s
      end
      while norepeat.include? name
        if name =~ / ?[0-9]$/
          name.next!
        else
          name = name + " 2"
        end
      end
      output << {'title' => name, 'link' => url[1] }
      norepeat.push name
    }
    output = output.sort {|a,b| a['title'] <=> b['title']}
    counter = 0
    o = prevline =~ /^(\s+|\[[^\]]+\]:\s.*?)?$/ ? '' : "\n"
    # o += "\n" if row >= lines.length
    output.each { |x|
      counter += 1
      name = x['link'] =~ /(itunes|phobos).apple.com/ ? "itunes " + x['title'] : x['title']
      o += "[#{name}]: #{x['link']}"
      o += "\n" unless counter == output.length
    }
    TextMate::CoolDialog.cool_tool_tip("Skipped #{skipped.length.to_s} repeats",false) if skipped.length > 0
    replace_if_needed(o)

  end

  def additional_menu(input)
    options = input.empty? ? [] : [		{'title' => "Link to Reference", 'name' => "reference"}]
    options += [{'title' => "Use Clipboard", 'name' => "clipboard"}] unless scan_links(CLIPBOARD).empty?
    options += [
      {'title' => "Get Safari Tabs", 'name' => "safari"},
      {'title' => "Get Evernote Urls", 'name' => "evernote"},
      {'title' => "Web Search", 'name' => "websearch"},
      {'title' => "Tag Link", 'name' => "taglink"},
      {'title' => "Blog Link", 'name' => "bloglink"},
      {'title' => "Search Link", 'name' => "searchlink"}
    ]
    plist = { 'menuItems' => options }.to_plist
    res = OSX::PropertyList.load(`#{e_sh DIALOG} -up #{e_sh plist}`)
    TextMate.exit_discard unless res.has_key? 'selectedMenuItem'
    choice = res['selectedMenuItem']['name']

    if choice == "reference"
      link = self.refs_menu
      links = [["_ref",link]]
    elsif choice == "clipboard"
      lines = INPUT.split("\n")
      row = ENV['TM_LINE_NUMBER'].to_i
      prevline = lines[row-2]
      links = scan_links(CLIPBOARD).map {|url| [nil,url] }
    elsif choice == "safari"
      links = Linkage.new.tabs_to_references(input)
      links = links.map {|url| [nil,url] }
    elsif choice == "evernote"
      links = Linkage.new.search_evernote(input)
      links = links.map {|url| [nil,url] }
    elsif choice == "websearch"
      title,link = Linkage.new.web_search(input)
      links = [[title,link]]
    elsif choice == "taglink"
      title,link = Linkage.new.make_tag_link(input)
      links = [[title,link]]
    elsif choice == "bloglink"
      title,link = Linkage.new.make_blog_link(input)
      links = [[title,link]]
    elsif choice == "searchlink"
      title,link = Linkage.new.make_search_link(input)
      links = [[title,link]]
    else
      TextMate::CoolDialog.cool_tool_tip("Cancelled",true)
    end
    return links
  end

  def is_linked(word)
    lines = INPUT.split("\n")
    row = ENV['TM_LINE_NUMBER'].to_i
    line = lines[row-1]
    cursor = ENV['TM_LINE_INDEX'].to_i
    ds = []
    if line =~ /(\[[^\]]+\]\[((?:[^\]]+)?#{e_sh word}(?:[^\]]+)?)\])/
      line.scan(/(\[[^\]]+\]\[((?:[^\]]+)?#{e_sh word}(?:[^\]]+)?)\])/).each {|w|
        idx = line.index(w[0]).to_i
        if idx > cursor
          d = idx - cursor
        else
          right = idx + w[0].length
          if right > cursor
            d = 0
          else
            d = cursor - right
          end
        end
        ds << { 'matchstring' => w[1], 'distance' => d, 'fullmatch' => w[0] }
      }
      ret = ds.sort{|a,b| a['distance'] <=> b['distance']}[0]
      fullmatch = ret['fullmatch']
      linkword = ret['matchstring']
      if linkword
        references = @references.clone.delete_if {|x| x['title'] == linkword }
        linklist = references.collect { |e| { 'title' => e['title'].to_s } }
        plist = { 'menuItems' => linklist }.to_plist
        res = OSX::PropertyList.load(`#{e_sh DIALOG} -up #{e_sh plist}`)
        TextMate.exit_discard unless res.has_key? 'selectedMenuItem'
        newlink = fullmatch.slice(0..fullmatch.index('][')) + "[#{res['selectedMenuItem']['title']}]"
        replace_whole_ref(fullmatch,newlink)
        exit
      end
    elsif line =~ /(\[((?:\w+)?#{e_sh word}(?:\w+)?)\]\[([^\]]+)\])/
      TextMate::CoolDialog.cool_tool_tip("Run the linker in the link portion of the reference",true)
    end
    return [nil,false]
  end

  def replace_whole_ref(string,replacement)
    lines = INPUT.split("\n")
    row = ENV['TM_LINE_NUMBER'].to_i
    currentLine = lines[row-1]
    cursor = ENV['TM_LINE_INDEX'].to_i
    curwordlen = string.length.to_i
    counter = cursor
    testword = currentLine[counter..counter+curwordlen]
    until testword =~ /#{e_sh(string)}/
      counter -= 1
      testword = currentLine[counter..counter+curwordlen]
    end
    before = []
    (row-1).times do before << lines.shift end
      lastline = counter > 0 ? lines[0][0..counter-1] : ""
      before << lastline
      line_end = lines.shift[counter+curwordlen..-1]
      line_end = "" if line_end.nil?
      print before.join("\n") + replacement + line_end + "\n" + lines.join("\n")
      oldcol = counter%ENV['TM_COLUMNS'].to_i
      `open "txmt://open?line=#{row}&column=#{counter+replacement.length+1}"`
    end

    def replace_if_needed(text)
      o = ''
      snippet = false
      if SELECTION.nil? && ! WORD.nil?
        lines = INPUT.split("\n")
        row = ENV['TM_LINE_NUMBER'].to_i
        currentLine = lines[row-1]
        cursor = ENV['TM_LINE_INDEX'].to_i
        curwordlen = WORD.length.to_i
        counter = cursor
        testword = currentLine[counter..counter+curwordlen]
        until testword =~ /#{e_sh(WORD)}/
          counter -= 1
          testword = currentLine[counter..counter+curwordlen]
        end
        before = []
        (row-1).times do before << lines.shift end
        lastline = counter > 0 ? lines[0][0..counter-1] : ""
        before << lastline
        line_end = lines.shift[counter+curwordlen..-1]
        o = before.join("\n") + text + line_end + "\n" + lines.join("\n")
        oldcol = counter%ENV['TM_COLUMNS'].to_i
        `open "txmt://open?line=#{row}&column=#{counter+text.length+1}"`
      elsif SELECTION.nil? && LINE =~ /^(\s+)?$/
        snippet = true
        o = text + "\n$0"
      else
        snippet = true
        o = "#{text}$0"
      end
      return [snippet,o]
    end

        def find_headers(lines)
          in_headers = false
          lines.each_with_index {|line, i|
            if line =~ /^\S[^\:]+\: .*$/
              in_headers = true
            elsif in_headers === true
              return i
            end
          }
        end

        def single_char_match
          if SELECTION.nil?
            left_edge = ENV['TM_LINE_INDEX'].to_i-2 < 1 ? 0 : ENV['TM_LINE_INDEX'].to_i-2
            left_char = LINE.slice(left_edge..ENV['TM_LINE_INDEX'].to_i)
            preceding_char = LINE.slice(left_edge..ENV['TM_LINE_INDEX'].to_i-1)
            return false unless preceding_char =~ /(\s|^)/
            if left_char =~ /\s?\b([stbwn])\b/
              case $1
                when "w" then
                  title,url = web_search("")
                when "t" then
                  title,url = make_tag_link("")
                when "b" then
                  title,url = make_blog_link("")
                when "s" then
                  title,url = make_search_link("")
                  # when "n" then puts "news search"
              end
              TextMate.exit_discard if title == false
              if !(ENV['TM_SCOPE'].scan(/markdown/).empty?) && LINE =~ /^[stbwn]\b(\s+)?$/
                replace_if_needed("[#{title}]: #{url}")
              else
                replace_if_needed("[#{title}](#{url})")
              end
              exit
            end
          end
        end

      end # Class Linkage

      public

        def do_superlink
          TextMate.exit_show_tool_tip("Sorry, the Super Linker is not currently functional.")
          linker = Linkage.new


          TextMate.exit_discard if LINE =~ /^(doctype|title|categories|tags): /i
          linker.single_char_match
          linker.find_main_link if LINE =~ /^[Ll]ink: /i
          linker.is_linked(WORD) unless INPUT.nil?

          if linker.links.empty? && linker.input.empty? then
            links = linker.additional_menu("")
            lines = INPUT.split("\n")
            row = ENV['TM_LINE_NUMBER'].to_i
            prevline = lines[row-2]
            linker.make_ref_list(links,prevline)
            exit
          elsif linker.input.empty? && ! LINE =~ /^(\s+)?$/
            TextMate::CoolDialog.cool_tool_tip("I wouldn't do that in the middle of a paragraph…",true)
          elsif linker.links.empty?
            if CLIPBOARD =~ /(?:\[([^\]]+)\]\: )?(https?:\/\/[^ \n"]+)/m
              input,url = linker.link_word(linker.input)
              is_ref = url =~ /^\[.*?\]$/ ? true : false
              if input.empty? && !(ENV['TM_SCOPE'].scan(/markdown/).empty?) && LINE =~ /^(\s+)?$/
                domain = url.match(/https?:\/\/([^\/]+)/)
                parts = domain[1].split('.')
                name = case parts.length
                  when 1: parts[0]
                  when 2: parts[0]
                  else parts[1]
                end
                name = "itunes " + name if url =~ /(itunes|phobos).apple.com/
                snippet,output = linker.replace_if_needed("[#{name}]: #{url}\n")
                TextMate.exit_insert_snippet(output+"$0") if snippet
                TextMate.exit_insert_text(output)
              elsif !(ENV['TM_SCOPE'].scan(/markdown/).empty?) && LINE =~ /^(\s+|#{e_sh(input)})?$/
                skip = false
                linker.references.each { |ref|
                  if ref.has_value?(url)
                    TextMate::CoolDialog.cool_tool_tip("Repeat url: #{url}\nRepeat of reference: [#{ref['title']}]",false)
                    skip = true
                  end
                }
                if skip == true || is_ref
                  TextMate::CoolDialog.cool_tool_tip("Repeat reference url: #{url}",false) if is_ref
                  TextMate.exit_discard
                else
                  input = "itunes " + input if url =~ /(itunes|phobos).apple.com/
                  linker.replace_if_needed("[#{input}]: #{url}")
                end
              else
                linker.references.each {|ref|
                  if ref.has_value?(url)
                    snippet,output = linker.replace_if_needed("[#{input}][#{ref['title']}]")
                    TextMate.exit_insert_snippet(output) if snippet
                    TextMate.exit_insert_text(output)
                    exit
                  end
                }
                if is_ref
                  out = "[#{linker.input}]#{url}"
                else
                  out = "[#{linker.input}](#{url})"
                  # TODO: if the link isn't already a reference, insert a new ref link at the top or under existing refs, incrementing title as necessary
                  # TODO: replace current word with ref link
                end
                linker.replace_if_needed(out)
              end
            else
              if linker.links.empty?
                if CLIPBOARD =~ /\[?([^\]]+)\]?(?:.*?)?/
                  linkword = $1
                  linker.references.each {|ref|
                    if ref['title'] == $1
                      linker.replace_if_needed("[#{linker.input}][#{ref['title']}]")
                      exit
                    end
                  }
                end
                links = linker.additional_menu(linker.input)
                o = links[0][0] == "_ref" ? "[#{linker.input}][#{links[0][1]}]" : "[#{linker.input}](#{links[0][1]})"
                linker.replace_if_needed(o)
                exit
              end
            end
          else
            links = linker.additional_menu('')
            lines = INPUT.split("\n")
            row = ENV['TM_LINE_NUMBER'].to_i
            prevline = lines[row-2]
            linker.make_ref_list(links,prevline)
            exit
          end
        end
