use strict;
use vars qw( $VERSION );
use warnings;
use File::Find;
use File::Spec;
use File::Path;
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

$VERSION = '0.40';

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
   $self->_change_versions( \@modules );
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

1;
