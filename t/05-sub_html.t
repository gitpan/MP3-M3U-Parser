#!/usr/bin/env perl -w
use strict;
use Test::More qw( no_plan );

my $parser = MyParser->new;
   $parser->parse('test.m3u');
   $parser->export(-format    => 'html',
                   -file      => "03_sub_html.html",
                   -overwrite => 1);

ok(1);

package MyParser;
use base qw[MP3::M3U::Parser];

sub _template {
   return <<'MP3M3UParserTemplate';
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"
   "http://www.w3.org/TR/html4/loose.dtd">
<html>
 <head>
   <title>MP3::M3U::Parser Generated PlayList</title>
   <meta name="Generator" content="MP3::M3U::Parser">
 </head>
<body>
 <h1>MP3::M3U::Parser - playlist</p></h1>

  <table border="0" cellspacing="0" cellpadding="0" width="98%">
   <tr><td>
    <%$HTML{SONGS}%> tracks and 
    <%$HTML{TOTAL}%> Lists in playlist, 
      average track length: 
      <%$HTML{AVERTIME}%>.
     <br>
    Playlist length:<%
   my $time;
   if ($HTML{TOTAL_TIME}) {
      my @time = @{$HTML{TOTAL_TIME}};
      $time  = "$time[0] hours " if $time[0] ne 'Z';
      $time .= "$time[1] minutes $time[2] seconds.";
   } else {
      $time = "Unknown.";
   }
   $time;

     %><br>
    Right-click <a href="file://<%$HTML{FILE}%>">here</a>
      to save this HTML file.
    </td>
   </tr>
 </table>
<h2><% $HTML{TOTAL_FILES} > 1 ? "Playlists and Files"
                              : "Playlist files"; %></h2>

<table border="0" cellspacing="1" cellpadding="2">

<!-- MP3DATASPLIT -->
<tr><td colspan="2"><b>%s</b></td></tr>
<!-- MP3DATASPLIT -->
<tr><td><span class="t"><%$data{len}%></span></td>
<td><%$data{song}%></td></tr>
<!-- MP3DATASPLIT -->
  </table>
</body>
</html>
MP3M3UParserTemplate
}
