package MP3::M3U::Parser::Constants;
use strict;
use warnings;
use vars qw( $VERSION @EXPORT @EXPORT_OK %EXPORT_TAGS $OID );

$VERSION = '2.31';

# Data table key map
use constant PATH    => $OID++;
use constant ID3     => $OID++;
use constant LEN     => $OID++;
use constant ARTIST  => $OID++;
use constant SONG    => $OID++;
use constant MAXDATA => $OID; # Maximum index number of the data table

use constant EMPTY_STRING          => q{};
use constant MINIMUM_SEARCH_LENGTH =>   3;

use constant MINUTE_MULTIPLIER => 60;
use constant DEFAULT_DRIVE     => 'CDROM:';
use constant RE_M3U_HEADER     => qr{ \A \#EXTM3U }xms;
use constant RE_INF_HEADER     => qr{    \#EXTINF }xmsi;
use constant RE_DRIVE_PATH     => qr{ \A \w:[\\/]      (.+?) \z }xms; # C:\mp3\Singer - Song.mp3
use constant RE_NORMAL_PATH    => qr{ \A    [\\/]([^\\/].+?) \z }xms; # \mp3\Singer - Song.mp3
use constant RE_PARTIAL_PATH   => qr{ \A               (.+?) \z }xms; # Singer - Song.mp3

use base qw( Exporter );

BEGIN {
    %EXPORT_TAGS = (
        fields => [qw(
                        PATH
                        ID3
                        LEN
                        ARTIST
                        SONG
                        MAXDATA
                    )],
        etc    => [qw(
                        EMPTY_STRING
                        MINIMUM_SEARCH_LENGTH
                        MINUTE_MULTIPLIER
                        DEFAULT_DRIVE
                    )],
        re     => [qw(
                        RE_M3U_HEADER
                        RE_DRIVE_PATH
                        RE_NORMAL_PATH
                        RE_PARTIAL_PATH
                        RE_INF_HEADER
                    )],
    );
    @EXPORT_OK        = map { @{ $EXPORT_TAGS{$_} } } keys %EXPORT_TAGS;
    $EXPORT_TAGS{all} = \@EXPORT_OK;
    @EXPORT           = @EXPORT_OK;
}

1;

__END__

=pod

=encoding utf8

=head1 NAME

MP3::M3U::Parser::Constants - Constants for MP3::M3U::Parser

=head1 SYNOPSIS

Private module.

=head1 DESCRIPTION

This document describes version C<2.31> of C<MP3::M3U::Parser::Constants>
released on C<9 September 2012>.

-

=head1 SEE ALSO

L<MP3::M3U::Parser>.

=head1 AUTHOR

Burak Gursoy <burak@cpan.org>.

=head1 COPYRIGHT

Copyright 2003 - 2012 Burak Gursoy. All rights reserved.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.12.3 or,
at your option, any later version of Perl 5 you may have available.
=cut
