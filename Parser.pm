package MP3::M3U::Parser;
use strict;
use File::Spec ();
use IO::File   ();
use vars qw/$AUTOLOAD $VERSION/;

$VERSION = '1.0';

sub new {
   my $class   = shift;
   my $self    = {};
   bless $self, $class;

      $self->error("Parameters passed to new() must be in 'param => value' format!") if(scalar(@_) % 2);
   my %options = @_; # Parameters;
      $self->validate('new',[qw/-type -path -file -seconds -search -parse_path/],[keys %options]);

   INIT: {
      $self->{type}          = $options{'-type'}       || 'file'; # file | dir
      $self->{path}          = $options{'-path'}       || '';     # Should never be empty.
      $self->{file}          = $options{'-file'}       || '';     # if type is file, this must be a real file.
      $self->{seconds}       = $options{'-seconds'}    || '';     # format or get seconds.
      $self->{search_string} = $options{'-search'}     || '';     # search_string
      $self->{parse_path}    = $options{'-parse_path'} || '';     # mixed list?
      $self->{full_path}     = undef; # If type is 'file', set this to path+file
      $self->{M3U}           = {};    # for parse()
      $self->{DRIVE}         = {};    # Drive names for all parsed lists
      $self->{TOTAL_FILES}   = 0;     # Counter
      $self->{TOTAL_TIME}    = 0;     # In seconds
      $self->{TOTAL_SONGS}   = 0;     # Counter
      $self->{AVERAGE_TIME}  = 0;     # Counter
      $self->{ACOUNTER}      = 0;     # Counter
      $self->{EXPORT_FORMAT} = undef; # Export to what?
      $self->{ERROR}         = undef; # Contains error messages.
   }

   CHECK_PARAMS: {
      $self->{path} = File::Spec->canonpath($self->{path});
      ($self->{path} and -d $self->{path}) or $self->error("I can't find the directory '$self->{path}': $!");
      if ($self->{type} eq 'file') {
          $self->{full_path} = File::Spec->catfile($self->{'path'},$self->{'file'});
          unless(-e $self->{full_path}) {
             $self->error("I can not find the mp3 list '$self->{full_path}': $!");
          }
      }
      if ($self->{search_string} and length($self->{search_string}) < 3) {
         $self->error("A search string must be at least three characters long!");
      }
   }
   return $self;
}

sub parse {
   # The parsed data structure is like this:
   # 
   # $parsed = {
   #              CDNAME => [
   #                          [
   #                            'ID3 NAME', # can be empty if no EXTINF line
   #                            'SECONDS',  # can be empty if no EXTINF line.
   #                            'FULLPATH', # always has a value.
   #                           ],
   #                         # Array continues ...
   #                         ]
   #            # and so on ...
   #            };
   #
   # CDNAME is the name of the m3u list.
   #
   # If a search is done and a list has no matches, then you'll get an 
   # empty list like:
   #
   # CDNAME => [['','','']]

   my $self    = shift;
   my $forward = shift;
   # Get the dir contents if we are parsing a directory.
   if($self->{type} eq 'dir') {
      my @dir = $self->read_dir;
      my $file;
      foreach $file (@dir) {
         $self->parse_file($file);
      }
   } else {
   # Just parse one file
      $self->parse_file;
   }

   # Average time of all the parsed songs:
   $self->{AVERAGE_TIME} = ($self->{ACOUNTER} and $self->{TOTAL_TIME}) 
                           ? $self->seconds(int($self->{TOTAL_TIME}/$self->{ACOUNTER}))
                           : 0;

   $self->error("I couldn't find any songs in the list(s)!") if $self->{TOTAL_SONGS} == 0;

   # If you call this sub like this: 
   # __PACKAGE__->new(ARGV)->parse(1)->export(ARGV)
   # Just returns the object itself.
   # Else: it returns the parsed results (hash or hashref).
   return $forward ? $self : (wantarray ? %{$self->{M3U}} : $self->{M3U});
}

