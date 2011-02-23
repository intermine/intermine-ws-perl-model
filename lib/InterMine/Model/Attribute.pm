package InterMine::Model::Attribute;

=head1 NAME

InterMine::Model::Attribute - represents an attribute of an InterMine class

=head1 SYNOPSIS

  use InterMine::Model::Attribute;

  ...
  my $field = InterMine::Model::Attribute->new(name => 'age', model => $model,
                                               type => 'Integer');

  ...

=head1 DESCRIPTION

Objects of this class describe the attributes of class in an InterMine model.
Attribute objects are generally part of ClassDescriptor objects.

=head1 AUTHOR

FlyMine C<< <support@flymine.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<support@flymine.org>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc InterMine::Model::Attribute

You can also look for information at:

=over 4

=item * FlyMine

L<http://www.flymine.org>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2006,2007,2008,2009 FlyMine, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=cut
use Moose;
with (
    'InterMine::Model::Role::Descriptor',
    'InterMine::Model::Role::Field',
);

use MooseX::Types::Moose qw(Str Int Num Bool);
use InterMine::TypeLibrary qw(BigInt);
use InterMine::Model::Types qw(ISO8601DateStamp);

has type => (
    reader   => '_type',
    isa	     => Str,
    required => 1,
);

=head2 attribute_type

 Usage   : my $type = $field->attribute_type();
 Function: return the (Java) type of this attribute, eg. "String", "Integer",
           "Date", "Boolean"

=cut

sub attribute_type {
    my $self = shift;
    my $value = $self->_type;
    $value =~ s/.*\.//;
    return $value;
}

my %moose_translation_for = (
    string  => Str,
    short   => Int,
    integer => Int,
    int     => Int,
    long    => BigInt,
    double  => Num,
    float   => Num,
    boolean => Bool,
    date    => ISO8601DateStamp,
);

sub _get_moose_type {
    my $self = shift;
    if (exists $moose_translation_for{lc($self->attribute_type)}) {
        return $moose_translation_for{lc($self->attribute_type)};
    } else {
        return 'Value'; # The broadest possible scalar type
    }
}

sub _get_moose_options {
    my $self = shift;
    my @options = (isa => $self->_get_moose_type);
    if (lc($self->attribute_type) eq 'long') {
        push @options, (coerce => 1);
    }
    return @options;
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
