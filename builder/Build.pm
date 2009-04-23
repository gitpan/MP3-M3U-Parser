package Build;
use strict;
use vars qw( $VERSION );
use warnings;

$VERSION = '0.50';

use File::Find;
use File::Spec;
use File::Path;
use Build::Spec;
use base qw( Module::Build );
use constant RE_VERSION_LINE => qr{
   \A \$VERSION \s+ = \s+ ["'] (.+?) ['"] ; (.+?) \z
}xms;
use constant RE_POD_LINE => qr{
\A =head1 \s+ DESCRIPTION \s+ \z
}xms;
use constant VTEMP  => q{$VERSION = '%s';};
use constant MONTHS => qw(
   January February March     April   May      June
   July    August   September October November December
);
use constant MONOLITH_TEST_FAIL =>
   "\nFAILED! Building the monolithic version failed during unit testing\n\n";

use constant NO_INDEX => qw( monolithic_version builder t );
use constant DEFAULTS => qw(
   license          perl
   create_license   1
   sign             0
);

__PACKAGE__->add_property( build_monolith      => 0  );
__PACKAGE__->add_property( change_versions     => 0  );
__PACKAGE__->add_property( vanilla_makefile_pl => 1  );
__PACKAGE__->add_property( monolith_add_to_top => [] );

sub new {
   my $class = shift;
   my %opt   = spec;
   my %def   = DEFAULTS;
   foreach my $key ( keys %def ) {
      $opt{ $key } = $def{ $key } if ! defined $opt{ $key };
   }
   $opt{no_index}            ||= {};
   $opt{no_index}{directory} ||= [];
   push @{ $opt{no_index}{directory} }, NO_INDEX;
   return $class->SUPER::new( %opt );
}

sub create_build_script {
   my $self = shift;
   $self->_add_vanilla_makefile_pl if $self->vanilla_makefile_pl;
   return $self->SUPER::create_build_script( @_ );
}

sub ACTION_dist {
   my $self = shift;
   warn  sprintf(
            "RUNNING 'dist' Action from subclass %s v%s\n",
            ref($self),
            $VERSION
         );
   my @modules;
   find {
      wanted => sub {
         my $file = $_;
         return if $file !~ m{ \. pm \z }xms;
         $file = File::Spec->catfile( $file );
         push @modules, $file;
         warn "FOUND Module: $file\n";
      },
      no_chdir => 1,
   }, "lib";
   $self->_change_versions( \@modules ) if $self->change_versions;
   $self->_build_monolith(  \@modules ) if $self->build_monolith;
   $self->SUPER::ACTION_dist( @_ );
}

sub _change_versions {
   my $self  = shift;
   my $files = shift;
   my $dver  = $self->dist_version;

   my($mday, $mon, $year) = (localtime time)[3, 4, 5];
   my $date = join ' ', $mday, [MONTHS]->[$mon], $year + 1900;

   warn "CHANGING VERSIONS\n";
   warn "\tDISTRO Version: $dver\n";

   foreach my $mod ( @{ $files } ) {
      warn "\tPROCESSING $mod\n";
      my $new = $mod . '.new';
      open my $RO_FH, '<:raw', $mod or die "Can not open file($mod): $!";
      open my $W_FH , '>:raw', $new or die "Can not open file($new): $!";

      CHANGE_VERSION: while ( my $line = readline $RO_FH ) {
         if ( $line =~ RE_VERSION_LINE ) {
            my $oldv      = $1;
            my $remainder = $2;
            warn "\tCHANGED Version from $oldv to $dver\n";
            printf $W_FH VTEMP . $remainder, $dver;
            last CHANGE_VERSION;
         }
         print $W_FH $line;
      }

      my $ns  = $mod;
         $ns  =~ s{ [\\/]     }{::}xmsg;
         $ns  =~ s{ \A lib :: }{}xms;
         $ns  =~ s{ \. pm \z  }{}xms;
      my $pod = "\nThis document describes version C<$dver> of C<$ns>\n"
              . "released on C<$date>.\n"
              ;

      if ( $dver =~ m{[_]}xms ) {
         $pod .= "\nB<WARNING>: This version of the module is part of a\n"
              .  "developer (beta) release of the distribution and it is\n"
              .  "not suitable for production use.\n";
      }

      CHANGE_POD: while ( my $line = readline $RO_FH ) {
         print $W_FH $line;
         print $W_FH $pod if $line =~ RE_POD_LINE;
      }

      close $RO_FH or die "Can not close file($mod): $!";
      close $W_FH  or die "Can not close file($new): $!";

      unlink($mod) || die "Can not remove original module($mod): $!";
      rename( $new, $mod ) || die "Can not rename( $new, $mod ): $!";
      warn "\tRENAME Successful!\n";
   }

   return;
}

