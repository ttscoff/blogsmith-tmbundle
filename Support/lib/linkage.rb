#!/usr/bin/env ruby -wKU
DIALOG = ENV['DIALOG']
require "#{ENV['TM_SUPPORT_PATH']}/lib/exit_codes"
require "#{ENV['TM_SUPPORT_PATH']}/lib/escape"
require "#{ENV['TM_SUPPORT_PATH']}/lib/ui"
require "#{ENV['TM_SUPPORT_PATH']}/lib/osx/plist"
require "#{ENV['TM_BUNDLE_SUPPORT']}/lib/cooldialog.rb"
require ENV['TM_BUNDLE_SUPPORT'] + '/lib/yahoo'
require 'net/http'
require 'rexml/document'
require 'erb'
require 'cgi'

$KCODE = 'u'

class Linkage
  def initialize

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

  def get_clipboard
    %x{__CF_USER_TEXT_ENCODING=$UID:0x8000100:0x8000100 pbpaste}.strip
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

  def link_word(input,refs = [])
    urls = scan_links(get_clipboard)
    unless refs.empty?
      urls.map! {|url|
        link = url.clone
        refs.each {|ref|
          link = "["+ref['title']+"]" if url == ref['link']
        }
        link
      }
    end
    return [input,''] unless urls.length > 0
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
    [input,url]
  end

  def create_app_store_link(document)
    errormessage = ""
    itunes = []
    iturls = document.scan(/^\[(itunes( ?[^\]]+)?)\]\:\s([^\s]+)\s/)
    errormessage += "Couldn't locate any iTunes urls. (e.g. [itunes linktitle]: http://...)\n" if iturls.empty?
    urls = document.scan(/^\[(dev( ?[^\]]+)?)\]\:\s([^\s]+)\s/)
    errormessage += "Couldn't locate any Developer urls. (e.g. [dev linktitle]: http://...)\n" if urls.empty?
    return [nil,nil,errormessage] unless errormessage == ""
    itunesurl,devurl,itunesmatch = ""
    iturls.each {|itmatch|
      urls.each{|url|
        urlmatch = url[1] ? url[1].strip.downcase.to_s : "blank"
        itunesmatch = itmatch[1] ? itmatch[1].strip.downcase.to_s : "blank"
        devurl = url[0].strip if urlmatch === itunesmatch || urlmatch.gsub(/ ?\d+$/,'') === itunesmatch.gsub(/ ?\d+$/,'')
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
        iturl = res['selectedMenuItem']['ref']
        url = res['selectedMenuItem']['dev']
      end
    end
    if itunes[0]['url'] !~ /(itunes|phobos).apple.com/
      return [nil,nil,"Selected iTunes link is not an App Store link"]
    else
      return [url,iturl,errormessage]
    end
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
    require 'erb'
    require 'net/http'
    require 'rexml/document'

    offset = 0
    if string.empty?
      phrase = TextMate::UI.request_string(:title => "Search Query",:prompt => "Enter terms to search for")
    else
      if ENV['TM_CURRENT_LINE'] =~ /^\[([^\]]+)/
        phrase = $1
        phrase = phrase.sub(/dev /,'') + " iphone" if ENV['TM_CURRENT_LINE'] =~ /^\[dev /
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
      title = res['selectedMenuItem']['title']
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
      return [title, url]

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
	    title = string.empty? ? answer.chomp : string
	    return [title,url]
	end
  end

end