sub parse_file {
   # Private function.
   # Do NOT call this sub from your program!

   # Parse an M3U file. This is the real parse() sub :)
   my $self = shift;
   # If we dont parse a dir, just get the full path to the file, 
   # else; use @_.
   my $file = ($self->{type} eq 'file') ? $self->{full_path} : shift(@_);
   my $fh   = IO::File->new;
   my $cd;
      $cd = (split /[\\\/]/, $file)[-1];
      $cd =~ s,\.m3u,,i;
      $self->{M3U}{$cd}     = [];       # Main key
      $self->{DRIVE}{$cd}   = 'CDROM:'; # Default drive name
      $self->{TOTAL_FILES} += 1;        # Total lists counter
   my $index = 0; # Index number of the list array
   # These three variables are used when there is a '-search' parameter.
   # long: total_time, total_songs, total_average_time
   my($ttime,$tsong,$taver) = (0,0,0);
   # while loop variables. j: junk data.
   my($m3u,$j,$song,$j2,$sec,$temp_sec);

      # Open the file to parse:
      $fh->open("< $file") or $self->error("I could't open '$file': $!");

RECORD: 

   while($m3u = <$fh>) {
      $#{$self->{M3U}{$cd}[$index]} = 2; # For the absence of EXTINF line.
      chomp $m3u;
      next if $m3u =~ m,^#EXTM3U,i;      # First line is just a comment.
      # If the extra information exists, parse it:
      if($m3u =~ m!#EXTINF!i) {
         ($j ,$song) = split(/\,/,$m3u); # ($artist,$song) = split / - /, $song; ???
         ($j ,$sec)  = split(/:/,$j);
         $ttime     += $sec;
         $temp_sec   = $sec;
         $self->{M3U}{$cd}[$index]->[0] = $song;
         if ($sec) {
            $sec = $self->seconds($sec);
         } else {
            $sec = '';
         }
         $self->{M3U}{$cd}[$index]->[1] = $sec;
         $taver++;
         next RECORD;
      }
      # Get the drive and path info.   Possible cases are:
      if($m3u =~ m,^\w:\\(.+?)$,i or # C:\mp3\Singer - Song.mp3
         $m3u =~ m,^\\(.+?)$,i    or # \mp3\Singer - Song.mp3
         $m3u =~ /^(.+?)$/           # Singer - Song.mp3
         ) {
         $self->{M3U}{$cd}[$index]->[2] = ($self->{parse_path} eq 'asis') ? $m3u : $1;
         unless ($self->{DRIVE}{$cd} && $self->{DRIVE}{$cd} ne 'CDROM:') {
            if($m3u =~ m,^(\w:),){
               $self->{DRIVE}{$cd} = $1;
            }
         }
         $tsong++;
         # If we are searching something:
         if($self->{search_string}) {
            if($self->search($self->{M3U}{$cd}[$index][0],$self->{M3U}{$cd}[$index][2])) {
               # If we got a match, increase the index
               $index++;
            } else {
               # If we didnt matched anything, resize these counters ...
               $tsong--;
               $ttime -= $temp_sec;
               $taver--;
               # ... and delete the empty index:
               delete $self->{M3U}{$cd}[$index];
            }
         } else {
            # If we are no searching, just increase the index:
            $index++;
         }
         next RECORD;
      }
   }
   # Close the file
   $fh->close;

   # Adjust the global counters:
   $self->{TOTAL_FILES}-- if($self->{search_string} and $#{ $self->{M3U}{$cd} } < 0);
   $self->{TOTAL_TIME}  += $ttime;
   $self->{TOTAL_SONGS} += $tsong;
   $self->{ACOUNTER}    += $taver;
   # Return the parse object.
   return $self;
}

sub search {
   # Private function.
   # Do NOT call this sub from your program!

   my $self  = shift;
   my $str   = shift;
   my $str2  = shift;
   return(0) unless( $str or $str2);
   my $search = quotemeta($self->{search_string});
   # Try a basic case-insensitive match:
   return(1) if($str =~ /$search/i or $str2 =~ /$search/i);
   return;
}

sub export {
# Export the parsed object to a format like xml or html.
# $self->{M3U}{$cd}[$index] = ["ID3","TIME","PATH"];
   my $self     = shift;
      $self->error("Parameters passed to export() must be in 'param => value' format!") if(scalar(@_) % 2);
   my %opt      = @_;
      $self->validate('export',[qw/-file -format -encoding -drives/],[keys %opt]);

   my $file     = $opt{'-file'}     || $self->error("You must specify a file to export!");
   my $format   = $opt{'-format'}   || $self->error("You must specify a format ('xml', 'html' or 'html_split') to export!");
   my $encoding = $opt{'-encoding'} || 'ISO-8859-1';
   my $drives   = $opt{'-drives'}   || 'on';
   $self->error("Unknown export format '$format'!") if ($format !~ /xml|html|html_split/);
      # Set this global for escape()
      $self->{EXPORT_FORMAT} = $format;
      $file = File::Spec->canonpath($file);
   my $fh   = IO::File->new;
      $fh->open("> $file") or $self->error("I can't open export file '$file' to write: $!"); 
   my($cd,$m3u);
   if ($format eq 'xml') {
      $self->{TOTAL_TIME} = $self->seconds($self->{TOTAL_TIME}) if($self->{TOTAL_TIME} > 0);
      print $fh qq~<?xml version="1.0" encoding="$encoding" ?>\n~;
      print $fh qq~<m3u lists="$self->{TOTAL_FILES}" songs="$self->{TOTAL_SONGS}" time="$self->{TOTAL_TIME}" average="$self->{AVERAGE_TIME}">\n~;
      my $sc = 0;
         foreach $cd (sort keys %{ $self->{M3U} }) {
            $sc = $#{$self->{M3U}{$cd}}+1;
            print $fh qq~<cd name="$cd" drive="$self->{DRIVE}{$cd}" songs="$sc">\n~;
            foreach $m3u (sort @{ $self->{M3U}{$cd} }) {
               print $fh sprintf qq~<song id3="%s" time="%s">%s</song>\n~,$self->escape($m3u->[0]),$m3u->[1],$self->escape($m3u->[2]);
            }
            print $fh "</cd>\n";
            $sc = 0;
         }
         print $fh "</m3u>\n";
   } else {
      if ($format eq 'html_split') {
         $self->error("'html_split' format has not been implemented yet.");
      } else {
         # I don't think that weird numbers in the html mean anything 
         # to anyone. So, if you didn't want to format seconds in your 
         # code, I'm overriding it here (only for export(); Outside 
         # export(), you'll get the old value):
         local $self->{seconds} = 'format';
         print $fh $self->html('start',total => $self->{TOTAL_FILES},
                                       ttime => $self->{TOTAL_TIME},
                                       songs => $self->{TOTAL_SONGS},
                                       file  => $file);
         my $song;
         my $cdrom;
         foreach $cd (sort keys %{ $self->{M3U} }) {
            next if($#{$self->{M3U}{$cd}} < 0);
            $cdrom .= "$self->{DRIVE}{$cd}\\" unless($drives eq 'off');
            $cdrom .= $cd;
            print $fh qq~<tr><td colspan="2"><b>$cdrom</b></td></tr>\n~;
            foreach $m3u (sort @{ $self->{M3U}{$cd} }) {
               $song = $m3u->[0];
               unless($song) {
                  $song = (split /\\/, $m3u->[2])[-1] || $m3u->[2];
                  $song = (split /\./, $song    )[0]  || $song;
               }
               # Hmm... $song must never be empty, but I put this code here.
               $song     = $song     ? $self->escape($song)      : '&nbsp;';
               $m3u->[1] = $m3u->[1] ? $self->seconds($m3u->[1]) : '&nbsp;';
               print $fh qq~<tr><td><span class="t">$m3u->[1]</span></td><td>$song</td></tr>\n~;
            }
            $cdrom = '';
         }
         print $fh $self->html('end');
      }
   }
   $fh->close;
   return $self if defined wantarray;
}

sub escape {
   # Private function.
   # Do NOT call this sub from your program!

   my $self = shift;
   my $text = shift || return;

   # These characters are represented as black rectangles 
   # (in my system) and these things (some of them) give 
   # "well-formed" error with XML::Simple (Well, actually 
   # XML::Parser dies). If anyone has any suggestions/info 
   # about this, please tell them to me :)

   # <del_or_correct>
   if ($self->{EXPORT_FORMAT} eq 'xml') {
      my $bad; 
         $bad .= chr $_ for (1..8,11,12,14..31,127..144,147..159);
         $text =~ s/[$bad]//gs;
   }
   # </del_or_correct>

      $text =~ s,&,&amp;,gs;  #&
      $text =~ s,",&quot;,gs; #"
   return $text;
}

sub info {
   # Instead of direct accessing to object tables, use 
   # This method.
   my $self = shift;
   return(
          songs   => $self->{TOTAL_SONGS},
          files   => $self->{TOTAL_FILES},
          ttime   => $self->{TOTAL_TIME}    ? $self->seconds($self->{TOTAL_TIME}) 
                                            : 'unknown',
          average => $self->{AVERAGE_TIME} || 'unknown',
          drive   => $self->{DRIVE},
   );
}

sub read_dir {
   # Private function.
   # Do NOT call this sub from your program!

   # Read a directory containing m3u files. 
   my $self = shift;
   my $path = $self->{path};
   my @list;
   opendir (DIRECTORY, $path) or $self->error("I can not open directory '$path' for reading: $!");
   my @dir = readdir(DIRECTORY);
   closedir(DIRECTORY);

   foreach (@dir) {
      next if     /^(?:\.|\.\.)$/;
      next unless /\.m3u$/i;
      push @list, File::Spec->catfile($path,$_);
   }
#   File::Find::find(sub {return unless /\.m3u$/i; push @list, File::Spec->catfile($path,$_)}, $path);
   return(sort @list);
}

sub seconds {
   # Format seconds if wanted.
   my $self = shift;
   my $all  = shift || 1;
   return($all) unless( $self->{seconds} eq 'format' );
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

sub Dump {
# Dump the structure of a variable. $self->{M3U} for example...
# You must specify a file to write the Dump into it.
   require Data::Dumper;
   my  $self  = shift;
   my  $file  = shift;
   my  $thing = shift;
   ref($thing) eq 'ARRAY' or $self->error("Structure passed to Dump() must be an arrayref!");
   my $fh     = IO::File->new;
      $fh->open("> $file") or $self->error("I could't open dump '$file' for writing: $!");
   my $dump   = Data::Dumper->Dump($thing);
   print $fh $dump;
   $fh->close;
}

sub song_name {
# You can do this yourself, but this is a shortcut.
# If ID3 Name is empty, returns the file name, 
# without path info and .mp3 extension.

# NOT documented, so this can be deleted in the future.

   my $self = shift;
   my $song = shift;
   if($song->[0]) {
      return $song->[0];
   } else {
      if ($song->[2]) {
         my $j = (split /\\/, $song->[2])[-1] || $song->[2];
            $j = (split /\.mp3$/i, $j   )[ 0] || $j;
         return $j;
      } else {
         return '';
      }
   }
}

sub validate {
   # Private function.
   # Do NOT call this sub from your program!

   my $self   = shift;
   my $sub    = shift;
   my %known  = map {$_ => 1} @{+shift};
   my %passed = map {$_ => 1} @{+shift};
   foreach (keys %passed) {
      $self->error("Validate: Unknown parameter '$_' passed to $sub()!") unless(exists $known{$_});
   }
}

sub error {
   # Private function.
   # Do NOT call this sub from your program!

   my  $self = shift;
   my  $mes  = "@_";
       $self->{ERROR} = $mes if ref $self;
   die $mes;
}

sub html {
   # You can re-define this sub from your package if you want.
   my $self = shift;
   my $type = shift;
   my(%opt,$time,$file);
       %opt    = @_ if(@_);
   if (%opt) {
      $time    = $opt{ttime} ? $self->seconds($opt{ttime}) : undef;
      if ($time) {
         my  @time = split /:/,$time;
         if ($#time > 1) {
            $time = qq~
            <span class="ts"  > $time[0] </span>
            <span class="info"> hours    </span>
            <span class="ts"  > $time[1] </span>
            <span class="info"> minutes  </span>
            <span class="ts"  > $time[2] </span>
            <span class="info"> seconds. </span>~;
         } else {
            $time = qq~
            <span class="ts"  > $time[0] </span>
            <span class="info"> minutes  </span>
            <span class="ts"  > $time[1] </span>
            <span class="info"> seconds. </span>~;
         }
      } else {
         $time = qq~<span class="ts"><i>Unknown</i></span><span class="info">.</span>~;
      }
   }

   unless($self->{AVERAGE_TIME}) {
      $self->{AVERAGE_TIME} = '<i>Unknown</i>';
   }

   if ($type eq 'start') {
   my $pls = ($self->{TOTAL_FILES} > 1) ? "Playlists and Files" : "Playlist files";
# Based on WinAmp' s HTML List:
return <<HTML_START;
<html>
 <head>
   <title>MP3::M3U::Parser Generated PlayList</title>
   <style type="text/css">
<!--
  BODY { background   : #000040; }
.para1 { margin-top   : -42px;
         margin-left  : 350px;
         margin-right : 10px;
         font-family  : "font2, Arial";
         font-size    : 30px; line-height: 35px;
         text-align   : left;
         color        : #E1E1E1;
         }
.para2 { margin-top   : 15px;
         margin-left  : 15px;
         margin-right : 50px;
         font-family  : "font1, Arial Black";
         font-size    : 50px;
         line-height  : 40px;
         text-align   : left;
         color        : #004080;
         }
td { font-family : "Arial";
     color       : "#FFFFFF";
     font-size   : 13px;
     }
.t { font-family : "Arial";
     color       : "#FFBF00";
     font-size   : 13px;
     }
.ts {font-family : "Arial";
     color       : "#FFBF00";
     font-size   : 10px;
     }
.s { font-family : "Arial";
     color       : "#FFFFFF";
     font-size   : 13px;
     }
.info {
     font-family : "Arial";
     color       : "#409FFF";
     font-size   : 10px;
      }
.infobig {
     font-family : "Arial";
     color       : "#FFBF00";
     font-size   : 15px;
      }
-->
   </style>
 </head>
<body BGCOLOR="#000080" topmargin="0" leftmargin="0" text="#FFFFFF">
 <div align="center">
  <div CLASS="para2" align="center"><p>MP3::M3U::Parser</p></div>
  <div CLASS="para1" align="center"><p>playlist</p></div>
 </div>

<hr align="left" width="90%" noshade size="1" color="#FFBF00">
 <div align="right">
  <table border="0" cellspacing="0" cellpadding="0" width="98%">
   <tr><td>
    <span class="ts">$opt{songs}</span> <span class="info"> tracks and 
    <span class="ts">$opt{total}</span> CDs in playlist, 
      average track length: </span> 
      <span class="ts">$self->{AVERAGE_TIME}</span><span class="info">.</span>
     <br>
    <span class="info">Playlist length: </span> 
     $time
     <br>
    <span class="info">Right-click <a href="file://$opt{file}">here</a>
      to save this HTML file.</span>
    </td>
   </tr>
 </table>
</div>
<blockquote>
<p><span class="infobig"><big>$pls:</big></span></p>

<table border="0" cellspacing="1" cellpadding="2">

HTML_START

   } elsif ($type eq 'end') {
      return <<HTML_END;
  </table>
</blockquote>
<hr align="left" width="90%" noshade size="1" color="#FFBF00">
<span class="s">This HTML File is based on 
<a href="http://www.winamp.com">WinAmp</a>'s HTML List.</span>
</body>
</html>
HTML_END

   }
   return;
}

sub AUTOLOAD {
   my $self = shift;
   my $name = $AUTOLOAD;
      $name =~ s/.*://;
   $self->error("There is no method called '$name'!");
}

sub DESTROY {
   my $self = shift;
#   delete $self->{$_} foreach keys %$self;
}

1;
__END__;

=head1 NAME

MP3::M3U::Parser - Perl extension for parsing mp3 lists.

=head1 SYNOPSIS

   use MP3::M3U::Parser;
   my $parser = MP3::M3U::Parser->new(-type    => 'dir',
                                      -path    => '/directory/containing/m3u_files',
                                      -seconds => 'format');

   my %results = $parser->parse;
   my %info    = $parser->info;
   my @lists   = keys %results;

   $parser->export(-format   => 'xml',
                   -file     => "/path/mp3.xml",
                   -encoding => 'ISO-8859-9');

   $parser->export(-format   => 'html',
                   -file     => "/path/mp3.html",
                   -drives   => 'off');

=head1 DESCRIPTION

B<MP3::M3U::Parser> is a parser for M3U mp3 song lists. It also parses 
the EXTINF lines (which contains id3 song name and time) if possible. 
You can get a parsed object or specify a format and export the parsed 
data to it. The format can be B<xml> or B<html>.

=head2 Methods

=over 8

=item B<new()>

The object constructor. Takes several arguments like:

=over 4

=item C<-type>

Sets the parse type. It's value can be C<dir> or C<file>. If you select 
C<file>, only the file specified will be parsed. If you set it to C<dir>, 
Then, you must set L<path|/-path> to a directory that contains m3u files.

If you don't set this parameter, it will take the default value C<file>.

=item C<-path>

Set this to the directory that holds one or more m3u files. Can NOT be blank. 
You must set this to a existing directory. Use "C</>" as the directory 
seperator. Also do NOT add a trailing slash:

   -path => "/my/path/", # WRONG
   -path => "/my/path",  # TRUE

Note that, *ONLY* the path you've specified will be searched. Any sub 
directories it I<may> contain will not be searched.

=item C<-file>

If you set L<type|/-type> to C<file>, then you must set this to an existing file. 
Don't set it to a full path. Only use the name of the file, because you 
specify the path with L<path|/-path>:

   -file => "/my/path/mp3.m3u", # WRONG
   -file => "mp3.m3u",          # TRUE

=item C<-seconds>

Format the seconds returned from parsed file? if you set this to the value 
C<format>, it will convert the seconds to a format like C<MM:SS> or C<H:MM:SS>.
Else: you get the time in seconds like; I<256> (if formatted: I<04:15>).

=item C<-search>

If you don't want to get a list of every song in the m3u list, but want to get 
a specific group's/singer's songs from the list, set this to the string you want 
to search. 

Note that, the module will do a *very* basic case-insensitive search. It does 
dot accept multiple words (if you pass a string like "michael beat it", it will 
not search every word seperated by space, it will search the string "michael beat it" 
and probably does not return any results -- it will not match 
"michael jackson - beat it"), it does not have a boolean search support, etc. If you 
want to do something more complex, get the parsed tree and use it in your own 
search function.

=item C<-parse_path>

The module assumes that all of the songs in your M3U lists are (or were: 
the module does not check the existence of them) on the same drive. And it 
builds a seperate table for drive names like:

   DRIVE => {
             FIRST_LIST => 'G:',
             # so on ...
             }

And removes that drive letter (if there is a drive letter) from the real file 
path. If there is no drive letter, then the drive value is 'CDROM:'.

So, if you have a mixed list like:

   G:\a.mp3
   F:\b.mp3
   Z:\xyz.mp3

set this parameter to 'C<asis>' to not to remove the drive letter from the real 
path. Also, you "must" ignore the DRIVE table contents which will still contain 
a possibly wrong value; export() does take the drive letters from the DRIVE table. 
So, you can not use the drive area in the exported xml (for example).

=back

=item B<parse()>

Normally it does not take any arguments. Just call it like:

   $parser->parse;

But, if you want to just parse a file or list of files (means you don't need an 
object) and export the parsed data to a xml or html file, you must call this 
method with a true value.

   MP3::M3U::Parser->new(ARGS)->parser(1)->export(ARGS);

See the related example below in the B<EXAMPLES> section.

If you call this method without any arguments, it will return the parsed data 
as a hash or hash reference:

   my $hash = $parser->parse;

or

   my %hash = $parser->parse;

=item B<info()>

You must call this after calling L<parse|/parse()>. It returns an info hash about 
the parsed data.

   my %info = $parser->info;

The keys of the C<%info> hash are:

   songs   => Total number of songs
   files   => Total number of lists parsed
   ttime   => Total time of the songs 
   average => Average time of the songs
   drive   => Drive manes for parsed lists

Note that the 'drive' key is a hash ref, while others are strings. If you 
have parsed a M3U list named "mp3_01.m3u" and want to learn the drive letter 
of it, call it like this: 

   printf "Drive is %s\n", $info{drive}->{'mp3_01'};

But, maybe you do not want to use the C<$info{drive}> table; see L<parse_path|/-parse_path> 
option in L<new|/new()>.

=item B<export()>

Exports the parsed data to a format. The format can be C<xml> or C<html>. 
The HTML File' s style is based on the popular mp3 player B<WinAmp>' s 
HTML List file. XML formatting (well... escaping) is experimental. Takes 
some arguments:

=over 4

=item C<-file>

The full path to the file you want to write the resulting data. Can NOT be blank.

=item C<-format>

Can be C<xml> or C<html>. Default is C<html>.

=item C<-encoding>

The exported C<xml> file's encoding. Default is B<ISO-8859-1>. 
See L<http://www.iana.org/assignments/character-sets> for a list.

=item C<-drives>

Only required for the html format. If set to C<off>, you will not 
see the drive information in the resulting html file. Default is 
C<on>. Also see L<parse_path|/-parse_path> option in L<new|/new()>.

=back

=item B<Dump()>

Dumps the data structure to a text file. Call this with a data structure 
and full path of the text file you want to save:

   $parser->Dump([%results],"/my/dump/file.txt");

First argument must be an arrayref. Uses the standard Data::Dumper module.

=back

=head2 Error handling

Note that, if there is an error, the module will die with that error. So, 
using C<eval> for all method calls can be helpful if you don't want to die:

   sub my_sub {
      # do some initial stuff ...
      my %results;
      eval { %results = $parser->parse };
      if($@) {
         warn "There was an error: $parser->{ERROR}";
         return;
      } else {
         # do something with %results ...
      }
      # do something or not ...
   }

As you can see, if there is an error, you can catch this with C<eval> and 
access the error message with the special object table called C<ERROR>.

=head1 EXAMPLES

=over 4

=item B<How can I parse an M3U List?>

Solution:

   #!/usr/bin/perl -w
   use strict;
   use MP3::M3U::Parser;
   my $parser = MP3::M3U::Parser->new(-type    => 'file',
                                      -path    => '/my/path',
                                      -file    => 'mp3.m3u',
                                      -seconds => 'format');
   my %results  = $parser->parse;

=item B<How can I parse a list of files?>

Solution: Put all your M3U lists into a directory and show this directory 
to the module with the "-path" parameter:

   #!/usr/bin/perl -w
   use strict;
   use MP3::M3U::Parser;
   my $parser = MP3::M3U::Parser->new(-type    => 'dir',
                                      -path    => '/my/path',
                                      -seconds => 'format');
   my %results  = $parser->parse;
   my @lists    = keys %results;
   my %info     = $parser->info;

   printf "I have parsed these lists: %s\n",join(", ",@lists);

   printf "There are %s songs in %s lists. Total time of the songs is %s. Average time is %s.",
          $info{songs},
          $info{files},
          $info{ttime},
          $info{average};

=item B<How can I get the names of the parsed lists?>

Solution: As you can see in the above examples:

      my @lists = keys %results;

Note that the C<.m3u> extension is removed from the file names when parsing.

=item B<How can I "just" export the parsed tree to a format?>

Solution (convert to xml and save):

   #!/usr/bin/perl -w
   use MP3::M3U::Parser;
   MP3::M3U::Parser->new(-type    => 'dir',
                         -path    => '/my/path',
                         -seconds => 'format',
                         )
                         ->parse(1)
                         ->export(-format   => 'xml',
                                  -file     => "/my/export/path/mp3.xml",
                                  -encoding => 'ISO-8859-9');
   print "Done!\n";

If you dont need any objects, just call new() followed by parse() followed by 
export(). But B<DON'T FORGET> to pass a true value to parse:

	parse(1)

If you don't do this, parse() method will not pass an object to export() and 
you'll get a fatal error. If you want to get the parsed results, you must call 
parse() without any arguments like in the examples above.

=item B<How can I do a basic case-insensitive search?>

Solution: Just pass the L<search|/-search> parameter with the string you want to search:

   my $parser = MP3::M3U::Parser->new(-type    => 'dir',
                                      -path    => '/my/path',
                                      -seconds => 'format',
                                      -search  => 'KLF', # Search KLF songs
                                      );

=item B<How can I change the HTML List layout?>

Solution: Just re-define the sub 'C<MP3::M3U::Parser::html>' in your program.
To do this, first copy the sub html

   sub html {
   # subroutine contents
   }

from this module into your program, but do NOT forget to rename it to:

   sub MP3::M3U::Parser::html {
   # subroutine contents
   }

if you don't name it like this, the module will not see your changed sub, 
because it belongs to your name space not this module's. Then change what 
you want. I don't plan to add a template option, because I find it unnecessary. 
But if you want to do such a thing, this is the solution.

=back

=head1 NOTES

This module is based on a code I'm using for my own mp3 archive. There is another 
M3U parser in CPAN, but it does not have the functionality I want and it skips 
the EXTINFO lines. So, I wrote this module. This module does not check the 
existence of the mp3 files, it just parses the playlist entries.

Tested under MS Win98/2000 (Active Perl 5.8.0 Build 804) and RH Linux 8.0 (Perl 5.8.0).

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


=head2 TODO

=over 4

=item *

Better xml transformation.

=item * 

Add C<flock()> (maybe).

=item *

Split big exported(HTML) into separate files (maybe).

=item * 

Multiple L<file|/-file> parameters (maybe).

=back

=head1 BUGS

I've tested this module a lot, but if you find any bugs or missed parts, 
you can contact me.

=head1 SEE ALSO

L<MP3::M3U>.

=head1 AUTHOR

Burak Gürsoy, E<lt>burakE<64>cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 Burak Gürsoy. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
