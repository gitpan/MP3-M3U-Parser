#!/usr/bin/env perl -w
use strict;
use vars qw( @LIST );
use Test::More qw( no_plan );
use File::Find qw( find );
use Data::Dumper;

BEGIN {
   find {
      no_chdir => 1,
      wanted   => sub {
         return if $File::Find::name !~ m{ \.pm \z }xmsi;
         my $mod = $File::Find::name;
         $mod =~ s{ [\\/] ? lib [\\/] }{}xms;
         $mod =~ s{ [\\/] }{::}xmsg;
         $mod =~ s{ \. pm \z }{}xmsi;
         push @LIST, $mod;
         use_ok( $mod );
      }
   }, "lib";
}

my @NONE;
my %CHECK;

foreach my $mod ( @LIST ) {
   my $v = $mod->VERSION;
   if ( not defined $v ) {
      push @NONE, $mod;
   }
   else {
      $CHECK{ $v } ||= [];
      push @{ $CHECK{ $v } }, $mod;
   }
   #diag "%s v%s\n", $mod, $v;
}

if ( @NONE ) {
   diag "NO VERSION: ", join(", ", @NONE), "\n";
} else {
   ok( 1, "All modules have version number");
}

my $total = () = keys %CHECK;

if ( $total > 1 ) {
   my $m = Data::Dumper->new( [ \%CHECK ], [ 'VERSION_MISMATCH' ] );
   diag($m->Dump);
}
else {
   ok( 1, "All module versions are identical\n");
}
