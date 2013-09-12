use v5.10;
use strict;
use warnings;

package Meerkat::Role::Document;
# ABSTRACT: Moose role for object persistence with Meerkat
# VERSION

use Moose::Role 2;
use MooseX::Storage;
use MooseX::Storage::Engine;

use Carp qw/croak/;
use MongoDB::OID;
use Type::Params qw/compile Invocant/;
use Types::Standard qw/slurpy :types/;

use namespace::autoclean;

with Storage;

# pass through OID's without modification as MongoDB will
# consume/provide them; pass through Meerkat::Collection
# as Meerkat will strip/add as necessary
for my $type (qw/MongoDB::OID Meerkat::Collection/) {
    MooseX::Storage::Engine->add_custom_type_handler(
        $type => (
            expand   => sub { shift },
            collapse => sub { shift },
        )
    );
}

has _collection => (
    is       => 'ro',
    isa      => 'Meerkat::Collection',
    required => 1,
);

has _id => (
    is      => 'ro',
    isa     => 'MongoDB::OID',
    default => sub { MongoDB::OID->new },
);

has _removed => (
    is        => 'ro',
    isa       => 'Bool',
    predicate => 'is_removed',
    default   => 0,
);

sub remove {
    state $check = compile(Object);
    my ($self) = $check->(@_);
    return 1 if $self->_removed; # NOP
    return $self->_collection->remove($self);
}

# returns true if synced or false if missing
sub sync {
    state $check = compile(Object);
    my ($self) = $check->(@_);
    return 0 if $self->_removed; # NOP
    return $self->_collection->sync($self);
}

sub update {
    state $check = compile( Object, HashRef );
    my ( $self, $update ) = $check->(@_);
    return if $self->_removed;   # NOP
    return $self->_collection->update( $self, $update );
}

my %update_operators = (
    set    => { op => '$set',      type => 'scalar' },
    inc    => { op => '$inc',      type => 'scalar' },
    push   => { op => '$push',     type => 'array_push' },
    add    => { op => '$addToSet', type => 'array_push' },
    pop    => { op => '$pop',      type => 'array_pop', direction => 1 },
    shift  => { op => '$pop',      type => 'array_pop', direction => -1 },
    remove => { op => '$pullAll',  type => 'array_rm' },
);

# stringify "$field" just in a case someone gave an object
while ( my ( $k, $v ) = each %update_operators ) {
    my $spec = { as => "update_$k" };
    my $op = $v->{op};
    if ( $v->{type} eq 'scalar' ) {
        $spec->{code} = sub {
            state $check = compile( Object, Defined, Defined );
            my ( $self, $field, $value ) = $check->(@_);
            return $self->update( { $op => { "$field" => $value } } );
        };
    }
    elsif ( $v->{type} eq 'array_push' ) {
        $spec->{code} = sub {
            state $check = compile( Object, Defined, slurpy ArrayRef );
            my ( $self, $field, $list ) = $check->(@_);
            if ( @$list == 1 ) {
                return $self->update( { $op => { "$field" => $list->[0] } } );
            }
            else {
                return $self->update( { $op => { "$field" => { '$each' => $list } } } );
            }
        };
    }
    elsif ( $v->{type} eq 'array_pop' ) {
        my $dir = $v->{direction};
        $spec->{code} = sub {
            state $check = compile( Object, Defined );
            my ( $self, $field ) = $check->(@_);
            return $self->update( { $op => { "$field" => $dir } } );
        };
    }
    elsif ( $v->{type} eq 'array_rm' ) {
        $spec->{code} = sub {
            state $check = compile( Object, Defined, slurpy ArrayRef );
            my ( $self, $field, $list ) = $check->(@_);
            return $self->update( { $op => { "$field" => $list } } );
        };
    }

    Sub::Install::install_sub($spec);
}

1;

=for Pod::Coverage method_names_here

=head1 SYNOPSIS

  use Meerkat::Role::Document;

=head1 DESCRIPTION

This module might be cool, but you'd never know it from the lack
of documentation.

=head1 USAGE

Good luck!

=head1 SEE ALSO

Maybe other modules do related things.

=cut

# vim: ts=4 sts=4 sw=4 et:
