# -*- Mode: HTML; -*- #

. "$TM_SUPPORT_PATH/lib/html.sh"

tm_live_stuff() {
  # $1 = filename
  # $2 = stop button?
  # $3 = tail?
  
  cat <<EOF
  <!-- TM_TAILER -->
  <script type="text/javascript">
  
  var TM_TAILER = null;
  var tm_tailer_hooks = [function(){}];
  
  Element = {};
  Element.scrollTo = function(element){
    element = document.getElementById(element);
    var x = element.x ? element.x : element.offsetLeft,
        y = element.y ? element.y : element.offsetTop;
    window.scrollTo(x, y);
  };
  
  function tm_tailer_done(){
    document.getElementById("tm_live_result").innerHTML += '\nDONE\n';
    tm_do_hooks()
  }
  
  function tm_tailer_end(){
    TM_TAILER.cancel();
    return 'done'
  }
  
  function tm_live_start(){
    if(TM_TAILER){ tm_tailer_end() };
    
    TM_TAILER              = TextMate.system('tail -f "$1"', tm_tailer_done);
    TM_TAILER.onreadoutput = tm_tailer_outputHandler;
    TM_TAILER.onreaderror  = tm_tailer_outputHandler;
  }
  
  function tm_tailer_outputHandler(currentStringOnStdout){
    tm_live_result = document.getElementById("tm_live_result");
    
    if(tm_auto_clear){ tm_live_result.innerHTML = '' };
    tm_live_result.innerHTML += currentStringOnStdout;
    
    Element.scrollTo('tm_tailer_end');
    tm_do_hooks()
  }
  
  function tm_do_hooks()
  {
    for (var i=0; i < tm_tailer_hooks.length; i++) {
      tm_tailer_hooks[i]();
    };
  }
  
  window.onunload = function(){
    tm_tailer_end()
    /*TextMate.system('echo '+ tm_tailer_end() +'|qs', null);*/
  };
  
  function tm_command_focus()
  {
     command = document.getElementById('command');
     if(command){command.focus()};
  }
  tm_tailer_hooks.push(tm_command_focus);
  
  </script>
EOF
  
  [ -n "$3" ] && echo -n <<EOF
<script type="text/javascript">
  _tm_tailer_outputHandler = tm_tailer_outputHandler;
  
  tm_tailer_outputHandler = function(currentStringOnStdout){
    TextMate.system('cat "$1"', _tm_tailer_outputHandler);
  };
</script>
EOF
  echo '<pre id="tm_live_result" style="white-space: pre-wrap"></pre><div id="tm_tailer_end"></div>'
}

stop_button() {
  echo -n '<!-- STOP --><input type="button" onclick="tm_tailer_end(); tm_do_hooks();" value="STOP" accesskey="." /><!-- /STOP -->'
}

tm_live_cat() {
  tm_live_stuff $1 $2 $3
  cat <<EOF
  <!-- TM_LIVE_CAT -->
  <script type="text/javascript">
  function tm_live_start(){
    if(TM_TAILER){ tm_tailer_end() };
    TM_TAILER              = TextMate.system('tail -f "$1"', tm_tailer_done);
    TM_TAILER.onreadoutput = tm_tailer_outputHandler;
    TM_TAILER.onreaderror  = tm_tailer_outputHandler;
  }
  tm_live_start();
  </script>
EOF
  echo '<!-- /TM_LIVE_CAT -->'
}

tm_live_cmd() {
  tm_live_stuff $1 $2 $3
  cat <<EOF
  <!-- TM_LIVE_CMD -->
  <script type="text/javascript">
  function tm_live_start(cmd){
    if(TM_TAILER){ tm_tailer_end() };
    
    TM_TAILER              = TextMate.system('$1' + cmd, tm_tailer_done);
    TM_TAILER.onreadoutput = tm_tailer_outputHandler;
    TM_TAILER.onreaderror  = tm_tailer_outputHandler;
  }
  </script>
EOF
  
  cat <<EOF
  <form onsubmit="tm_live_start(document.getElementById('command').value);return false">
    <input type="text" name="command" value="$TM_SELECTED_TEXT" id="command" style="width:100%">
  </form>
EOF
  stop_button
  clear_button
  echo '<!-- /TM_LIVE_CMD -->'
}

auto_resize_js() {
  cat <<EOF
  <!-- AUTO_RESIZE_JS -->
  <script type="text/javascript" charset="utf-8">
  function auto_resize_js()
  {
    window.resizeTo(200,200);/*WxH*/
    /*window.moveTo(0,0);*/
    
    w_max = self.screen.width
    w_content = document.documentElement.scrollWidth
    if(w_content > w_max){ w_content = w_max };
    window.resizeTo(w_content,self.innerHeight);/*WxH*/
    
    
    h_max = self.screen.height - 50
    h_content = document.documentElement.scrollHeight
    if(h_content > h_max){ h_content = h_max };
    
    window.resizeTo(w_content,h_content);/*WxH*/
EOF
  [ -n "$1" ] && echo "window.resizeBy($1,$2)"
  echo '
  }
  if(tm_tailer_hooks){ tm_tailer_hooks.push( auto_resize_js ) };
  auto_resize_js();
  </script>
  <!-- /AUTO_RESIZE_JS -->'
}

clear_button() {
cat <<EOF
<!-- CLEAR_BUTTON -->
<div> <input type="button" name="clear" value="clear" id="clear" onclick="document.getElementById('tm_live_result').innerHTML=''; tm_do_hooks();" accesskey="k" /> </div>
<!-- /CLEAR_BUTTON -->
EOF
}

auto_clear() {
cat <<EOF
<script type="text/javascript">
tm_auto_clear = true;
</script>
EOF
}
