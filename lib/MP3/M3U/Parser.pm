package MP3::M3U::Parser;
use strict;
use vars qw[$VERSION $AUTOLOAD];

# Data table key map
use constant PATH    => 0;
use constant ID3     => 1;
use constant LEN     => 2;
use constant ARTIST  => 3;
use constant SONG    => 4;

use constant MAXDATA => 4; # Maximum index number of the data table

use File::Spec ();
use IO::File   ();
use Cwd;

$VERSION = '2.01';

sub new {
   # -parse_path -seconds -search -overwrite
   my $class = shift;
   my %o     = scalar(@_) % 2 ? () : (@_); # options
   my $self  = {
                _M3U_         => [], # for parse()
                TOTAL_FILES   =>  0, # Counter
                TOTAL_TIME    =>  0, # In seconds
                TOTAL_SONGS   =>  0, # Counter
                AVERAGE_TIME  =>  0, # Counter
                ACOUNTER      =>  0, # Counter
                ANON          =>  0, # Counter for SCALAR & GLOB M3U
                INDEX         =>  0, # index counter for _M3U_
                EXPORTF       =>  0, # Export file name counter for anonymous exports
                seconds       => $o{'-seconds'}    || '', # format or get seconds.
                search_string => $o{'-search'}     || '', # search_string
                parse_path    => $o{'-parse_path'} || '', # mixed list?
                overwrite     => $o{'-overwrite'}  ||  0, # overwrite export file if exists?
                encoding      => $o{'-encoding'}   || '', # leave it to export() if no param
                expformat     => $o{'-expformat'}  || '', # leave it to export() if no param
                expdrives     => $o{'-expdrives'}  || '', # leave it to export() if no param
   };
   if ($self->{search_string} and length($self->{search_string}) < 3) {
      die "A search string must be at least three characters long!";
   }
   bless  $self, $class;
   return $self;
}

sub parse {
   my $self  = shift;
   my @files = @_;
   my $file;
   foreach $file (@files) {
      unless(ref $file) {
         $file = File::Spec->canonpath($file);
         -e $file or die "'$file' does not exists!";
      }
      $self->parse_file($file);
   }

   # Average time of all the parsed songs:
   $self->{AVERAGE_TIME} = ($self->{ACOUNTER} and $self->{TOTAL_TIME}) 
                           ? $self->seconds($self->{TOTAL_TIME}/$self->{ACOUNTER})
                           : 0;
   return $self if defined wantarray;
}

