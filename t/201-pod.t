#!/usr/bin/env perl -w
use strict;
use Test::More;

my @errors;
eval { require Test::Pod; };
push @errors, "Test::Pod is required for testing POD"   if $@;
eval { require Pod::Simple; };
push @errors, "Pod::Simple is required for testing POD" if $@;

if ( not @errors ) {
   my $tpv = $Test::Pod::VERSION;
   my $psv = $Pod::Simple::VERSION;

   if ( $tpv < 1.26 ) {
      push @errors, "Upgrade Test::Pod to 1.26 to run this test. "
                   ."Detected version is: $tpv";
   }

   if ( $psv < 3.05 ) {
      push @errors, "Upgrade Pod::Simple to 3.05 to run this test. "
                   ."Detected version is: $psv";
   }
}

if ( $] < 5.008 ) {
   # Any older perl does not have Encode.pm. Thus, Pod::Simple
   # can not handle utf8 encoding and it will die, the tests
   # will fail. This skip part, skips an inevitable failure.
   push @errors, "'=encoding utf8' directives in Pods don't work "
                ."with legacy perl.";
}

if ( @errors ) {
   plan skip_all => "Errors detected: @errors";
}
else {
   Test::Pod::all_pod_files_ok();
}
