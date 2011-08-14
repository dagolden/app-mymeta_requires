use 5.010;
use strict;
use warnings;

package App::mymeta_requires;
# VERSION

# Dependencies
use autodie 2.00;
use Class::Load qw/try_load_class/;
use CPAN::Meta;
use Log::Dispatchouli;
use Getopt::Lucid ':all';
use Object::Tiny qw/opt logger/;
use Version::Requirements;

my $opt_spec = [
  Param("file|f"),
  Switch("verbose|v"),
  Switch("help|h"),
  Switch("runtime|r")->default(1),
  Switch("configure|c")->default(1),
  Switch("build|b")->default(1),
  Switch("test|t")->default(1),
  Switch("develop|d")->default(0),
  Switch("recommends")->default(1),
  Switch("suggests")->default(1),
];

sub new {
  my $class = shift;
  my $self = bless {}, $class;
  $self->{opt} = Getopt::Lucid->getopt($opt_spec);
  $self->{logger} = Log::Dispatchouli->new({
      ident => 'mymeta-requires',
      to_stderr => 1,
      debug => $self->opt->get_verbose,
      log_pid => 0,
  });
  return $self;
}

sub run {
  my $self = shift;
  $self = $self->new unless ref $self;

  if ( $self->opt->get_help ) {
    require File::Basename;
    require Pod::Usage;
    my $file = File::Basename::basename($0);
    Pod::Usage::pod2usage();
  }

  my $mymeta = $self->load_mymeta
    or $self->logger->log_fatal("Could not load a MYMETA file");
  my $prereqs = $self->merge_prereqs( $mymeta->effective_prereqs );
  my @missing = $self->find_missing( $prereqs );
  say for sort @missing;
  return 0;
}

sub load_mymeta {
  my $self = shift;
  my @candidates = $self->opt->get_file
    ? ($self->opt->get_file)
    : qw/MYMETA.json MYMETA.yml META.json META.yml/;
  for my $f ( @candidates ) {
    next unless -r $f;
    my $mymeta = eval { CPAN::Meta->load_file($f) }
      or $self->logger->log_debug("Error loading '$f': $@");
    if ( $mymeta ) {
      $self->logger->log_debug("Got MYMETA from '$f'");
      return $mymeta;
    }
  }
  return;
}

sub merge_prereqs {
  my ($self, $prereqs) = @_;
  my $merged = Version::Requirements->new;
  for my $phase (qw(configure runtime build test develop)) {
    my $get_p = "get_$phase";
    next unless $self->opt->$get_p;
    # Always get 'requires'
    $merged->add_requirements( $prereqs->requirements_for( $phase, 'requires' ) );
    # Maybe get other types
    for my $extra( qw/recommends suggests/ ) {
      my $get_x = "get_$extra";
      next unless $self->opt->$get_x;
      $merged->add_requirements( $prereqs->requirements_for( $phase, $extra ) );
    }
  }
  return $merged;
}

sub find_missing {
  my ($self, $prereqs) = @_;
  my @missing;
  for my $mod ( $prereqs->required_modules ) {
    if ( try_load_class($mod) ) {
      push @missing, $mod unless $prereqs->accepts_module($mod);
    }
    else {
      push @missing, $mod;
    }
  }
  return @missing;
}

1;

# ABSTRACT: Extract module requirements from MYMETA files

=for Pod::Coverage
find_missing
load_mymeta
logger
merge_prereqs
new
opt
run

=begin wikidoc

= SYNOPSIS

  use App::mymeta_requires;
  exit App::mymeta_requires->run;

= DESCRIPTION

This module contains the guts of the L<mymeta_requires> program.  See
that program for command line usage information.

=end wikidoc

=cut

# vim: ts=2 sts=2 sw=2 et:
