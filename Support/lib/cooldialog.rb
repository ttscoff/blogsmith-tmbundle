module TextMate

  module CoolDialog
	
	class << self
		def has_dialog2
			tm_dialog = e_sh ENV['DIALOG']
			! tm_dialog.match(/2$/).nil? 
		end
		def cool_tool_tip(content)
			if has_dialog2
			output = %^<div style="background: #666;">^
			output += content.gsub(/([^\n+]+)\n/m,"<p>\\1</p>")
			output += %^</div>^
			html = <<-HTML
			<head>
			<style type="text/css" media="screen">
			body{padding:1em;max-width:400px;}
			#css0 {
			  -webkit-transition: all 0.3s ease-in;
			  -webkit-transform: scale(0.5);
			  opacity:0;
			}
			div div {
				padding: 0.8em 0.5em;
				color:#fff;
				text-shadow: 1px 1px 2px #000;
				-webkit-box-shadow: 0.2em 0.3em 1em #000;
				-webkit-border-radius: 1em;
				line-height: 2.5em;
				padding: 0 1em;
				float: left;
				-webkit-box-shadow: -4px 4px 1px #fff;
			}
			</style>
			</head>
			<body onload="document.getElementById('css0').style.opacity='.9';document.getElementById('css0').style.webkitTransform='scale(1)'">

			<div id="css0">
			#{output}
			</div>

			</body>
			HTML

			TextMate::UI.tool_tip("#{html}", {:transparent => true, :format => :html})
			# %x{"$DIALOG" tooltip -t --format html #{e_sh(html)}}
			else
				TextMate.exit_show_tool_tip content
			end
		end
	end
	end		
end