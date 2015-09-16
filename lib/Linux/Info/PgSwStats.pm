package Linux::Info::PgSwStats;

use strict;
use warnings;
use Carp qw(croak);
use Time::HiRes;

=head1 NAME

Linux::Info::PgSwStats - Collect linux paging and swapping statistics.

=head1 SYNOPSIS

    use Linux::Info::PgSwStats;

    my $lxs = Linux::Info::PgSwStats->new;
    $lxs->init;
    sleep 1;
    my $stat = $lxs->get;

Or

    my $lxs = Linux::Info::PgSwStats->new(initfile => $file);
    $lxs->init;
    my $stat = $lxs->get;

=head1 DESCRIPTION

Linux::Info::PgSwStats gathers paging and swapping statistics from the virtual F</proc> filesystem (procfs).

For more information read the documentation of the front-end module L<Linux::Info>.

=head1 PAGING AND SWAPPING STATISTICS

Generated by F</proc/stat> or F</proc/vmstat>.

    pgpgin      -  Number of pages the system has paged in from disk per second.
    pgpgout     -  Number of pages the system has paged out to disk per second.
    pswpin      -  Number of pages the system has swapped in from disk per second.
    pswpout     -  Number of pages the system has swapped out to disk per second.

    The following statistics are only available by kernels from 2.6.

    pgfault     -  Number of page faults the system has made per second (minor + major).
    pgmajfault  -  Number of major faults per second the system required loading a memory page from disk.

=head1 METHODS

=head2 new()

Call C<new()> to create a new object.

    my $lxs = Linux::Info::PgSwStats->new;

Maybe you want to store/load the initial statistics to/from a file:

    my $lxs = Linux::Info::PgSwStats->new(initfile => '/tmp/pgswstats.yml');

If you set C<initfile> it's not necessary to call sleep before C<get()>.

It's also possible to set the path to the proc filesystem.

     Linux::Info::PgSwStats->new(
        files => {
            # This is the default
            path   => '/proc',
            stat   => 'stat',
            vmstat => 'vmstat',
        }
    );

=head2 init()

Call C<init()> to initialize the statistics.

    $lxs->init;

=head2 get()

Call C<get()> to get the statistics. C<get()> returns the statistics as a hash reference.

    my $stat = $lxs->get;

=head2 raw()

Get raw values.

=head1 EXPORTS

Nothing.

=head1 SEE ALSO

=over

=item *

B<proc(5)>

=item *

L<Linux::Info>

=back

=head1 AUTHOR

Alceu Rodrigues de Freitas Junior, E<lt>arfreitas@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2015 of Alceu Rodrigues de Freitas Junior, E<lt>arfreitas@cpan.orgE<gt>

This file is part of Linux Info project.

Linux Info is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Linux Info is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Linux Info.  If not, see <http://www.gnu.org/licenses/>.

=cut

sub new {
    my $class = shift;
    my $opts = ref( $_[0] ) ? shift : {@_};

    my %self = (
        files => {
            path   => '/proc',
            stat   => 'stat',
            vmstat => 'vmstat',
        }
    );

    if ( defined $opts->{initfile} ) {
        require YAML::Syck;
        $self{initfile} = $opts->{initfile};
    }

    foreach my $file ( keys %{ $opts->{files} } ) {
        $self{files}{$file} = $opts->{files}->{$file};
    }

    return bless \%self, $class;
}

sub init {
    my $self = shift;

    if ( $self->{initfile} && -r $self->{initfile} ) {
        $self->{init} = YAML::Syck::LoadFile( $self->{initfile} );
        $self->{time} = delete $self->{init}->{time};
    }
    else {
        $self->{time} = Time::HiRes::gettimeofday();
        $self->{init} = $self->_load;
    }
}

sub get {
    my $self  = shift;
    my $class = ref $self;

    if ( !exists $self->{init} ) {
        croak "$class: there are no initial statistics defined";
    }

    $self->{stats} = $self->_load;
    $self->_deltas;

    if ( $self->{initfile} ) {
        $self->{init}->{time} = $self->{time};
        YAML::Syck::DumpFile( $self->{initfile}, $self->{init} );
    }

    return $self->{stats};
}

sub raw {
    my $self = shift;
    my $stat = $self->_load;

    return $stat;
}

#
# private stuff
#

sub _load {
    my $self  = shift;
    my $class = ref $self;
    my $file  = $self->{files};
    my %stats = ();

    my $filename =
      $file->{path} ? "$file->{path}/$file->{stat}" : $file->{stat};
    open my $fh, '<', $filename
      or croak "$class: unable to open $filename ($!)";

    while ( my $line = <$fh> ) {
        if ( $line =~ /^page\s+(\d+)\s+(\d+)$/ ) {
            @stats{qw(pgpgin pgpgout)} = ( $1, $2 );
        }
        elsif ( $line =~ /^swap\s+(\d+)\s+(\d+)$/ ) {
            @stats{qw(pswpin pswpout)} = ( $1, $2 );
        }
    }

    close($fh);

    # if paging and swapping are not found in /proc/stat
    # then let's try a look into /proc/vmstat (since 2.6)

    if ( !defined $stats{pswpout} ) {
        my $filename =
          $file->{path} ? "$file->{path}/$file->{vmstat}" : $file->{vmstat};
        open my $fh, '<', $filename
          or croak "$class: unable to open $filename ($!)";
        while ( my $line = <$fh> ) {
            next
              unless $line =~
              /^(pgpgin|pgpgout|pswpin|pswpout|pgfault|pgmajfault)\s+(\d+)/;
            $stats{$1} = $2;
        }
        close($fh);
    }

    return \%stats;
}

sub _deltas {
    my $self  = shift;
    my $class = ref $self;
    my $istat = $self->{init};
    my $lstat = $self->{stats};
    my $time  = Time::HiRes::gettimeofday();
    my $delta = sprintf( '%.2f', $time - $self->{time} );
    $self->{time} = $time;

    while ( my ( $k, $v ) = each %{$lstat} ) {
        if ( !defined $istat->{$k} || !defined $lstat->{$k} ) {
            croak "$class: not defined key found '$k'";
        }

        if ( $v !~ /^\d+\z/ || $istat->{$k} !~ /^\d+\z/ ) {
            croak "$class: invalid value for key '$k'";
        }

        if ( $lstat->{$k} == $istat->{$k} || $istat->{$k} > $lstat->{$k} ) {
            $lstat->{$k} = sprintf( '%.2f', 0 );
        }
        elsif ( $delta > 0 ) {
            $lstat->{$k} =
              sprintf( '%.2f', ( $lstat->{$k} - $istat->{$k} ) / $delta );
        }
        else {
            $lstat->{$k} = sprintf( '%.2f', $lstat->{$k} - $istat->{$k} );
        }

        $istat->{$k} = $v;
    }
}

1;