sub parse_file {
   # supports disk files, scalar variables and filehandles (typeglobs)
   my $self = shift;
   my $file = shift;
   my $ref  = ref($file) || '';
   if($ref and $ref !~ m[^(?:GLOB|SCALAR)$]) {
      die "Unknown parameter of type '$ref' passed to parse()!";
   }
   my $cd;
   unless ($ref) {
      $cd = (split /[\\\/]/, $file)[-1];
      $cd =~ s,\.m3u,,i;
   }
   my $i = $self->{INDEX};
   my $this_file;
   if ($ref) {
      $this_file = 'ANON'.$self->{ANON}++;
   } else {
      $this_file = $self->locate_file($file);
   }
   $self->{'_M3U_'}[$i] = {file  => $this_file,
                           list  => $ref ? $this_file : ($cd || ''),
                           drive => 'CDROM:',
                           data  => [],
                           total => 0,
                           };
   $self->{TOTAL_FILES} += 1; # Total lists counter
   my $index             = 0; # Index number of the list array
   # These three variables are used when there is a '-search' parameter.
   # long: total_time, total_songs, total_average_time
   my($ttime,$tsong,$taver) = (0,0,0);
   # while loop variables. j: junk data.
   my($m3u,$j,@song,$j2,$sec,$temp_sec);

   my($fh, @fh);
   if($ref eq 'GLOB') {
      $fh = $file;
   } elsif ($ref eq 'SCALAR') {
      @fh = split /\n/, $$file;
   } else {
      # Open the file to parse:
      $fh = IO::File->new;
      $fh->open("< $file") or die "I could't open '$file': $!" unless $ref;
   }

PREPROCESS:
   while ($m3u = ($ref eq 'SCALAR') ? (shift @fh) : <$fh>) {
      # First line is just a comment. But we need it to validate
      # the file as a m3u playlist file.
      chomp $m3u;
      if($m3u !~ m[^#EXTM3U]) {
         die $ref ? "The '$ref' parameter you have passed does not contain valid m3u data!"
                  : "'$file' is not a valid m3u file!";
      }
      last PREPROCESS;
   }

   my $dkey   =  $self->{'_M3U_'}[$i]{data};  # data key
   my $device = \$self->{'_M3U_'}[$i]{drive}; # device letter

RECORD: 
   while ($m3u = ($ref eq 'SCALAR') ? (shift @fh) : <$fh>) {
      chomp $m3u;
      next unless $m3u; # Record may be blank if it is not a disk file.
      $#{$dkey->[$index]} = MAXDATA; # For the absence of EXTINF line.
      # If the extra information exists, parse it:
      if($m3u =~ m!#EXTINF!i) {
         ($j ,@song) = split(/\,/,$m3u);
         ($j ,$sec)  = split(/:/,$j);
         $ttime     += $sec;
         $temp_sec   = $sec;
         $dkey->[$index][ID3] = join(",", @song);
         $dkey->[$index][LEN] = $self->seconds($sec || 0);
         $taver++;
         next RECORD; # jump to path info
      }

      # Get the drive and path info.      Possible cases are:
      if($m3u =~ m{^\w:[\\/](.+?)$}x or # C:\mp3\Singer - Song.mp3
         $m3u =~ m{^   [\\/](.+?)$}x or # \mp3\Singer - Song.mp3
         $m3u =~ m{^        (.+?)$}x    # Singer - Song.mp3
         ) {
         $dkey->[$index][PATH] = $self->{parse_path} eq 'asis' ? $m3u : $1;
         $$device = $1 if $$device eq 'CDROM:' and $m3u =~ m[^(\w:)];
         $tsong++;
      }

      # Try to extract artist and song info 
      # and remove leading and trailing spaces
      # Some artist names can also have a "-" in it. 
      # For this reason; require that the data has " - " in it. 
      # ... but the spaces can be one or more.
      # So, things like "artist-song" does not work...
      my($artist, @xsong) = split /\s{1,}-\s{1,}/, $dkey->[$index][ID3] || $dkey->[$index][PATH];
      if ($artist) {
         $artist =~ s[^\s+][];
         $artist =~ s[\s+$][];
         $artist =~ s[.*[\\/]][]; # remove path junk
         $dkey->[$index][ARTIST] = $artist;
      }
      if (@xsong) {
         my $song = join '-', @xsong;
         $song =~ s[^\s+][];
         $song =~ s[\s+$][];
         $song =~ s[\.[a-zA-Z0-9]+$][]; # remove extension if exists
         $dkey->[$index][SONG] = $song;
      }

      # convert undefs to empty strings
      foreach my $CHECK (0..MAXDATA) {
         $dkey->[$index][$CHECK] = '' unless defined $dkey->[$index][$CHECK];
      }

      # If we are searching something:
      if($self->{search_string}) {
         if($self->search($dkey->[$index][PATH], $dkey->[$index][ID3])) {
            $index++; # If we got a match, increase the index
         } else { # If we didnt matched anything, resize these counters ...
            $tsong--;
            $taver--;
            $ttime -= $temp_sec;
            delete $dkey->[$index]; # ... and delete the empty index
         }
      } else {
         $index++; # If we are not searching, just increase the index
      }
   }
   # Close the file
   $fh->close unless $ref;

   # Calculate the total songs in the list:
   $self->{'_M3U_'}[$i]{total} = $#{$self->{'_M3U_'}[$i]{data}} + 1;

   # Adjust the global counters:
   $self->{TOTAL_FILES}-- if($self->{search_string} and $#{ $self->{'_M3U_'}[$i]{data} } < 0);
   $self->{TOTAL_TIME}  += $ttime;
   $self->{TOTAL_SONGS} += $tsong;
   $self->{ACOUNTER}    += $taver;
   $self->{INDEX}++;
   # Return the parse object.
   return $self;
}

sub reset {
   # reset the object
   my $self = shift;
      $self->{'_M3U_'}      = [];
      $self->{TOTAL_FILES}  = 0;
      $self->{TOTAL_TIME}   = 0;
      $self->{TOTAL_SONGS}  = 0;
      $self->{AVERAGE_TIME} = 0;
      $self->{ACOUNTER}     = 0;
      $self->{INDEX}        = 0;
   return $self if defined wantarray;
}

sub result {
   my $self = shift;
   return(wantarray ? @{$self->{'_M3U_'}} : $self->{'_M3U_'});
}

sub locate_file {
   my $self = shift;
   my $file = shift;
   if ($file !~ m{[\\/]}) {
      # if $file does not have a slash in it then it is in the cwd.
      # don't know if this code is valid in some other filesystems.
      $file = File::Spec->canonpath(getcwd()."/".$file);
   }
   return $file;
}

sub search {
   my $self = shift;
   my $path = shift;
   my $id3  = shift;
   return(0) unless( $id3 or $path);
   my $search = quotemeta($self->{search_string});
   # Try a basic case-insensitive match:
   return(1) if($id3 =~ /$search/i or $path =~ /$search/i);
   return(0);
}

sub escape {
   my $self = shift;
   my $text = shift || return '';
   #$bad .= chr $_ for (1..8,11,12,14..31,127..144,147..159);$text =~ s/[$bad]//gs;
   my %escape = (
              '&' => '&amp;',
              '"' => '&quot;',
              '<' => '&lt;',
              '>' => '&gt;',
   );
   $text =~ s,\Q$_,$escape{$_},gs foreach keys %escape;
   return $text;
}

sub info {
   # Instead of direct accessing to object tables, use this method.
   my $self = shift;
   my @drive;
   for (my $i = 0; $i <= $#{ $self->{'_M3U_'} }; $i++) {
      push @drive, $self->{'_M3U_'}[$i]{drive};
   }
   return(
          songs   => $self->{TOTAL_SONGS},
          files   => $self->{TOTAL_FILES},
          ttime   => $self->{TOTAL_TIME}    ? $self->seconds($self->{TOTAL_TIME}) 
                                            : 0,
          average => $self->{AVERAGE_TIME} || 0,
          drive   => [@drive],
   );
}

sub seconds {
   # Format seconds if wanted.
   my $self = shift;
   my $all  = shift;
   return $all    unless( $self->{seconds} eq 'format' and $all !~ /:/);
   return '00:00' unless $all;
      $all  = $all/60;
   my $min  = int($all);
   my $sec  = sprintf("%02d",int(($all - $min)*60));
   my $hr;
   if($min > 60) {
      $all = $min/60;
      $hr  = int $all;
      $min = int(($all - $hr)*60);
   }
   $min = sprintf("%02d",$min);
   return $hr ? "$hr:$min:$sec" : "$min:$sec";
}

sub export {
   my $self      = shift;
   my %opt       = scalar(@_) % 2 ? () : (@_);
   my $format    = $opt{'-format'}    || $self->{'expformat'} || 'html';
   my $file      = File::Spec->canonpath($opt{'-file'}        || sprintf 'mp3_m3u%s.%s', $self->{EXPORTF}, $format);
   my $encoding  = $opt{'-encoding'}  || $self->{'encoding'}  || 'ISO-8859-1';
   my $drives    = $opt{'-drives'}    || $self->{'expdrives'} || 'on';
   my $overwrite = $opt{'-overwrite'} || $self->{'overwrite'} ||  0; # global overwrite || local overwrite || don't overwrite
   die "Unknown export format '$format'!" if $format !~ m[^(?:x|ht)ml$];
   if (-e $file and not $overwrite) {
      die "The export file '$file' exists on disk and you didn't select to overwrite it!";
   }
   my $fh = IO::File->new;
      $fh->open("> $file") or die "I can't open export file '$file' for writing: $!"; 
   my($cd,$m3u);
   if ($format eq 'xml') {
      $self->{TOTAL_TIME} = $self->seconds($self->{TOTAL_TIME}) if $self->{TOTAL_TIME} > 0;
      printf $fh qq~<?xml version="1.0" encoding="%s" ?>\n~, $encoding;
      printf $fh qq~<m3u lists="%s" songs="%s" time="%s" average="%s">\n~, $self->{TOTAL_FILES}, $self->{TOTAL_SONGS}, $self->{TOTAL_TIME}, $self->{AVERAGE_TIME};
      my $sc = 0;
      foreach $cd (@{ $self->{'_M3U_'} }) {
         $sc = $#{$cd->{data}}+1;
         next unless $sc;
         printf $fh qq~<list name="%s" drive="%s" songs="%s">\n~, $cd->{list}, $cd->{drive}, $sc;
         foreach $m3u (@{ $cd->{data} }) { 
            printf $fh qq~<song id3="%s" time="%s">%s</song>\n~, $self->escape($m3u->[ID3]) || '',$m3u->[LEN] || '',$self->escape($m3u->[PATH]);
         }
         print $fh "</list>\n";
         $sc = 0;
      }
      print $fh "</m3u>\n";
   } else {
      require Text::Template;
      # I don't think that weird numbers in the html mean anything 
      # to anyone. So, if you didn't want to format seconds in your 
      # code, I'm overriding it here (only for export(); Outside 
      # export(), you'll get the old value):
      local $self->{seconds} = 'format';
      my %t;
      ($t{up},$t{cd},$t{data},$t{down}) = split /<!-- MP3DATASPLIT -->/, $self->template;
      foreach (keys %t) {
         $t{$_} =~ s,^\s+,,gs;
         $t{$_} =~ s,\s+$,,gs;
      }
      my $tmptime = $self->{TOTAL_TIME} ? $self->seconds($self->{TOTAL_TIME}) : undef;
      my @tmptime;
      if ($tmptime) {
         @tmptime = split /:/,$tmptime;
         unshift @tmptime, 'Z' unless $#tmptime > 1;
      }
      my $HTML = {
              ENCODING    => $encoding,
              SONGS       => $self->{TOTAL_SONGS},
              TOTAL       => $self->{TOTAL_FILES},
              AVERTIME    => $self->{AVERAGE_TIME} ? $self->seconds($self->{AVERAGE_TIME}) : '<i>Unknown</i>',
              FILE        => $self->locate_file($file),
              TOTAL_FILES => $self->{TOTAL_FILES},
              TOTAL_TIME  => @tmptime ? [@tmptime] : '',
      };

      print $fh $self->tcompile(template => $t{up}, params=> {HTML => $HTML});
      my($song,$cdrom, $dlen);
      foreach $cd (@{ $self->{'_M3U_'} }) {
         next if($#{$cd->{data}} < 0);
         $cdrom .= "$cd->{drive}\\" unless($drives eq 'off');
         $cdrom .= $cd->{list};
         printf $fh $t{cd}."\n", $cdrom;
         foreach $m3u (@{ $cd->{data} }) {
            $song = $m3u->[ID3];
            unless($song) {
               $song = (split /\\/, $m3u->[PATH])[-1] || $m3u->[PATH];
               $song = (split /\./, $song       )[ 0] || $song;
            }
            $dlen = $m3u->[LEN] ? $self->seconds($m3u->[LEN]) : '&nbsp;';
            $song = $song       ? $self->escape($song)        : '&nbsp;';
            printf $fh "%s\n", $self->tcompile(template => $t{data}, params=> {data => {len => $dlen, song => $song}});
         }
         $cdrom = '';
      }
      print $fh $t{down};
   }
   $fh->close;
   $self->{EXPORTF}++;
   return $self if defined wantarray;
}

# compile template
sub tcompile {
   my $self     = shift;
   my $class    = ref $self;
   die "Invalid number of parameters!" if scalar @_ % 2;
   my %opt      = @_;
   my $template = Text::Template->new(TYPE       => 'STRING', 
                                      SOURCE     => $opt{template},
                                      DELIMITERS => ['<%', '%>'],
                                      ) or die "Couldn't construct the HTML template: $Text::Template::ERROR";
   my(@globals, $prefix, $ref);
   foreach (keys %{ $opt{params} }) {
      if ($ref = ref $opt{params}->{$_}) {
            if ($ref eq 'HASH')  {$prefix = '%'}
         elsif ($ref eq 'ARRAY') {$prefix = '@'}
         else                    {$prefix = '$'}
      }
      else {$prefix = '$'}
      push @globals, $prefix . $_;
   }

   my $text = $template->fill_in(PACKAGE => $class . '::Dummy',
                                 PREPEND => sprintf('use strict;use vars qw[%s];', join(" ", @globals)),
                                 HASH    => $opt{params},
              ) or die "Couldn't fill in template: $Text::Template::ERROR";
   return $text;
}

# HTML template code
sub template {
   return <<'MP3M3UParserTemplate';
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"
   "http://www.w3.org/TR/html4/loose.dtd">
<html>
 <head>
   <title>MP3::M3U::Parser Generated PlayList</title>
   <meta name="Generator" content="MP3::M3U::Parser">
   <meta http-equiv="content-type" content="text/html; charset=<%$HTML{ENCODING}%>">

   <style type="text/css">
   <!--
      body   { background   : #000040;
               font-family  : font1, Arial, serif;
               color        : #FFFFFF;
               font-size    : 10pt;    }
      td     { background   : none;
               font-family  : Arial, serif;
               color        : #FFFFFF;
               font-size    : 13px;    }
      hr     { background   : none;
               color        : #FFBF00; }
      .para1 { margin-top   : -42px;
               margin-left  : 350px;
               margin-right : 10px;
               font-family  : font2, Arial, serif;
               font-size    : 30px; 
               line-height  : 35px;
               background   : none;
               color        : #E1E1E1;
               text-align   : left;    }
      .para2 { margin-top   : 15px;
               margin-left  : 15px;
               margin-right : 50px;
               font-family  : font1, Arial Black, serif;
               font-size    : 50px;
               line-height  : 40px;
               background   : none;
               color        : #004080;
               text-align   : left;    }
      .t     { font-family  : Arial, serif;
               background   : none;
               color        : #FFBF00;
               font-size    : 13px;    }
      .ts    { font-family  : Arial, serif;
               color        : #FFBF00;
               background   : none;
               font-size    : 10px;    }
      .s     { font-family  : Arial, serif;
               background   : none;
               color        : #FFFFFF;
               font-size    : 13px;    }
      .info  { font-family  : Arial, serif;
               background   : none;
               color        : #409FFF;
               font-size    : 10px;    }
      .infob { font-family  : Arial, serif;
               background   : none;
               color        : #FFBF00;
               font-size    : 15px;    }
    -->
   </style>

 </head>

<body>

 <div align="center">
  <div class="para2" align="center"><p>MP3::M3U::Parser</p></div>
  <div class="para1" align="center"><p>playlist</p></div>
 </div>

<hr align="left" width="90%" noshade="noshade" size="1">
 <div align="left">

  <table border="0" cellspacing="0" cellpadding="0" width="98%">
   <tr><td>
    <span class="ts"><%$HTML{SONGS}%></span> <span class="info"> tracks and 
    <span class="ts"><%$HTML{TOTAL}%></span> Lists in playlist, 
      average track length: </span> 
      <span class="ts"><%$HTML{AVERTIME}%></span><span class="info">.</span>
     <br>
    <span class="info">Playlist length: </span><%
   my $time;
   if ($HTML{TOTAL_TIME}) {
      my @time = @{$HTML{TOTAL_TIME}};
      $time = qq~<span class="ts"  > $time[0] </span>
                 <span class="info"> hours    </span>~ if $time[0] ne 'Z';
      $time .= qq~
            <span class="ts"  > $time[1] </span>
            <span class="info"> minutes  </span>
            <span class="ts"  > $time[2] </span>
            <span class="info"> seconds. </span>~;
   } else {
      $time = qq~<span class="ts"><i>Unknown</i></span><span class="info">.</span>~;
   }
   $time;

     %><br>
    <span class="info">Right-click <a href="file://<%$HTML{FILE}%>">here</a>
      to save this HTML file.</span>
    </td>
   </tr>
 </table>

</div>
<blockquote>
<p><span class="infob"><big><% 
$HTML{TOTAL_FILES} > 1 ? "Playlists and Files" : "Playlist files"; 
%>:</big></span></p>

<table border="0" cellspacing="1" cellpadding="2">

<!-- MP3DATASPLIT -->
<tr><td colspan="2"><b>%s</b></td></tr>
<!-- MP3DATASPLIT -->
<tr><td><span class="t"><%$data{len}%></span></td><td><%$data{song}%></td></tr>
<!-- MP3DATASPLIT -->

  </table>
</blockquote>
<hr align="left" width="90%" noshade size="1">
<span class="s">This HTML File is based on 
<a href="http://www.winamp.com">WinAmp</a>`s HTML List.</span>
</body>
</html>
MP3M3UParserTemplate
}

sub AUTOLOAD {
   my $self = shift;
   my $name = $AUTOLOAD;
      $name =~ s/.*://;
   die ref($self) . " has no method called '$name'!";
}

sub DESTROY {}

package MP3::M3U::Parser::Dummy;

1;

__END__;

=head1 NAME

MP3::M3U::Parser - MP3 playlist parser.

=head1 SYNOPSIS

   use MP3::M3U::Parser;
   my $parser = MP3::M3U::Parser->new(%options);

   $parser->parse(\*FILEHANDLE, \$scalar, "/path/to/playlist.m3u");
   my $result = $parser->result;
   my %info   = $parser->info;

   $parser->export(-format   => 'xml',
                   -file     => "/path/mp3.xml",
                   -encoding => 'ISO-8859-9');

   $parser->export(-format   => 'html',
                   -file     => "/path/mp3.html",
                   -drives   => 'off');

   # convert all m3u files to individual html files.
   foreach (<*.m3u>) {
      $parser->parse($_)->export->reset;
   }

   # convert all m3u files to one big html file.
   foreach (<*.m3u>) {
      $parser->parse($_);
   }
   $parser->export;

=head1 DESCRIPTION

B<MP3::M3U::Parser> is a parser for M3U mp3 playlist files. It also 
parses the EXTINF lines (which contains id3 song name and time) if 
possible. You can get a parsed object or specify a format and export 
the parsed data to it. The format can be B<xml> or B<html>.

=head2 Methods

=head3 B<new>

The object constructor. Takes several arguments like:

=over 4

=item C<-seconds>

Format the seconds returned from parsed file? if you set this to the value 
C<format>, it will convert the seconds to a format like C<MM:SS> or C<H:MM:SS>.
Else: you get the time in seconds like; I<256> (if formatted: I<04:15>).

=item C<-search>

If you don't want to get a list of every song in the m3u list, but want to get 
a specific group's/singer's songs from the list, set this to the string you want 
to search. Think this "search" as a parser filter.

Note that, the module will do a *very* basic case-insensitive search. It does 
dot accept multiple words (if you pass a string like "michael beat it", it will 
not search every word seperated by space, it will search the string "michael beat it" 
and probably does not return any results -- it will not match 
"michael jackson - beat it"), it does not have a boolean search support, etc. If you 
want to do something more complex, get the parsed tree and use it in your own 
search function, or subclass this module and write your own C<search> method.

=item C<-parse_path>

The module assumes that all of the songs in your M3U lists are (or were: 
the module does not check the existence of them) on the same drive. And it 
builds a seperate data table for drive names and removes that drive letter 
(if there is a drive letter) from the real file path. If there is no drive 
letter (eg: under linux there is no such thing, or you saved m3u file into 
the same volume as your mp3s), then the drive value is 'CDROM:'.

So, if you have a mixed list like:

   G:\a.mp3
   F:\b.mp3
   Z:\xyz.mp3

set this parameter to 'C<asis>' to not to remove the drive letter from the real 
path. Also, you "must" ignore the drive table contents which will still contain 
a possibly wrong value; C<export> does take the drive letters from the drive tables. 
So, you can not use the drive area in the exported xml (for example).

=item C<-overwrite>

Same as the C<-overwrite> option in L<export|/export> but C<new> sets this 
C<export> option globally.

=item C<-encoding>

Same as the C<-encoding> option in L<export|/export> but C<new> sets this 
C<export> option globally.

=item C<-expformat>

Same as the C<-format> option in L<export|/export> but C<new> sets this 
C<export> option globally.

=item C<-expdrives>

Same as the C<-drives> option in L<export|/export> but C<new> sets this 
C<export> option globally.

=back

=head3 B<parse>

It takes a list of arguments. The list can include file paths, 
scalar references or filehandle references. You can mix these 
types. Module interface can handle them correctly.

   open FILEHANDLE, ...
   $parser->parse(\*FILEHANDLE);

or with new versions of perl:

   open my $fh, ...
   $parser->parse($fh);

   my $scalar = "#EXTM3U\nFoo - bar.mp3";
   $parser->parse(\$scalar);

or

   $parser->parse("/path/to/some/playlist.m3u");

or

   $parser->parse("/path/to/some/playlist.m3u",\*FILEHANDLE,\$scalar);

Note that globs and scalars are passed as references.

Returns the object itself.

=head3 B<result>

Must be called after C<parse>. Returns the result set created from
the parsed data(s). Returns the data as an array or arrayref.

   $result = $parser->result;
   @result = $parser->result;

Data structure is like this:

   $VAR1 = [
             {
               'drive' => 'G:',
               'file' => '/path/to/mylist.m3u',
               'data' => [
                           [
                             'mp3\Singer - Song.mp3',
                             'Singer - Song',
                             232,
                             'Singer',
                             'Song'
                           ],
                           # other songs in the list
                         ],
               'total' => '3',
               'list' => 'mylist'
             },
             # other m3u list
           ];

Each playlist is added as a hashref:

   $pls = {
           drive => "Drive letter if available",
           file  => "Path to the parsed m3u file or generic name if GLOB/SCALAR",
           data  => "Songs in the playlist",
           total => "Total number of songs in the playlist",
           list  => "name of the list",
   }

And the C<data> key is an AoA:

   data => [
            ["MP3 PATH INFO", "ID3 INFO","TIME","ARTIST","SONG"],
            # other entries...
            ]

You can use the Data::Dumper module to see the structure yourself:

   use Data::Dumper;
   print Dumper $result;

=head3 B<info>

You must call this after calling L<parse|/parse>. It returns an info hash 
about the parsed data.

   my %info = $parser->info;

The keys of the C<%info> hash are:

   songs   => Total number of songs
   files   => Total number of lists parsed
   ttime   => Total time of the songs 
   average => Average time of the songs
   drive   => Drive names for parsed lists

Note that the 'drive' key is an arrayref, while others are strings. 

   printf "Drive letter for first list is %s\n", $info{drive}->[0];

But, maybe you do not want to use the C<$info{drive}> table; see C<-parse_path> 
option in L<new|/new>.

=head3 B<export>

Exports the parsed data to a format. The format can be C<xml> or C<html>. 
The HTML File' s style is based on the popular mp3 player B<WinAmp>' s 
HTML List file. Takes several arguments:

=over 4

=item C<-file>

The full path to the file you want to write the resulting data. 
If you do not set this parameter, a generic name will be used.

=item C<-format>

Can be C<xml> or C<html>. Default is C<html>.

=item C<-encoding>

The exported C<xml> file's encoding. Default is B<ISO-8859-1>. 
See L<http://www.iana.org/assignments/character-sets> for a list. 
If you don't define the correct encoding for xml, you can get 
"not well-formed" errors from the xml parsers. This value is 
also used in the meta tag section of the html file.

=item C<-drives>

Only required for the html format. If set to C<off>, you will not 
see the drive information in the resulting html file. Default is 
C<on>. Also see C<-parse_path> option in L<new|/new>.

=item C<-overwrite>

If the file to export exists on the disk and you didn't set this 
parameter to a true value, C<export> will die with an error.

If you set this parameter to a true value, the named file will be 
overwritten if already exists. Use carefully.

=back

Returns the object itself.

=head3 B<reset>

Resets the parser object and returns the object itself. Can be usefull 
when exporting to html.

   $parser->parse($fh       )->export->reset;
   $parser->parse(\$scalar  )->export->reset;
   $parser->parse("file.m3u")->export->reset;

Will create individual files while this code

   $parser->parse($fh       )->export;
   $parser->parse(\$scalar  )->export;
   $parser->parse("file.m3u")->export;

creates also individual files but, file2 content will include 
C<$fh> + C<$scalar> data and file3 will include 
C<$fh> + C<$scalar> + C<file.m3u> data.

=head2 Subclassing

You may want to subclass the module to implement a more advanced
search or to change the HTML template.

To override the default search method create a C<search> method 
in your class and to override the default template create a C<template> 
method in your class.

See the tests in the distribution for examples.

=head2 Error handling

Note that, if there is an error, the module will die with that error. So, 
using C<eval> for all method calls can be helpful if you don't want to die:


   eval {$parser->parse(@list)}
   die "Parser error: $@" if $@;

As you can see, if there is an error, you can catch this with C<eval> and 
access the error message with the special Perl variable C<$@>.

=head1 EXAMPLES

See the tests in the distribution for example codes. If you don't have 
the distro, you can download it from CPAN.

=head2 TIPS

=over 4

=item B<WinAmp>

(For v2.80. I don't use Winamp v3 series.) If you don't see any EXTINF lines in 
your saved M3U lists, open preferences, go to "Options", set "Read titles on" 
to "B<Display>", add songs to your playlist and scroll down/up in the playlist 
window until you see all songs' time infos. If you don't do this, you'll get 
only the file names or only the time infos for the songs you have played. Because, 
to get the time info, winamp must read/scan the file first.

=item B<Naming M3U Files>

Give your M3U files unique names and put them into the same directory. This way, 
you can have an easy maintained archive.

=back

=head1 CAVEATS

v2 is B<not> compatible with v1x. v2 of this module breaks
old code. See the I<Changes> file for details.

=head1 BUGS

=over 4

=item * 

HTML and XML escaping is limited to these characters: 
E<amp> E<quot> E<lt> E<gt>.

=back 

Contact the author if you find any other bugs.

=head1 SEE ALSO

L<MP3::M3U>.

=head1 AUTHOR

Burak Gürsoy, E<lt>burakE<64>cpan.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 Burak Gürsoy. All rights reserved.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
