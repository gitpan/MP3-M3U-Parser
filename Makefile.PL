use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'MP3::M3U::Parser',
    'VERSION_FROM'	=> 'Parser.pm',
    'PREREQ_PM'		=> {
                             File::Spec   => 0.83,
                             IO::File     => 1.09,
                             Data::Dumper => 2.12,
                            },
    ($] >= 5.005 ? 
      (AUTHOR   => 'Burak Gürsoy <burak@cpan.org>',
       ABSTRACT => 'Perl extension for parsing mp3 lists') : ()),
);