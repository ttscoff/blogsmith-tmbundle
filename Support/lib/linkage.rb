#!/usr/bin/env ruby -wKU
DIALOG = ENV['DIALOG']
require "#{ENV['TM_SUPPORT_PATH']}/lib/exit_codes"
require "#{ENV['TM_SUPPORT_PATH']}/lib/escape"
require "#{ENV['TM_SUPPORT_PATH']}/lib/ui"
require "#{ENV['TM_SUPPORT_PATH']}/lib/osx/plist"
require 'erb'

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

  def link_word(input)
    urls = scan_links(get_clipboard)
    TextMate.exit_show_tool_tip "No links" unless urls.length > 0
    if urls.length == 1
      url = urls[0]
    else
      linklist = []
      urls.each {|link|
        linklist << {'title' => link, 'url' => link }
      }
      plist = { 'menuItems' => linklist }.to_plist

      res = OSX::PropertyList.load(`#{e_sh DIALOG} -up #{e_sh plist}`)
      TextMate.exit_show_tool_tip "Cancelled" unless res.has_key? 'selectedMenuItem'
      url = res['selectedMenuItem']['url']
    end
    [input,url]
  end

  def create_app_store_link(document)
    errormessage = ""
    itunes = []
    iturls = document.scan(/^\[itunes( ?[^\]]+)?\]\:\s([^\s]+)\s/)
    errormessage = "Couldn't locate any iTunes urls.\n" if iturls.nil?
    urls = document.scan(/^\[dev( ?[^\]]+)?\]\:\s([^\s]+)\s/)
    errormessage += "Couldn't locate any Developer urls.\n" if urls.nil?
    itunesurl = ""
    devurl = ""
    iturls.each {|itmatch|
      urls.each{|url|
		if url[0].strip.downcase.to_s === itmatch[0].strip.downcase.to_s
        	devurl = url[1].strip
		end
      }
	if devurl.nil?
      errormessage += "Couldn't find a match for iTunes url #{itmatch[0].strip.downcase}" 
    else
  	  itunes << { 'title' => itmatch[0].strip.downcase, 'url' => itmatch[1].strip, 'dev' => devurl }
	end
    }
	if itunes.length == 0
		errormessage += "No sets of dev/itunes links found"
    elsif itunes.length === 1
      return [itunes[0]['dev'],itunes[0]['url']]
    else
      plist = { 'menuItems' => itunes }.to_plist
      res = OSX::PropertyList.load(`#{e_sh DIALOG} -up #{e_sh plist}`)
      TextMate.exit_show_tool_tip "Cancelled" unless res.has_key? 'selectedMenuItem'
      iturl = res['selectedMenuItem']['url']
      url = res['selectedMenuItem']['dev']
    end
    if errormessage.nil?
      return [url,iturl]
    else
#	  TextMate::UI.show_tool_tip "Error:\n" + errormessage
	  return [url,iturl]
    end
  end
end
