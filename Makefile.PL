#!perl
use ExtUtils::MakeMaker;

WriteMakefile(
   NAME         => 'MP3::M3U::Parser',
   VERSION_FROM => 'lib/MP3/M3U/Parser.pm',
   PREREQ_PM    => {
      'File::Spec'     => 0,
      'IO::File'       => 0,
      'Cwd'            => 0,
      'Text::Template' => 0,
      'Test::More'     => '0.40',
   },
   ($] >= 5.005 ? (
   AUTHOR   => 'Burak Gursoy <burak@cpan.org>',
   ABSTRACT => 'MP3 playlist parser',
   ) : ()),
   PL_FILES     => {},
);