sub _build_monolith {
   my $self   = shift;
   my $files  = shift;
   my @mono_dir = ( monolithic_version => split /::/, $self->module_name );
   my $mono_file = pop(@mono_dir) . '.pm';
   my $dir    = File::Spec->catdir( @mono_dir );
   my $mono   = File::Spec->catfile( $dir, $mono_file );
   my $buffer = File::Spec->catfile( $dir, 'buffer.txt' );
   my $readme = File::Spec->catfile( qw( monolithic_version README ) );
   my $copy   = $mono . '.tmp';

   mkpath $dir;

   warn "STARTING TO BUILD MONOLITH\n";
   open my $MONO  , '>:raw', $mono   or die "Can not open file($mono): $!";
   open my $BUFFER, '>:raw', $buffer or die "Can not open file($buffer): $!";

   my %add_pod;
   my $POD = '';

   my @files;
   my $c;
   foreach my $f ( @{ $files }) {
      my(undef, undef, $base) = File::Spec->splitpath($f);
      if ( $base eq 'Constants.pm' ) {
         $c = $f;
         next;
      }
      push @files, $f;
   }
   push @files, $c;

   MONO_FILES: foreach my $mod ( reverse @files ) {
      my(undef, undef, $base) = File::Spec->splitpath($mod);
      warn "\tMERGE $mod\n";
      my $is_eof = 0;
      my $is_pre = $self->_monolith_add_to_top( $base );
      open my $RO_FH, '<:raw', $mod or die "Can not open file($mod): $!";
      MONO_MERGE: while ( my $line = readline $RO_FH ) {
         #print $MONO "{\n" if ! $curly_top{ $mod }++;
         my $chomped  = $line;
         chomp $chomped;
         $is_eof++ if $chomped eq '1;';
         my $no_pod   = $is_eof && $base ne $mono_file;
         $no_pod ? last MONO_MERGE
                 : do {
                     warn "\tADD POD FROM $mod\n"
                        if $is_eof && ! $add_pod{ $mod }++;
                  };
         $is_eof ? do { $POD .= $line; }
                : do {
                     print { $is_pre ? $BUFFER : $MONO } $line;
                  };
      }
      close $RO_FH;
      #print $MONO "}\n";
   }
   close $MONO;
   close $BUFFER;

   ADD_PRE: {
      require File::Copy;
      File::Copy::copy( $mono, $copy ) or die "Copy failed: $!";
      my @inc_files = map {
                        my $f = $_;
                        $f =~ s{    \\   }{/}xmsg;
                        $f =~ s{ \A lib/ }{}xms;
                        $f;
                     } @{ $files };

      my @packages = map {
                        my $m = $_;
                        $m =~ s{ [.]pm \z }{}xms;
                        $m =~ s{  /       }{::}xmsg;
                        $m;
                     } @inc_files;

      open my $W,    '>:raw', $mono   or die "Can not open file($mono): $!";
      open my $TOP,  '<:raw', $buffer or die "Can not open file($buffer): $!";
      open my $COPY, '<:raw', $copy   or die "Can not open file($copy): $!";

      printf $W q/BEGIN { $INC{$_} = 1 for qw(%s); }/, join(' ', @inc_files);
      print  $W "\n";

      foreach my $name ( @packages ) {
         print $W qq/package $name;\nsub ________monolith {}\n/;
      }

      while ( my $line = readline $TOP ) {
         print $W $line;
      }

      while ( my $line = readline $COPY ) {
         print $W $line;
      }

      close  $W;
      close  $COPY;
      close  $TOP;
   }

   if ( $POD ) {
      open my $MONOX, '>>:raw', $mono or die "Can not open file($mono): $!";
      foreach my $line ( split /\n/, $POD ) {
         print $MONOX $line, "\n";
         print $MONOX $self->_monolith_pod_warning if "$line\n" =~ RE_POD_LINE;
      }
      close $MONOX;
   }

   unlink $buffer or die "Can not delete $buffer $!";
   unlink $copy   or die "Can not delete $copy $!";

   print "\t";
   system( $^X, '-wc', $mono ) && die "$mono does not compile!\n";

   PROVE: {
      warn "\tTESTING MONOLITH\n";
      local $ENV{AUTHOR_TESTING_MONOLITH_BUILD} = 1;
      my @output = qx(prove -Isingle);
      print "\t$_" for @output;
      chomp(my $result = pop @output);
      die MONOLITH_TEST_FAIL if $result ne 'Result: PASS';
   }

   warn "\tADD README\n";
   $self->_write_file('>', $readme, $self->_monolith_readme);

   warn "\tADD TO MANIFEST\n";
   (my $monof   = $mono  ) =~ s{\\}{/}xmsg;
   (my $readmef = $readme) =~ s{\\}{/}xmsg;
   my $name = $self->module_name;
   $self->_write_file( '>>', 'MANIFEST',
      "$readmef\n",
      "$monof\tThe monolithic version of $name",
      " to ease dropping into web servers. Generated automatically.\n"
   );
}

