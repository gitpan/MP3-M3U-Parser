#!/usr/bin/env perl -w
use strict;
use Test;
BEGIN { plan tests => 1 }

my $parser = MyParser->new(-search => 'fred mer');
   $parser->parse('test.m3u');
   $parser->export(-format    => 'html',
                   -file      => "04_sub_search.html",
                   -overwrite => 1);

ok(1);
exit;

package MyParser;
use base qw[MP3::M3U::Parser];

sub _search {
   my $self   = shift;
   my $path   = shift;
   my $id3    = shift;
   my $search = $self->{search_string};
   return(0) unless( $id3 or $path);
   my @search = split /\s{1,}/, $search;
   my %c = (id3 => 0, path => 0);
   foreach my $s (@search) {
      $c{id3 }++ if $id3  =~ /$s/i;
      $c{path}++ if $path =~ /$s/i;
   }
   return 1 if $c{id3} == @search || $c{path} == @search;
   return(0);
}

1;

__END__