sub _write_file {
   my $self = shift;
   my $mode = shift;
   my $file = shift;
   my @data = @_;
   $mode = $mode . ':raw';
   open my $FH, $mode, $file or die "Can not open file($file): $!";
   foreach my $content ( @data ) {
      print $FH $content;
   }
   close $FH;
}

sub _monolith_add_to_top {
   my $self = shift;
   my $base = shift;
   my $list = $self->monolith_add_to_top || die "monolith_add_to_top not set";
   die "monolith_add_to_top is not an ARRAY" if ref($list) ne 'ARRAY';
   foreach my $test ( @{ $list } ) {
      return 1 if $test eq $base;
   }
   return 0;
}

sub _monolith_readme {
   my $self = shift;
   my $pod  = $self->_monolith_pod_warning;
   $pod =~ s{B<(.+?)>}{$1}xmsg;
   return $pod;
}

sub _monolith_pod_warning {
   my $self = shift;
   my $name = $self->module_name;
   return <<"MONOLITH_POD_WARNING";

B<WARNING>! This is the monolithic version of $name
generated with an automatic build tool. If you experience problems
with this version, please install and use the supported standard
version. This version is B<NOT SUPPORTED>.
MONOLITH_POD_WARNING
}

sub _add_vanilla_makefile_pl {
   my $self = shift;
   my $file = 'Makefile.PL';
   return if -e $file; # do not overwrite
   $self->_write_file(  '>', $file, $self->_vanilla_makefile_pl );
   $self->_write_file( '>>', 'MANIFEST', "$file\tGenerated automatically\n");
   warn "ADDED VANILLA $file\n";
   return;
}

sub _vanilla_makefile_pl {
   <<'VANILLA_MAKEFILE_PL';
#!/usr/bin/env perl
use strict;
use ExtUtils::MakeMaker;
use lib qw( builder );
use Build::Spec qw( mm_spec );

my %spec = mm_spec;

WriteMakefile(
    NAME         => $spec{module_name},
    VERSION_FROM => $spec{VERSION_FROM},
    PREREQ_PM    => $spec{PREREQ_PM},
    PL_FILES     => {},
    ($] >= 5.005 ? (
    AUTHOR       => $spec{dist_author},
    ABSTRACT     => $spec{ABSTRACT},
    ) : ()),
);
VANILLA_MAKEFILE_PL
}

1;

__END__
